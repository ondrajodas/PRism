import Foundation
import Testing

@testable import PRism

/// Kdy se pustí agent na vlastním PR (#510) — **vyčerpávajícím výčtem**, protože je to čistá
/// funkce a jediné místo, kde se to rozhoduje.
///
/// **Nejcennější jsou tady tvrzení, která říkají, že se agent NEpustí**: na cizím PR, s vypnutou
/// bránou, nad vlastním komentářem, nad zavřeným PR. Ta se rozbijí potichu — výsledkem porušení
/// není chyba, ale session, která píše do souborů, aniž o ni kdo požádal.
@Suite("Policy — spouštěč agenta na vlastním PR")
struct AgentFixPolicyTests {
    private let pr = PRIdentifier("ondrajodas/PRism#510")!

    private func comment(_ id: String = "c1", author: String = "kolega") -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: "tohle přepiš",
            createdAt: Date(timeIntervalSince1970: 200),
            url: URL(string: "https://github.com/ondrajodas/PRism/pull/510#issuecomment-\(id)")!
        )
    }

    private func activity() -> ForeignActivity {
        ForeignActivity(comments: [comment()], reviews: [])
    }

    private func conversation(
        threads: [ReviewThread] = [],
        comments: [ThreadComment] = [],
        reviews: [SubmittedReview] = []
    ) -> Conversation {
        Conversation(
            viewer: "ondrajodas",
            reviews: ConversationPage(items: reviews, total: reviews.count, hasNextPage: false),
            threads: ConversationPage(items: threads, total: threads.count, hasNextPage: false),
            comments: ConversationPage(items: comments, total: comments.count, hasNextPage: false)
        )
    }

    // MARK: - Pět odpovědí, každá z jiného důvodu

    @Test("Vlastní otevřený PR s cizí aktivitou a zapnutou branou agenta pustí")
    func startsOnOwnPullRequest() {
        #expect(
            Policy.agentFix(
                ownership: .mine,
                state: .open,
                isAllowed: true,
                activity: activity(),
                isRunning: false
            ) == .start
        )
    }

    /// **Cizí PR nikdy**, ať si repo řeklo cokoli — tatáž konstrukce jako u automatu review (#332).
    /// Aplikace nemá co opravovat cizí práci.
    @Test("Na cizím PR se agent nepustí ani se zapnutou branou")
    func neverOnForeignPullRequests() {
        #expect(
            Policy.agentFix(
                ownership: .theirs,
                state: .open,
                isAllowed: true,
                activity: activity(),
                isRunning: false
            ) == .ignore(.notMine)
        )
    }

    /// **Vypnutá brána je výchozí stav**, a právě ona drží vlastnost „samo nic nezačne“
    /// (tvrdá podmínka č. 2).
    @Test("S vypnutou branou se nepustí nic")
    func neverWithTheGateClosed() {
        #expect(
            Policy.agentFix(
                ownership: .mine,
                state: .open,
                isAllowed: false,
                activity: activity(),
                isRunning: false
            ) == .ignore(.gateClosed)
        )
    }

    /// **Draft ano, zavřený a mergnutý ne.** Copilot review píše i na draftu a je to zrovna ten
    /// hlas, kvůli kterému #510 vzniklo; nad zavřeným PR by commit neměl kam odejít.
    @Test("Stav PR: otevřený a draft ano, zavřený a mergnutý ne")
    func onlyOnOpenPullRequests() {
        for state in [PullRequestState.open, .draft] {
            #expect(
                Policy.agentFix(
                    ownership: .mine,
                    state: state,
                    isAllowed: true,
                    activity: activity(),
                    isRunning: false
                ) == .start
            )
        }
        for state in [PullRequestState.merged, .closed] {
            #expect(
                Policy.agentFix(
                    ownership: .mine,
                    state: state,
                    isAllowed: true,
                    activity: activity(),
                    isRunning: false
                ) == .ignore(.notOpen(state))
            )
        }
    }

    /// **Prázdná cizí aktivita nespustí nic** — a protože `ForeignActivity` moje vlastní komentáře
    /// ani pushe nenese (#335), je tohle ta věta, na které celé #510 stojí: **vlastní hlas agenta
    /// nepustí**.
    @Test("Bez cizí aktivity se nepustí nic")
    func neverWithoutForeignActivity() {
        #expect(
            Policy.agentFix(
                ownership: .mine,
                state: .open,
                isAllowed: true,
                activity: .none,
                isRunning: false
            ) == .ignore(.nothingNew)
        )
    }

    /// **Jedna session na PR.** Druhá by pracovala v tomtéž stromě — a `queue` je vlastní odpověď,
    /// ne `ignore`: podnět se má vyřídit potom, ne zahodit.
    @Test("Nad běžící session se podnět zařadí, nezahodí")
    func queuesWhileSomethingRuns() {
        #expect(
            Policy.agentFix(
                ownership: .mine,
                state: .open,
                isAllowed: true,
                activity: activity(),
                isRunning: true
            ) == .queue
        )
    }

    /// **Pořadí kontrol je součástí odpovědi.** Cizí PR s vypnutou branou je `notMine`, ne
    /// `gateClosed`: vlastnictví se vyhodnocuje první a `ignore` nese ten důvod, který se má ukázat.
    @Test("Vyhrává první důvod v pořadí")
    func firstReasonWins() {
        #expect(
            Policy.agentFix(
                ownership: .theirs,
                state: .closed,
                isAllowed: false,
                activity: .none,
                isRunning: true
            ) == .ignore(.notMine)
        )
        #expect(
            Policy.agentFix(
                ownership: .mine,
                state: .closed,
                isAllowed: false,
                activity: .none,
                isRunning: true
            ) == .ignore(.gateClosed)
        )
    }

    // MARK: - Co se agentovi předá

    /// **Komentář ve vlákně se převádí na vlákno**, ne na komentář: zadání zná vlákno jako jednu
    /// položku i s kontextem u řádku, kdežto `ForeignActivity.comments` míchá obojí. Kdyby se
    /// hledalo podle identity komentáře, nová odpověď ve vlákně by do zadání nepřinesla nic.
    @Test("Nová odpověď ve vlákně se předá jako vlákno")
    func mapsThreadCommentsToTheirThread() {
        let inThread = comment("c9")
        let thread = ReviewThread(
            id: "t7",
            path: "App/A.swift",
            line: 12,
            originalLine: 12,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(items: [inThread], total: 1, hasNextPage: false)
        )
        let conversation = conversation(threads: [thread])

        let ids = Policy.agentFixItems(
            ForeignActivity(comments: [inThread], reviews: []),
            in: conversation
        )

        #expect(ids == [AgentPromptItem.thread(thread).id])
    }

    /// Komentář pod PR zůstává komentářem a review zůstává review.
    @Test("Komentář pod PR a review si drží svou identitu")
    func mapsCommentsAndReviews() {
        let below = comment("c3")
        let review = SubmittedReview(
            id: "r5",
            author: "kolega",
            state: .changesRequested,
            body: "prosím opravit",
            submittedAt: Date(timeIntervalSince1970: 300)
        )

        let ids = Policy.agentFixItems(
            ForeignActivity(comments: [below], reviews: [review]),
            in: conversation(comments: [below], reviews: [review])
        )

        #expect(ids == [AgentPromptItem.comment(below).id, AgentPromptItem.review(review).id])
    }

    /// **Bez konverzace prázdno, ne „všechno“.** Zúžení na prázdno znamená zadání bez položek,
    /// tedy bezpečná strana.
    @Test("Bez načtené konverzace se nepředá nic")
    func withoutConversationNothingIsSelected() {
        #expect(Policy.agentFixItems(activity(), in: nil).isEmpty)
    }

    // MARK: - Prompt a commit

    /// **Čtyři meze v promptu**, protože prompt je pojistka nad bránou, ne brána: sada bez `Bash`e
    /// drží „session necommituje“ doopravdy, tahle věta to jen říká nahlas.
    @Test("Prompt zakazuje commit, push, git i práci mimo strom")
    func promptCarriesTheLimits() {
        let prompt = Policy.agentFixPrompt(handoff: "— oprav překlep", base: "main")

        #expect(prompt.contains("do not commit"))
        #expect(prompt.contains("do not push"))
        #expect(prompt.contains("do not run `git` at all"))
        #expect(prompt.contains("do not touch anything outside the current directory"))
        // Testy nepouští a **nesmí tvrdit, že je pustila** — nemá čím.
        #expect(prompt.contains("You cannot run tests"))
        // Zadání jde do promptu **celé**, ne v odkazu na soubor.
        #expect(prompt.contains("— oprav překlep"))
        #expect(prompt.contains("main"))
    }

    /// **Zprávu commitu skládá aplikace, ne model** — je to jediné místo, kde by se text od modelu
    /// dostal do historie repa. Anglicky, Conventional Commits, **bez AI atribuce**.
    @Test("Zpráva commitu je určená daty, ne modelem")
    func commitMessageIsOurs() {
        let message = Policy.agentFixCommitMessage(for: pr)

        #expect(message == "fix: address review feedback (#510)")
        for banned in ["Claude", "claude", "AI", "Co-Authored", "generated"] {
            #expect(!message.contains(banned), "atribuce ve zprávě commitu: \(message)")
        }
    }

    // MARK: - Věty do okna

    /// Věta o výsledku **nesmí mluvit o rebase** — žádný v tom stromě neproběhl.
    @Test("Věta o výsledku agenta o rebase nemluví")
    func resultSentenceDoesNotClaimARebase() {
        let sentence = Policy.agentFixResult(files: 2, skipped: "README nechávám tobě.")

        #expect(sentence.contains("2 soubory"))
        #expect(sentence.contains("Do remote se zatím nesáhlo."))
        #expect(sentence.contains("README nechávám tobě."))
        #expect(!sentence.lowercased().contains("rebase"))
    }

    /// Věta o zápisu mimo strom musí říct, **co z toho plyne** — „nepovedlo se“ by u ní vypadalo
    /// jako spadlá session.
    @Test("Věta o zápisu mimo strom říká, že se nic necommitlo")
    func writesOutsideSentenceSaysNothingWasCommitted() {
        let sentence = Policy.agentFixWritesOutside(["/Users/ondra/klon/A.swift", "/etc/hosts", "/tmp/x"])

        #expect(sentence.contains("/Users/ondra/klon/A.swift"))
        #expect(sentence.contains("1 další"))
        #expect(sentence.contains("nic se necommitlo"))
    }
}
