import Foundation

/// Mapa PR pro **řádek fronty** (#502) — mini pás místo spektra reviewerů.
///
/// **Je to tatáž mapa, jakou kreslí pás pod hlavičkou** (#501), jen vykreslená na 110 × 6 bodů:
/// skládá ji `Policy.pullRequestMap`, tedy jedno místo. Dvě funkce by znamenaly, že řádek
/// a hlavička téhož PR tvrdí každý něco jiného — a rozdíl by se poznal jedině tak, že by si
/// jeden všiml obojího naráz.
///
/// Stav (`queueMapCache`) zůstává v `AppStore.swift` — dělí se metody, ne data.
extension AppStore {
    /// Mini pás do řádku fronty. `nil` = **pás se nekreslí**, a jsou pro to dva důvody:
    ///
    /// 1. **Na PR nic neběželo.** Barva segmentu je závažnost, takže pás bez běhu by byl celý
    ///    neutrální — tedy k nerozeznání od PR, na kterém review doběhlo a nic nenašlo. Tatáž
    ///    úvaha, kvůli které se do #502 nekreslilo spektrum u řádku bez běhu: prázdný obdélník
    ///    se tváří jako údaj.
    /// 2. **Diff téhle aplikace ještě neviděla.** Pás stojí na seznamu souborů a jejich objemu,
    ///    a to je jediný vstup, který se **ve frontě nemá odkud vzít**: diff se dotahuje při
    ///    otevření PR (#306), kdežto polling přinese jen shrnutí. Dotáhnout ho pro každý řádek
    ///    by bylo N volání `gh` na tik — zamítnutá cesta (naposledy u #515). Řádek, u kterého
    ///    se pás nekreslí, proto vypadá jako řádek do #502 bez spektra: odznak stavu, nic víc.
    ///
    /// **Vlákna se do pásu v řádku nedostanou, a je to důsledek téhož** (#502): zakotvená vlákna
    /// jsou v konverzaci, a ta se — stejně jako diff — tahá až v detailu. Čárku vlákna by tedy pás
    /// v řádku uměl nakreslit jedině u PR, který je zrovna otevřený, takže by její chybění
    /// neznamenalo „žádná diskuze“, ale „nevíme“. Nekreslí se proto **nikdy**; kdo chce vidět,
    /// kde se diskutuje, otevře PR. Popisek (`map.summary`) tím o vláknech mlčí, ne lže —
    /// `Policy.mapSummary` části bez obsahu vynechává.
    func queueMap(for pr: PRIdentifier) -> PullRequestMap? {
        // Pořadí je schválně tohle: záznam je v paměti vždycky, kdežto `diff.files` je pole
        // o stovkách prvků. Nejdřív tedy ta levná otázka.
        guard let record = reviewRecords[pr], !record.runs.isEmpty else { return nil }
        guard case .loaded(let diff, let updatedAt) = diffStates[pr], !diff.isEmpty else { return nil }

        // Blokující sada je **per repo**, stejně jako u `queueRow(for:)` a `reviewState(for:)`.
        // Jinak by řádek kreslil červený segment nad nálezem, který odznak vedle něj za blokující
        // nepovažuje.
        let categories = resolved(for: pr.repo).blockingCategories
        // **Platné nálezy záznamu**, ne `visibleFindings` z detailu: řádek nemá zúžení podle
        // revieweera ani kurzor. Odmítnutí se tím vyřídí (`activeFindings`), takže se skupinám
        // už nepředává — `group.activeFindings` je pak celá skupina.
        let groups = Policy.groups(of: record.activeFindings)
        let readStates = readStates[pr] ?? [:]
        let stamp = QueueMapStamp(
            diff: updatedAt,
            files: diff.files.count,
            findings: groups.flatMap { $0.findings.map(QueueMapStamp.Mark.init) },
            readStates: readStates,
            categories: categories
        )
        if let cached = queueMapCache[pr], cached.stamp == stamp { return cached.map }

        let map = Policy.pullRequestMap(
            files: diff.files,
            findings: groups,
            threads: [],
            readStates: readStates,
            categories: categories
        )
        queueMapCache[pr] = (stamp, map)
        return map
    }
}

/// Otisk vstupů, ze kterých mapa v řádku vzniká (#502) — a tedy **to, co cache vyprazdňuje**.
///
/// Cache musí být (#224): pás se skládá při **každém** průchodu tělem seznamu, tedy po každém
/// tiku a u každého řádku, a je to práce lineární v počtu souborů (u `cli/cli#14320` sto padesát
/// osm). Klíčem ale nesmí být nic jiného než vstupy (#153), jinak by řádek kreslil pás jednoho PR
/// nad daty druhého — potichu.
///
/// **Otisk je proto úplný a přitom malý**: všechno, co `Policy.pullRequestMap` čte, je tady
/// zastoupené hodnotou, jejíž velikost roste s počtem **nálezů a značek**, ne souborů.
struct QueueMapStamp: Hashable {
    /// Identita diffu. `updatedAt` je smlouva, na které stojí i cache diffu samotného
    /// (`AppStore.hasCurrentDiff`): jiný obsah znamená jiné razítko, protože `loadDiff` jinak
    /// zapsat nemůže. Počet souborů je k tomu kontrola navíc — zdarma, a rozpozná
    /// i diff, který by se pod týmž razítkem přerozparsoval.
    let diff: Date
    let files: Int
    /// Z každého platného nálezu jen to, co pás doopravdy čte. **Celé skupiny sem nepatří**:
    /// `FindingGroup` nese texty nálezů, takže by se otisk srovnával po znacích — tedy prací
    /// srovnatelnou s tou, které se cachí vyhýbáme.
    let findings: [Mark]
    /// Značky `Prošlo` (#500) — tlumení segmentu. Klíčů je tolik, kolik je **značek**, ne souborů
    /// (`Policy.fileReviewStates` vrací jen to, co značku má).
    let readStates: [String: FileReviewState]
    /// Blokující kategorie z konfigurace. Mění barvu segmentu, aniž by se dotkla nálezů — bez
    /// nich by přepnutí v nastavení nechalo v řádku pás z minula.
    let categories: Set<String>

    /// Co z nálezu rozhoduje o pásu: **kde** je (soubor a řádek, z toho je skupina) a **jestli
    /// blokuje** (kategorie a verdikt, o zbytek se stará `Policy.isBlocking`).
    struct Mark: Hashable {
        let file: String?
        let line: Int?
        let category: String?
        let verdict: FindingVerdict?

        init(_ finding: Finding) {
            file = finding.file
            line = finding.line
            category = finding.category
            verdict = finding.verdict
        }
    }
}
