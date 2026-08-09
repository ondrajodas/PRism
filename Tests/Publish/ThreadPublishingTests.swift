import Foundation
import Testing

@testable import PRism

/// Odpovídání do vláken a jejich vyřešení (#73) — čisté funkce a publisher proti
/// `FakeProcessRunner`.
///
/// Nejdůležitější testy tady, stejně jako u review, netvrdí, co se odeslalo, ale že se
/// **nic neodeslalo**: brána, prázdné tělo a zavřený PR musí skončit dřív, než se sáhne na `gh`.
@Suite("Odpovídání do vláken")
struct ThreadPublishingTests {
    private let gh = URL(filePath: KnownPath.gh)
    private let sandbox = PRIdentifier(
        repo: RepoID(owner: "ondrajodas", name: "prism-review-sandbox"),
        number: 3
    )
    private let head = "4a7469f930880b0683354191d315bacfe941ef93"

    private var target: ThreadTarget {
        ThreadTarget(pullRequest: sandbox, threadID: "PRRT_kwDOTrIEts6WHlSg")
    }

    private func detail(
        headSha: String? = nil,
        state: PullRequestState = .open
    ) -> PullRequest {
        PullRequest(
            id: sandbox,
            title: "Testovací PR",
            author: "github-actions",
            headSha: headSha ?? head,
            baseSha: "7b3f740e",
            url: URL(string: "https://github.com/\(sandbox.repo)/pull/\(sandbox.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: state
        )
    }

    private func publisher(
        _ runner: ProcessRunning,
        detail: Result<PullRequest, any Error>? = nil,
        scope: PublishScope? = nil
    ) -> GhReviewPublisher {
        GhReviewPublisher(
            gh: gh,
            runner: runner,
            gateway: FakeGitHubGateway(
                always: .success([]),
                detail: detail ?? .success(self.detail())
            ),
            scope: scope ?? .allowing(sandbox.repo)
        )
    }

    /// Skutečná odpověď mutace, změřená v sandboxu. Inline, ne fixture: je to jeden objekt
    /// a fixture by k němu přidala soubor bez další informace.
    private let replyOutput = """
    {"data":{"addPullRequestReviewThreadReply":{"comment":{
      "id":"PRRC_kwDOTrIEts7dI-Ux","databaseId":3710117169,
      "body":"Ověření #73: odpověď do vlákna.","createdAt":"2026-08-04T06:54:10Z",
      "url":"https://github.com/ondrajodas/prism-review-sandbox/pull/3#discussion_r3710117169",
      "author":{"login":"ondrajodas"},"replyTo":{"id":"PRRC_kwDOTrIEts7c_S9G"}}}}}
    """

    private let resolveOutput = """
    {"data":{"resolveReviewThread":{"thread":{
      "id":"PRRT_kwDOTrIEts6WHlSk","isResolved":true,
      "viewerCanResolve":false,"viewerCanUnresolve":true}}}}
    """

    // MARK: - Nic se neodeslalo

    /// Ve výchozím nastavení neodejde do vlákna nic — a brána je **první** kontrola v cestě,
    /// takže se na nepovolené repo ani neptáme na detail.
    @Test("Bez povolení se do vlákna nic neodešle")
    func doesNotReplyWithoutPermission() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: replyOutput)
        let publisher = publisher(runner, scope: .standard)

        await #expect(throws: PublishError.publishingNotAllowed(sandbox.repo)) {
            try await publisher.reply(to: target, body: "díky, mrknu na to")
        }
        #expect(runner.invocations.isEmpty)
    }

    @Test("Bez povolení se vlákno nevyřeší")
    func doesNotResolveWithoutPermission() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: resolveOutput)
        let publisher = publisher(runner, scope: .standard)

        await #expect(throws: PublishError.publishingNotAllowed(sandbox.repo)) {
            try await publisher.setResolved(true, of: target)
        }
        #expect(runner.invocations.isEmpty)
    }

    /// Prázdná odpověď **nesmí odejít**: změřeno v sandboxu, že ji GitHub přijme, nic nevytvoří
    /// a vrátí exit 0 — takže bez téhle brány by okno hlásilo odeslanou odpověď, která nevznikla.
    @Test(
        "Prázdná odpověď se nevolá",
        arguments: ["", " ", "\n", "  \n\t "]
    )
    func doesNotSendABlankReply(body: String) async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: replyOutput)
        let publisher = publisher(runner)

        await #expect(throws: PublishError.blankReply) {
            try await publisher.reply(to: target, body: body)
        }
        #expect(runner.invocations.isEmpty)
    }

    @Test("Na zavřený PR se neodpovídá")
    func doesNotReplyToAClosedPullRequest() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: replyOutput)
        let publisher = publisher(runner, detail: .success(detail(state: .merged)))

        await #expect(throws: PublishError.pullRequestNotOpen(.merged)) {
            try await publisher.reply(to: target, body: "díky")
        }
        #expect(runner.invocations.isEmpty)
    }

    // MARK: - Pre-flight je užší než u review

    /// **Nový commit odpověď neblokuje.** Odpověď se váže na vlákno, ne na commit, takže
    /// kontrola hlavy by zakázala zrovna tu situaci, kvůli které se do vlákna píše
    /// („opraveno v abc123“). U review je to naopak tvrdá podmínka.
    @Test("Odpověď projde i po novém commitu")
    func repliesEvenAfterANewCommit() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: replyOutput)
        let publisher = publisher(runner, detail: .success(detail(headSha: "ffffffffffffffff")))

        let comment = try await publisher.reply(to: target, body: "opraveno v abc123")

        #expect(comment.author == "ondrajodas")
        #expect(runner.invocations.count == 1)
    }

    @Test("Vyřešení projde i po novém commitu")
    func resolvesEvenAfterANewCommit() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: resolveOutput)
        let publisher = publisher(runner, detail: .success(detail(headSha: "ffffffffffffffff")))

        let resolution = try await publisher.setResolved(true, of: target)

        #expect(resolution.isResolved)
    }

    // MARK: - Co se odeslalo

    /// Odpověď adresuje **vlákno** (`PRRT_…`), ne komentář — proto se nepotřebuje `databaseId`
    /// a proto to jde přes GraphQL, ne přes REST z původního zadání.
    @Test("Odpověď jde na gh api graphql s id vlákna")
    func sendsTheThreadIDToGraphQL() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: replyOutput)

        _ = try await publisher(runner).reply(to: target, body: "díky, mrknu na to")

        let arguments = try #require(runner.invocations.first?.arguments)
        #expect(arguments.prefix(2) == ["api", "graphql"])
        #expect(arguments.contains("thread=PRRT_kwDOTrIEts6WHlSg"))
        #expect(arguments.contains("body=díky, mrknu na to"))
        #expect(arguments.contains { $0.contains("addPullRequestReviewThreadReply") })
    }

    /// Odpověď se vloží do vlákna bez dalšího čtení, takže z ní musí vyjít celý komentář —
    /// tvar je změřený na živém API.
    @Test("Z odpovědi vyjde celý komentář")
    func readsTheWholeComment() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: replyOutput)

        let comment = try await publisher(runner).reply(to: target, body: "díky")

        #expect(comment.id == "PRRC_kwDOTrIEts7dI-Ux")
        #expect(comment.author == "ondrajodas")
        #expect(comment.body == "Ověření #73: odpověď do vlákna.")
        #expect(comment.replyToID == "PRRC_kwDOTrIEts7c_S9G")
        #expect(comment.url.absoluteString.contains("#discussion_r3710117169"))
    }

    /// Dvě mutace, ne jedna s příznakem — GitHub jinou možnost nedává, takže se to musí
    /// poznat i v argumentech.
    @Test("Vyřešit a otevřít zpátky jsou dvě různé mutace", arguments: [true, false])
    func usesTwoMutationsForResolution(resolved: Bool) async throws {
        let output = resolved
            ? resolveOutput
            : resolveOutput.replacingOccurrences(of: "resolveReviewThread", with: "unresolveReviewThread")
                .replacingOccurrences(of: "\"isResolved\":true", with: "\"isResolved\":false")
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: output)

        let resolution = try await publisher(runner).setResolved(resolved, of: target)

        let arguments = try #require(runner.invocations.first?.arguments)
        let expected = resolved ? "resolveReviewThread" : "unresolveReviewThread"
        #expect(arguments.contains { $0.contains(expected) })
        #expect(resolution.isResolved == resolved)
    }

    /// Práva se berou z odpovědi, ne z toho, co jsme poslali: po vyřešení už `canResolve`
    /// neplatí a okno má nabídnout `Znovu otevřít`.
    @Test("Z vyřešení vyjdou přepočítaná práva")
    func readsRecalculatedRights() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: resolveOutput)

        let resolution = try await publisher(runner).setResolved(true, of: target)

        #expect(!resolution.canResolve)
        #expect(resolution.canUnresolve)
    }

    // MARK: - Rozbité odpovědi

    /// `comment: null` přijde s **nulovým** exit kódem (změřeno u prázdného těla), takže se
    /// nesmí vydávat za úspěch — do vlákna by se vložil komentář, který neexistuje.
    @Test("Odpověď bez komentáře je malformedResponse")
    func rejectsAReplyWithoutAComment() async throws {
        let runner = FakeProcessRunner(
            exitCode: 0,
            standardOutput: #"{"data":{"addPullRequestReviewThreadReply":{"comment":null}}}"#
        )

        await #expect(throws: PublishError.self) {
            try await publisher(runner).reply(to: target, body: "díky")
        }
    }

    @Test("Vyřešení bez stavu vlákna je malformedResponse")
    func rejectsAResolutionWithoutAThread() async throws {
        let runner = FakeProcessRunner(
            exitCode: 0,
            standardOutput: #"{"data":{"resolveReviewThread":{"thread":{"id":"PRRT_1"}}}}"#
        )

        await #expect(throws: PublishError.self) {
            try await publisher(runner).setResolved(true, of: target)
        }
    }

    /// Chybějící vlákno **není výpadek sítě**, i když si ty dvě hlášky vypadají podobně.
    /// Skutečná hláška z živého API; kdyby se pořadí případů v klasifikaci prohodilo, vyšel by
    /// z toho `network` a okno by radilo zkoušet znovu místo načíst konverzaci.
    @Test("Chybějící vlákno se pozná od výpadku sítě")
    func classifiesAMissingThread() {
        let missing = PublishError(failure: ProcessResult(
            exitCode: 1,
            standardOutput: "",
            standardError: "gh: Could not resolve to a node with the global id of 'PRRT_nonsense'"
        ))
        let network = PublishError(failure: ProcessResult(
            exitCode: 1,
            standardOutput: "",
            standardError: "Could not resolve to a Repository with the name 'cli/nope'."
        ))

        #expect(missing == .threadNotFound("gh: Could not resolve to a node with the global id of 'PRRT_nonsense'"))
        guard case .network = network else {
            Issue.record("hláška o repozitáři má zůstat u sítě, vyšlo \(network)")
            return
        }
    }

    /// Do vlákna se nic neodeslalo, takže se dá zkusit znovu bez rizika duplikátu.
    @Test("Po zamítnutém odeslání se nabídne zkusit znovu")
    func allowsRetryAfterRejection() {
        #expect(!PublishError.blankReply.mightHaveReachedGitHub)
        #expect(!PublishError.threadNotFound("x").mightHaveReachedGitHub)
    }

    /// Každý nový důvod musí umět říct, **co s ním jde udělat** — chyba bez dalšího kroku je
    /// jen zpráva o smůle. Tatáž kontrola jako u `DraftSendBlock`.
    @Test("Nové chyby mají neprázdnou větu")
    func explainsTheNewErrors() {
        for error in [PublishError.blankReply, .threadNotFound("detail")] {
            #expect(!error.userDescription.isEmpty)
        }
    }

    /// Chyby, které dostane **i odpověď do vlákna**, o review mluvit nesmí.
    ///
    /// Vzor z nálezu Copilota na #119: věta „zapni odesílání review v nastavení“ u zakázaného
    /// `Odpovědět` mluví o něčem jiném, než co člověk právě dělá. Při opravě se ukázalo, že to
    /// sahá dál než na to jedno místo — `pullRequestNotOpen`, `timedOut`, `malformedResponse`
    /// i `interrupted` posílaly hledat „jestli review nedošlo“ nad odpovědí, která žádné review
    /// nebyla. Tenhle test tu třídu drží, protože jinak se to vrátí u další sdílené chyby.
    @Test("Sdílené chyby nemluví o review")
    func keepsSharedErrorsNeutral() {
        // **Ne sandboxové repo**: jmenuje se `prism-review-sandbox`, takže by slovo „review“
        // do věty dodal jeho název a test by padal na vlastní past — hláška v pořádku je.
        let shared: [PublishError] = [
            .publishingNotAllowed(RepoID(owner: "cli", name: "cli")),
            .pullRequestNotOpen(.merged),
            .notAuthenticated,
            .rateLimited("limit"),
            .network("nejde"),
            .timedOut,
            .toolUnavailable("nespustilo se"),
            .malformedResponse("rozbité"),
            .interrupted,
            .unknown("nevím"),
            .blankReply,
            .threadNotFound("chybí"),
        ]

        for error in shared {
            #expect(
                !error.userDescription.lowercased().contains("review"),
                "věta u \(error) mluví o review, ale dostane ji i odpověď do vlákna"
            )
        }
    }

    /// A obráceně: chyby, které **jsou** jen o review, o něm mluvit mají — jinak by z hlášky
    /// nebylo poznat, čeho se týká.
    @Test("Chyby jen od review o review mluví")
    func keepsReviewOnlyErrorsSpecific() {
        #expect(PublishError.pendingReviewExists.userDescription.lowercased().contains("review"))
        #expect(PublishError.nothingToSend.userDescription.lowercased().contains("draft"))
    }

    // MARK: - Čisté funkce

    @Test("Prázdné tělo se nepovažuje za odesílatelné", arguments: ["", "   ", "\n\t"])
    func rejectsBlankBodies(body: String) {
        #expect(!PublishRequest.isSendable(body))
    }

    /// Odsazení a nové řádky **uvnitř** textu jsou součást zprávy (ukázka kódu), takže se
    /// posílá netrimovaný text — kontroluje se jen, že v něm něco je.
    @Test("Text s obsahem projde i s odsazením")
    func acceptsIndentedText() {
        #expect(PublishRequest.isSendable("  díky  "))
        #expect(PublishRequest.isSendable("\n    if x {\n"))
    }

    /// `ID!` je v GraphQL řetězec, takže `-f`; kdyby se poslalo `-F`, `gh` by se pokusil
    /// hodnotu typovat a dotaz by spadl.
    @Test("Vlákno i tělo jdou přes -f")
    func sendsStringsAsStrings() throws {
        let arguments = ThreadRequest.replyArguments(to: target, body: "ok")

        let thread = try #require(arguments.firstIndex(of: "thread=PRRT_kwDOTrIEts6WHlSg"))
        #expect(arguments[thread - 1] == "-f")
        let body = try #require(arguments.firstIndex(of: "body=ok"))
        #expect(arguments[body - 1] == "-f")
    }

    /// Mutace musí vracet všechna pole, ze kterých se skládá `ThreadComment` — bez nich by se
    /// odpověď nedala vložit do vlákna a musela by se dotahovat znovu.
    @Test("Dotaz na odpověď si říká o celý komentář")
    func asksForEveryFieldTheCommentNeeds() {
        for field in ["id", "body", "createdAt", "url", "author", "replyTo"] {
            #expect(ThreadRequest.replyDocument.contains(field), "v mutaci chybí \(field)")
        }
    }

    @Test("Dotaz na vyřešení si říká o stav i práva", arguments: [true, false])
    func asksForStateAndRights(resolved: Bool) {
        let document = ThreadRequest.resolutionDocument(resolved: resolved)

        for field in ["isResolved", "viewerCanResolve", "viewerCanUnresolve"] {
            #expect(document.contains(field), "v mutaci chybí \(field)")
        }
    }
}
