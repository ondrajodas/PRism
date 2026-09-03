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
    /// Souvislý úsek řádků jako **jeden text** (#157) — kvůli selekci přes víc řádků, kterou
    /// SwiftUI `Text` nedá. Skládá je `DiffRow.blocked(_:)` z `.line` řádků; `.line` proto
    /// v pohledu pod sebou do seznamu přímo **nechodí**, jen jako mezikrok.
    case block(String, DiffBlock)
    /// Totéž pro pohled vedle sebe — dva sloupce, které si odpovídají řádek po řádku.
    case pairBlock(String, DiffPairBlock)
    /// Dvojice řádků v pohledu **vedle sebe** — vlevo starý obsah, vpravo nový.
    ///
    /// Jeden model pro oba pohledy, ne vlastní typ vedle `DiffRow`: se samostatným typem by
    /// se logika bublin, expanderů a kotev psala dvakrát, a to je zrovna ta část, na které
    /// visí „nález nesmí zmizet“. Skládá je `DiffRow.paired(_:)`.
    ///
    /// Chybějící strana (`nil`) je prázdná buňka, ne mezera — u kontextového řádku je na
    /// obou stranách **tatáž hodnota**, protože je to jeden řádek souboru.
    case pair(String, left: DiffLine?, right: DiffLine?)
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
    /// Moje rozdělané komentáře k řádku nad sebou, rozdělené podle strany diffu.
    ///
    /// Kotví se jako vlákno (podle `side`), ne jako nález. Komentář, jehož řádek v aktuálním
    /// diffu není, se **nekreslí** — celý seznam je vidět v panelu, takže se neztrácí.
    ///
    /// **Jeden řádek na řádek diffu, ne na komentář**: ve split pohledu stojí komentáře ke staré
    /// a k nové straně **vedle sebe** ve svých polovinách, a to ze dvou samostatných řádků
    /// složit nejde. Rozdělení podle strany platí i v pohledu pod sebou (`side` je vlastnost
    /// komentáře, ne pohledu) — tam se jen vypíšou pod sebou přes celou šířku.
    case draftComments(String, left: [ReviewDraftComment], right: [ReviewDraftComment])
    /// Věta místo obsahu — u binárky nebo u souboru beze změny obsahu.
    case note(String, String)

    /// Identita v rámci **celého** diffu, ne jen souboru: skáče se na ni z panelu nálezů,
    /// takže se dvě různá místa nesmí trefit do jedné.
    ///
    /// **Neodvozuje se z pořadí v seznamu.** Rozbalení kontextu řádky přidává, takže by
    /// se identity posunuly a odkaz z nálezu by po rozbalení ukázal jinam.
    var id: String {
        switch self {
        case .hunk(let id, _), .line(let id, _), .pair(let id, _, _), .expander(let id, _),
             .note(let id, _), .finding(let id, _, _), .thread(let id, _),
             .draftComments(let id, _, _), .block(let id, _), .pairBlock(let id, _): id
        }
    }

    /// Řádky po stranách: u dvojice zleva a zprava, u řádku v pohledu pod sebou **tentýž na
    /// obou** — jedna řádka tam nese starou i novou verzi. Prázdné u všeho, co obsah souboru
    /// nenese (hlavička hunku, expander, bublina, poznámka).
    ///
    /// Odsud se vybírají vlákna i komentáře, takže rozdělení na strany je jedno a totéž pro
    /// oba pohledy. Kdo se ptá „ke které straně to patří“, dostane odpověď z jednoho místa.
    var sides: (left: DiffLine?, right: DiffLine?) {
        switch self {
        case .line(_, let line): (line, line)
        case .pair(_, let left, let right): (left, right)
        default: (nil, nil)
        }
    }

    /// Řádky souboru, které tenhle řádek diffu nese — u dvojice jeden nebo dva.
    ///
    /// Kontextová dvojice má na obou stranách **tutéž hodnotu** a vrací se proto **jednou**:
    /// dvakrát by se porovnávala dvakrát a vlákno u ní vyšlo jako dvě bubliny.
    var sourceLines: [DiffLine] {
        let sides = sides
        guard sides.left != sides.right else { return [sides.left].compactMap { $0 } }
        return [sides.left, sides.right].compactMap { $0 }
    }

    /// Číslo řádku v **nové** verzi souboru, na které se zavěšují bubliny. U dvojice vychází
    /// z pravé strany, protože nová čísla stojí vždycky vpravo.
    ///
    /// Odvozuje se ze `sourceLines`, ať se ty dvě odpovědi nemůžou rozejít.
    var newNumber: Int? {
        sourceLines.compactMap(\.newNumber).first
    }

    /// Řádky souboru k vykreslení.
    ///
    /// - Parameters:
    ///   - layout: `unified` skládá řádky pod sebe, `split` je slévá do dvojic. Slévá se
    ///     **před** zavěšením bublin — viz `DiffRow.paired(_:)`.
    ///   - revealed: skryté úseky, které si uživatel nechal dotáhnout.
    ///   - content: obsah souboru na hlavě PR, po řádcích. Prázdný, dokud se nenačetl —
    ///     pak se ukazují jen rozbalovací řádky.
    ///   - findings: nálezy napříč diffem; k tomuhle souboru se z nich vyberou samy.
    ///   - inlineFindings: zavěsit **zakotvený** nález jako bublinu pod jeho řádek? Od #548 je to
    ///     zpátky výchozí místo nálezu (#503 ho na jednu verzi přesunulo do okraje vpravo) a okraj
    ///     je za přepínačem `Nálezy pod řádky` v liště. Nálezu **bez řádku** se to netýká: ten se
    ///     v okraji nemá k čemu zarovnat, takže visí u hlavičky souboru vždycky — jinak by se
    ///     zapnutým okrajem zmizel úplně.
    ///   - threads: vlákna konverzace napříč diffem; vybírají se stejně jako nálezy.
    ///   - comments: moje rozdělané komentáře napříč diffem; vybírají se stejně.
    static func rows(
        of file: FileDiff,
        layout: DiffLayout = .unified,
        revealed: RevealedLines = RevealedLines(),
        content: [String] = [],
        findings: [FindingGroup] = [],
        inlineFindings: Bool = true,
        threads: [ReviewThread] = [],
        comments: [ReviewDraftComment] = []
    ) -> [DiffRow] {
        // I zkratka projde přes `withBubbles`: nález na binárce nebo na souboru beze změny
        // obsahu se jinak z diffu ztratí úplně — a tiše zmizelý nález vypadá jako čistý PR.
        if file.isBinary {
            return withBubbles(
                [.note(id(of: file, "note"), "Binární soubor — obsah se nezobrazuje.")],
                of: file,
                findings: findings,
                inlineFindings: inlineFindings,
                threads: threads,
                comments: comments
            )
        }
        if file.hunks.isEmpty {
            return withBubbles(
                [.note(id(of: file, "note"), "Beze změny obsahu.")],
                of: file,
                findings: findings,
                inlineFindings: inlineFindings,
                threads: threads,
                comments: comments
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
        // **Bez slučování do bloků** — to je věc vykreslení, ne modelu, a dělá ho `DiffView`
        // (`DiffRow.blocked(_:)`). Kdyby se slučovalo tady, musela by o blocích vědět i kotva
        // skoku na nález a všechno, co se řádků ptá.
        return withBubbles(
            layout == .split ? paired(rows) : rows,
            of: file,
            findings: findings,
            inlineFindings: inlineFindings,
            threads: threads,
            comments: comments
        )
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

        if let spot = position(of: line, in: file) { return id(of: file, "h\(spot.hunk)l\(spot.line)") }
        if revealed.ranges.contains(where: { $0.contains(line) }) { return id(of: file, "c\(line)") }
        return file.id
    }

    /// **Kreslí se ten řádek vůbec?** Odpověď na tutéž otázku, na kterou odpovídá `anchor` — jen
    /// bez identity, protože okraj (#503) potřebuje vědět jedině to, jestli má karta k čemu
    /// zarovnat.
    ///
    /// Je to schválně **jedno místo pro obojí** (`position(of:in:)` a rozsah odkrytého kontextu):
    /// dvě odpovědi na „je ten řádek v diffu“ znamenají, že karta v okraji stojí u řádku, na který
    /// skok nedojde — a naopak.
    static func renders(line: Int, of file: FileDiff, revealed: RevealedLines) -> Bool {
        if position(of: line, in: file) != nil { return true }
        return revealed.ranges.contains { $0.contains(line) }
    }

    /// Kde v hunkách leží řádek s tímhle **novým** číslem. `nil` = v hunkách není (odebraný řádek,
    /// nebo mimo diff).
    private static func position(of line: Int, in file: FileDiff) -> (hunk: Int, line: Int)? {
        for (index, hunk) in file.hunks.enumerated() {
            if let position = hunk.lines.firstIndex(where: { $0.newNumber == line }) {
                return (index, position)
            }
        }
        return nil
    }

    /// Kam v diffu ukazuje můj rozdělaný komentář.
    ///
    /// Vlastní funkce, ne `anchor(in:file:line:)`: ta porovnává **nové** číslo řádku, kdežto
    /// komentář k odebranému řádku má číslo ze staré verze souboru. Bez toho by skok
    /// z panelu na takový komentář skončil u hlavičky souboru.
    ///
    /// Hledá se nad **hotovými řádky**, ne nad hunky, a to kvůli split pohledu: odebraný
    /// řádek je tam slitý do dvojice, jejíž identita je z **pravé** strany — id složené
    /// z hunku a pozice by v seznamu vůbec nebylo a skok by neudělal nic. Jedno místo, které
    /// rozhoduje o identitě řádku, je zároveň jediné, které se s ní nemůže rozejít.
    ///
    /// Obsah souboru ani odkryté úseky se nepředávají: komentář může vzniknout jedině
    /// na řádku uvnitř hunku (`Policy.commentableSide`), a ty jsou v řádcích tak či tak.
    /// Když řádek v diffu není (přišel nový commit), vrací se **soubor** — odskočit aspoň
    /// na něj je pořád lepší než nehnout se.
    static func anchor(in diff: Diff, comment: ReviewDraftComment, layout: DiffLayout = .unified) -> String? {
        guard let file = diff.file(at: comment.path) else { return nil }
        for row in rows(of: file, layout: layout)
        where row.sourceLines.contains(where: { Policy.matches(comment, $0) }) {
            return row.id
        }
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
        inlineFindings: Bool = true,
        threads: [ReviewThread] = [],
        comments: [ReviewDraftComment] = []
    ) -> [DiffRow] {
        let mine = groups(of: file, from: findings)
        let myThreads = Policy.threads(of: file, from: threads)
        let myComments = Policy.comments(of: file, from: comments)
        guard !mine.isEmpty || !myThreads.isEmpty || !myComments.isEmpty else { return rows }

        // Čte se `newNumber` z řádku i z dvojice — u dvojice je z pravé strany. Bez toho by
        // se ve split pohledu každý nález tvářil jako nález na řádku, který v diffu není.
        let rendered = Set(rows.compactMap(\.newNumber))
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
        result.reserveCapacity(rows.count + mine.count + myThreads.count + myComments.count)
        for row in rows {
            result.append(row)
            // Ve split pohledu nese řádky souboru dvojice, jinak `.line`. Zbytek (hlavička,
            // expander, poznámka) žádné nemá a bublina se k němu nevěší.
            let lines = row.sourceLines
            guard !lines.isEmpty else { continue }
            // **Zakotvený nález jde do bubliny jedině na požádání** (#503): jeho domovem je od
            // té doby okraj vpravo, kde stojí vedle řádku místo pod ním. Nezakotvený nález
            // (`unanchored` výš) se tím neřídí — v okraji se nemá k čemu zarovnat, takže u
            // hlavičky souboru zůstává vždycky.
            if inlineFindings, let number = row.newNumber, let group = byLine[number] {
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
            //
            // U dvojice se porovnávají **obě** strany: vlákno na odebraném řádku má číslo ze
            // staré verze, tedy z té levé. Jeden thread nemůže sednout na obě — `side` určuje,
            // které číslo se porovnává, a to má vždycky jen jedna strana.
            for thread in myThreads where lines.contains(where: { Policy.matches(thread, $0) }) {
                result.append(.thread(id(of: file, "t\(thread.id)"), thread))
            }
            // Moje rozdělané komentáře jdou **naspod**: nález a cizí komentář jsou to, co si
            // mám přečíst, kdežto svou vlastní rozepsanou větu znám. Neslévají se do jedné
            // bubliny, ze stejného důvodu jako vlákna — dva komentáře na jednom řádku jsou dvě
            // věci — ale jsou v **jednom řádku** rozdělené po stranách, aby mohly ve split
            // pohledu stát vedle sebe.
            //
            // Identitu řádku dává **místo, ne komentář**: kdyby vycházela z prvního komentáře,
            // vyjmutí levého by ji změnilo a editor toho druhého by přišel o rozepsaný text.
            // Identita jednotlivých bublin je `id` komentáře, viz `DiffRowView`.
            //
            // Do které poloviny komentář patří, říká jeho `side`; že patří k **tomuhle** řádku,
            // ověří `Policy.matches`. Obojí je potřeba: v pohledu pod sebou (a u kontextové
            // dvojice) stojí na obou stranách tatáž řádka, takže samotné `matches` by komentář
            // vrátilo do obou polovin — tedy dvakrát.
            let byLeft = myComments.filter { $0.side == .left && matches($0, row.sides.left) }
            let byRight = myComments.filter { $0.side == .right && matches($0, row.sides.right) }
            if !byLeft.isEmpty || !byRight.isEmpty {
                result.append(.draftComments("\(row.id)|d", left: byLeft, right: byRight))
            }
        }
        return result
    }

    /// Patří komentář k řádku na téhle straně? Bez řádku (chybějící protistrana) nikdy.
    private static func matches(_ comment: ReviewDraftComment, _ line: DiffLine?) -> Bool {
        line.map { Policy.matches(comment, $0) } ?? false
    }

    /// Nálezy, které patří tomuhle souboru.
    ///
    /// Soubor se poznává i podle **staré** cesty, stejně jako u skoku z nálezu: reviewer
    /// může přejmenovaný soubor nahlásit pod tou, kterou měl dřív. Když se pak na jednom
    /// řádku potkají nálezy z obou cest, **slijí se** — zahodit jeden by byla tichá ztráta.
    ///
    /// **Od #503 to není jen pro bubliny**: tou samou funkcí si vybírá skupiny i okraj vpravo
    /// (`Policy.marginCards`), aby se karta a bublina nemohly rozejít v tom, kolik nálezů na
    /// jednom řádku je.
    static func groups(of file: FileDiff, from findings: [FindingGroup]) -> [FindingGroup] {
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
