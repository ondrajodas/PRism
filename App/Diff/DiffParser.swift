import Foundation

/// Unified diff z `gh pr diff` → `Diff`.
///
/// **Nikdy nevyhodí výjimku.** Čemu nerozumí, to spočítá do `unrecognizedLines`: diff,
/// ze kterého kus tiše vypadl, vypadá jako úplný.
///
/// Řádek se zařazuje podle **stavu** (hlavička souboru / uvnitř hunku), ne podle prvního
/// znaku. Odebraný řádek začínající `---` je jinak k nerozeznání od hlavičky souboru.
enum DiffParser {
    static func parse(_ text: String) -> Diff {
        var parser = Parser()
        // **Dělí `TextLines`, ne `split(separator: "\n")`** (#295). Zakončení řádků si vybírá cizí
        // repo, ne my: v `gh pr diff` na `microsoft/terminal#20524` je `CRLF` na 70 řádcích ze 76
        // a `"\r\n"` je ve Swiftu jeden `Character` — z takového diffu by byl **jediný** řádek,
        // tedy soubor s jedním nesmyslným kontextovým řádkem místo dvou hunků.
        //
        // `content(_:)`, protože text zakončený novým řádkem dá prázdný poslední prvek. To není
        // řádek diffu — počítat ho jako nerozpoznaný by hlásilo ztrátu u každého úplného vstupu.
        for line in TextLines.content(text) {
            parser.consume(line)
        }
        return parser.finish()
    }
}

/// Průchod diffem po řádcích. Drží rozdělaný soubor a v něm rozdělaný hunk.
private struct Parser {
    private var files: [FileDiff] = []
    private var current: FileBuilder?
    private var unrecognized = 0

    mutating func consume(_ line: Substring) {
        if line.hasPrefix("diff --git ") {
            closeCurrentFile()
            current = FileBuilder(header: line)
        } else if current == nil {
            // Před prvním souborem nemá řádek kam patřit.
            unrecognized += 1
        } else if current?.consume(line) == false {
            unrecognized += 1
        }
    }

    mutating func finish() -> Diff {
        closeCurrentFile()
        return Diff(files: files, unrecognizedLines: unrecognized)
    }

    private mutating func closeCurrentFile() {
        guard var file = current else { return }
        files.append(file.finish())
        current = nil
    }
}

/// Skládá jeden soubor. Rozlišuje dva stavy: hlavičku a otevřený hunk.
private struct FileBuilder {
    private let headerPaths: (old: String?, new: String?)
    private var oldPath: String?
    private var newPath: String?
    private var change: FileDiff.Change = .modified
    private var isBinary = false
    private var blobs: String?
    private var hunks: [DiffHunk] = []
    private var hunk: HunkBuilder?
    /// `GIT binary patch` uvozuje blok, kterému nerozumíme — ale je to **očekávaný**
    /// obsah, ne rozbitý řádek, takže se přeskočí a do ztrát nepočítá.
    private var skippingBinaryPayload = false

    init(header line: Substring) {
        headerPaths = FileBuilder.paths(fromHeader: line)
    }

    /// `false` znamená řádek, kterému parser nerozumí.
    mutating func consume(_ line: Substring) -> Bool {
        if skippingBinaryPayload { return true }
        if line.hasPrefix("@@") { return startHunk(line) }
        if hunk != nil { return consumeHunkLine(line) }
        return consumeHeaderLine(line)
    }

    mutating func finish() -> FileDiff {
        closeHunk()
        return FileDiff(
            // `/dev/null` na jedné straně je pravda o souboru, ne chybějící údaj — proto
            // se cesta u přidaného a smazaného souboru zahazuje i tehdy, když ji hlavička
            // `diff --git` nabízí.
            oldPath: change == .added ? nil : (oldPath ?? headerPaths.old),
            newPath: change == .deleted ? nil : (newPath ?? headerPaths.new),
            change: change,
            isBinary: isBinary,
            hunks: hunks,
            blobs: blobs
        )
    }

    // MARK: - Hlavička souboru

    private mutating func consumeHeaderLine(_ line: Substring) -> Bool {
        if line.hasPrefix("--- ") { return readOldPath(line.dropFirst(4)) }
        if line.hasPrefix("+++ ") { return readNewPath(line.dropFirst(4)) }
        if line.hasPrefix("rename from ") { return rename(from: line.dropFirst(12)) }
        if line.hasPrefix("rename to ") { return rename(to: line.dropFirst(10)) }
        if line.hasPrefix("index ") { return readBlobs(line.dropFirst(6)) }
        if line.hasPrefix("new file mode ") { change = .added; return true }
        if line.hasPrefix("deleted file mode ") { change = .deleted; return true }
        if line.hasPrefix("Binary files ") { isBinary = true; return true }
        if line == "GIT binary patch" {
            isBinary = true
            skippingBinaryPayload = true
            return true
        }
        return FileBuilder.isIgnorable(line)
    }

    /// Řádky, které nesou informaci, kterou aplikace nezobrazuje. Rozpoznat je je potřeba
    /// proto, aby se nepočítaly jako ztráta.
    ///
    /// **`index ` mezi nimi od #500 není** — z něj se čte otisk obsahu souboru (`FileDiff.blobs`).
    private static func isIgnorable(_ line: Substring) -> Bool {
        ["old mode ", "new mode ", "similarity index ", "dissimilarity index ",
         "copy from ", "copy to "]
            .contains { line.hasPrefix($0) }
    }

    /// `index b01c2e9..3b6bc60 100644` → `b01c2e9..3b6bc60` (#500).
    ///
    /// Mód se **odřezává**: je to práva souboru, ne jeho obsah, a `chmod +x` bez změny řádku by
    /// jinak shodil značku `Prošlo` na `změněno od prošlého`. U nového a smazaného souboru je
    /// jedna strana samá nula (`00000000000..98625bb`) — to je pravda o souboru, ne chybějící
    /// údaj, takže se nechává, jak přišla.
    ///
    /// Řádka, které nerozumíme, **není ztráta**: `index` byl do #500 na seznamu ignorovaných
    /// a nepřečtený otisk znamená jen `nil`, tedy „nevím“ — což `Policy` umí. Hlásit kvůli
    /// tvaru téhle řádky rozbitý diff by bylo tvrzení o kódu, který je celý v pořádku.
    private mutating func readBlobs(_ token: Substring) -> Bool {
        let value = token.prefix { $0 != " " }
        // Bez `..` to není dvojice sha, ale něco jiného — takový řádek se nechává bez otisku.
        blobs = value.contains("..") ? String(value) : nil
        return true
    }

    private mutating func readOldPath(_ token: Substring) -> Bool {
        oldPath = FileBuilder.path(from: token)
        // `--- /dev/null` znamená, že soubor vznikl. Odvodit to odsud je spolehlivější než
        // čekat na `new file mode`, který u zvláštních diffů chybět může.
        if oldPath == nil, change == .modified { change = .added }
        return true
    }

    private mutating func readNewPath(_ token: Substring) -> Bool {
        newPath = FileBuilder.path(from: token)
        if newPath == nil, change == .modified { change = .deleted }
        return true
    }

    private mutating func rename(from token: Substring) -> Bool {
        oldPath = FileBuilder.unquoted(token)
        change = .renamed
        return true
    }

    private mutating func rename(to token: Substring) -> Bool {
        newPath = FileBuilder.unquoted(token)
        change = .renamed
        return true
    }

    // MARK: - Hunky

    private mutating func startHunk(_ line: Substring) -> Bool {
        closeHunk()
        guard let started = HunkBuilder(header: line) else { return false }
        hunk = started
        return true
    }

    private mutating func consumeHunkLine(_ line: Substring) -> Bool {
        switch line.first {
        case "+": hunk?.append(.added, text: String(line.dropFirst()))
        case "-": hunk?.append(.removed, text: String(line.dropFirst()))
        case " ": hunk?.append(.context, text: String(line.dropFirst()))
        case "\\": hunk?.append(.meta, text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
        // Prázdný řádek posílá `gh` jako " ", ale cokoli, co po cestě ořeže koncové
        // mezery, z něj udělá "". Hlásit kvůli tomu rozbitý diff by byl planý poplach.
        case nil: hunk?.append(.context, text: "")
        default:
            // Hunk skončil něčím, co do něj nepatří — např. patkou e-mailového patche.
            closeHunk()
            return consumeHeaderLine(line)
        }
        return true
    }

    private mutating func closeHunk() {
        guard let hunk else { return }
        hunks.append(hunk.hunk())
        self.hunk = nil
    }

    // MARK: - Cesty

    /// Cesty z `diff --git a/… b/…`. Jsou jen **záchrana** pro soubory, které `---`/`+++`
    /// ani `rename from`/`rename to` nemají (binárky, přejmenování beze změny obsahu):
    /// u cesty s mezerou se tahle hlavička rozdělit spolehlivě nedá.
    private static func paths(fromHeader line: Substring) -> (old: String?, new: String?) {
        let rest = line.dropFirst("diff --git ".count)
        guard let separator = rest.range(of: " b/") else { return (nil, nil) }
        return (
            path(from: rest[rest.startIndex..<separator.lowerBound]),
            path(from: rest[separator.lowerBound...].dropFirst())
        )
    }

    private static func path(from token: Substring) -> String? {
        let raw = unquoted(token)
        guard raw != "/dev/null" else { return nil }
        // `git` prefixuje staré cesty `a/` a nové `b/`; jiný prefix `gh` neposílá.
        if raw.hasPrefix("a/") || raw.hasPrefix("b/") { return String(raw.dropFirst(2)) }
        return raw
    }

    private static func unquoted(_ token: Substring) -> String {
        guard token.count >= 2, token.hasPrefix("\""), token.hasSuffix("\"") else {
            return String(token)
        }
        return String(token.dropFirst().dropLast())
    }
}

/// Skládá jeden hunk a přiděluje řádkům čísla.
private struct HunkBuilder {
    private let oldStart: Int
    private let oldCount: Int
    private let newStart: Int
    private let newCount: Int
    private let heading: String
    private var lines: [DiffLine] = []
    private var oldNumber: Int
    private var newNumber: Int

    /// `nil` u hlavičky, které nerozumíme — volající ji spočítá jako ztracený řádek.
    init?(header line: Substring) {
        guard line.hasPrefix("@@ ") else { return nil }
        let rest = line.dropFirst(3)
        guard let end = rest.range(of: " @@") else { return nil }

        let ranges = rest[..<end.lowerBound].split(separator: " ")
        guard ranges.count == 2,
              let old = HunkBuilder.range(ranges[0], sign: "-"),
              let new = HunkBuilder.range(ranges[1], sign: "+")
        else { return nil }

        oldStart = old.start
        oldCount = old.count
        newStart = new.start
        newCount = new.count
        oldNumber = old.start
        newNumber = new.start
        let trailing = rest[end.upperBound...]
        heading = String(trailing.hasPrefix(" ") ? trailing.dropFirst() : trailing)
    }

    /// `-171,8` → od 171 osm řádků. Chybějící počet znamená jeden řádek.
    private static func range(_ token: Substring, sign: Character) -> (start: Int, count: Int)? {
        guard token.first == sign else { return nil }
        let parts = token.dropFirst().split(separator: ",")
        guard let first = parts.first, let start = Int(first) else { return nil }
        guard parts.count > 1 else { return (start, 1) }
        guard parts.count == 2, let count = Int(parts[1]) else { return nil }
        return (start, count)
    }

    mutating func append(_ kind: DiffLine.Kind, text: String) {
        switch kind {
        case .context:
            lines.append(DiffLine(kind: kind, oldNumber: oldNumber, newNumber: newNumber, text: text))
            oldNumber += 1
            newNumber += 1
        case .added:
            lines.append(DiffLine(kind: kind, oldNumber: nil, newNumber: newNumber, text: text))
            newNumber += 1
        case .removed:
            lines.append(DiffLine(kind: kind, oldNumber: oldNumber, newNumber: nil, text: text))
            oldNumber += 1
        case .meta:
            // Poznámka `git`u není obsah souboru, takže počítadla nechává být.
            lines.append(DiffLine(kind: kind, oldNumber: nil, newNumber: nil, text: text))
        }
    }

    func hunk() -> DiffHunk {
        DiffHunk(
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            heading: heading,
            lines: lines
        )
    }
}
