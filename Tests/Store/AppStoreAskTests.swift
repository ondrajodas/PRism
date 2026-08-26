import Foundation
import Testing

@testable import PRism

/// Rozhovor nad PR (#452) — od otázky po uloženou odpověď.
///
/// Tři věci, které se rozbijí potichu, a proto mají vlastní test: **druhá otázka musí navázat**
/// (jinak se za kontext platí znovu a odpovědi si protiřečí), **spadlá odpověď nesmí zmizet**
/// (zaplacená session, o které se mlčí, vypadá jako by nikdy nebyla) a **rozhovor nesmí
/// zneplatnit nový commit** (na rozdíl od nálezů).
@Suite("AppStore — rozhovor nad PR")
@MainActor
struct AppStoreAskTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let time = FakeTimeSource()

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func detail(headSha: String = "aaaa1111") -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: headSha,
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open,
            body: "popis"
        )
    }

    private func store(
        asker: FakeAskRunner,
        headSha: String = "aaaa1111",
        spend: SpendLedger? = nil,
        asks: AskStore? = nil
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail(headSha: headSha))),
            time: time,
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(),
            asker: asker,
            asks: asks ?? AskStore(layout: layout),
            askContexts: AskContextStore(layout: layout),
            spend: spend
        )
    }

    private func ask(_ store: AppStore, _ question: String) {
        store.setAskDraft(question, for: pr)
        store.askQuestion(about: pr)
    }

    private func waitUntilAnswered(_ store: AppStore) async {
        await waitUntil("odpověď doběhne") { !store.isAnswering(pr) }
        #expect(!store.isAnswering(pr))
    }

    private func messages(_ store: AppStore) -> [AskMessage] {
        store.askConversation(for: pr)?.messages ?? []
    }

    // MARK: - Otázka a odpověď

    /// Otázka se do rozhovoru zapíše **hned**, ne až s odpovědí: bublina má být vidět ve chvíli,
    /// kdy se klikne.
    @Test("Otázka je v rozhovoru dřív, než dorazí odpověď")
    func theQuestionAppearsImmediately() async {
        let asker = FakeAskRunner(holdsUntilRelease: true)
        let store = store(asker: asker)

        ask(store, "proč se ten mutex bere?")

        #expect(messages(store).map(\.speaker) == [.mine])
        #expect(messages(store).first?.text == "proč se ten mutex bere?")
        // A pole se vyprázdní, ať se táž otázka neodešle podruhé.
        #expect(store.askDraft(for: pr).isEmpty)

        asker.releaseAll()
        await waitUntilAnswered(store)
    }

    @Test("Odpověď přibude jako druhá bublina i s cenou a dokladem")
    func theAnswerIsRecorded() async {
        let asker = FakeAskRunner(answers: [
            AskAnswer(
                text: "protože fetch plní cache",
                sessionID: "s1",
                readFiles: ["SecretClient.php"],
                usage: RunUsage(cost: 0.04, duration: .seconds(12), turns: 3)
            ),
        ])
        let store = store(asker: asker)

        ask(store, "proč?")
        await waitUntilAnswered(store)

        #expect(messages(store).map(\.speaker) == [.mine, .claude])
        let answer = messages(store).last
        #expect(answer?.text == "protože fetch plní cache")
        #expect(answer?.readFiles == ["SecretClient.php"])
        #expect(answer?.usage?.cost == 0.04)
        #expect(answer?.failure == nil)
    }

    /// **Prázdná otázka session nespustí** — session za nic jsou reálné peníze.
    @Test("Prázdná otázka nic nespustí")
    func emptyQuestionsAreIgnored() {
        let asker = FakeAskRunner()
        let store = store(asker: asker)

        ask(store, "   \n  ")

        #expect(messages(store).isEmpty)
        #expect(asker.requests.isEmpty)
        #expect(!store.isAnswering(pr))
    }

    /// Druhá otázka během běžící odpovědi se **zahodí**: v jednom rozhovoru běží jedna session,
    /// jinak by si dvě navazovaly na tutéž a odpovědi by se přeskládaly.
    @Test("Během běžící odpovědi se druhá otázka nepustí")
    func onlyOneSessionPerConversation() async {
        let asker = FakeAskRunner(holdsUntilRelease: true)
        let store = store(asker: asker)

        ask(store, "první")
        await waitUntil("session naběhne") { !asker.requests.isEmpty }
        ask(store, "druhá")

        #expect(messages(store).count == 1)
        #expect(asker.requests.count == 1)

        asker.releaseAll()
        await waitUntilAnswered(store)
    }

    // MARK: - Navázání

    /// **Tohle je to podstatné z celého issue**: druhá otázka jede přes `--resume`, takže session
    /// drží rozhovor i to, co už přečetla.
    ///
    /// **Materiál přitom dostane taky** — a je to oprava první podoby #452, ne opomenutí. Pruh
    /// `ví o tomhle PR:` se počítá **živě**, takže by nad navazující otázkou tvrdil `3 nálezy`
    /// o session, která o nich nikdy neslyšela; zápis do cache je zdarma, kdežto tohle stálo
    /// pravdivost toho pruhu. Prompt navazující otázky proto říká, že je soubor **čerstvý**.
    @Test("Druhá otázka navazuje a materiál dostane čerstvý")
    func theSecondQuestionResumes() async {
        let asker = FakeAskRunner(answers: [
            AskAnswer(text: "první odpověď", sessionID: "s1"),
            AskAnswer(text: "druhá odpověď", sessionID: "s2"),
        ])
        let store = store(asker: asker)

        ask(store, "první")
        await waitUntilAnswered(store)
        ask(store, "druhá")
        await waitUntilAnswered(store)

        #expect(asker.requests.count == 2)
        #expect(asker.requests[0].resuming == nil)
        #expect(asker.requests[1].resuming == "s1")
        // Cesta k materiálu je v obou, ale úvodní věta se liší: navazující otázka říká, že je
        // soubor čerstvý, ne že ho session vidí poprvé.
        #expect(asker.requests[0].prompt.contains("42-ask.md"))
        #expect(asker.requests[1].prompt.contains("42-ask.md"))
        #expect(asker.requests[1].prompt.contains("have been refreshed"))
        #expect(!asker.requests[0].prompt.contains("have been refreshed"))
        // A id se posouvá: `claude --resume` id **může vrátit jiné** (v naměřeném běhu zůstalo
        // totéž), takže se bere to poslední — třetí otázka musí navázat na druhou, ne na první.
        #expect(store.askConversation(for: pr)?.sessionID == "s2")
    }

    /// Materiál doopravdy leží **vedle pracovního stromu**, ne uvnitř — soubor uvnitř kopie by se
    /// objevil v `git status` a session by ho viděla jako součást změny.
    @Test("Materiál se uloží vedle pracovního stromu")
    func theContextFileLandsNextToTheWorktree() async throws {
        let store = store(asker: FakeAskRunner())

        ask(store, "proč?")
        await waitUntilAnswered(store)

        let file = layout.askContextFile(for: pr)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("## What PRism's reviewers reported"))
        #expect(text.contains("- Base commit: bbbb2222"))
        #expect(!layout.worktree(for: pr, at: "aaaa1111").path().contains(file.lastPathComponent))
    }

    // MARK: - Když se to nepovede

    /// **Spadlá odpověď nesmí zmizet.** Session, která doběhla a nic neřekla, peníze stála —
    /// a prázdno v okně se od „nikdo se nic neptal“ nedá odlišit.
    @Test("Odpověď bez textu dostane bublinu s důvodem")
    func anEmptyAnswerStillSaysSomething() async {
        let store = store(asker: FakeAskRunner(answers: [AskAnswer(sessionID: "s1")]))

        ask(store, "proč?")
        await waitUntilAnswered(store)

        #expect(messages(store).count == 2)
        #expect(messages(store).last?.failure != nil)
    }

    /// Vytimeoutovaná session, která něco stihla říct, si text **nechá** — zahodit ho kvůli tomu,
    /// že u něj stojí hláška, by znamenalo zaplatit odpověď a nezobrazit ji.
    @Test("Částečná odpověď zůstane i s hláškou")
    func partialAnswersKeepTheirText() async {
        let store = store(asker: FakeAskRunner(answers: [
            AskAnswer(text: "začal jsem tím, že", sessionID: "s1", failure: "Odpověď nedoběhla v limitu."),
        ]))

        ask(store, "proč?")
        await waitUntilAnswered(store)

        #expect(messages(store).last?.text == "začal jsem tím, že")
        #expect(messages(store).last?.failure == "Odpověď nedoběhla v limitu.")
    }

    /// Nepovedená příprava kopie se hlásí **v rozhovoru**, ne jen ve stavovém řádku: otázka tam
    /// visí a bez odpovědi vypadá jako zaseknuté okno.
    @Test("Selhání checkoutu skončí bublinou s důvodem")
    func checkoutFailuresAreVisible() async {
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail())),
            time: time,
            checkout: FakeRepoCheckout(outcome: .failure(.cacheUnavailable("disk je plný"))),
            reviewer: FakeReviewRunner(),
            asker: FakeAskRunner(),
            asks: AskStore(layout: layout),
            askContexts: AskContextStore(layout: layout)
        )

        ask(store, "proč?")
        await waitUntilAnswered(store)

        #expect(messages(store).count == 2)
        #expect(messages(store).last?.failure?.contains("kopii") == true)
    }

    /// **Mrtvé navázání se zahodí, ne drží.** Když `claude --resume <id>` selže (session vypršela,
    /// cache se uklidila), nedorazí žádné nové id — a kdyby se to staré nechalo, každá další
    /// otázka na tom PR by selhala **stejně a navždycky**, protože v okně není nic, čím rozhovor
    /// začít znovu. Zprávy zůstávají; ztrácí se jen to, co stejně nefunguje.
    @Test("Odpověď bez id zahodí navázání, takže příští otázka začne novou session")
    func adeadResumeIsDropped() async {
        let asker = FakeAskRunner(answers: [
            AskAnswer(text: "první", sessionID: "s1"),
            AskAnswer(failure: "Session se nespustila."),
            AskAnswer(text: "třetí", sessionID: "s3"),
        ])
        let store = store(asker: asker)

        ask(store, "první")
        await waitUntilAnswered(store)
        ask(store, "druhá")
        await waitUntilAnswered(store)

        #expect(store.askConversation(for: pr)?.sessionID == nil)

        ask(store, "třetí")
        await waitUntilAnswered(store)

        #expect(asker.requests.map(\.resuming) == [nil, "s1", nil])
        #expect(store.askConversation(for: pr)?.sessionID == "s3")
        // Zprávy zůstaly všechny — i ta odpověď, která selhala.
        #expect(messages(store).count == 6)
    }

    // MARK: - Peníze

    /// Útrata jde do **téhož** počitadla jako review (#148) — druhé počítání by o mém účtu lhalo.
    @Test("Odpověď se počítá do útraty za dnešek")
    func theAnswerCountsIntoTheDailySpend() async {
        let spend = SpendLedger(layout: layout, time: time)
        let store = store(
            asker: FakeAskRunner(answers: [AskAnswer(text: "x", sessionID: "s1", usage: RunUsage(cost: 0.04))]),
            spend: spend
        )

        ask(store, "proč?")
        await waitUntilAnswered(store)

        #expect(store.dailySpend?.cost == 0.04)
        #expect(store.dailySpend?.runs == 1)
    }

    // MARK: - Persistence

    /// **Rozhovor přežije restart** a **nový commit ho nezneplatní** — na rozdíl od nálezů, které
    /// jsou klíčované `headSha` (tvrdá podmínka č. 5). Otázka „proč se ten mutex bere“ pushem
    /// nezastará.
    @Test("Rozhovor přežije restart i nový commit")
    func theConversationSurvivesARestartAndANewCommit() async {
        let asks = AskStore(layout: layout)
        let first = store(
            asker: FakeAskRunner(answers: [AskAnswer(text: "protože", sessionID: "s1")]),
            asks: asks
        )
        ask(first, "proč?")
        await waitUntilAnswered(first)
        // Zápis si store rozjede vlastním taskem, o kterém si nedrží handle (`persistAsk`, tentýž
        // vzor jako u draftu), takže jediný jev, na který se dá čekat, je **soubor**.
        await waitUntil("rozhovor dosedne na disk", step: .milliseconds(10)) {
            (try? await asks.load(for: pr))??.messages.count == 2
        }

        // Nová instance nad toutéž cache a nad **jinou hlavou** PR.
        let restarted = store(asker: FakeAskRunner(), headSha: "cccc3333")
        await restarted.loadAskConversation(for: pr)

        #expect(restarted.askConversation(for: pr)?.messages.map(\AskMessage.text) == ["proč?", "protože"])
        #expect(restarted.askConversation(for: pr)?.sessionID == "s1")
    }

    /// **Tvrdí, že se něco NEstalo**: bez jediné otázky se na disk nic nezapíše, takže „rozhovor
    /// existuje“ nezačne znamenat „někdo si otevřel tab“.
    @Test("Otevřený tab bez otázky na disk nic nenapíše")
    func openingTheTabWritesNothing() async {
        let store = store(asker: FakeAskRunner())

        await store.loadAskConversation(for: pr)

        #expect(store.askConversation(for: pr)?.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: layout.askFile(for: pr).path()))
    }

    // MARK: - Zrušení

    /// Zrušená odpověď **neuloží nic**, ale otázka zůstane: zeptal jsem se doopravdy.
    @Test("Zrušení nechá otázku a odpověď nepřidá")
    func cancellingKeepsTheQuestion() async {
        let asker = FakeAskRunner(holdsUntilRelease: true)
        let store = store(asker: asker)

        ask(store, "proč?")
        await waitUntil("session naběhne") { !asker.requests.isEmpty }
        store.cancelAsk(for: pr)
        await waitUntilAnswered(store)

        #expect(messages(store).map(\.speaker) == [.mine])
    }
}
