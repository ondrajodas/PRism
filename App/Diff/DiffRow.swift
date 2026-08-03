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
    /// Nálezy k řádku nad sebou. `anchored: false` znamená, že řádek v diffu není a
    /// bublina visí u hlavičky souboru — schovat ji by znamenalo, že ji nikdo neuvidí.
    case finding(String, FindingGroup, anchored: Bool)
    /// Vlákno konverzace z GitHubu u řádku nad sebou.
    ///
    /// Vždycky zakotvené — na rozdíl od nálezu. Vlákno bez řádku v aktuálním diffu se sem
    /// **nedostane**: jeho číslo platilo pro starý head, takže by bublina sedla na cizí kód.
    /// Domov má v `Overview` (#72), vybírá je `Policy.threadsOutsideTheDiff`.
    case thread(String, ReviewThread)
    /// Věta místo obsahu — u binárky nebo u souboru beze změny obsahu.
    case note(String, String)

    /// Identita v rámci **celého** diffu, ne jen souboru: skáče se na ni z panelu nálezů,
    /// takže se dvě různá místa nesmí trefit do jedné.
    ///
    /// **Neodvozuje se z pořadí v seznamu.** Rozbalení kontextu řádky přidává, takže by
    /// se identity posunuly a odkaz z nálezu by po rozbalení ukázal jinam.
    var id: String {
        switch self {
        case .hunk(let id, _), .line(let id, _), .expander(let id, _), .note(let id, _),
             .finding(let id, _, _), .thread(let id, _): id
        }
    }

    /// Řádky souboru k vykreslení.
    ///
    /// - Parameters:
    ///   - revealed: skryté úseky, které si uživatel nechal dotáhnout.
    ///   - content: obsah souboru na hlavě PR, po řádcích. Prázdný, dokud se nenačetl —
    ///     pak se ukazují jen rozbalovací řádky.
    ///   - findings: nálezy napříč diffem; k tomuhle souboru se z nich vyberou samy.
    ///   - threads: vlákna konverzace napříč diffem; vybírají se stejně jako nálezy.
    static func rows(
        of file: FileDiff,
        revealed: RevealedLines = RevealedLines(),
        content: [String] = [],
        findings: [FindingGroup] = [],
        threads: [ReviewThread] = []
    ) -> [DiffRow] {
        // I zkratka projde přes `withBubbles`: nález na binárce nebo na souboru beze změny
        // obsahu se jinak z diffu ztratí úplně — a tiše zmizelý nález vypadá jako čistý PR.
        if file.isBinary {
            return withBubbles(
                [.note(id(of: file, "note"), "Binární soubor — obsah se nezobrazuje.")],
                of: file,
                findings: findings,
                threads: threads
            )
        }
        if file.hunks.isEmpty {
            return withBubbles(
                [.note(id(of: file, "note"), "Beze změny obsahu.")],
                of: file,
                findings: findings,
                threads: threads
            )
        }

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
        return withBubbles(rows, of: file, findings: findings, threads: threads)
    }

    /// Kam v diffu ukazuje nález — id řádku, na který se dá odscrollovat.
    ///
    /// Hledá se v hunkách i v **rozbaleném kontextu**: nález mimo diff si svůj kód dotáhne
    /// (#47), takže jeho řádek je vykreslený, jen jinou cestou. Kotva na hlavičku souboru
    /// by u něj přistála jinde, než kde nález opravdu je.
    ///
    /// Když řádek vykreslený není (nález bez čísla nebo nedotažený kontext), vrací se
    /// **soubor** — odskočit aspoň na něj je pořád lepší než nic.
    static func anchor(
        in diff: Diff,
        file path: String,
        line: Int?,
        revealed: RevealedLines = RevealedLines()
    ) -> String? {
        guard let file = diff.file(at: path) else { return nil }
        guard let line else { return file.id }

        for (index, hunk) in file.hunks.enumerated() {
            if let position = hunk.lines.firstIndex(where: { $0.newNumber == line }) {
                return id(of: file, "h\(index)l\(position)")
            }
        }
        if revealed.ranges.contains(where: { $0.contains(line) }) { return id(of: file, "c\(line)") }
        return file.id
    }

    // MARK: - Bubliny nálezů

    /// Zavěsí nálezy pod řádky, kterých se týkají.
    ///
    /// Dělá se to **nad hotovým seznamem**, ne uvnitř skládání: bublina tak sedne i na
    /// rozbalený kontext (#47), aniž by o nálezech musela vědět každá větev.
    ///
    /// Nález, jehož řádek v diffu **není** (reviewer čte celý pracovní strom, ne jen diff)
    /// nezmizí — visí u hlavičky souboru a nabídne svůj řádek dotáhnout. Schovat ho by
    /// znamenalo, že si ho nikdo nepřečte.
    private static func withBubbles(
        _ rows: [DiffRow],
        of file: FileDiff,
        findings: [FindingGroup],
        threads: [ReviewThread] = []
    ) -> [DiffRow] {
        let mine = groups(of: file, from: findings)
        let myThreads = Policy.threads(of: file, from: threads)
        guard !mine.isEmpty || !myThreads.isEmpty else { return rows }

        let rendered = Set(rows.compactMap { row -> Int? in
            guard case .line(_, let line) = row else { return nil }
            return line.newNumber
        })
        // Nálezy bez řádku se schválně neslučují, takže jich k jednomu souboru může být
        // víc; drží se v pořadí, ve kterém přišly. Ty s řádkem se řadí podle něj —
        // slovník pořadí nemá a bubliny by mezi překresleními poskakovaly.
        let withoutLine = mine.filter { $0.line == nil }
        let missingLines = mine
            .filter { line in line.line.map { !rendered.contains($0) } ?? false }
            .sorted { ($0.line ?? 0) < ($1.line ?? 0) }
        let unanchored = withoutLine + missingLines
        let byLine = Dictionary(
            mine.compactMap { group in group.line.map { ($0, group) } },
            uniquingKeysWith: { first, _ in first }
        )

        // Identita se čísluje pořadím: `line` na ni nestačí, protože nálezů bez řádku
        // může být k jednomu souboru několik a se stejným `id` by je `ForEach` nerozeznal.
        var result = unanchored.enumerated().map { offset, group in
            DiffRow.finding(id(of: file, "u\(offset)"), group, anchored: false)
        }
        result.reserveCapacity(rows.count + mine.count + myThreads.count)
        for row in rows {
            result.append(row)
            guard case .line(_, let line) = row else { continue }
            if let number = line.newNumber, let group = byLine[number] {
                result.append(.finding(id(of: file, "f\(number)"), group, anchored: true))
            }
            // Vlákna jdou **pod** nálezy téhož řádku: nález je to, kvůli čemu je okno
            // otevřené, konverzace je kontext k němu.
            //
            // Kam vlákno patří, rozhoduje `Policy.matches` — **jedno místo** i pro výběr
            // v `Policy.threadsInTheDiff`, aby se umístění a výběr nemohly rozejít. Řeší
            // i `side`: vlákno na odebraném řádku má číslo ze staré verze souboru.
            //
            // Vlákna se na řádku **neslučují do jednoho**, na rozdíl od nálezů: každé je
            // vlastní konverzace s vlastním stavem vyřešení. Klíčem identity je `id`
            // z GitHubu, ne pořadí — je stabilní i přes obnovení konverzace.
            for thread in myThreads where Policy.matches(thread, line) {
                result.append(.thread(id(of: file, "t\(thread.id)"), thread))
            }
        }
        return result
    }

    /// Nálezy, které patří tomuhle souboru.
    ///
    /// Soubor se poznává i podle **staré** cesty, stejně jako u skoku z nálezu: reviewer
    /// může přejmenovaný soubor nahlásit pod tou, kterou měl dřív. Když se pak na jednom
    /// řádku potkají nálezy z obou cest, **slijí se** — zahodit jeden by byla tichá ztráta.
    private static func groups(of file: FileDiff, from findings: [FindingGroup]) -> [FindingGroup] {
        var byLine: [Int: FindingGroup] = [:]
        var withoutLine: [FindingGroup] = []

        for group in findings {
            guard let path = group.file, path == file.newPath || path == file.oldPath else { continue }
            guard let line = group.line else {
                withoutLine.append(group)
                continue
            }

            if let existing = byLine[line] {
                byLine[line] = FindingGroup(
                    file: existing.file,
                    line: line,
                    findings: existing.findings + group.findings
                )
            } else {
                byLine[line] = group
            }
        }
        return withoutLine + byLine.values
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
