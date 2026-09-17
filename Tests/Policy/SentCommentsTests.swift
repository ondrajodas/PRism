import Foundation
import Testing

@testable import PRism

/// Které komentáře pod PR jsou **moje** a na které z nich se ptá session (#522).
///
/// Testuje se nad **skutečnými** odpověďmi z veřejných PR `cli/cli` a z tohohle repa, protože
/// právě tady se dá splést tvar dat: vlákno se pozná podle **prvního** komentáře, kdežto v datech
/// jsou vlákna, ve kterých jsem odpověděl na cizí. Kdo se bude ptát na „je v něm můj komentář“,
/// dostane u těch vláken jinou odpověď — a na syntetickém vzorku by mu to prošlo.
///
/// `viewer` se u některých případů přepisuje. Není to vymyšlené: `viewer` je **samostatné pole
/// GraphQL odpovědi** (kdo se dívá), takže tatáž vlákna viděná jiným účtem jsou stav, který
/// v provozu běžně nastane — a jediný způsob, jak se na `cli/cli` dostat k vláknům, která jsou
/// „moje“.
@Suite("Policy — moje odeslané komentáře")
struct SentCommentsTests {
    private func load(
        _ fixture: String,
        number: Int,
        repo: String = "cli/cli",
        viewer: String? = nil
    ) throws -> Conversation {
        let text = try Fixture.text("gh/\(fixture)")
        let response = try GhOutput.decoder.decode(
            GhConversationResponse.self,
            from: Data(text.utf8)
        )
        let conversation = try response.conversation(
            id: PRIdentifier(repo: RepoID(repo)!, number: number)
        )
        guard let viewer else { return conversation }
        return Conversation(
            viewer: viewer,
            reviews: conversation.reviews,
            threads: conversation.threads,
            comments: conversation.comments,
            events: conversation.events
        )
    }

    // MARK: - Co je moje

    /// `conversation-small.json` má dvě vlákna: jedno od Copilota a jedno od `babakks`, do
    /// kterého odpověděl `ejahnGithub`. Viděno účtem `babakks` je moje **jen to druhé**.
    @Test("Moje je vlákno, které jsem založil")
    func aThreadIOpenedIsMine() throws {
        let conversation = try load("conversation-small.json", number: 11451, viewer: "babakks")

        let comments = Policy.sentComments(in: conversation)

        #expect(comments.count == 1)
        #expect(comments.first?.threadID == "PRRT_kwDODKw3uc5XAsRq")
        #expect(comments.first?.path == "pkg/cmd/release/shared/fetch.go")
        #expect(comments.first?.line == 168)
        #expect(comments.first?.body.isEmpty == false)
    }

    /// Nejcennější případ celého souboru: `conversation-timeline.json` jsou tři vlákna, která
    /// **založil Copilot** a do kterých `ondrajodas` odpověděl. Kdyby se „moje“ poznávalo podle
    /// toho, že je ve vlákně můj komentář, vyšla by z toho tři cizí vlákna jako moje — a druhé
    /// kolo by se ptalo na věty, které jsem nenapsal.
    @Test("Odpověď do cizího vlákna ze mě autora nedělá")
    func replyingToSomeoneElsesThreadDoesNotMakeItMine() throws {
        let conversation = try load(
            "conversation-timeline.json",
            number: 167,
            repo: "ondrajodas/PRism"
        )

        #expect(conversation.viewer == "ondrajodas")
        #expect(conversation.threads.items.count == 3)
        #expect(conversation.threads.items.allSatisfy { thread in
            thread.comments.items.contains { conversation.isMine($0) }
        })
        #expect(Policy.sentComments(in: conversation).isEmpty)
    }

    /// Osmatřicet vláken od `babakks` viděných jeho účtem — všechna moje a v žádném odpověď.
    @Test("Všechna vlákna můžou být moje")
    func everyThreadCanBeMine() throws {
        let conversation = try load("conversation-threads.json", number: 13084, viewer: "babakks")

        #expect(Policy.sentComments(in: conversation).count == 38)
        #expect(Policy.answeredThreadIDs(in: conversation).isEmpty)
    }

    /// Kotva zastaralého vlákna je jediné, čím se dá umístit — `line` u něj GitHub neposílá.
    /// Bez `originalLine` by komentář šel do promptu bez čísla řádku a session by ho hledala
    /// v celém souboru.
    @Test("Zastaralé vlákno si nese původní řádek")
    func anOutdatedThreadKeepsItsOriginalLine() throws {
        let conversation = try load("conversation-threads.json", number: 13084, viewer: "babakks")
        let outdated = try #require(conversation.threads.items.first { $0.isOutdated })

        let comment = try #require(
            Policy.sentComments(in: conversation).first { $0.threadID == outdated.id }
        )

        #expect(outdated.line == nil)
        #expect(comment.line == outdated.originalLine)
        #expect(comment.line != nil)
    }

    /// Vyřešená vlákna se **neodečítají**: vyřešit smí kdokoli a o kódu to neříká nic. Odečíst
    /// je tady by znamenalo, že komentář z druhého kola zmizí kliknutím, ne opravou.
    @Test("Vyřešené vlákno z druhého kola nevypadne")
    func aResolvedThreadStays() throws {
        let conversation = try load("conversation-threads.json", number: 13084, viewer: "babakks")
        let resolved = try #require(conversation.threads.items.first { $0.isResolved })

        #expect(Policy.sentComments(in: conversation).contains { $0.threadID == resolved.id })
    }

    /// Nenačtená konverzace je prázdno, ne pád. Že se **neví nic**, se od „nic tam nemám“
    /// rozlišuje až v reportu (`ReviewReplyReport.unknown`), ne tady.
    @Test("Bez konverzace není seznam")
    func withoutAConversationThereIsNoList() {
        #expect(Policy.sentComments(in: nil).isEmpty)
        #expect(Policy.unansweredComments(in: nil).isEmpty)
    }

    // MARK: - Na co se ptá model

    /// Hranice mezi daty a modelem se drží **už ve vstupu**: vlákno, do kterého mi někdo
    /// odpověděl, se session vůbec nepředkládá. Kdyby se předložilo, ležel by v úložišti verdikt,
    /// který se nikdy nemá ukázat — a čekal by, až ho někdo omylem přečte.
    @Test("Zodpovězené vlákno se modelu nepředkládá")
    func anAnsweredThreadIsNotHandedToTheModel() throws {
        let conversation = try load("conversation-small.json", number: 11451, viewer: "babakks")

        #expect(Policy.sentComments(in: conversation).count == 1)
        #expect(Policy.answeredThreadIDs(in: conversation) == ["PRRT_kwDODKw3uc5XAsRq"])
        #expect(Policy.unansweredComments(in: conversation).isEmpty)
    }

    /// A naopak: vlákno bez cizí odpovědi se předkládá celé.
    @Test("Nezodpovězená vlákna jdou modelu všechna")
    func unansweredThreadsAreAllHandedOver() throws {
        let conversation = try load("conversation-threads.json", number: 13084, viewer: "babakks")

        #expect(Policy.unansweredComments(in: conversation).count == 38)
    }

    /// Vlákno, ve kterém jsem po svém komentáři napsal ještě jednou, **není zodpovězené**: že
    /// jsem si odpověděl sám, není odpověď (tatáž úvaha jako u cizí aktivity #335).
    @Test("Vlastní druhý komentář ve vlákně odpověď není")
    func myOwnFollowUpIsNotAReply() throws {
        let real = try load("conversation-small.json", number: 11451, viewer: "babakks")
        let thread = try #require(real.threads.items.first { $0.comments.items.count > 1 })
        // Tatáž vlákna viděná účtem, který napsal **oba** komentáře. Inline složené schválně:
        // vlákno, kde si autor odpověděl sám, ve veřejném vzorku není, a tenhle případ rozhoduje
        // o tom, jestli se na něj session zeptá.
        let mine = Conversation(
            viewer: "babakks",
            reviews: real.reviews,
            threads: ConversationPage(
                items: [reauthored(thread, as: "babakks")],
                total: 1,
                hasNextPage: false
            ),
            comments: real.comments,
            events: real.events
        )

        #expect(Policy.answeredThreadIDs(in: mine).isEmpty)
        #expect(Policy.unansweredComments(in: mine).count == 1)
    }

    private func reauthored(_ thread: ReviewThread, as author: String) -> ReviewThread {
        ReviewThread(
            id: thread.id,
            path: thread.path,
            line: thread.line,
            originalLine: thread.originalLine,
            side: thread.side,
            isResolved: thread.isResolved,
            isOutdated: thread.isOutdated,
            canResolve: thread.canResolve,
            canUnresolve: thread.canUnresolve,
            diffHunk: thread.diffHunk,
            comments: ConversationPage(
                items: thread.comments.items.map {
                    ThreadComment(
                        id: $0.id,
                        author: author,
                        body: $0.body,
                        createdAt: $0.createdAt,
                        url: $0.url,
                        replyToID: $0.replyToID
                    )
                },
                total: thread.comments.total,
                hasNextPage: thread.comments.hasNextPage
            )
        )
    }
}
