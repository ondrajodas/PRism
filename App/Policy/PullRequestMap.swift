import Foundation

/// Jeden soubor jako segment mapy PR (#501).
///
/// **Barva je závažnost, ne reviewer** — v pásu se obojí naráz kódovat nedá a závažnost je to,
/// podle čeho se čte první. Kdo našel, zůstává v chipech runbaru a v dráhách `Průběhu`.
struct PullRequestMapSegment: Hashable, Sendable, Identifiable {
    /// Cesta, pod kterou soubor v okně vystupuje (`FileDiff.displayPath`) — a zároveň identita
    /// segmentu i to, na co se skáče kliknutím.
    let path: String
    /// Poslední část cesty. Pod pásem se v decku kreslí jméno, ne cesta: na `src/Vault/` není
    /// v segmentu o dvaceti bodech místo a nese ho hlavička souboru v diffu.
    let name: String
    /// Kolik řádků soubor mění — `+` a `−` dohromady. Z toho je šířka.
    let changedLines: Int
    let additions: Int
    let deletions: Int
    /// Nejhorší nález v souboru. `nil` = žádný platný nález tu není.
    let marker: FileMarker?
    /// Je soubor v PR nový? Tón `ok`, protože na novém souboru není co rozbít — je celý ke čtení.
    let isNew: Bool
    /// Stav značky `Prošlo` (#500). Prošlý segment se tlumí, `changed` **ne**: je to práce,
    /// která se vrátila.
    let readState: FileReviewState
    /// Kolik míst k vyřízení v souboru je — **skupin**, ne nálezů, jako u kapsle v hlavičce
    /// souboru: tři reviewery, kteří se shodli na témž řádku, jsou jedna věc k rozhodnutí.
    let findings: Int
    /// Kde v souboru leží vlákna — podíl `0…1` na jeho rozsahu v diffu, jeden na vlákno.
    ///
    /// Podíl, ne číslo řádku: šířka segmentu se v okně mění a čárka má sedět na tom místě,
    /// kam v pásu padne. Počítá se **z pořadí řádku v diffu toho souboru**, ne z čísla řádku
    /// v souboru — mezi hunky jsou mezery a pás kreslí změněné řádky, ne celý soubor.
    let threads: [Double]

    var id: String { path }

    /// Šířka segmentu roste s **logaritmem** změněných řádků.
    ///
    /// `log₂(n + 1)`, tedy `0` u binárky beze změny řádků a `11,45` u `composer.lock`u
    /// o 2 790 řádcích. Lineární šířka je změřená a **zahozená**: v rozložení ze sekce 03
    /// návrhu (2 790 z 2 952 řádků) by lock vzal 94,5 % pásu a ze zbytku by bylo šest čárek,
    /// s logaritmem má 30,8 % — pořád největší, ale test o 64 řádcích je vidět.
    var weight: Double { log2(Double(changedLines) + 1) }
}

/// Pás pod hlavičkou PR (#501) — segmenty a popisek vpravo od nich.
struct PullRequestMap: Hashable, Sendable {
    let segments: [PullRequestMapSegment]
    /// `7 souborů · 3 prošlé · 5 nálezů · 2 vlákna`.
    let summary: String

    var isEmpty: Bool { segments.isEmpty }
}

extension Policy {
    /// Nejmenší šířka segmentu v bodech. **Jedno místo** — čte ji dělení šířek i `Layout`, který
    /// z ní skládá odpověď na neurčitý dotaz; dvě konstanty by znamenaly dvě pravdy o tom, kdy je
    /// pás ještě pás.
    static let mapSegmentMinimum = 3.0

    /// Pás pod hlavičkou PR ze všeho, co o souborech v okně víme (#501).
    ///
    /// **Jedno místo, ze kterého se pás skládá** — a čte tytéž vstupy jako strom, hlavička
    /// souboru a bubliny v diffu: soubory diffu, skupiny nálezů, zakotvená vlákna a značky
    /// `Prošlo`. Dvě místa by znamenala, že popisek `5 nálezů` tvrdí něco jiného, než co je
    /// v pásu vidět.
    ///
    /// Nálezy se hledají **po obou cestách souboru** (`newPath` i `oldPath`), stejně jako to
    /// dělá `DiffView.findings(in:)`: reviewer umí nález nahlásit pod tou starou, kdežto pás
    /// kreslí `displayPath`. Bez toho by přejmenovaný soubor vyšel jako neutrální.
    static func pullRequestMap(
        files: [FileDiff],
        findings: [FindingGroup] = [],
        threads: [ReviewThread] = [],
        readStates: [String: FileReviewState] = [:],
        categories: Set<String> = defaultBlockingCategories
    ) -> PullRequestMap {
        // **Předfiltr, ne dvojitá smyčka.** Pás se skládá při každém průchodu tělem detailu, takže
        // `files × groups` by u padesátisouborového PR s dvaceti nálezy znamenalo tisíc dotazů na
        // každé překreslení. Skupiny se proto **jednou** rozdělí podle cesty; nález bez cesty patří
        // celému PR, ne souboru, a do mapy se nedostane.
        var byPath: [String: [FindingGroup]] = [:]
        for group in findings {
            guard let path = group.file else { continue }
            byPath[path, default: []].append(group)
        }
        let segments = files.map { file in
            segment(of: file, findings: byPath, threads: threads, readStates: readStates, categories: categories)
        }
        return PullRequestMap(
            segments: segments,
            summary: mapSummary(
                files: segments.count,
                read: segments.count(where: { $0.readState.isRead }),
                findings: segments.reduce(0) { $0 + $1.findings },
                threads: segments.reduce(0) { $0 + $1.threads.count }
            )
        )
    }

    private static func segment(
        of file: FileDiff,
        findings: [String: [FindingGroup]],
        threads: [ReviewThread],
        readStates: [String: FileReviewState],
        categories: Set<String>
    ) -> PullRequestMapSegment {
        // **Obě cesty souboru**, a bez duplikátu: u souboru, který se nepřejmenoval, jsou `newPath`
        // a `oldPath` totéž, takže by se jeho nálezy počítaly dvakrát.
        var groups = file.newPath.flatMap { findings[$0] } ?? []
        if let old = file.oldPath, old != file.newPath { groups += findings[old] ?? [] }
        let tally = fileFindings(in: groups, categories: categories)
        return PullRequestMapSegment(
            path: file.displayPath,
            name: file.displayPath.split(separator: "/").last.map(String.init) ?? file.displayPath,
            changedLines: file.additions + file.deletions,
            additions: file.additions,
            deletions: file.deletions,
            // Blokující přebíjí obyčejný, jako uvnitř `fileMarkers` — a nic nepřebíjí zpátky.
            marker: tally.blocking > 0 ? .blocking : (tally.total > 0 ? .findings : nil),
            isNew: file.change == .added,
            readState: readStates[file.displayPath] ?? .unread,
            findings: tally.total,
            threads: threadSpots(of: file, threads: threads)
        )
    }

    /// Kde v segmentu leží vlákna — podíl `0…1` z **pořadí řádku v diffu toho souboru**.
    ///
    /// Který řádek vláknu patří, rozhoduje `Policy.matches(_:_:)`, tedy **totéž místo**, podle
    /// kterého se v diffu zavěšují bubliny. Kdyby se to tady rozhodovalo znovu (podle `line`
    /// a nové strany), sedla by čárka u vlákna na smazaném řádku někam jinam než bublina.
    ///
    /// Soubor o **jednom** řádku dostane `0,5` — každý podíl je v něm týž bod a střed se čte lépe
    /// než hrana. **Pravidlo `matches` ale platí i tam**, a je to oprava po Copilotovi na PR #539:
    /// první podoba vracela `0,5` pro každé vlákno, jakmile měl soubor nejvýš jeden řádek, tedy
    /// **bez** kontroly, jestli se to vlákno na něj vůbec kotví. Pás by pak tvrdil diskuzi
    /// v souboru, ve kterém pro ni není řádek — a `anchoredThreads` to sice v okně nepustí, ale
    /// `Policy` je čistá funkce a odpovídá na to, co dostane. Bez řádků (binárka) se nekreslí nic.
    private static func threadSpots(of file: FileDiff, threads: [ReviewThread]) -> [Double] {
        let candidates = threads.filter { $0.path == file.newPath || $0.path == file.oldPath }
        guard !candidates.isEmpty else { return [] }
        // **Bez `flatMap(\.lines)`**: u locku o dvou tisících řádků by to při každém průchodu
        // tělem detailu alokovalo celé pole. Hunky se prochází na místě a hledání skončí na
        // prvním sedícím řádku.
        let total = file.hunks.reduce(0) { $0 + $1.lines.count }
        guard total > 0 else { return [] }
        return candidates.compactMap { thread in
            guard let index = lineIndex(of: thread, in: file) else { return nil }
            return total > 1 ? Double(index) / Double(total - 1) : 0.5
        }
    }

    /// Pořadí řádku, na který se vlákno kotví, mezi všemi řádky hunků toho souboru.
    /// `nil` = takový řádek v diffu není.
    private static func lineIndex(of thread: ReviewThread, in file: FileDiff) -> Int? {
        var index = 0
        for hunk in file.hunks {
            for line in hunk.lines {
                if matches(thread, line) { return index }
                index += 1
            }
        }
        return nil
    }

    /// Popisek vpravo od pásu: `7 souborů · 3 prošlé · 5 nálezů · 2 vlákna`.
    ///
    /// **Části se připojují, až když mají co říct** — tentýž vzorec jako u hlavičky stromu
    /// (`fileTreeSummary`): `0 nálezů` je stálý řádek o tom, že se nic nestalo, a v pásu, který
    /// má nést rozsah PR, by to bylo místo ukrojené z ničeho. Počet souborů zůstává vždycky.
    static func mapSummary(files: Int, read: Int, findings: Int, threads: Int) -> String {
        var parts = [Plural.czech(files, one: "soubor", few: "soubory", many: "souborů")]
        if read > 0 {
            parts.append(Plural.czech(read, one: "prošlý", few: "prošlé", many: "prošlých"))
        }
        if findings > 0 {
            parts.append(Plural.czech(findings, one: "nález", few: "nálezy", many: "nálezů"))
        }
        if threads > 0 {
            parts.append(Plural.czech(threads, one: "vlákno", few: "vlákna", many: "vláken"))
        }
        return parts.joined(separator: " · ")
    }

    /// Nápověda pod kurzorem: `Encryptor.php · +31 −12 · 1 nález · 1 vlákno · neprošlo`.
    ///
    /// Stav značky je **vždycky poslední a vždycky tam je**: pás je zároveň ukazatel, kolik
    /// zbývá, takže „četl jsem to?“ je u segmentu ta druhá otázka v pořadí. Nálezy a vlákna se
    /// vynechávají, když žádné nejsou — jinak by nápověda u čistého souboru byla ze dvou třetin
    /// o nulách.
    static func mapTooltip(of segment: PullRequestMapSegment) -> String {
        var parts = [segment.name, "+\(segment.additions) −\(segment.deletions)"]
        if segment.findings > 0 {
            parts.append(Plural.czech(segment.findings, one: "nález", few: "nálezy", many: "nálezů"))
        }
        if !segment.threads.isEmpty {
            parts.append(Plural.czech(
                segment.threads.count,
                one: "vlákno",
                few: "vlákna",
                many: "vláken"
            ))
        }
        parts.append(mapReadLabel(of: segment.readState))
        return parts.joined(separator: " · ")
    }

    /// Jak se stav značky pojmenuje v nápovědě. Vyčerpávající `switch`, ne `isRead`: čtvrtý stav
    /// značky by jinak mlčky vyšel jako `neprošlo`.
    static func mapReadLabel(of state: FileReviewState) -> String {
        switch state {
        case .unread: "neprošlo"
        case .read: "prošlo"
        case .changed: "změněno od prošlého"
        }
    }

    /// Kreslí se popisek vpravo od pásu? (#501)
    ///
    /// **Popisek ustupuje první**, a je to tatáž úvaha jako u `+X −Y` v pruhu záložek (#316): jeho
    /// čísla stojí i v hlavičce stromu (`7 souborů · 3 prošlé`) a v odznacích záložek, kdežto pás
    /// jinde není. Zúžit se přitom nedá — je to jedna řádka mono textu, a `7 sou…` neřekne nic
    /// a zabere totéž.
    ///
    /// **Práh je změřený, ne kulatý.** Popisek referenčního rozložení (sedm souborů, sekce 42)
    /// stojí ~230 bodů; v pohledu vedle sebe má detail 347 bodů, takže by na pás zbylo **73** —
    /// a v nich vyjde nejmenší segment na 4,5 bodu, tedy na hranici minima, a lock na 22. Se
    /// **180 body** má nejmenší 11 bodů a lock 55; to je pořád plocha, na kterou se dá kliknout.
    /// Pod tím je z pásu řada čárek, a to už není mapa.
    ///
    /// `nil` = šířka se ještě neměřila. Pak se popisek kreslí — tentýž vzorec jako
    /// `IncrementalDiffBar.layout(in:)`: neznámá šířka znamená plnou podobu, ne tu nejchudší.
    static func mapShowsSummary(
        available: Double?,
        label: Double,
        gap: Double = 12,
        minimumStrip: Double = 180
    ) -> Bool {
        guard let available, available > 0 else { return true }
        return available - label - gap >= minimumStrip
    }

    /// Šířky segmentů v bodech — **spočítané, ne vyjednané** (#220).
    ///
    /// Tři pravidla, a všechna se dají vyčerpat výčtem:
    ///
    /// 1. **Podíl z logaritmu.** `segment.weight / Σweight` z toho, co zbude po mezerách.
    /// 2. **Nejmíň `minimum`.** Segment o třech bodech je pořád vidět a dá se na něj kliknout;
    ///    segment o půl bodu je antialiasing. Co spadne pod minimum, dostane minimum a **vypadne
    ///    z dělení** — zbytek se pak přepočítá znovu, dokud se něco mění. Bez toho přepočtu by
    ///    součet přerostl dostupnou šířku právě u PR s jedním lockem a šesti drobnostmi, tedy
    ///    v tom případě, kvůli kterému logaritmus existuje.
    /// 3. **Součet je přesně dostupná šířka.** Pás jde od hrany k hraně; kdyby zbývalo, byl by
    ///    vpravo prázdný pruh, který se čte jako „a tady už nic není“.
    ///
    /// Když se ani minima nevejdou (padesát souborů v úzkém okně), dělí se **rovným dílem**:
    /// pás pak přestává mluvit o velikosti a zbývá z něj počet souborů a barvy, což je pořád
    /// víc než nic. Zúžit ho pod tuhle hranici jinak nejde — segmenty se zahodit nesmí, protože
    /// zmizelý soubor je horší než tenký.
    static func mapWidths(
        of segments: [PullRequestMapSegment],
        in total: Double,
        spacing: Double = 2,
        minimum: Double = mapSegmentMinimum
    ) -> [Double] {
        guard !segments.isEmpty else { return [] }
        let count = segments.count
        let available = total - spacing * Double(count - 1)
        guard available > 0 else { return Array(repeating: 0, count: count) }
        guard available >= minimum * Double(count) else {
            return Array(repeating: available / Double(count), count: count)
        }

        var widths = Array(repeating: 0.0, count: count)
        var open = Array(segments.indices)
        var pool = available
        while !open.isEmpty {
            let shares = mapShares(of: segments, at: open)
            let squeezed = zip(open, shares).filter { pool * $1 < minimum }.map(\.0)
            guard !squeezed.isEmpty else {
                for (index, share) in zip(open, shares) { widths[index] = pool * share }
                break
            }
            for index in squeezed {
                widths[index] = minimum
                pool -= minimum
            }
            open.removeAll { squeezed.contains($0) }
        }
        return widths
    }

    /// Podíly vybraných segmentů, součtem `1`. Samé nulové váhy (samé binárky) se dělí rovným
    /// dílem — dělení nulou by jinak vydalo `NaN` a pás by zmizel.
    private static func mapShares(of segments: [PullRequestMapSegment], at indices: [Int]) -> [Double] {
        let sum = indices.reduce(0.0) { $0 + segments[$1].weight }
        guard sum > 0 else { return indices.map { _ in 1 / Double(indices.count) } }
        return indices.map { segments[$0].weight / sum }
    }

    /// Který segment je **pod výřezem** — z rozsahů souborů a horní hrany výřezu.
    ///
    /// Je to `pinnedFileHeader` beze zbytku posunu: pás se ptá na **týž** soubor, jaký drží
    /// ukotvená hlavička v diffu a jaký zaškrtne `⌥V`. Dvě odpovědi na jednu otázku by
    /// znamenaly obrys u jiného souboru, než jehož jméno je nad kódem.
    static func mapCurrentSegment(extents: [ClosedRange<Double>], top: Double) -> Int? {
        pinnedFileHeader(files: extents, top: top, headerHeight: 0)?.index
    }

    /// Skok na předchozí nebo další soubor (`⌥←`/`⌥→`).
    ///
    /// **Nezacykluje se** — u posledního souboru `⌥→` nedělá nic. Pás je mapa diffu, tedy věc
    /// s koncem; skok z konce na začátek by v padesátisouborovém PR vypadal jako by se okno
    /// odscrollovalo samo.
    ///
    /// `nil` u prázdného pásu i tehdy, když se ještě neví, kde jsme — bez výchozího bodu by
    /// `⌥→` skočilo na první soubor a to je odpověď na jinou otázku než „další“.
    static func mapStep(from current: Int?, _ direction: NavigationStep, count: Int) -> Int? {
        guard count > 0, let current, (0..<count).contains(current) else { return nil }
        let next = direction == .forward ? current + 1 : current - 1
        return (0..<count).contains(next) ? next : nil
    }
}
