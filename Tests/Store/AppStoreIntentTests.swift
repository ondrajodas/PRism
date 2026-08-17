import Foundation
import Testing

@testable import PRism

/// Cesta zadání od popisu PR až k session (#120).
///
/// Nejcennější tvrzení jsou tři a všechna jsou o tom, co se **nestane**: review doběhne i tehdy,
/// když se zadání nepodaří připravit; prompt o souboru mlčí, dokud soubor není; a sada nástrojů
/// reviewera se tím nemění (tvrdá podmínka č. 2).
@Suite("AppStore — zadání pro reviewera (#120)")
@MainActor
struct AppStoreIntentTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let headSha = "aaaa1111"

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func detail(body: String) -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: headSha,
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open,
            body: body
        )
    }

    private func store(body: String, reviewer: FakeReviewRunner, skills: [String]? = nil) -> AppStore {
        var configuration = Configuration.standard
        if let skills { configuration.global.skills = skills }
        return AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail(body: body))),
            configuration: configuration,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            intents: ReviewIntentStore(layout: layout)
        )
    }

    private func run(_ store: AppStore) async {
        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }
    }

    // MARK: - Zadání dojede k session

    @Test("Popis PR se uloží vedle stromu a session dostane cestu k němu")
    func theDescriptionReachesTheSessionAsAFile() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(body: "Opravit součet v košíku.", reviewer: reviewer)

        await run(store)

        let request = try #require(reviewer.requests.first)
        let file = try #require(request.intentFile)
        #expect(file == layout.intentFile(for: pr, at: headSha))
        let saved = try String(contentsOf: file, encoding: .utf8)
        #expect(saved.contains("Opravit součet v košíku."))
        // A prompt nese **cestu**, ne obsah.
        let prompt = ClaudeCommand.prompt(for: request)
        #expect(prompt.contains(file.path(percentEncoded: false)))
        #expect(!prompt.contains("Opravit součet v košíku."))
        #expect(store.intentFailure == nil)
    }

    /// Odkaz na zadání z popisu se do souboru zapíše **jako odkaz**, i když se jeho text v téhle
    /// verzi nedotahuje: bez něj reviewer nemá čím pojmenovat, co v zadání chybí.
    @Test("Odkaz z popisu se do souboru zapíše")
    func writesTheLinkFromTheDescription() async throws {
        let body = try Fixture.text("gh/pr-body-linear.md")
        let reviewer = FakeReviewRunner()
        let store = store(body: body, reviewer: reviewer)

        await run(store)

        let file = try #require(reviewer.requests.first?.intentFile)
        let saved = try String(contentsOf: file, encoding: .utf8)
        #expect(saved.contains("- COR-1775 — https://linear.app/metalbear/issue/COR-1775"))
        #expect(saved.contains(ReviewIntentText.noIssueText))
    }

    /// Zadání se váže na `(PR, headSha)` a **sdílí ho všechny skilly jednoho review** — jinak by se
    /// psalo na každou session znovu a dvě session by si na jeden soubor sáhly naráz.
    @Test("Všechny skilly jednoho běhu dostanou tentýž soubor")
    func everySkillGetsTheSameFile() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(body: "Popis.", reviewer: reviewer, skills: ["code-review", "php-review"])

        await run(store)

        #expect(reviewer.requests.count == 2)
        #expect(Set(reviewer.requests.compactMap(\.intentFile)).count == 1)
    }

    // MARK: - Když není co uložit

    /// Prázdný popis znamená, že se **nezakládá nic** a věta se do promptu nepřipojí. Soubor se
    /// samými větami o tom, co v něm není, by reviewera poslal čtením za nic — a prompt nesmí
    /// ukazovat na soubor, který neexistuje.
    @Test("PR bez popisu zadání nedostane a prompt o něm mlčí")
    func aPullRequestWithoutADescriptionGetsNoIntent() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(body: "", reviewer: reviewer)

        await run(store)

        let request = try #require(reviewer.requests.first)
        #expect(request.intentFile == nil)
        #expect(!ClaudeCommand.prompt(for: request).contains("The intent of this pull request"))
        // A **není to porucha**: hláška v okně se neobjeví.
        #expect(store.intentFailure == nil)
        #expect(!FileManager.default.fileExists(
            atPath: layout.intentFile(for: pr, at: headSha).path(percentEncoded: false)
        ))
    }

    /// Store bez zadání (testy, starší sestavení) se chová jako do #120 — review běží, prompt je
    /// bez věty o souboru.
    @Test("Bez store na zadání review běží jako dřív")
    func runsWithoutAnIntentStoreAtAll() async throws {
        let reviewer = FakeReviewRunner()
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail(body: "Popis."))),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource())
        )

        await run(store)

        #expect(reviewer.requests.first?.intentFile == nil)
        #expect(store.intentFailure == nil)
    }

    // MARK: - Když se zadání nepodaří připravit

    /// **Tohle je to tvrzení, které se rozbije potichu**: review doběhne, jen bez zadání — a musí
    /// být z čeho poznat, že se to stalo. Selhání zápisu se vyrobí tím, že na místě souboru už
    /// leží **složka**, do které `write` zapsat nemůže.
    @Test("Nepovedené zadání review nepoloží, ale je vidět v okně")
    func afailedIntentDoesNotStopTheReview() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(body: "Popis, který se nemá kam uložit.", reviewer: reviewer)
        let blocked = layout.intentFile(for: pr, at: headSha)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)

        await run(store)

        // Review proběhlo: session se spustila a záznam se uložil.
        #expect(reviewer.requests.count == 1)
        #expect(store.reviewRecords[pr] != nil)
        #expect(store.reviewPhases[pr] == nil)
        // Ale bez zadání — a prompt na neexistující soubor neukazuje.
        #expect(reviewer.requests.first?.intentFile == nil)
        // A mlčí se o tom **ne**: v okně stojí hláška — a jmenuje PR, protože ve frontě dvaceti
        // PR je hláška bez subjektu nepoužitelná.
        let failure = try #require(store.intentFailure)
        #expect(failure.contains("Zadání pro reviewera cli/cli#42 se nepodařilo připravit"))
        #expect(failure.contains("review běží bez něj"))
    }

    /// Hláška je pravda o **posledním** běhu, ne trvalá vzpomínka: povedený zápis ji smaže.
    @Test("Povedený zápis starou hlášku smaže")
    func aSuccessfulWriteClearsTheNotice() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(body: "Popis.", reviewer: reviewer)
        store.intentFailure = "něco starého"

        await run(store)

        #expect(store.intentFailure == nil)
    }

    // MARK: - Tvrdá podmínka č. 2

    /// Sada nástrojů se zadáním **nemění** — zadání je soubor ke čtení, ne nový nástroj. Kdyby si
    /// někdo pro dotažení zadání přidal MCP nástroj (což je #345), spadne to tady.
    @Test("Se zadáním se reviewerovi nepřidá ani jedno povolení")
    func theIntentAddsNoPermission() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(body: "Popis.", reviewer: reviewer)

        await run(store)

        let request = try #require(reviewer.requests.first)
        let arguments = ClaudeCommand.arguments(prompt: ClaudeCommand.prompt(for: request))
        #expect(arguments.contains(ClaudeCommand.allowedTools))
        #expect(arguments.last == ClaudeCommand.disallowedTools)
        #expect(ClaudeCommand.allowedTools == "Read,Grep,Glob,Bash(git:*),ReportFindings,Skill")
        #expect(!ClaudeCommand.allowedTools.contains("mcp__"))
        #expect(!ClaudeCommand.allowedTools.contains("Write"))
        #expect(!ClaudeCommand.allowedTools.contains("Edit"))
    }
}
