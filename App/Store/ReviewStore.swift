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
    @discardableResult
    func save(_ run: ReviewRun) throws -> ReviewRecord {
        let pullRequest = run.key.pullRequest
        try markStale(everythingBut: run.key.headSha, of: pullRequest)

        let url = layout.reviewFile(for: pullRequest, at: run.key.headSha)
        var record = (try? read(at: url))
            ?? ReviewRecord(pullRequest: pullRequest, headSha: run.key.headSha)
        record.replace(StoredReviewRun(run, finishedAt: time.now))
        record.isStale = false
        // Běh nad PR je důkaz, že o něj pořád je zájem.
        record.closedAt = nil

        try write(record, to: url)
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
        for url in recordFiles(in: layout.reviews) {
            guard let record = try? read(at: url) else {
                loaded.unreadable += 1
                continue
            }
            loaded.records.append(record)
        }
        // Pořadí z `FileManageru` není zaručené a UI ani testy se na náhodu spoléhat nemají.
        loaded.records.sort { ($0.pullRequest.description, $0.headSha) < ($1.pullRequest.description, $1.headSha) }
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

        for url in recordFiles(in: layout.reviews) {
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

            if now.timeIntervalSince(closedAt) >= retention {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func markStale(everythingBut headSha: String, of pullRequest: PRIdentifier) throws {
        for url in recordFiles(in: layout.reviews(of: pullRequest.repo)) {
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
    private func write(_ record: ReviewRecord, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(record).write(to: url, options: .atomic)
    }

    /// Chybějící složka není chyba — do prvního review žádná neexistuje.
    private func recordFiles(in directory: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        return (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "json" }
    }
}
