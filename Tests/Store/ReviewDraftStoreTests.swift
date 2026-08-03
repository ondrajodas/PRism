import Foundation
import Testing

@testable import PRism

/// Proti skutečné dočasné složce, ne proti fake filesystému — stejná úvaha jako
/// u `ReviewStore`: ověřuje se to, na čem store stojí, tedy `Codable` cesta na disk a zpět
/// a chování `FileManageru`.
@Suite("ReviewDraftStore")
struct ReviewDraftStoreTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func store() -> ReviewDraftStore { ReviewDraftStore(layout: layout) }

    private var pr: PRIdentifier { PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42) }

    private func comment(
        path: String = "Cart.php",
        line: Int = 28,
        side: DiffSide = .right,
        body: String = "tady to spadne",
        origin: ReviewDraftComment.Origin = .own
    ) -> ReviewDraftComment {
        ReviewDraftComment(path: path, line: line, side: side, body: body, origin: origin)
    }

    private func draft(
        headSha: String = "abc123",
        body: String = "celkem to vypadá dobře",
        verdict: ReviewDraft.Verdict? = .comment,
        comments: [ReviewDraftComment]? = nil
    ) -> ReviewDraft {
        ReviewDraft(
            pullRequest: pr,
            headSha: headSha,
            body: body,
            verdict: verdict,
            comments: comments ?? [comment()]
        )
    }

    // MARK: - Uložení a restart

    /// To hlavní, kvůli čemu store existuje: rozdělané review přežije zavření aplikace.
    @Test("Draft přežije restart")
    func survivesARestart() async throws {
        // Jedna hodnota, ne dvě volání `draft()`: komentář si při každém vytvoření generuje
        // vlastní `UUID`, takže by se dvě „stejné“ instance nerovnaly.
        let saved = draft()
        try await store().save(saved)

        // Nový store nad tou samou složkou = to, co se stane po restartu.
        let loaded = try await store().load(for: pr)

        #expect(loaded == saved)
    }

    @Test("Uložení podruhé draft přepíše, nezaloží druhý")
    func overwritesOnSecondSave() async throws {
        let store = store()
        try await store.save(draft(body: "první"))
        try await store.save(draft(body: "druhý"))

        #expect(try await store.load(for: pr)?.body == "druhý")
        #expect(try await store.load().drafts.count == 1)
    }

    @Test("Draft, který nikdo nezaložil, je nil")
    func returnsNilWithoutADraft() async throws {
        #expect(try await store().load(for: pr) == nil)
    }

    @Test("Prázdná složka není chyba")
    func readsAnEmptyCache() async throws {
        let loaded = try await store().load()

        #expect(loaded.drafts.isEmpty)
        #expect(loaded.unreadable == 0)
    }

    /// Bez toho by v cache zůstal soubor po každém PR, které si někdo jen otevřel — a
    /// „draft existuje“ by přestalo znamenat „je co poslat“.
    @Test("Prázdný draft se smaže, ne uloží")
    func deletesAnEmptyDraft() async throws {
        let store = store()
        try await store.save(draft())
        #expect(try await store.load(for: pr) != nil)

        try await store.save(ReviewDraft(pullRequest: pr, headSha: "abc123"))

        #expect(try await store.load(for: pr) == nil)
        #expect(!FileManager.default.fileExists(
            atPath: layout.draftFile(for: pr).path(percentEncoded: false)
        ))
    }

    // MARK: - Víc PR

    @Test("Drafty různých PR se nepletou")
    func keepsDraftsOfDifferentPullRequestsApart() async throws {
        let other = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 43)
        let store = store()

        try await store.save(draft(body: "čtyřicet dva"))
        try await store.save(ReviewDraft(pullRequest: other, headSha: "def", body: "čtyřicet tři"))

        #expect(try await store.load(for: pr)?.body == "čtyřicet dva")
        #expect(try await store.load(for: other)?.body == "čtyřicet tři")
        #expect(try await store.load().drafts.count == 2)
    }

    /// Pořadí z `FileManageru` zaručené není a testy se na náhodu spoléhat nemají.
    ///
    /// Čísla jsou schválně přes desítku: **řetězcově** by `#10` vyšlo před `#2`, což je past,
    /// do které řazení podle `description` spadlo.
    @Test("Výpis řadí čísla PR číselně, ne řetězcově")
    func sortsTheListingNumerically() async throws {
        let store = store()
        for number in [10, 2, 42, 1] {
            let id = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: number)
            try await store.save(ReviewDraft(pullRequest: id, headSha: "x", body: "tělo"))
        }

        let drafts = try await store.load().drafts

        #expect(drafts.map(\.pullRequest.number) == [1, 2, 10, 42])
    }

    @Test("Výpis řadí i podle repa")
    func sortsTheListingByRepository() async throws {
        let store = store()
        for repo in [RepoID(owner: "cli", name: "go-gh"), RepoID(owner: "cli", name: "cli")] {
            let id = PRIdentifier(repo: repo, number: 1)
            try await store.save(ReviewDraft(pullRequest: id, headSha: "x", body: "tělo"))
        }

        let drafts = try await store.load().drafts

        #expect(drafts.map(\.pullRequest.repo.name) == ["cli", "go-gh"])
    }

    /// Výpis, ve kterém je draft, co se přes `load(for:)` nedá otevřít, je horší než
    /// počítadlo, které o anomálii aspoň řekne.
    @Test("Draft v cizím souboru se do výpisu nedostane a spočítá se")
    func skipsAMisplacedDraftInTheListing() async throws {
        let other = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 99)
        let url = layout.draftFile(for: pr)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(ReviewDraft(pullRequest: other, headSha: "x", body: "špatné místo"))
            .write(to: url)

        let loaded = try await store().load()

        #expect(loaded.drafts.isEmpty)
        #expect(loaded.unreadable == 1)
    }

    // MARK: - Rozbité soubory

    /// Rozbitý soubor znamená ztracenou **ručně psanou** práci a nesmí se tvářit jako
    /// „nic tu rozdělané nebylo“.
    @Test("Nečitelné soubory se ve výpisu počítají")
    func countsUnreadableFiles() async throws {
        let store = store()
        try await store.save(draft())
        let broken = layout.drafts(of: pr.repo).appending(path: "99.json")
        try Data("{ tohle není draft".utf8).write(to: broken)

        let loaded = try await store.load()

        #expect(loaded.drafts.count == 1)
        #expect(loaded.unreadable == 1)
    }

    /// Tichá nula by znamenala, že rozepsané review vypadá jako neexistující — a člověk by
    /// ho psal znovu, aniž by věděl, že mu na disku leží rozbitý.
    @Test("Nečitelný draft konkrétního PR vyhodí chybu, nevrátí nil")
    func throwsOnAnUnreadableDraft() async throws {
        let url = layout.draftFile(for: pr)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{ rozbité".utf8).write(to: url)

        await #expect(throws: (any Error).self) { try await store().load(for: pr) }
    }

    /// Jméno souboru není pravda — tou je `pullRequest` uvnitř. Rozchod by znamenal, že se
    /// cizí rozdělané review nabídne k odeslání na tenhle PR.
    @Test("Draft cizího PR uvnitř souboru se odmítne")
    func rejectsADraftOfADifferentPullRequest() async throws {
        let other = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 99)
        let url = layout.draftFile(for: pr)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(ReviewDraft(pullRequest: other, headSha: "x", body: "cizí"))
            .write(to: url)

        await #expect(throws: ReviewDraftStoreError.self) { try await store().load(for: pr) }
    }

    // MARK: - Mazání

    @Test("Zahození draft smaže a jde zmáčknout dvakrát")
    func deletesIdempotently() async throws {
        let store = store()
        try await store.save(draft())

        try await store.delete(for: pr)
        try await store.delete(for: pr)

        #expect(try await store.load(for: pr) == nil)
    }

    @Test("Zahození draftu, který není, není chyba")
    func deletesNothingWithoutADraft() async throws {
        try await store().delete(for: pr)
    }

    // MARK: - Rozvržení cache

    /// Draft je ručně psaná práce, kterou by rozpočet na místo neměl smazat. Eviction chodí
    /// jen po `repos/` a `worktrees/`, takže je `drafts/` mimo její dosah — a tenhle test to
    /// drží, i kdyby někdo eviction rozšířil.
    @Test("Drafty leží mimo složky, po kterých chodí eviction")
    func staysOutsideEvictionReach() {
        let path = layout.draftFile(for: pr).path(percentEncoded: false)

        #expect(!path.hasPrefix(layout.repositories.path(percentEncoded: false)))
        #expect(!path.hasPrefix(layout.worktrees.path(percentEncoded: false)))
        #expect(path.hasPrefix(layout.drafts.path(percentEncoded: false)))
    }

    /// Bez `headSha` v názvu, na rozdíl od nálezů: draft je jeden na PR a nový commit ho
    /// nezahazuje.
    @Test("Cesta k draftu je zanořená pod repem a bez sha")
    func nestsTheDraftUnderTheRepository() {
        let path = layout.draftFile(for: pr).path(percentEncoded: false)

        #expect(path.hasSuffix("drafts/cli/cli/42.json"))
    }
}
