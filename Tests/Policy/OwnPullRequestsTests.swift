import Foundation
import Testing

@testable import PRism

/// Sekce `Moje PR` (#331) — rozřazení seznamu, prázdná místa a odznak „čeká na tah“.
///
/// Čisté funkce, takže vyčerpávajícím výčtem a bez mockování. Tři věci se tu dají pokazit
/// potichu: **prázdno bez zdroje vypadat jako hotová práce** (nenastavená aplikace se pak
/// nedá odlišit od uklizeného stolu), **odznak počítat otevřené PR místo těch, na kterých
/// leží tah** (číslo pak nic neznamená) a **nálezy počítat i po odmítnutí**.
@Suite("Moje PR (#331)")
struct OwnPullRequestsTests {
    private func pullRequest(
        _ number: Int,
        author: String = "kolega",
        repo: String = "cli/cli"
    ) -> PullRequestSummary {
        PullRequestSummary(
            id: PRIdentifier(repo: RepoID(repo)!, number: number),
            title: "PR \(number)",
            author: author,
            url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_000_000),
            state: .open
        )
    }

    private func comment(id: String = "c1", author: String) -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: "text",
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            url: URL(string: "https://github.com/cli/cli/pull/1#discussion_r\(id)")!
        )
    }

    private func thread(
        id: String = "t1",
        resolved: Bool = false,
        outdated: Bool = false,
        authors: [String]
    ) -> ReviewThread {
        ReviewThread(
            id: id,
            path: "Cart.php",
            line: outdated ? nil : 27,
            originalLine: 27,
            side: .right,
            isResolved: resolved,
            isOutdated: outdated,
            comments: ConversationPage(
                items: authors.enumerated().map { comment(id: "\(id)-\($0.offset)", author: $0.element) },
                total: authors.count,
                hasNextPage: false
            )
        )
    }

    private func conversation(_ threads: [ReviewThread], viewer: String = "ondrajodas") -> Conversation {
        Conversation(
            viewer: viewer,
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: threads, total: threads.count, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }

    private func record(findings: [ReportedFinding], dismissAll: Bool = false) -> ReviewRecord {
        var record = makeRecord(runs: [makeStoredRun(findings: findings)])
        if dismissAll {
            record.dismissals = makeDismissals(record.findings)
        }
        return record
    }

    // MARK: - Rozřazení seznamu

    @Test("Rozřazení vybere podle autora, ne podle pořadí v seznamu")
    func splitsByAuthor() {
        let list = [
            pullRequest(1, author: "ondrajodas"),
            pullRequest(2, author: "kolega"),
            pullRequest(3, author: "OndraJodas"),
        ]

        let mine = Policy.pullRequests(list, ownedBy: .mine, mine: ["ondrajodas"])
        let theirs = Policy.pullRequests(list, ownedBy: .theirs, mine: ["ondrajodas"])

        // Velikost písmen nerozhoduje — `ownership` porovnává loginy v malých písmenech.
        #expect(mine.map(\.number) == [1, 3])
        #expect(theirs.map(\.number) == [2])
    }

    /// **Tvrzení, že se něco nestalo**: bez známého loginu není nic moje. Sekce `Moje PR` je pak
    /// prázdná a řekne proč (`unknownViewer`), místo aby do ní spadl celý seznam.
    @Test("Bez známého loginu není moje nic")
    func claimsNothingWithoutLogins() {
        let list = [pullRequest(1, author: "ondrajodas"), pullRequest(2)]

        #expect(Policy.pullRequests(list, ownedBy: .mine, mine: []).isEmpty)
        #expect(Policy.pullRequests(list, ownedBy: .theirs, mine: []).count == 2)
    }

    /// Pořadí se nemění — je to zúžení, ne řazení (tatáž zásada jako u `filtered(_:by:)`).
    @Test("Rozřazení nesahá na pořadí")
    func keepsTheOrder() {
        let list = [
            pullRequest(3, author: "ondrajodas"),
            pullRequest(1, author: "ondrajodas"),
            pullRequest(2, author: "ondrajodas"),
        ]

        #expect(Policy.pullRequests(list, ownedBy: .mine, mine: ["ondrajodas"]).map(\.number) == [3, 1, 2])
    }

    // MARK: - Proč je sekce prázdná

    @Test("Neprázdná sekce žádný důvod nedá")
    func hasNoReasonWhenSomethingIsVisible() {
        #expect(reason(visible: 2) == nil)
        // I nad chybějícím zdrojem: kdo si dopsal jiný dotaz, který moje PR přinese, má sekci
        // plnou — a věta o chybějícím zdroji by nad plným seznamem byla nesmysl.
        #expect(reason(tracksOwnSource: false, visible: 1) == nil)
    }

    /// **Nejdůležitější případ celého issue**: prázdno bez zdroje **není** „nic nemáš“.
    @Test("Chybějící zdroj má vlastní důvod, ne prázdno")
    func explainsTheMissingSource() {
        #expect(reason(tracksOwnSource: false) == .ownSourceMissing)
        // A vyhrává i nad nenačteným loginem a nad filtrem: bez zdroje se aplikace na moje PR
        // vůbec neptá, takže na ničem dalším nezáleží.
        #expect(reason(tracksOwnSource: false, knowsViewer: false, hidden: 3) == .ownSourceMissing)
    }

    @Test("Nenačtený login má vlastní důvod")
    func explainsTheUnknownViewer() {
        #expect(reason(knowsViewer: false) == .unknownViewer)
        // A vyhrává nad filtrem: dokud se neví, kdo jsem, není o čem tvrdit, že to filtr schoval.
        #expect(reason(knowsViewer: false, hidden: 2) == .unknownViewer)
    }

    @Test("Filtr, který schoval moje PR, nabídne cestu zpátky")
    func reportsTheFilter() {
        #expect(reason(hidden: 2) == .filtered(hidden: 2))
    }

    @Test("Zdroj i login jsou a nic není — ten dobrý stav")
    func reportsTheGoodEmptiness() {
        #expect(reason() == .noOwnPullRequests)
    }

    /// **Pořadí důvodů se nesmí prohodit** — nad daty, která nedorazila, se o zdrojích ani
    /// o loginu nedá tvrdit nic. Tatáž lekce jako u `listEmptyReason`.
    @Test("Nad selhaným a rozdělaným tikem vyhrává polling")
    func prefersThePollOverEverything() {
        let failure = PollEmptyReason.failure(.commandFailed(exitCode: 1, message: "bum"))

        #expect(reason(poll: failure, tracksOwnSource: false) == .poll(failure))
        #expect(reason(poll: .loading, tracksOwnSource: false) == .poll(.loading))
        #expect(reason(poll: .rateLimited(retryAt: Date(timeIntervalSince1970: 10))) != nil)
    }

    /// „Žádné PR k review“ o vlastních PR nemluví, takže z téhle funkce **nesmí** vypadnout —
    /// prázdný seznam je tady otázka zdroje, loginu a autora.
    @Test("Prázdný tik se na vlastní sekci nepřelije")
    func neverReportsNoPullRequests() {
        #expect(reason(poll: .noPullRequests) == .noOwnPullRequests)
        #expect(reason(poll: .noPullRequests, tracksOwnSource: false) == .ownSourceMissing)
        #expect(reason(poll: .noPullRequests, knowsViewer: false) == .unknownViewer)
    }

    private func reason(
        poll: PollEmptyReason? = nil,
        tracksOwnSource: Bool = true,
        knowsViewer: Bool = true,
        visible: Int = 0,
        hidden: Int = 0
    ) -> ListEmptyReason? {
        Policy.ownListEmptyReason(
            poll: poll,
            tracksOwnSource: tracksOwnSource,
            knowsViewer: knowsViewer,
            visible: visible,
            hidden: hidden
        )
    }

    // MARK: - Odznak: co čeká na tah

    /// Odznak počítá **práci**, ne otevřené PR: PR bez nálezů a bez cizích vláken se nepočítá.
    @Test("PR bez nálezů a bez vláken na tah nečeká")
    func countsNothingWithoutWork() {
        let list = [pullRequest(1, author: "ondrajodas"), pullRequest(2, author: "ondrajodas")]

        #expect(Policy.ownPullRequestsAwaitingMove(list, records: [:]) == 0)
    }

    @Test("Nález na vlastním PR čeká na tah")
    func countsFindings() {
        let list = [pullRequest(1, author: "ondrajodas")]
        let records = [list[0].id: record(findings: [makeReported()])]

        #expect(Policy.ownPullRequestsAwaitingMove(list, records: records) == 1)
    }

    /// Odmítnutý nález je vyřízená práce (#113) — do odznaku nepatří.
    @Test("Odmítnutý nález na tah nečeká")
    func ignoresDismissedFindings() {
        let list = [pullRequest(1, author: "ondrajodas")]
        let records = [list[0].id: record(findings: [makeReported()], dismissAll: true)]

        #expect(Policy.ownPullRequestsAwaitingMove(list, records: records) == 0)
    }

    @Test("Nevyřešené cizí vlákno čeká na tah")
    func countsUnresolvedForeignThreads() {
        let list = [pullRequest(1, author: "ondrajodas")]
        let conversations = [list[0].id: conversation([thread(authors: ["kolega"])])]

        #expect(Policy.ownPullRequestsAwaitingMove(list, records: [:], conversation: { conversations[$0] }) == 1)
    }

    /// Vyřešené vlákno je zavřená diskuze — po mně nechce nic.
    @Test("Vyřešené vlákno na tah nečeká")
    func ignoresResolvedThreads() {
        let list = [pullRequest(1, author: "ondrajodas")]
        let conversations = [list[0].id: conversation([thread(resolved: true, authors: ["kolega"])])]

        #expect(Policy.ownPullRequestsAwaitingMove(list, records: [:], conversation: { conversations[$0] }) == 0)
    }

    /// Vlákno, ve kterém jsem mluvil jen já, není cizí diskuze — je to moje poznámka.
    @Test("Vlákno jen s mými komentáři na tah nečeká")
    func ignoresMyOwnThreads() {
        let list = [pullRequest(1, author: "ondrajodas")]
        let conversations = [list[0].id: conversation([thread(authors: ["ondrajodas", "ondrajodas"])])]

        #expect(Policy.ownPullRequestsAwaitingMove(list, records: [:], conversation: { conversations[$0] }) == 0)
    }

    /// Kolega, který odpověděl do **mého** vlákna, po mně chce odpověď stejně jako ten, který ho
    /// založil — rozhoduje tedy „je v něm cizí komentář“, ne „kdo ho začal“.
    @Test("Cizí odpověď v mém vlákně na tah čeká")
    func countsForeignRepliesInMyThread() {
        let list = [pullRequest(1, author: "ondrajodas")]
        let conversations = [list[0].id: conversation([thread(authors: ["ondrajodas", "kolega"])])]

        #expect(Policy.ownPullRequestsAwaitingMove(list, records: [:], conversation: { conversations[$0] }) == 1)
    }

    /// Zmizelá kotva je věc dnešního diffu, ne diskuze — nevyřešené vlákno zůstává nevyřešené.
    @Test("Zastaralé vlákno se počítá")
    func countsOutdatedThreads() {
        let list = [pullRequest(1, author: "ondrajodas")]
        let conversations = [list[0].id: conversation([thread(outdated: true, authors: ["kolega"])])]

        #expect(Policy.ownPullRequestsAwaitingMove(list, records: [:], conversation: { conversations[$0] }) == 1)
    }

    /// **Nenačtená konverzace nepřidá nic** — a je to vědomá spodní hranice: konverzace se tahá
    /// při výběru řádku, ne při pollingu. Odznak tedy o části práce ještě neví, ale nikdy jí
    /// nevykáže víc, než kolik jí je.
    @Test("PR bez načtené konverzace vláknem nepřispěje")
    func countsNothingFromUnloadedConversations() {
        let list = [pullRequest(1, author: "ondrajodas"), pullRequest(2, author: "ondrajodas")]
        let conversations = [list[0].id: conversation([thread(authors: ["kolega"])])]

        #expect(Policy.ownPullRequestsAwaitingMove(list, records: [:], conversation: { conversations[$0] }) == 1)
    }

    /// Nález **i** vlákno na jednom PR je jedna položka k práci, ne dvě: počítají se PR.
    @Test("Nález i vlákno na jednom PR se počítají jednou")
    func countsPullRequestsNotReasons() {
        let list = [pullRequest(1, author: "ondrajodas")]
        let records = [list[0].id: record(findings: [makeReported()])]
        let conversations = [list[0].id: conversation([thread(authors: ["kolega"])])]

        #expect(
            Policy.ownPullRequestsAwaitingMove(list, records: records, conversation: { conversations[$0] }) == 1
        )
    }

    // MARK: - Karta na dashboardu

    @Test("Karta počítá moje PR a z nich ty, na kterých leží tah")
    func fillsTheCard() {
        let list = [
            pullRequest(1, author: "ondrajodas"),
            pullRequest(2, author: "ondrajodas"),
            pullRequest(3, author: "kolega"),
        ]
        let records = [list[0].id: record(findings: [makeReported()])]

        let card = Policy.dashboard(
            pullRequests: list,
            records: records,
            drafts: [:],
            mine: ["ondrajodas"],
            tracksOwnSource: true
        ).mine

        #expect(card.pullRequests == 2)
        #expect(card.awaitingMove == 1)
        #expect(card.isTracked)
    }

    /// Nula bez zdroje je údaj o **nastavení**, ne o mojí práci — a karta to musí rozlišit,
    /// jinak nad nenastavenou aplikací vypadá jako uklizený stůl.
    @Test("Karta bez zdroje se pozná od karty s nulou")
    func distinguishesTheMissingSource() {
        let card = Policy.dashboard(
            pullRequests: [pullRequest(1)],
            records: [:],
            drafts: [:],
            mine: ["ondrajodas"],
            tracksOwnSource: false
        ).mine

        #expect(card.pullRequests == 0)
        #expect(!card.isTracked)
    }

    /// **Fronta zůstává celá, i s mými PR** — odříznout je patří k #332. Bez tohohle tvrzení by
    /// se dvojí započtení opravilo „mimochodem“ a nikdo by nevěděl, kdy se to stalo.
    @Test("Karta Čeká na mě po tomhle issue počítá pořád i moje PR")
    func stillCountsOwnPullRequestsInTheQueueCard() {
        let list = [pullRequest(1, author: "ondrajodas"), pullRequest(2, author: "kolega")]

        let dashboard = Policy.dashboard(
            pullRequests: list,
            records: [:],
            drafts: [:],
            mine: ["ondrajodas"],
            tracksOwnSource: true
        )

        #expect(dashboard.queue.pullRequests == 2)
        #expect(dashboard.mine.pullRequests == 1)
    }
}
