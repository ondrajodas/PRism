import Foundation
import Testing

@testable import PRism

/// Psaní komentáře do diskuze pod PR (#216) — publisher proti `FakeProcessRunner`.
///
/// Nejdůležitější testy tady, stejně jako u review a u vláken, netvrdí, co se odeslalo, ale že
/// se **nic neodeslalo**: brána, prázdné tělo a zavřený PR musí skončit dřív, než se sáhne na
/// `gh`. Komentář pod PR je od #216 čtvrtá metoda `ReviewPublishing`, a rozšířit tvrdou podmínku
/// č. 1 se smí jedině tak, že si nová cesta ven ohlídá totéž co ty tři předchozí.
@Suite("Komentář pod PR")
struct CommentPublishingTests {
    private let gh = URL(filePath: KnownPath.gh)
    private let sandbox = PRIdentifier(
        repo: RepoID(owner: "ondrajodas", name: "prism-review-sandbox"),
        number: 4
    )
    private let head = "f213b4ee595585a3a918b67ff630099b616c2ea1"

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

    /// Skutečný tvar issue komentáře, **změřený** na `ondrajodas/prism-review-sandbox#1`
    /// (`gh api repos/{repo}/issues/1/comments`). `POST` na tentýž endpoint vrací vytvořený
    /// komentář ve stejném schématu, takže se dá vzít odsud.
    ///
    /// Inline, ne fixture: je to jeden objekt a soubor by k němu nepřidal žádnou další
    /// informaci — tatáž úvaha jako u odpovědi do vlákna v #73.
    private let commentOutput = """
    {"id":5158771955,
     "html_url":"https://github.com/ondrajodas/prism-review-sandbox/pull/1#issuecomment-5158771955",
     "created_at":"2026-08-02T15:10:38Z","updated_at":"2026-08-02T15:10:38Z",
     "author_association":"OWNER",
     "body":"Nahrazeno PR #2, které zakládá bot — na tomhle nejde dělat approve, protože jsem jeho autor.",
     "user":{"login":"ondrajodas"}}
    """

    // MARK: - Nic se neodeslalo

    /// Ve výchozím nastavení neodejde pod PR nic — a brána je **první** kontrola v cestě,
    /// takže se na nepovolené repo ani neptáme na detail.
    @Test("Bez povolení se komentář neodešle")
    func doesNotCommentWithoutPermission() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: commentOutput)
        let publisher = publisher(runner, scope: .standard)

        await #expect(throws: PublishError.publishingNotAllowed(sandbox.repo)) {
            try await publisher.comment(on: sandbox, body: "mrknu na to zítra")
        }
        #expect(runner.invocations.isEmpty)
    }

    /// Prázdný komentář **nesmí odejít** ze stejného důvodu jako prázdná odpověď: změřeno
    /// v sandboxu u #73, že GitHub prázdné tělo přijme a zahodí, takže by okno hlásilo
    /// odeslaný komentář, který nevznikl.
    @Test("Prázdný komentář se nevolá", arguments: ["", " ", "\n", "  \n\t "])
    func doesNotSendABlankComment(body: String) async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: commentOutput)
        let publisher = publisher(runner)

        await #expect(throws: PublishError.blankComment) {
            try await publisher.comment(on: sandbox, body: body)
        }
        #expect(runner.invocations.isEmpty)
    }

    @Test("Pod zavřený PR se nepíše")
    func doesNotCommentOnAClosedPullRequest() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: commentOutput)
        let publisher = publisher(runner, detail: .success(detail(state: .merged)))

        await #expect(throws: PublishError.pullRequestNotOpen(.merged)) {
            try await publisher.comment(on: sandbox, body: "díky")
        }
        #expect(runner.invocations.isEmpty)
    }

    // MARK: - Pre-flight je užší než u review

    /// **Nový commit komentář neblokuje.** Komentář pod PR se neváže na žádný commit, takže
    /// kontrola hlavy by zakázala zrovna to, kvůli čemu se pod PR píše. U review je naopak
    /// shoda s hlavou tvrdá podmínka.
    @Test("Komentář projde i po novém commitu")
    func commentsEvenAfterANewCommit() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: commentOutput)
        let publisher = publisher(runner, detail: .success(detail(headSha: "ffffffffffffffff")))

        let comment = try await publisher.comment(on: sandbox, body: "mrknu na to zítra")

        #expect(comment.author == "ondrajodas")
        #expect(runner.invocations.count == 1)
    }

    // MARK: - Co se odeslalo

    /// REST, ne GraphQL — `addComment` chce node ID pull requestu, které v modelu není.
    /// Endpoint je `issues`, protože komentář pod PR je z pohledu API issue comment.
    @Test("Komentář jde na REST endpoint issues")
    func sendsToTheIssuesEndpoint() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: commentOutput)

        _ = try await publisher(runner).comment(on: sandbox, body: "mrknu na to zítra")

        let arguments = try #require(runner.invocations.first?.arguments)
        #expect(arguments.prefix(2) == [
            "api", "repos/ondrajodas/prism-review-sandbox/issues/4/comments",
        ])
        #expect(arguments.contains("POST"))
        #expect(arguments.contains("body=mrknu na to zítra"))
    }

    /// **`-f`, ne `-F`.** `--field` čte hodnotu začínající `@` jako jméno souboru, takže
    /// komentář otevřený zmínkou by se `gh` pokusil načíst z disku. Regrese by byla tichá:
    /// projde všechno kromě komentářů, které začínají zmínkou.
    @Test("Tělo jde přes -f, takže zmínka na začátku není soubor")
    func sendsTheBodyAsARawField() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: commentOutput)

        _ = try await publisher(runner).comment(on: sandbox, body: "@ondrajodas mrkni na to")

        let arguments = try #require(runner.invocations.first?.arguments)
        let index = try #require(arguments.firstIndex(of: "body=@ondrajodas mrkni na to"))
        #expect(arguments[index - 1] == "-f")
    }

    /// Komentář se připisuje do konverzace bez dalšího čtení, takže z odpovědi musí vyjít celý.
    @Test("Z odpovědi vyjde celý komentář")
    func readsTheWholeComment() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: commentOutput)

        let comment = try await publisher(runner).comment(on: sandbox, body: "díky")

        #expect(comment.id == "5158771955")
        #expect(comment.author == "ondrajodas")
        #expect(comment.body.hasPrefix("Nahrazeno PR #2"))
        #expect(comment.url.absoluteString.contains("#issuecomment-5158771955"))
        // Komentář pod PR není ve vlákně — kdyby `replyTo` vyplněné bylo, kreslil by se
        // v ose odsazený jako odpověď na něco, co neexistuje.
        #expect(comment.replyToID == nil)
    }

    /// Odpověď bez autora **není** komentář, kterému rozumíme. Doplnit prázdné jméno by
    /// znamenalo vymyslet si identitu — a v ose by se objevil komentář „od nikoho“.
    @Test("Odpověď bez autora se nepřijímá")
    func rejectsAResponseWithoutAnAuthor() async throws {
        let runner = FakeProcessRunner(
            exitCode: 0,
            standardOutput: """
            {"id":1,"html_url":"https://github.com/o/r/pull/1#issuecomment-1",
             "created_at":"2026-08-02T15:10:38Z","body":"ahoj"}
            """
        )

        await #expect(throws: PublishError.self) {
            try await publisher(runner).comment(on: sandbox, body: "díky")
        }
    }

    /// Hláška o prázdném komentáři musí mluvit o **komentáři**, ne o odpovědi do vlákna —
    /// věta, která pojmenuje něco jiného, než na co se člověk dívá, vypadá jako chyba jinde
    /// v okně.
    @Test("Prázdný komentář a prázdná odpověď mají různé hlášky")
    func keepsTheBlankMessagesApart() {
        #expect(PublishError.blankComment.userDescription != PublishError.blankReply.userDescription)
        #expect(PublishError.blankComment.userDescription.lowercased().contains("komentář"))
        #expect(PublishError.blankReply.userDescription.lowercased().contains("odpověď"))
    }

    /// Odmítnuté odeslání nesmí nabízet „zkontroluj GitHub“ — nic se nevolalo.
    @Test("Prázdný komentář na GitHub nedošel")
    func blankCommentNeverReachedGitHub() {
        #expect(!PublishError.blankComment.mightHaveReachedGitHub)
    }
}
