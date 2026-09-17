import Foundation

/// Persistence výsledků review — jeden JSON soubor na `(repo, PR, headSha)`.
///
/// Aktor schválně: uložení je čtení, změna a zápis téhož souboru, a dva skilly nad jedním
/// commitem doběhnou klidně naráz. Bez serializace by si výsledky vzájemně přepsaly.
///
/// SwiftData ani databáze ne — dat je málo, přístupový vzor je souborový a čistý `Codable`
/// drží uložený tvar pod kontrolou modelů.
actor ReviewStore {
    /// Jak dlouho se drží výsledky PR, který zmizel ze sledovaného seznamu. Do konfigurace
    /// se přesune s #23.
    static let defaultRetention: TimeInterval = 30 * 24 * 60 * 60

    /// Co se našlo na disku.
    struct Loaded: Sendable, Equatable {
        var records: [ReviewRecord] = []
        /// Kolik souborů se nepodařilo přečíst.
        ///
        /// Nula není samozřejmost a mlčet o tom nejde: rozbitý soubor znamená ztracené
        /// nálezy, a ty se v UI nesmí tvářit jako „review neběželo“.
        var unreadable = 0
    }

    private let layout: CacheLayout
    private let retention: TimeInterval
    private let time: any TimeSource
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        layout: CacheLayout = .applicationSupport,
        retention: TimeInterval = ReviewStore.defaultRetention,
        time: any TimeSource = SystemTimeSource()
    ) {
        self.layout = layout
        self.retention = retention
        self.time = time

        // ISO 8601 a odsazení stojí pár bajtů navíc a vrací se to při prvním pohledu do
        // souboru. Je to osobní nástroj — data se čtou i očima.
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Uloží doběhlý běh a vrátí záznam, jak po něm vypadá.
    ///
    /// Zároveň se tím aplikace dozvěděla aktuální `headSha`, takže starší záznamy téhož PR
    /// zestárnou. Kdyby se to nechalo jen na `markCurrent`, stačilo by ho jednou zapomenout
    /// zavolat a nálezy proti neexistujícímu kódu by se ukazovaly jako platné.
    ///
    /// - Parameter run: **jen běžné review** (#150). Kontrola nálezů tudy neprojde: její výsledek
    ///   je tvrzení o nálezech, ne nález, takže by se v `runs` tvářila jako reviewer — přepsala by
    ///   běh téhož skillu (`replace(_:)`), přidala si chip a její „nálezy“ (`ReviewRun.findings`
    ///   nad prázdným seznamem) by se počítaly do návrhu verdiktu. Kontrola má vlastní cestu,
    ///   `saveRecheck(_:for:at:)`.
    @discardableResult
    func save(_ run: ReviewRun, timeline: StoredTimeline? = nil) throws -> ReviewRecord {
        guard run.key.kind == .review else {
            throw ReviewStoreError.notAReviewRun(kind: run.key.kind)
        }
        let pullRequest = run.key.pullRequest
        try markStale(everythingBut: run.key.headSha, of: pullRequest)

        let url = layout.reviewFile(for: pullRequest, at: run.key.headSha)
        // Odkaz se bere jako **prázdné místo**, ne jako záznam (#106): číst cizí soubor
        // nechceme, a zápis je atomický, takže se odkaz vzápětí nahradí naším souborem —
        // cíl zůstane netknutý. Nálezy se tím neztrácejí: záznam pro tenhle commit stejně
        // žádný náš neexistuje.
        var record = (CacheFile.refusal(for: url, in: layout) == nil ? try? read(at: url) : nil)
            ?? ReviewRecord(pullRequest: pullRequest, headSha: run.key.headSha)
        // Osa se **nepřepisuje na nic**: překlad nálezů (#94) ukládá týž běh podruhé a osu
        // s sebou nenese, takže by ji jinak druhý zápis smazal.
        let stored = timeline ?? record.runs.first { $0.skillID == run.key.skillID }?.timeline
        record.replace(StoredReviewRun(run, finishedAt: time.now, timeline: stored))
        record.isStale = false
        // Běh nad PR je důkaz, že o něj pořád je zájem.
        record.closedAt = nil

        try write(record, to: url)
        return record
    }

    /// Zahodí uložený záznam jednoho `(PR, headSha)`.
    ///
    /// Maže se **jen ten viditelný commit**, ne historie PR: zastaralé záznamy jsou záznam
    /// toho, co kdy platilo, a specifikace je schválně nechává. Chybějící soubor není chyba
    /// — tlačítko se dá zmáčknout dvakrát a druhé zmáčknutí nemá nic položit.
    ///
    /// Mimo cache se nemaže. Cesta se skládá z `CacheLayout`, takže by ven vést nemohla,
    /// ale tvrdá podmínka „nikdy nesahat na uživatelovy soubory“ nemá viset na tom, že si
    /// to někdo pamatuje — kontrola je jedno volání a je stejná jako u eviction.
    func delete(for pullRequest: PRIdentifier, at headSha: String) throws {
        let url = layout.reviewFile(for: pullRequest, at: headSha)
        guard CacheFile.isInsideCache(url, in: layout),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Uloží kontrolu nálezů (#150) a vrátí záznam, jak po ní vypadá.
    ///
    /// Zapisuje se do záznamu **těch nálezů**, na které se kontrola ptala — `headSha` je proto
    /// commit, na kterém nálezy vznikly, ne hlava, proti které se kontrolovalo (tu nese
    /// `StoredRecheck.againstHeadSha`).
    ///
    /// Chybějící soubor je **chyba**, ne prázdný záznam, a je to tatáž úvaha jako u odmítnutí:
    /// nálezy, na které se kontrola ptala, byly vidět v okně, takže na disku být musí — a nový
    /// prázdný záznam by je všechny zahodil. Kontrola sama by v něm navíc mluvila o nálezech,
    /// které v něm nejsou.
    ///
    /// `isStale` se **nesrovnává**, na rozdíl od `save`: nálezy dál patří staršímu commitu a to,
    /// že se na ně někdo ptal, na tom nic nemění.
    @discardableResult
    func saveRecheck(
        _ recheck: StoredRecheck,
        for pullRequest: PRIdentifier,
        at headSha: String
    ) throws -> ReviewRecord {
        let url = layout.reviewFile(for: pullRequest, at: headSha)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw ReviewStoreError.recordNotFound(pullRequest, headSha: headSha)
        }
        // Odkaz **i cesta ven** jsou totéž co chybějící soubor: **náš** záznam tam není a přečíst
        // cizí kvůli zápisu do něj je to poslední, co chceme (#106, hranice doplněna u #458).
        guard CacheFile.refusal(for: url, in: layout) == nil else {
            throw ReviewStoreError.recordNotFound(pullRequest, headSha: headSha)
        }

        var record = try read(at: url)
        guard record.pullRequest == pullRequest else {
            throw ReviewStoreError.recordNotFound(pullRequest, headSha: headSha)
        }
        record.recheck = recheck
        try write(record, to: url)
        return record
    }

    /// Uloží razítko návrhu review (#520) — nebo ho `nil`em **smaže** (`Zahodit návrh`).
    ///
    /// Zapisuje se do záznamu **těch nálezů**, ze kterých návrh vznikl, tedy stejně jako
    /// u kontroly: `headSha` je commit, na kterém nálezy stojí.
    ///
    /// Chybějící soubor je **chyba**, ne prázdný záznam, a je to tatáž úvaha jako u kontroly
    /// a u odmítnutí: nálezy, ze kterých se návrh složil, byly vidět v okně, takže na disku být
    /// musí — a nový prázdný záznam by je všechny zahodil.
    ///
    /// **Jedna metoda na zápis i na smazání**, ne dvě: obojí je tentýž zápis jedné hodnoty
    /// a dvě cesty k ní by znamenaly dvě místa, kde se dá zapomenout na hranici cache.
    @discardableResult
    func saveAutoDraft(
        _ stamp: StoredAutoDraft?,
        for pullRequest: PRIdentifier,
        at headSha: String
    ) throws -> ReviewRecord {
        let url = layout.reviewFile(for: pullRequest, at: headSha)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw ReviewStoreError.recordNotFound(pullRequest, headSha: headSha)
        }
        // Odkaz **i cesta ven** jsou totéž co chybějící soubor (#106, hranice doplněna u #458) —
        // tvrdá podmínka č. 3 platí i pro zápis jedné hodnoty do cizího souboru.
        guard CacheFile.refusal(for: url, in: layout) == nil else {
            throw ReviewStoreError.recordNotFound(pullRequest, headSha: headSha)
        }

        var record = try read(at: url)
        guard record.pullRequest == pullRequest else {
            throw ReviewStoreError.recordNotFound(pullRequest, headSha: headSha)
        }
        record.autoDraft = stamp
        try write(record, to: url)
        return record
    }

    /// Odmítne nález jako falešně pozitivní (#113) a vrátí záznam, jak po tom vypadá.
    ///
    /// Soubor se hledá podle `finding.headSha`, ne podle parametru: nález si commit nese sám
    /// (tvrdá podmínka č. 5) a druhá cesta k témuž údaji je druhé místo, kde se dá minout.
    ///
    /// Aktor to serializuje ze stejného důvodu jako `save`: dva doběhlé skilly a kliknutí
    /// v okně si nesmí přepsat soubor.
    @discardableResult
    func dismiss(
        _ finding: Finding,
        as reason: FindingDismissal.Reason,
        in pullRequest: PRIdentifier
    ) throws -> ReviewRecord {
        try setDismissal(
            FindingDismissal(reason: reason, dismissedAt: time.now),
            of: finding,
            in: pullRequest
        )
    }

    /// Vrátí nález mezi platné.
    @discardableResult
    func restore(_ finding: Finding, in pullRequest: PRIdentifier) throws -> ReviewRecord {
        try setDismissal(nil, of: finding, in: pullRequest)
    }

    /// Zápis odmítnutí. Chybějící soubor je **chyba**, ne prázdný záznam: nález, který je
    /// vidět v okně, musí na disku být — a kdyby se místo toho založil nový záznam bez běhů,
    /// zmizely by z okna všechny ostatní nálezy.
    ///
    /// Rozbitý soubor hlásí **svoji** chybu, ne `recordNotFound`: `try?` nad čtením by
    /// z nečitelného souboru udělal chybějící a hláška by posílala hledat něco jiného, než
    /// se stalo. Cizí PR uvnitř souboru je naopak `recordNotFound` — záznam **tohohle** PR
    /// tam opravdu není a dělat se s tím dá totéž.
    private func setDismissal(
        _ dismissal: FindingDismissal?,
        of finding: Finding,
        in pullRequest: PRIdentifier
    ) throws -> ReviewRecord {
        let url = layout.reviewFile(for: pullRequest, at: finding.headSha)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw ReviewStoreError.recordNotFound(pullRequest, headSha: finding.headSha)
        }
        // Odkaz **i cesta ven** jsou totéž co chybějící soubor: **náš** záznam tam není a přečíst
        // cizí kvůli tomu, abychom do něj zapsali odmítnutí, je to poslední, co chceme (#106,
        // hranice doplněna u #458).
        guard CacheFile.refusal(for: url, in: layout) == nil else {
            throw ReviewStoreError.recordNotFound(pullRequest, headSha: finding.headSha)
        }

        var record = try read(at: url)
        guard record.pullRequest == pullRequest else {
            throw ReviewStoreError.recordNotFound(pullRequest, headSha: finding.headSha)
        }
        record.setDismissal(dismissal, of: finding)
        try write(record, to: url)
        return record
    }

    /// Záznam pro jeden commit, pokud nějaký je (#97).
    ///
    /// Cílené čtení podle cesty, ne výpis: dotažení po pádu se ptá na konkrétní `(PR, sha)`
    /// a projít kvůli tomu celou historii repa by bylo drahé. Chybějící ani nečitelný soubor
    /// není chyba — volající z toho vyvodí „záznam není“, a to je pro obě odpovědi správně.
    /// Odkaz se bere jako **chybějící záznam** (#106): číst soubor mimo cache nechceme ani
    /// tady. Je to třetí cílené čtení podle cesty vedle `save` a `setDismissal` a kontrola
    /// v něm chybět nesmí jen proto, že přibylo později.
    func record(for pullRequest: PRIdentifier, at headSha: String) -> ReviewRecord? {
        let url = layout.reviewFile(for: pullRequest, at: headSha)
        guard CacheFile.refusal(for: url, in: layout) == nil else { return nil }
        guard let record = try? read(at: url), record.pullRequest == pullRequest else { return nil }
        return record
    }

    /// PR má tenhle head commit. Všechno starší se označí jako zastaralé.
    ///
    /// Volá se, jakmile se dotáhne detail PR — tedy v jediné chvíli, kdy aplikace aktuální
    /// `headSha` zná.
    func markCurrent(_ headSha: String, of pullRequest: PRIdentifier) throws {
        try markStale(everythingBut: headSha, of: pullRequest)
    }

    /// Všechno, co na disku je. Volá se při startu.
    func load() throws -> Loaded {
        var loaded = Loaded()
        let found = recordFiles(in: layout.reviews)
        // Odkaz se do `unreadable` počítá jako rozbitý soubor: obojí znamená, že v cache něco
        // leží a nálezy z toho nejsou — a v okně se to nesmí tvářit jako „review neběželo“.
        loaded.unreadable += found.symlinks
        for url in found.files {
            guard let record = try? read(at: url) else {
                loaded.unreadable += 1
                continue
            }
            loaded.records.append(record)
        }
        // Pořadí z `FileManageru` není zaručené a UI ani testy se na náhodu spoléhat nemají.
        // Číslo PR se srovnává číselně (`PRIdentifier: Comparable`) — podle `description`
        // by `#10` vyšlo před `#2`.
        loaded.records.sort {
            ($0.pullRequest, $0.headSha) < ($1.pullRequest, $1.headSha)
        }
        return loaded
    }

    /// Úklid: záznamy PR, které už ve sledovaném seznamu nejsou, po lhůtě zmizí.
    ///
    /// - Parameter openPullRequests: co je teď v seznamu. Pouštět to smí jen po **úspěšném**
    ///   tiku pollingu — po výpadku sítě je seznam prázdný a úklid by z něj vyvodil, že
    ///   zavřené je všechno.
    func cleanUp(openPullRequests: [PRIdentifier]) throws {
        let open = Set(openPullRequests)
        let now = time.now

        // Odkaz se sem nedostane, takže se nepřečte ani nesmaže cizí soubor. Nepočítá se —
        // úklid nemá kam počet ohlásit a `load()` ho při startu spočítá tak jako tak.
        for url in recordFiles(in: layout.reviews).files {
            guard var record = try? read(at: url) else { continue }

            guard !open.contains(record.pullRequest) else {
                // PR se vrátil mezi sledované — lhůta se ruší, ne jen pozastavuje.
                guard record.closedAt != nil else { continue }
                record.closedAt = nil
                try write(record, to: url)
                continue
            }

            guard let closedAt = record.closedAt else {
                record.closedAt = now
                try write(record, to: url)
                continue
            }

            // Mimo cache se nemaže. Výpis z disku sem symlinkem ven nedostane — `enumerator`
            // do odkazovaných složek nesestupuje —, ale tvrdá podmínka „nikdy nesahat na
            // uživatelovy soubory“ nemá viset na tomhle detailu `FileManageru`. Radši
            // nesmazat než smazat cizí.
            if now.timeIntervalSince(closedAt) >= retention, CacheFile.isInsideCache(url, in: layout) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func markStale(everythingBut headSha: String, of pullRequest: PRIdentifier) throws {
        let files = recordFiles(
            in: layout.reviews(of: pullRequest.repo),
            named: "\(pullRequest.number)-"
        ).files
        for url in files {
            guard var record = try? read(at: url), record.pullRequest == pullRequest else {
                continue
            }
            let stale = record.headSha != headSha
            guard record.isStale != stale else { continue }
            record.isStale = stale
            try write(record, to: url)
        }
    }

    private func read(at url: URL) throws -> ReviewRecord {
        try decoder.decode(ReviewRecord.self, from: try Data(contentsOf: url))
    }

    /// Zápis je atomický: půlka souboru je horší než žádný, protože se od celého nedá
    /// odlišit jinak než tím, že se nepodaří dekódovat.
    ///
    /// **Hranice cache se ověřuje i tady** (#458): do té doby ji měl v tomhle storu jen `delete`,
    /// takže zápis by šel symlinkem v rodičovské složce ven. Odkaz na **samotném souboru** se
    /// neodmítá schválně — `save` ho výš bere jako prázdné místo a atomický zápis ho nahradí naším
    /// souborem, aniž by sáhl na cíl; to je zapsané rozhodnutí z #106, ne mezera.
    private func write(_ record: ReviewRecord, to url: URL) throws {
        guard CacheFile.isInsideCache(url, in: layout) else {
            throw CheckoutError.cacheUnavailable(
                "Cesta \(url.path(percentEncoded: false)) vede mimo cache aplikace."
            )
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(record).write(to: url, options: .atomic)
    }

    /// Soubory se záznamy. Chybějící složka není chyba — do prvního review žádná neexistuje.
    ///
    /// `prefix` odfiltruje cizí PR **ještě před čtením**: jméno souboru začíná číslem PR,
    /// takže se ušetří dekódování celé historie repa při každém uložení. Na jméno se přitom
    /// nespoléhá jako na pravdu — tou zůstává `pullRequest` uvnitř souboru, který si volající
    /// stejně ověří. `42-` navíc nesedí na `421-`, protože pomlčka je součást prefixu.
    ///
    /// **Symlinky se přeskakují a počítají** (#106). `enumerator` do odkazovaných složek
    /// nesestupuje, ale odkaz na **soubor** do výpisu dá — a ten by se přečetl mimo cache
    /// (změřeno u #65). `layout.contains` to nezachytí, protože rozbaluje symlinky na obou
    /// stranách, takže cíl vyjde rovný cíli; odkaz se musí odmítnout výslovně. Počítá se,
    /// protože něco v cache leží a nedá se z toho záznam udělat — tiché přeskočení by
    /// anomálii schovalo. Stejně to dělá `ReviewDraftStore` od #65.
    private func recordFiles(
        in directory: URL,
        named prefix: String? = nil
    ) -> (files: [URL], symlinks: Int) {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey]
        ) else { return ([], 0) }

        // Po prvcích, ne `allObjects`: ten vylistuje celý strom do paměti, včetně souborů,
        // které nás nezajímají.
        var files: [URL] = []
        var symlinks = 0
        for case let url as URL in enumerator where url.pathExtension == "json" {
            guard prefix.map(url.lastPathComponent.hasPrefix) ?? true else { continue }
            if layout.isSymbolicLink(url) {
                symlinks += 1
                continue
            }
            files.append(url)
        }
        return (files, symlinks)
    }
}

/// Chyby, které store hlásí sám za sebe — všechno ostatní jsou chyby `FileManageru`.
enum ReviewStoreError: LocalizedError, Equatable {
    /// Záznam, do kterého se má zapsat, na disku není.
    case recordNotFound(PRIdentifier, headSha: String)
    /// Do `runs` se pokusil zapsat běh, který není review (#150).
    ///
    /// Není to chyba uživatele, ale chyba v kódu — a hlásí se právě proto, že tichý zápis by
    /// z kontroly nálezů udělal reviewera se nálezy, které nikdy nenahlásila.
    case notAReviewRun(kind: ReviewRunKind)

    var errorDescription: String? {
        switch self {
        case .recordNotFound(let pullRequest, let headSha):
            "Uložené nálezy pro \(pullRequest) na commitu \(headSha.prefix(7)) se nenašly. "
                + "Zkus review pustit znovu."
        case .notAReviewRun(let kind):
            "Běh druhu \(kind.rawValue) se neukládá jako review."
        }
    }
}
