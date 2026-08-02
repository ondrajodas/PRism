import Foundation

/// Obarvení jednoho řádku kódu.
///
/// **Řádek po řádku, bez paměti.** Blokový komentář nebo řetězec přes víc řádků se
/// obarví jen tam, kde začíná — dál to nejde: diff je útržek a mezi hunky chybí řádky,
/// ze kterých by se stav dopočítal. Držet stav napříč hunky by barvilo podle textu,
/// který v okně není.
///
/// Není to gramatika jazyka: cílem je, aby se v diffu chytlo oko, ne aby se prošel
/// standard.
enum SyntaxHighlighter {
    static func runs(of line: String, in language: Language) -> [SyntaxRun] {
        var scanner = LineScanner(line: Array(line), language: language)
        scanner.scan()
        return scanner.runs
    }
}

/// Průchod řádkem po znacích. Znaky jsou `[Character]`, ne `String.Index` — s indexy je
/// každé nahlédnutí dopředu o dva znaky nečitelné a diakritika se v obojím chová stejně.
///
/// Jméno není `Scanner`, aby nestínilo ten z `Foundation`.
private struct LineScanner {
    private let line: [Character]
    private let language: Language
    /// Uvozující značky rozepsané na znaky **jednou za řádek**, ne při každém porovnání.
    /// Obarvení běží při každém vykreslení řádku, takže alokace na znak je znát.
    private let lineComments: [[Character]]
    private let blockComment: (open: [Character], close: [Character])?
    private var position = 0
    private var plainStart = 0
    private(set) var runs: [SyntaxRun] = []

    init(line: [Character], language: Language) {
        self.line = line
        self.language = language
        lineComments = language.lineComments.map(Array.init)
        blockComment = language.blockComment.map { (Array($0.open), Array($0.close)) }
    }

    mutating func scan() {
        while position < line.count {
            if scanComment() || scanString() || scanVariable() || scanNumber() || scanWord() { continue }
            position += 1
        }
        flushPlain(upTo: line.count)
    }

    // MARK: - Jednotlivé kusy

    private mutating func scanComment() -> Bool {
        if lineComments.contains(where: { matches($0) }) {
            emit(from: position, to: line.count, as: .comment)
            return true
        }
        guard let block = blockComment, matches(block.open) else { return false }

        let end = index(of: block.close, from: position + block.open.count)
        // Blok, který na řádku nekončí, obarvíme do konce řádku.
        emit(from: position, to: end.map { $0 + block.close.count } ?? line.count, as: .comment)
        return true
    }

    private mutating func scanString() -> Bool {
        guard let delimiter = language.stringDelimiters.first(where: { line[position] == $0 })
        else { return false }

        var end = position + 1
        while end < line.count {
            if line[end] == "\\" { end += 2; continue }   // escapovaný znak řetězec neukončí
            if line[end] == delimiter { end += 1; break }
            end += 1
        }
        emit(from: position, to: min(end, line.count), as: .string)
        return true
    }

    private mutating func scanVariable() -> Bool {
        guard language.variableSigils.contains(line[position]) else { return false }

        // `${HOME}` — jméno v závorkách bere celé, včetně nich.
        if line.indices.contains(position + 1), line[position + 1] == "{" {
            let end = index(of: ["}"], from: position + 2).map { $0 + 1 } ?? line.count
            emit(from: position, to: end, as: .variable)
            return true
        }

        // Osamocený dolar (v textu, v ceně) proměnná není.
        guard isWordCharacter(at: position + 1) else { return false }
        var end = position + 1
        while isWordCharacter(at: end) { end += 1 }
        emit(from: position, to: end, as: .variable)
        return true
    }

    private mutating func scanNumber() -> Bool {
        guard line[position].isNumber, !isWordCharacter(at: position - 1) else { return false }

        var end = position
        while end < line.count, line[end].isNumber || line[end] == "." || line[end] == "_" {
            end += 1
        }
        // `utf8` je jméno, ne číslo — číslice těsně před písmenem nic neznačí.
        guard !isWordCharacter(at: end) else { return false }
        emit(from: position, to: end, as: .number)
        return true
    }

    private mutating func scanWord() -> Bool {
        guard isWordCharacter(at: position), !line[position].isNumber else { return false }

        var end = position
        while isWordCharacter(at: end) { end += 1 }
        let word = String(line[position..<end])

        guard language.keywords.contains(word.lowercased()) else {
            position = end   // jméno přeskočíme celé, ať se v něm nehledá klíčové slovo
            return true
        }
        emit(from: position, to: end, as: .keyword)
        return true
    }

    // MARK: - Skládání

    /// Zapíše kus a to, co mu předcházelo, jako obyčejný text.
    private mutating func emit(from start: Int, to end: Int, as kind: SyntaxKind) {
        flushPlain(upTo: start)
        runs.append(SyntaxRun(text: String(line[start..<end]), kind: kind))
        position = end
        plainStart = end
    }

    private mutating func flushPlain(upTo end: Int) {
        guard plainStart < end else { return }
        runs.append(SyntaxRun(text: String(line[plainStart..<end]), kind: .plain))
        plainStart = end
    }

    // MARK: - Drobnosti

    private func matches(_ token: [Character], at start: Int? = nil) -> Bool {
        let start = start ?? position
        guard let first = token.first, line.indices.contains(start), line[start] == first else { return false }
        guard start + token.count <= line.count else { return false }
        return !zip(token.indices, token).contains { line[start + $0.0] != $0.1 }
    }

    private func index(of token: [Character], from start: Int) -> Int? {
        guard !token.isEmpty else { return nil }
        return (start...max(start, line.count - token.count)).first { matches(token, at: $0) }
    }

    private func isWordCharacter(at index: Int) -> Bool {
        guard index >= 0, index < line.count else { return false }
        return line[index].isLetter || line[index].isNumber || line[index] == "_"
    }
}
