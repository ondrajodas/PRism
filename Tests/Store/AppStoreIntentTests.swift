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

    /// Konverzace s vyjmenovanými komentáři pod PR. Prázdná znamená **načtená a bez komentářů**,
    /// ne „nepodařilo se“ — tenhle rozdíl je od #345 vidět v souboru se zadáním.
    static func conversation(comments: [String]) -> Conversation {
        Conversation(
            viewer: "ondrajodas",
            reviews: ConversationPage(items: [], hasNextPage: false),
            threads: ConversationPage(items: [], hasNextPage: false),
            comments: ConversationPage(
                items: comments.enumerated().map { index, body in
                    ThreadComment(
                        id: "c\(index)",
                        author: "linear[bot]",
                        body: body,
                        createdAt: Date(timeIntervalSince1970: Double(index)),
                        url: URL(string: "https://github.com/cli/cli/pull/42#issuecomment-\(index)")!
                    )
                },
                hasNextPage: false
            )
        )
    }

    private func store(
        body: String,
        reviewer: FakeReviewRunner,
        skills: [String]? = nil,
        comments: Result<Conversation, any Error> = .success(conversation(comments: [])),
        tool: String? = nil,
        intentText: (any IntentTextFetching)? = nil
    ) -> AppStore {
        var configuration = Configuration.standard
        if let skills { configuration.global.skills = skills }
        configuration.global.issueTextTool = tool
        return AppStore(
            gateway: FakeGitHubGateway(
                always: .success([]),
                detail: .success(detail(body: body)),
                conversations: [comments]
            ),
            configuration: configuration,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: reviewer,
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            intents: ReviewIntentStore(layout: layout),
            intentText: intentText
        )
    }

    /// Vrátí, co si test předepsal, a pamatuje si, na co se ho ptali.
    ///
    /// Počet volání je součást kontraktu: session se **nesmí** pustit, když není na co se ptát
    /// nebo když v konfiguraci není jméno nástroje. Boot session stojí ~$0,2.
    final class FakeIntentTextFetcher: IntentTextFetching, @unchecked Sendable {
        private let answer: IntentTextResult
        private let lock = NSLock()
        private var recorded: [(links: [IntentLink], tool: String)] = []

        init(_ answer: IntentTextResult) {
            self.answer = answer
        }

        var calls: [(links: [IntentLink], tool: String)] { lock.withLock { recorded } }

        func fetchText(of links: [IntentLink], using tool: String) async throws -> IntentTextResult {
            lock.withLock { recorded.append((links, tool)) }
            return answer
        }
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

    /// Odkaz na zadání z popisu se do souboru zapíše **jako odkaz**, i když se jeho text
    /// nedotahuje: bez něj reviewer nemá čím pojmenovat, co v zadání chybí.
    ///
    /// Store tady dotahování nemá (`intentText: nil`), takže u issue stojí věta **bez příčiny**
    /// (#345) — a to je schválně: „nezkoušelo se“ a „nepovedlo se“ se nesmí slít, takže se ani
    /// jedno netvrdí.
    @Test("Odkaz z popisu se do souboru zapíše")
    func writesTheLinkFromTheDescription() async throws {
        let body = try Fixture.text("gh/pr-body-linear.md")
        let reviewer = FakeReviewRunner()
        let store = store(body: body, reviewer: reviewer)

        await run(store)

        let file = try #require(reviewer.requests.first?.intentFile)
        let saved = try String(contentsOf: file, encoding: .utf8)
        #expect(saved.contains("- COR-1775 — https://linear.app/metalbear/issue/COR-1775"))
        #expect(saved.contains(ReviewIntentText.issueSubheading("COR-1775")))
        #expect(saved.contains(ReviewIntentText.notRead))
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

    // MARK: - Text issue a komentáře pod PR (#345)

    private static let linkbackBody = """
    <a href="https://linear.app/keboola/issue/AJDA-3003">AJDA-3003</a> je zadání tohohle PR.
    """

    /// Dráhy z tabu `Průběh` — tam se příznak zadání kreslí.
    private func lanes(of store: AppStore) -> [ReviewerLane] {
        Policy.lanes(
            of: store.timelines(for: pr),
            skills: store.reviewSkills(for: pr.repo),
            record: store.reviewRecords[pr]
        )
    }

    /// **Tohle je ten častý případ, kvůli kterému #120 vzniklo**: odkaz na zadání není v popisu, ale
    /// v linkbacku od bota. Do #345 se konverzace v cestě review nenačítala vůbec.
    @Test("Odkaz z komentáře pod PR se do zadání dostane")
    func picksUpTheLinkFromAComment() async throws {
        let reviewer = FakeReviewRunner()
        let fetcher = FakeIntentTextFetcher(
            IntentTextResult(issues: [IntentIssueText(id: "AJDA-3003", text: "Atomický zápis.")])
        )
        let store = store(
            body: "Popis bez odkazu.",
            reviewer: reviewer,
            comments: .success(Self.conversation(comments: [Self.linkbackBody])),
            tool: "mcp__claude_ai_Linear__get_issue",
            intentText: fetcher
        )

        await run(store)

        // Ptalo se na to, co bylo v komentáři — a jménem nástroje z konfigurace.
        #expect(fetcher.calls.map { $0.links.map(\.id) } == [["AJDA-3003"]])
        #expect(fetcher.calls.first?.tool == "mcp__claude_ai_Linear__get_issue")
        let file = try #require(reviewer.requests.first?.intentFile)
        let saved = try String(contentsOf: file, encoding: .utf8)
        #expect(saved.contains("- AJDA-3003 — https://linear.app/keboola/issue/AJDA-3003"))
        #expect(saved.contains("Atomický zápis."))
        // A nic nechybí, takže se na ose **nic nehlásí**.
        #expect(lanes(of: store).allSatisfy { $0.intentGap == nil })
    }

    /// **Chybějící jméno nástroje znamená „netahat“, ne prázdný pokus.** Session by stála boot
    /// (~$0,2) a nevrátila nic — a v okně to má být poznat, protože reviewer dostal jen odkazy.
    @Test("Bez jména nástroje se nic nepustí a na ose je to vidět")
    func doesNotFetchWithoutAConfiguredTool() async throws {
        let reviewer = FakeReviewRunner()
        let fetcher = FakeIntentTextFetcher(IntentTextResult())
        let store = store(
            body: Self.linkbackBody,
            reviewer: reviewer,
            tool: nil,
            intentText: fetcher
        )

        await run(store)

        #expect(fetcher.calls.isEmpty)
        #expect(lanes(of: store).map(\.intentGap) == [.toolNotConfigured])
        let file = try #require(reviewer.requests.first?.intentFile)
        let saved = try String(contentsOf: file, encoding: .utf8)
        #expect(saved.contains(ReviewIntentText.notFetched(.toolNotConfigured)))
        // Review přitom doběhlo — chybějící zadání ho nepokládá.
        #expect(store.reviewRecords[pr] != nil)
    }

    /// Prázdné jméno se bere jako chybějící: pole se prázdné jen prochází (⌘A a píše se znovu).
    @Test("Prázdné jméno nástroje se chová jako chybějící")
    func treatsABlankToolNameAsMissing() async throws {
        let fetcher = FakeIntentTextFetcher(IntentTextResult())
        let store = store(body: Self.linkbackBody, reviewer: FakeReviewRunner(), tool: "   ", intentText: fetcher)

        await run(store)

        #expect(fetcher.calls.isEmpty)
        #expect(lanes(of: store).map(\.intentGap) == [.toolNotConfigured])
    }

    /// **Bez odkazů se neptá nikdo** — a na ose se nic nehlásí: nechybí nic, protože není na co se
    /// ptát. Odznak nad během, kterému nic nechybělo, by byl šum, který se přestane čítat.
    @Test("PR bez odkazu na zadání session nepustí a nic nehlásí")
    func fetchesNothingWithoutLinks() async throws {
        let fetcher = FakeIntentTextFetcher(IntentTextResult())
        let store = store(
            body: "Popis bez odkazu.",
            reviewer: FakeReviewRunner(),
            tool: "mcp__claude_ai_Linear__get_issue",
            intentText: fetcher
        )

        await run(store)

        #expect(fetcher.calls.isEmpty)
        #expect(lanes(of: store).allSatisfy { $0.intentGap == nil })
    }

    /// Nedotažený text review **nepoloží**, ale musí být vidět — a to na **každé** dráze, protože
    /// příznak žije na dráze a dráha bez něj by o sobě tvrdila, že zadání dostala celé.
    @Test("Nedotažený text nese příznak každá dráha běhu")
    func everyLaneCarriesTheGap() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(
            body: Self.linkbackBody,
            reviewer: reviewer,
            skills: ["code-review", "php-review"],
            tool: "mcp__claude_ai_Linear__get_issue",
            intentText: FakeIntentTextFetcher(IntentTextResult(gap: .serverUnavailable(status: "failed")))
        )

        await run(store)

        #expect(reviewer.requests.count == 2)
        let lanes = lanes(of: store)
        #expect(lanes.count == 2)
        #expect(lanes.allSatisfy { $0.intentGap == .serverUnavailable(status: "failed") })
        // A příznak osu **neposouvá** — fáze se počítají z běhu, ne z materiálu.
        #expect(lanes.allSatisfy { $0.state == .finished })
        let saved = try String(contentsOf: #require(reviewer.requests.first?.intentFile), encoding: .utf8)
        #expect(saved.contains(ReviewIntentText.notFetched(.serverUnavailable(status: "failed"))))
    }

    /// Selhaný dotaz na komentáře review nepoloží — ale **nemlčí se o něm**: linkback chodí
    /// komentářem, takže „žádný odkaz jsme nenašli“ by tvrdilo víc, než data unesou.
    @Test("Selhané komentáře jsou vidět na ose i v souboru")
    func reportsUnreadableComments() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(
            body: "Popis s odkazem: https://linear.app/keboola/issue/AJDA-3003",
            reviewer: reviewer,
            comments: .failure(GitHubError.notFound("GraphQL selhalo")),
            tool: "mcp__claude_ai_Linear__get_issue",
            intentText: FakeIntentTextFetcher(
                IntentTextResult(issues: [IntentIssueText(id: "AJDA-3003", text: "Text.")])
            )
        )

        await run(store)

        #expect(store.reviewRecords[pr] != nil)
        #expect(lanes(of: store).map(\.intentGap) == [.commentsUnavailable])
        let saved = try String(contentsOf: #require(reviewer.requests.first?.intentFile), encoding: .utf8)
        #expect(saved.contains(ReviewIntentText.commentsUnavailable))
        // Text issue se přitom dotáhl, takže se o něm nic nehlásí.
        #expect(saved.contains("Text."))
        #expect(!saved.contains(ReviewIntentText.notRead))
    }

    /// **Nepovedený zápis na osu nic nepošle** (nález Copilota na #388), i když by gap jinak byl:
    /// reviewer nedostal soubor **vůbec**, takže věta „dostal jen odkazy“ by tvrdila víc, než data
    /// unesou. Je to jiná porucha a hlásí ji stavový řádek.
    @Test("Selhaný zápis zadání příznak na osu nepošle")
    func aFailedWriteReportsNoGapOnTheLane() async throws {
        let reviewer = FakeReviewRunner()
        let store = store(
            body: Self.linkbackBody,
            reviewer: reviewer,
            tool: nil,
            intentText: FakeIntentTextFetcher(IntentTextResult())
        )
        // Na místě souboru leží složka, takže `write` nemá kam zapsat.
        try FileManager.default.createDirectory(
            at: layout.intentFile(for: pr, at: headSha),
            withIntermediateDirectories: true
        )

        await run(store)

        // Bez zápisu by gap byl `.toolNotConfigured` — jméno nástroje v konfiguraci není.
        #expect(reviewer.requests.first?.intentFile == nil)
        #expect(lanes(of: store).allSatisfy { $0.intentGap == nil })
        // Mlčí se o tom **ne**: v okně stojí hláška a review doběhlo.
        #expect(store.intentFailure != nil)
        #expect(store.reviewRecords[pr] != nil)
    }

    /// Konverzace se v cestě review tahá **vždycky znovu**, ne z uložené: ta je klíčovaná
    /// `updatedAt` z posledního seznamu, takže komentář s odkazem mohl přijít mezitím.
    @Test("Komentáře se v cestě review načtou jedním dotazem")
    func asksForTheConversationOnce() async throws {
        let gateway = FakeGitHubGateway(
            always: .success([]),
            detail: .success(detail(body: "Popis.")),
            conversations: [.success(Self.conversation(comments: []))]
        )
        let store = AppStore(
            gateway: gateway,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(),
            reviews: ReviewStore(layout: layout, time: FakeTimeSource()),
            intents: ReviewIntentStore(layout: layout)
        )

        await run(store)

        #expect(gateway.conversationRequests == [pr])
    }
}
