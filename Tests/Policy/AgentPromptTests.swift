import Foundation
import Testing

@testable import PRism

/// Zadání pro agenta (#333) — čistá funkce, nic se nemockuje.
///
/// Testuje se **výčtem**, protože každé z těch rozhodnutí se dá pokazit potichu: položka bez
/// souboru přišpendlená k náhodnému souboru, vynechané vyřešené vlákno, o kterém se nikde
/// nenapíše, nebo chybějící hlava PR v textu, který se předává dál.
@Suite("Policy — zadání pro agenta")
struct AgentPromptTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "ondrajodas", name: "PRism"), number: 324)

    private var subject: AgentPromptSubject {
        AgentPromptSubject(pullRequest: pr, branch: "issue-320-timeout", headSha: "9c1de02aaaa")
    }

    private func comment(
        id: String = "c1",
        author: String = "ErikZigo",
        body: String = "Pozor, tohle se potká s #318.",
        at seconds: TimeInterval = 100
    ) -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: body,
            createdAt: Date(timeIntervalSince1970: seconds),
            url: URL(string: "https://github.com/ondrajodas/PRism/pull/324#discussion_r1")!
        )
    }

    private func thread(
        id: String = "t1",
        path: String = "App/Review/ClaudeReviewRunner.swift",
        line: Int? = 88,
        originalLine: Int? = 88,
        resolved: Bool = false,
        outdated: Bool = false,
        hunk: String? = nil,
        comments: [ThreadComment]? = nil
    ) -> ReviewThread {
        let items = comments ?? [comment(id: "\(id)-1", author: "Copilot", body: "The timeout is read on every run.")]
        return ReviewThread(
            id: id,
            path: path,
            line: line,
            originalLine: originalLine,
            side: .right,
            isResolved: resolved,
            isOutdated: outdated,
            diffHunk: hunk,
            comments: ConversationPage(items: items, total: items.count, hasNextPage: false)
        )
    }

    private func review(
        id: String = "r1",
        author: String = "odinuv",
        state: SubmittedReview.State? = .changesRequested,
        body: String = "Ta mez by měla být pojmenovaná na jednom místě."
    ) -> SubmittedReview {
        SubmittedReview(
            id: id,
            author: author,
            state: state,
            body: body,
            submittedAt: Date(timeIntervalSince1970: 50)
        )
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

    /// Diff, ve kterém jsou nové řádky 25–27 souboru `Cart.swift`.
    private func diff(path: String = "Cart.swift") -> Diff {
        DiffParser.parse("""
        diff --git a/\(path) b/\(path)
        --- a/\(path)
        +++ b/\(path)
        @@ -25,3 +25,3 @@
         kontext
        -staré
        +nové
         další
        """)
    }

    private func prompt(
        findings: [Finding] = [],
        dismissals: [FindingKey: FindingDismissal] = [:],
        conversation: Conversation? = nil,
        diff: Diff? = nil,
        options: AgentPromptOptions = .standard,
        subject: AgentPromptSubject? = nil
    ) -> AgentPrompt {
        Policy.agentPrompt(
            for: subject ?? self.subject,
            findings: findings,
            dismissals: dismissals,
            conversation: conversation,
            diff: diff,
            options: options
        )
    }

    // MARK: - Sběr

    /// Čtyři druhy naráz — a všechny čtyři musí v textu být poznat, protože podle původu agent
    /// pozná, komu se dá odpovědět.
    @Test("Sbírá nálezy, vlákna, komentáře pod PR i souhrny review")
    func collectsAllFourKinds() {
        let result = prompt(
            findings: [makeFinding(file: "Cart.swift", line: 26, summary: "sražení do mezí")],
            conversation: conversation(
                threads: [thread()],
                comments: [comment()],
                reviews: [review()]
            )
        )

        #expect(result.included.total == 4)
        #expect(result.text.contains("nález (code-review, correctness)"))
        #expect(result.text.contains("vlákno (Copilot, nevyřešené)"))
        #expect(result.text.contains("komentář v diskuzi — ErikZigo"))
        #expect(result.text.contains("souhrn review — odinuv, vyžádal změny"))
    }

    /// Prázdná obálka review (bez verdiktu i bez prózy) je jen nosič řádkových komentářů —
    /// v zadání by z ní byla položka „někdo napsal review: (nic)“.
    @Test("Review bez verdiktu a bez prózy se zahodí")
    func dropsEmptyReviewEnvelopes() {
        let result = prompt(conversation: conversation(reviews: [review(state: .commented, body: "")]))

        #expect(result.included.total == 0)
        #expect(result.inventory.total == 0)
    }

    /// Schválení bez komentáře je plnohodnotný verdikt (čtvrtina vzorku u #63), takže se
    /// nezahazuje — a v zadání je to informace, že někdo PR odsouhlasil.
    @Test("Schválení s prázdným tělem zůstává")
    func keepsAnEmptyApproval() {
        let result = prompt(conversation: conversation(reviews: [review(state: .approved, body: "")]))

        #expect(result.included.total == 1)
        #expect(result.text.contains("souhrn review — odinuv, schválil"))
    }

    // MARK: - Co se vynechává

    /// Vyřešené vlákno ani odmítnutý nález nejdou do textu, ale **v inventáři zůstávají** —
    /// z něj se v panelu kreslí počet u vypnuté volby a v sheetu odznak „vynecháno“.
    @Test("Vyřešená vlákna a odmítnuté nálezy se vynechají, ale spočítají")
    func omitsResolvedAndDismissedButCountsThem() {
        let dismissed = makeFinding(file: "Cart.swift", line: 26, summary: "prý chyba")
        let result = prompt(
            findings: [dismissed],
            dismissals: makeDismissals([dismissed]),
            conversation: conversation(threads: [thread(resolved: true)])
        )

        #expect(result.included.total == 0)
        #expect(result.inventory.count(of: .resolvedThreads) == 1)
        #expect(result.inventory.count(of: .dismissedFindings) == 1)
        #expect(result.omittedCount == 2)
        #expect(!result.text.contains("vlákno ("))
        #expect(!result.text.contains("prý chyba"))
    }

    /// Zapnutá volba je přibere — `vyřešeno` je stav vlákna na GitHubu, ne důkaz, že je hotovo.
    @Test("Zapnutá volba přibere vyřešená vlákna i odmítnuté nálezy")
    func includesThemWhenAskedFor() {
        let dismissed = makeFinding(file: "Cart.swift", line: 26, summary: "prý chyba")
        let result = prompt(
            findings: [dismissed],
            dismissals: makeDismissals([dismissed]),
            conversation: conversation(threads: [thread(resolved: true)]),
            options: AgentPromptOptions(enabled: [.resolvedThreads, .dismissedFindings])
        )

        #expect(result.included.total == 2)
        #expect(result.text.contains("vlákno (Copilot, vyřešené)"))
        // Odmítnutý nález se **označí**: agent má vědět, že tomuhle člověk nevěří.
        #expect(result.text.contains("ODMÍTNUTÝ NÁLEZ (neplatný)"))
    }

    /// Odmítnutý nález neblokuje ani v zadání — je to totéž pravidlo jako u odznaku v seznamu.
    @Test("Odmítnutý nález se nepočítá jako blokující")
    func neverCountsADismissedFindingAsBlocking() {
        let dismissed = makeFinding(file: "Cart.swift", line: 26, category: "correctness")
        let result = prompt(
            findings: [dismissed],
            dismissals: makeDismissals([dismissed]),
            conversation: conversation(),
            options: AgentPromptOptions(enabled: [.dismissedFindings])
        )

        #expect(result.blocking == 0)
        #expect(!result.text.contains("BLOKUJE"))
    }

    // MARK: - Rozdělení po souborech

    /// Souhrn review a komentář pod PR se k žádnému řádku nevážou, takže mají vlastní sekci —
    /// a ta stojí **před** soubory.
    @Test("Co nemá soubor, jde do vlastní sekce před soubory")
    func putsFilelessItemsFirst() {
        let sections = Policy.agentPromptSections([
            .finding(makeFinding(file: "Cart.swift", line: 26), dismissedAs: nil),
            .review(review()),
            .comment(comment()),
        ])

        #expect(sections.map(\.file) == [nil, "Cart.swift"])
        #expect(sections.first?.items.count == 2)
    }

    /// Pořadí v sekci bez souboru je z návrhu: souhrn review, pak komentář v diskuzi.
    @Test("V sekci bez souboru jde souhrn review před komentář")
    func ordersReviewsBeforeComments() {
        let sections = Policy.agentPromptSections([
            .comment(comment(at: 10)),
            .review(review()),
        ])

        #expect(sections.first?.items.first == .review(review()))
    }

    /// Nález bez souboru (chybějící test, poznámka k architektuře) je tentýž případ jako komentář
    /// pod PR — přišpendlit ho k náhodnému souboru by lhalo o tom, kde se to řeší.
    @Test("Nález bez souboru skončí v sekci bez souboru")
    func putsAFindingWithoutFileInTheWholeSection() {
        let sections = Policy.agentPromptSections([
            .finding(makeFinding(file: nil, line: nil, summary: "chybí test"), dismissedAs: nil),
        ])

        #expect(sections.map(\.file) == [nil])
    }

    /// Soubor, ve kterém něco blokuje, jde první; zbytek abecedně. Deterministické pořadí je
    /// podmínka toho, aby se text dvou po sobě sestavených zadání dal porovnat.
    @Test("Soubor s blokujícím nálezem jde první, ostatní abecedně")
    func ordersBlockingFileFirst() {
        let sections = Policy.agentPromptSections([
            .thread(thread(path: "Zzz.swift")),
            .thread(thread(id: "t2", path: "Aaa.swift")),
            .finding(makeFinding(file: "Mmm.swift", line: 5, category: "correctness"), dismissedAs: nil),
        ])

        #expect(sections.map(\.file) == ["Mmm.swift", "Aaa.swift", "Zzz.swift"])
    }

    /// Uvnitř souboru podle řádku; co platí pro celý soubor, jde nahoru.
    @Test("V sekci souboru se řadí podle řádku, položka bez řádku je první")
    func ordersByLineWithinAFile() {
        let sections = Policy.agentPromptSections([
            .finding(makeFinding(file: "Cart.swift", line: 40), dismissedAs: nil),
            .finding(makeFinding(file: "Cart.swift", line: nil, summary: "celý soubor"), dismissedAs: nil),
            .thread(thread(path: "Cart.swift", line: 12)),
        ])

        #expect(sections.count == 1)
        #expect(sections.first?.items.map(\.line) == [nil, 12, 40])
    }

    // MARK: - Hlavička textu

    /// Hlava PR patří do textu (tvrdá podmínka č. 5): zadání se předává dál, takže musí jít
    /// poznat, proti čemu vzniklo — jinak agent opraví řádky, které mezitím zmizely.
    @Test("Hlavička nese repo, číslo, větev a hlavu")
    func namesThePullRequestAndItsHead() {
        let text = prompt(findings: [makeFinding(file: "Cart.swift", line: 26)]).text

        #expect(text.contains("ondrajodas/PRism#324"))
        #expect(text.contains("ve větvi issue-320-timeout"))
        #expect(text.contains("hlava 9c1de02"))
    }

    /// Neznámá hlava se **řekne**. Mlčení by vypadalo, že zadání platí pro dnešní kód.
    @Test("Bez známé hlavy to text napíše")
    func saysWhenTheHeadIsUnknown() {
        let text = prompt(
            findings: [makeFinding(file: "Cart.swift", line: 26)],
            subject: AgentPromptSubject(pullRequest: pr)
        ).text

        #expect(text.contains("hlavu PR aplikace nezná"))
        #expect(!text.contains("ve větvi"))
    }

    /// Nenačtená konverzace je **mezera v tom, co aplikace ví**, ne moje rozhodnutí — proto se
    /// píše i do textu, který jde dál. Vypnuté volby se tam naopak neopisují.
    @Test("Nenačtená konverzace je napsaná v textu")
    func saysWhenTheConversationIsMissing() {
        let result = prompt(findings: [makeFinding(file: "Cart.swift", line: 26)], conversation: nil)

        #expect(!result.isConversationLoaded)
        #expect(result.text.contains("Konverzace k PR se nenačetla"))
    }

    @Test("S načtenou konverzací tam ta věta není")
    func staysQuietWhenTheConversationIsLoaded() {
        let result = prompt(conversation: conversation(comments: [comment()]))

        #expect(result.isConversationLoaded)
        #expect(!result.text.contains("Konverzace k PR se nenačetla"))
    }

    // MARK: - Vlákna

    /// „O tomhle už se mluvilo“ mění zadání: bez počtu odpovědí napíše agent totéž znovu.
    @Test("Vlákno nese počet odpovědí i jejich text")
    func carriesRepliesOfAThread() {
        let result = prompt(conversation: conversation(threads: [thread(comments: [
            comment(id: "a", author: "Copilot", body: "cache to"),
            comment(id: "b", author: "ondrajodas", body: "změřím to"),
            comment(id: "c", author: "Copilot", body: "ok"),
        ])]))

        #expect(result.text.contains("vlákno (Copilot, nevyřešené, 2 odpovědi)"))
        #expect(result.text.contains("Odpověď od ondrajodas: změřím to"))
    }

    /// Zastaralé vlákno má jen `originalLine`. Umístí se podle něj **a napíše se, že je
    /// zastaralé** — tvrdit dnešní řádek u kotvy, která platila pro starý head, je horší než nic.
    @Test("Zastaralé vlákno se umístí podle původního řádku a řekne to")
    func marksAnOutdatedThread() {
        let result = prompt(conversation: conversation(threads: [
            thread(line: nil, originalLine: 88, outdated: true),
        ]))

        #expect(result.text.contains("řádek 88 (zastaralé — číslo platí pro starší commit)"))
    }

    /// Useknutá stránka odpovědí se **hlásí**: „tohle je celé vlákno“ nad polovinou diskuze je
    /// tvrzení, které data neunesou.
    @Test("Useknuté vlákno to v textu přizná")
    func admitsATruncatedThread() {
        let items = [comment(id: "a", author: "Copilot", body: "první")]
        let truncated = ReviewThread(
            id: "t9",
            path: "Cart.swift",
            line: 26,
            originalLine: 26,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(items: items, total: 5, hasNextPage: true)
        )
        let result = prompt(conversation: conversation(threads: [truncated]))

        #expect(result.text.contains("dorazila jen část odpovědí"))
    }

    // MARK: - Diff hunk

    /// U vlákna je hunk snímek z commitu, na kterém vzniklo — u zastaralého je to jediný kód,
    /// o kterém je řeč.
    @Test("Hunk vlákna jde do textu z diffHunku")
    func attachesTheThreadHunk() {
        let result = prompt(conversation: conversation(threads: [
            thread(hunk: "@@ -85,3 +85,4 @@\n+let timeout = 60"),
        ]))

        #expect(result.text.contains("```diff"))
        #expect(result.text.contains("+let timeout = 60"))
    }

    /// U nálezu se hunk hledá v načteném diffu podle čísla řádku — a nese znaky změny, protože
    /// tady jde o to, co se v tom místě změnilo (na rozdíl od kopie kódu do editoru).
    @Test("Hunk nálezu se najde v diffu a nese znaky změny")
    func attachesTheFindingHunkFromTheDiff() {
        let result = prompt(
            findings: [makeFinding(file: "Cart.swift", line: 26)],
            conversation: conversation(),
            diff: diff()
        )

        #expect(result.text.contains("@@ -25,3 +25,3 @@"))
        #expect(result.text.contains("-staré"))
        #expect(result.text.contains("+nové"))
    }

    /// Vypnutá volba hunky **nepřiloží ani u vláken**, kde se mají kde vzít bez diffu.
    @Test("Vypnutý hunk zmizí u nálezu i u vlákna")
    func dropsHunksWhenTheOptionIsOff() {
        let result = prompt(
            findings: [makeFinding(file: "Cart.swift", line: 26)],
            conversation: conversation(threads: [thread(hunk: "@@ -85,3 +85,4 @@\n+let timeout = 60")]),
            diff: diff(),
            options: AgentPromptOptions(enabled: [.findings, .unresolvedThreads])
        )

        #expect(!result.text.contains("```diff"))
        #expect(result.included.total == 2)
    }

    /// Bez načteného diffu se u nálezu nepřiloží nic — položka ale zůstává. Text tím ztrácí
    /// pohodlí, ne obsah.
    @Test("Bez diffu zůstane nález v textu bez hunku")
    func keepsTheFindingWithoutADiff() {
        let result = prompt(findings: [makeFinding(file: "Cart.swift", line: 26)], diff: nil)

        #expect(result.included.count(of: .findings) == 1)
        #expect(!result.text.contains("```diff"))
    }

    // MARK: - Blokující nález a scénář

    @Test("Blokující nález je v nadpisu označený")
    func marksABlockingFinding() {
        let result = prompt(findings: [
            makeFinding(file: "Cart.swift", line: 26, category: "correctness"),
            makeFinding(file: "Zzz.swift", line: 5, category: "style", verdict: .plausible),
        ])

        #expect(result.blocking == 1)
        #expect(result.text.contains("nález (code-review, correctness) — BLOKUJE"))
        #expect(result.text.contains("nález (code-review, style)"))
    }

    @Test("Scénář selhání jde do textu, když ho reviewer napsal")
    func carriesTheFailureScenario() {
        let result = prompt(findings: [
            makeFinding(file: "Cart.swift", line: 26, failureScenario: "uživatel napíše 120"),
        ])

        #expect(result.text.contains("Kdy to selže: uživatel napíše 120"))
    }

    // MARK: - Prázdno a velikost

    @Test("Bez čehokoli je zadání prázdné a text to řekne")
    func handlesAnEmptyPullRequest() {
        let result = prompt(conversation: conversation())

        #expect(result.isEmpty)
        #expect(result.text.contains("Aplikace nemá co předat"))
    }

    @Test("Velikost textu se počítá v bajtech UTF-8")
    func measuresTheTextInBytes() {
        let result = prompt(findings: [makeFinding(file: "Cart.swift", line: 26)])

        #expect(result.byteCount == result.text.utf8.count)
        #expect(result.byteCount > 0)
    }

    // MARK: - Název souboru

    /// Dva soubory z různých commitů téhož PR se od sebe musí poznat i po týdnu ve složce.
    @Test("Název souboru nese repo, číslo PR a hlavu")
    func namesTheFileByPullRequestAndHead() {
        #expect(Policy.agentPromptFileName(for: subject) == "PRism-324-zadani-9c1de02.md")
    }

    @Test("Bez známé hlavy se název obejde bez ní")
    func namesTheFileWithoutAHead() {
        let name = Policy.agentPromptFileName(for: AgentPromptSubject(pullRequest: pr))

        #expect(name == "PRism-324-zadani.md")
        // Lomítko v názvu souboru je problém pokaždé, kdežto shoda dvou vlastníků jednou za život.
        #expect(!name.contains("/"))
    }

    // MARK: - Volby

    @Test("Výchozí volba bere nevyřízené a hunky, ne vyřešené a odmítnuté")
    func hasSaneDefaults() {
        let options = AgentPromptOptions.standard

        #expect(options.includes(.findings))
        #expect(options.includes(.unresolvedThreads))
        #expect(options.includes(.comments))
        #expect(options.includes(.reviews))
        #expect(options.includes(.diffHunks))
        #expect(!options.includes(.resolvedThreads))
        #expect(!options.includes(.dismissedFindings))
    }

    @Test("Přepínač volbu zapne i vypne")
    func togglesBothWays() {
        var options = AgentPromptOptions.standard
        options.toggle(.findings)
        #expect(!options.includes(.findings))
        options.toggle(.findings)
        #expect(options.includes(.findings))
    }

    /// `diffHunks` položky nepočítá, takže se na jeho počet nemá ptát — a nula by tvrdila, že se
    /// spočítalo a vyšlo prázdno.
    @Test("Počet u diff hunku není")
    func hasNoCountForHunks() {
        let result = prompt(findings: [makeFinding(file: "Cart.swift", line: 26)])

        #expect(result.inventory.count(of: .diffHunks) == nil)
        #expect(result.inventory.count(of: .findings) == 1)
    }
}
