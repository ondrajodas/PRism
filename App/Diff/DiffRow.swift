import Foundation

/// Jeden řádek diffu tak, jak se kreslí.
///
/// Diff se do líného seznamu skládá **rozbalený na řádky**, ne po hunkách. Hunk jako
/// jedna buňka se po zvětšení okna překreslil jen zčásti a mezi hlavičkami zůstala
/// prázdná místa — buňka, kterou líný seznam vytvořil při jiné šířce, se sama od sebe
/// nepřeměří. Řádek jako vlastní buňka tenhle problém nemá.
enum DiffRow: Identifiable {
    case hunk(String, DiffHunk)
    case line(String, DiffLine)
    /// Skrytý úsek mimo hunky, který se dá dotáhnout.
    case expander(String, DiffExpander)
    /// Věta místo obsahu — u binárky nebo u souboru beze změny obsahu.
    case note(String, String)

    /// Identita v rámci **celého** diffu, ne jen souboru: skáče se na ni z panelu nálezů,
    /// takže se dvě různá místa nesmí trefit do jedné.
    ///
    /// **Neodvozuje se z pořadí v seznamu.** Rozbalení kontextu řádky přidává, takže by
    /// se identity posunuly a odkaz z nálezu by po rozbalení ukázal jinam.
    var id: String {
        switch self {
        case .hunk(let id, _), .line(let id, _), .expander(let id, _), .note(let id, _): id
        }
    }

    /// Řádky souboru k vykreslení.
    ///
    /// - Parameters:
    ///   - revealed: skryté úseky, které si uživatel nechal dotáhnout.
    ///   - content: obsah souboru na hlavě PR, po řádcích. Prázdný, dokud se nenačetl —
    ///     pak se ukazují jen rozbalovací řádky.
    static func rows(
        of file: FileDiff,
        revealed: RevealedLines = RevealedLines(),
        content: [String] = []
    ) -> [DiffRow] {
        if file.isBinary { return [.note(id(of: file, "note"), "Binární soubor — obsah se nezobrazuje.")] }
        if file.hunks.isEmpty { return [.note(id(of: file, "note"), "Beze změny obsahu.")] }

        // Bez obsahu není co odkrývat. Kdyby se úsek přesto tvářil jako odkrytý, zmizel by
        // rozbalovací řádek i se spinnerem a zůstalo by po něm prázdno.
        let revealed = content.isEmpty ? RevealedLines() : revealed
        // U smazaného souboru nový obsah neexistuje, takže není co dotahovat. Vychází to
        // i z čísel (nový rozsah je nulový), ale spoléhat se na to znamená čekat, až se
        // někdy nevyjde.
        let expandable = file.change != .deleted

        var rows: [DiffRow] = []
        for (index, hunk) in file.hunks.enumerated() {
            let gap = expandable ? gapRows(before: index, of: file, revealed: revealed, content: content) : []
            rows += gap
            // Rozbalená mezera slila hunk s tím, co je nad ním: řádky jdou nepřetržitě za
            // sebou a hlavička uprostřed nemá co oddělovat. Mezera, která nikdy nebyla,
            // hlavičku nechává — u prvního hunku je pořád jediné, z čeho se pozná, kde
            // v souboru jsme.
            if !merged(gap) {
                rows.append(.hunk(id(of: file, "h\(index)"), hunk))
            }
            for (position, line) in hunk.lines.enumerated() {
                rows.append(.line(id(of: file, "h\(index)l\(position)"), line))
            }
        }
        rows += expandable ? trailingGapRows(of: file, revealed: revealed, content: content) : []
        return rows
    }

    /// Kam v diffu ukazuje nález — id řádku, na který se dá odscrollovat.
    ///
    /// Když se řádek najít nedá (nález bez čísla nebo na řádku mimo hunky), vrací se
    /// **soubor**: reviewer čte celý pracovní strom, ne jen diff, takže umí nahlásit
    /// řádek, který se nezměnil. Odskočit aspoň na soubor je pořád lepší než nic.
    static func anchor(in diff: Diff, file path: String, line: Int?) -> String? {
        guard let file = diff.files.first(where: { $0.newPath == path || $0.oldPath == path })
        else { return nil }
        guard let line else { return file.id }

        for (index, hunk) in file.hunks.enumerated() {
            if let position = hunk.lines.firstIndex(where: { $0.newNumber == line }) {
                return id(of: file, "h\(index)l\(position)")
            }
        }
        return file.id
    }

    // MARK: - Skryté úseky

    /// Slil se hunk s tím, co je nad ním? Jen když nad ním **mezera byla** a je celá pryč.
    private static func merged(_ gap: [DiffRow]) -> Bool {
        guard !gap.isEmpty else { return false }
        return !gap.contains { if case .expander = $0 { true } else { false } }
    }

    /// Úsek před hunkem: nad prvním od začátku souboru, jinak od konce předchozího.
    private static func gapRows(
        before index: Int,
        of file: FileDiff,
        revealed: RevealedLines,
        content: [String]
    ) -> [DiffRow] {
        let hunk = file.hunks[index]
        let previous = index > 0 ? file.hunks[index - 1] : nil
        let first = previous.map { $0.newStart + $0.newCount } ?? 1
        let shift = previous.map { ($0.newStart + $0.newCount) - ($0.oldStart + $0.oldCount) }
            ?? (hunk.newStart - hunk.oldStart)

        guard first <= hunk.newStart - 1 else { return [] }
        return rows(
            forGap: first...(hunk.newStart - 1),
            shift: shift,
            of: file,
            revealed: revealed,
            content: content
        )
    }

    /// Úsek za posledním hunkem. Kde končí, víme teprve z obsahu souboru — do té doby se
    /// nabízí bez počtu, protože jinak by se na konec souboru nedalo vůbec dostat.
    private static func trailingGapRows(
        of file: FileDiff,
        revealed: RevealedLines,
        content: [String]
    ) -> [DiffRow] {
        guard let last = file.hunks.last else { return [] }
        let first = last.newStart + last.newCount
        let shift = (last.newStart + last.newCount) - (last.oldStart + last.oldCount)

        guard content.isEmpty else {
            guard first <= content.count else { return [] }
            return rows(forGap: first...content.count, shift: shift, of: file, revealed: revealed, content: content)
        }
        return [.expander(id(of: file, "e\(first)"), DiffExpander(firstLine: first, lastLine: nil, shift: shift))]
    }

    private static func rows(
        forGap gap: ClosedRange<Int>,
        shift: Int,
        of file: FileDiff,
        revealed: RevealedLines,
        content: [String]
    ) -> [DiffRow] {
        revealed.split(gap).flatMap { part in
            switch part {
            case .hidden(let range):
                [expanderRow(range, shift: shift, of: file)]
            case .shown(let range):
                contextRows(range, shift: shift, of: file, content: content)
            }
        }
    }

    private static func expanderRow(_ range: ClosedRange<Int>, shift: Int, of file: FileDiff) -> DiffRow {
        .expander(
            id(of: file, "e\(range.lowerBound)"),
            DiffExpander(firstLine: range.lowerBound, lastLine: range.upperBound, shift: shift)
        )
    }

    /// Rozbalený řádek je obyčejný kontext — má obě čísla a nic se v něm nemění.
    private static func contextRows(
        _ range: ClosedRange<Int>,
        shift: Int,
        of file: FileDiff,
        content: [String]
    ) -> [DiffRow] {
        range.compactMap { number in
            guard number >= 1, number <= content.count else { return nil }
            return .line(
                id(of: file, "c\(number)"),
                DiffLine(
                    kind: .context,
                    oldNumber: number - shift,
                    newNumber: number,
                    text: content[number - 1]
                )
            )
        }
    }

    /// Identity vycházejí z `file.id`, na kterém visí i sekce souboru — proto se na soubor
    /// dá skočit stejnou cestou jako na řádek a nekříží se mezi soubory.
    private static func id(of file: FileDiff, _ suffix: String) -> String {
        "\(file.id)|\(suffix)"
    }
}
