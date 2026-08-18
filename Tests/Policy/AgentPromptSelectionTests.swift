import Foundation
import Testing

@testable import PRism

/// Výběr jednotlivých položek do zadání (#377) — čistá funkce, nic se nemockuje.
///
/// Nejcennější tvrzení tady jsou ta, která říkají, že se něco **nestalo**: odškrtnutá položka není
/// v textu, ale **nezmizela ze seznamu**; počet v hlavičce se **nerozešel** s počtem položek
/// v textu; heuristika `shrnuje diff` **nevypnula** souhrn, který diff nepřevypráví. Všechny tři
/// se dají pokazit potichu — obrazovka bude vypadat správně a lhát o tom, co se zkopíruje.
@Suite("Policy — výběr položek do zadání (#377)")
struct AgentPromptSelectionTests {
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
        author: String = "Copilot",
        resolved: Bool = false
    ) -> ReviewThread {
        let items = [comment(id: "\(id)-1", author: author, body: "The timeout is read on every run.")]
        return ReviewThread(
            id: id,
            path: path,
            line: line,
            originalLine: line,
            side: .right,
            isResolved: resolved,
            isOutdated: false,
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
        viewer: String = "ondrajodas",
        threads: [ReviewThread] = [],
        comments: [ThreadComment] = [],
        reviews: [SubmittedReview] = []
    ) -> Conversation {
        Conversation(
            viewer: viewer,
            reviews: ConversationPage(items: reviews, total: reviews.count, hasNextPage: false),
            threads: ConversationPage(items: threads, total: threads.count, hasNextPage: false),
            comments: ConversationPage(items: comments, total: comments.count, hasNextPage: false)
        )
    }

    private func selection(
        findings: [Finding] = [],
        dismissals: [FindingKey: FindingDismissal] = [:],
        conversation: Conversation? = nil,
        options: AgentPromptOptions = .standard,
        toggled: Set<String> = [],
        only: Set<String>? = nil
    ) -> AgentPromptSelection {
        Policy.agentPromptSelection(
            for: subject,
            findings: findings,
            dismissals: dismissals,
            conversation: conversation,
            options: options,
            toggled: toggled,
            only: only
        )
    }

    /// Kolik položek text doopravdy nese — počítá se z nadpisů `###`, tedy z toho, co v něm je,
    /// ne z toho, co jsme si o něm mysleli.
    private func itemsInText(of prompt: AgentPrompt) -> Int {
        TextLines.nonEmpty(prompt.text).count { $0.hasPrefix("### ") }
    }

    // MARK: - Odškrtnutá položka

    /// **Celý smysl issue.** Odškrtnutá položka v textu není — a text je to jediné, co se předává.
    @Test("Odškrtnutá položka není v textu")
    func leavesADeselectedItemOutOfTheText() {
        let kept = comment(id: "c1", body: "tohle chci předat")
        let dropped = comment(id: "c2", body: "tohle ne")
        let result = selection(
            conversation: conversation(comments: [kept, dropped]),
            toggled: [AgentPromptItem.comment(dropped).id]
        )

        #expect(result.prompt.text.contains("tohle chci předat"))
        #expect(!result.prompt.text.contains("tohle ne"))
        #expect(result.prompt.included.total == 1)
        #expect(result.prompt.handed == [AgentPromptItem.comment(kept).id])
    }

    /// **A přesto zůstává v seznamu.** Tiše zmizelá položka vypadá jako „tohle je všechno“ —
    /// tatáž úvaha jako u vyřešených vláken a odmítnutých nálezů.
    @Test("Odškrtnutá položka zůstává v seznamu")
    func keepsADeselectedItemVisible() {
        let dropped = comment(id: "c2", body: "tohle ne")
        let result = selection(
            conversation: conversation(comments: [comment(), dropped]),
            toggled: [AgentPromptItem.comment(dropped).id]
        )

        let picks = result.groups.flatMap(\.picks)
        #expect(picks.count == 2)
        #expect(result.available == 2)
        let pick = picks.first { $0.id == AgentPromptItem.comment(dropped).id }
        #expect(pick?.isIncluded == false)
        // Ručně odškrtnutá položka **nemá důvod**: znám ho, byl jsem to já.
        #expect(pick?.exclusion == nil)
    }

    /// Vypnutá položka jde zapnout — i ta, které aplikace vypnula celý druh.
    @Test("Vypnutý druh se dá zapnout u jedné položky")
    func reenablesAnItemFromASwitchedOffKind() {
        let resolved = thread(id: "t9", resolved: true)
        let id = AgentPromptItem.thread(resolved).id
        let off = selection(conversation: conversation(threads: [resolved]))
        let on = selection(conversation: conversation(threads: [resolved]), toggled: [id])

        #expect(off.groups.flatMap(\.picks).first?.exclusion == .resolved)
        #expect(off.prompt.included.total == 0)
        #expect(on.prompt.included.total == 1)
        #expect(on.prompt.text.contains("vlákno (Copilot, vyřešené)"))
    }

    // MARK: - Počet v hlavičce se rovná počtu v textu

    /// Kdyby se rozešly, obrazovka lže o tom, co se zkopíruje. Tvrdí se to na **všech** stavech
    /// výběru, ne na jednom: prázdný, plný i uprostřed.
    @Test("Počet vybraných se rovná počtu položek v textu")
    func agreesWithTheText() {
        let comments = [comment(id: "c1"), comment(id: "c2", body: "druhý")]
        let ids = comments.map { AgentPromptItem.comment($0).id }
        let material = conversation(
            threads: [thread()],
            comments: comments,
            reviews: [review()]
        )

        for toggled in [Set<String>(), Set([ids[0]]), Set(ids)] {
            let result = selection(
                findings: [makeFinding(file: "Cart.swift", line: 26, summary: "sražení do mezí")],
                conversation: material,
                toggled: toggled
            )

            #expect(result.selected == result.prompt.included.total)
            #expect(result.selected == itemsInText(of: result.prompt))
            // Nález, vlákno, dva komentáře a souhrn review — ze seznamu odškrtnutím nic nemizí.
            #expect(result.available == 5)
        }
    }

    /// Součet vybraných přes grupy je totéž číslo jako v hlavičce — grupy jsou jen jiné dělení
    /// téhož seznamu.
    @Test("Součet grup se rovná počtu vybraných")
    func sumsUpAcrossGroups() {
        let result = selection(
            findings: [makeFinding(file: "Cart.swift", line: 26)],
            conversation: conversation(threads: [thread()], comments: [comment()], reviews: [review()])
        )

        #expect(result.groups.map(\.kind) == [.findings, .threads, .reviews, .comments])
        #expect(result.groups.reduce(0) { $0 + $1.selected } == result.prompt.included.total)
        #expect(result.groups.allSatisfy { $0.countLabel == "1 z 1" })
    }

    // MARK: - Předvybírá aplikace

    /// Vlastní komentář pod PR se předvybere jako **vypnutý**, a s důvodem: release notes, které
    /// jsem si sám napsal, jsou nejdelší blok v promptu a agentovi neříkají nic.
    @Test("Vlastní komentář pod PR je vypnutý s důvodem")
    func preselectsMyOwnCommentOff() {
        let mine = comment(id: "c2", author: "ondrajodas", body: "# Release Notes")
        let result = selection(conversation: conversation(comments: [comment(), mine]))

        let pick = result.groups.flatMap(\.picks).first { $0.id == AgentPromptItem.comment(mine).id }
        #expect(pick?.isIncluded == false)
        #expect(pick?.exclusion == .mine)
        #expect(!result.prompt.text.contains("Release Notes"))
    }

    /// **Vlastní se pozná i tehdy, když PR psal agent pod mým účtem** (změřeno u #330): `isMine`
    /// bere `viewer` z konverzace, tedy přihlášený účet, ne autora PR. Kdyby se ptalo autora PR,
    /// vypadal by na mých agentských PR každý komentář jako vlastní.
    @Test("Vlastní komentář se pozná podle viewera, ne podle autora PR")
    func recognizesMineByViewer() {
        let mine = comment(id: "c1", author: "ondrajodas")
        let foreign = comment(id: "c2", author: "odinuv")
        let result = selection(conversation: conversation(viewer: "ondrajodas", comments: [mine, foreign]))

        let picks = result.groups.flatMap(\.picks)
        #expect(picks.first { $0.id == AgentPromptItem.comment(mine).id }?.exclusion == .mine)
        #expect(picks.first { $0.id == AgentPromptItem.comment(foreign).id }?.exclusion == nil)

        // Tentýž materiál očima někoho jiného: „vlastní“ se přehodí na druhý komentář. Je to vztah
        // mezi komentářem a tím, kdo se dívá, ne vlastnost komentáře (viz `Conversation.viewer`).
        let asSomebodyElse = selection(conversation: conversation(viewer: "odinuv", comments: [mine, foreign]))
        let others = asSomebodyElse.groups.flatMap(\.picks)
        #expect(others.first { $0.id == AgentPromptItem.comment(mine).id }?.exclusion == nil)
        #expect(others.first { $0.id == AgentPromptItem.comment(foreign).id }?.exclusion == .mine)
    }

    /// Vlákno, které jsem si na vlastním PR založil sám, je poznámka „tady se musím vrátit“ — tedy
    /// **práce**, ne cizí názor (rozhodnutí #333). Předvybrání ho proto nesundá.
    @Test("Vlastní vlákno u řádku se nepředvybírá jako vypnuté")
    func keepsMyOwnThread() {
        let result = selection(conversation: conversation(threads: [thread(author: "ondrajodas")]))

        #expect(result.groups.flatMap(\.picks).first?.exclusion == nil)
        #expect(result.prompt.included.total == 1)
    }

    /// Souhrn, ve kterém kromě nadpisů nic není, je nulová informace. Není to heuristika, ale
    /// syntaktický test — proto se dá tvrdit výčtem.
    @Test(
        "Souhrn bez obsahu je vypnutý",
        arguments: [
            "",
            "## Review\n",
            "### Reviewed changes\n\n#### Nic\n",
            "<!-- auto-generated -->\n## Review\n",
        ]
    )
    func preselectsAnEmptySummaryOff(body: String) {
        let result = selection(conversation: conversation(reviews: [review(state: .approved, body: body)]))

        #expect(result.groups.flatMap(\.picks).first?.exclusion == .empty)
        #expect(result.prompt.included.total == 0)
    }

    /// A naopak: souhrn s jednou větou pod nadpisem obsah **má**.
    @Test("Souhrn s prózou pod nadpisem obsah má")
    func keepsASummaryWithProse() {
        let result = selection(
            conversation: conversation(reviews: [review(body: "## Poznámka\n\nMez pojmenuj na jednom místě.")])
        )

        #expect(result.groups.flatMap(\.picks).first?.exclusion == nil)
        #expect(result.prompt.included.total == 1)
    }

    // MARK: - Heuristika `shrnuje diff`

    /// Copilotův `Pull request overview` je převyprávěný diff, který agent má sám — **fixture je
    /// skutečné review** na `ondrajodas/PRism#378`, včetně `CRLF` na devíti řádcích.
    @Test("Copilotův přehled PR se předvybere jako vypnutý")
    func preselectsCopilotsOverviewOff() throws {
        let body = try Fixture.text("gh/review-copilot-overview.md")
        // Doklad, že fixture pořád nese `CRLF`: kdyby ho `core.autocrlf` normalizoval, přestala by
        // tvrdit, že heuristika dělí řádky přes `TextLines` (#295).
        #expect(body.contains("\r\n"))

        let result = selection(
            conversation: conversation(reviews: [review(author: "copilot-pull-request-reviewer[bot]", state: .commented, body: body)])
        )

        #expect(Policy.summarizesDiff(body))
        #expect(result.groups.flatMap(\.picks).first?.exclusion == .summarizesDiff)
        #expect(result.prompt.included.total == 0)
    }

    /// **Heuristika nevypíná všechno** — a tohle je ten test, kvůli kterému je jedna a na jednom
    /// místě. Fixture je skutečné `CHANGES_REQUESTED` review z `cli/cli#13084`: próza, odrážky,
    /// nadpis `### Further questions` — tedy přesně to, co se předat musí.
    @Test("Souhrn, který diff nepřevypráví, heuristika nevypne")
    func keepsASummaryThatDoesNotRetellTheDiff() throws {
        let body = try Fixture.text("gh/review-changes-requested.md")
        let result = selection(conversation: conversation(reviews: [review(author: "babakks", body: body)]))

        #expect(!Policy.summarizesDiff(body))
        #expect(result.groups.flatMap(\.picks).first?.exclusion == nil)
        #expect(result.prompt.included.total == 1)
        #expect(result.prompt.text.contains("Add tests for discussion client methods."))
    }

    /// Zmínka v próze nadpis není. Kdyby stačilo `contains`, vypadl by ze zadání kolegův komentář
    /// o tom, co v Copilotově přehledu stálo.
    @Test("Zmínka o přehledu v próze heuristice nesedí")
    func needsAHeadingNotAMention() {
        let body = "Viz Pull request overview výš — ta tabulka souborů je mimo, chybí v ní Cart.swift."

        #expect(!Policy.summarizesDiff(body))
    }

    /// Starší formát Copilotova přehledu **tabulku souborů nemá** (změřeno na `cli/cli#11451`),
    /// takže se pozná jedině z nadpisu — a přesně proto tabulka není druhá podmínka heuristiky.
    @Test("Starší přehled bez tabulky souborů heuristice sedí")
    func matchesTheOlderOverviewWithoutATable() {
        let body = """
            ## Pull Request Overview

            This PR fixes an error handling issue in the `FetchRefSHA` function.

            - Replaces generic JSON decoding error with specific `ErrReleaseNotFound` error
            """

        #expect(Policy.summarizesDiff(body))
        #expect(!body.contains("| File |"))
    }

    /// Heuristika se pouští **jen na souhrny review**. Vlákno u řádku ani nález nemají jak
    /// převyprávět diff — a vypnout je z textu na základě nadpisu v prvním komentáři by znamenalo
    /// zahodit práci.
    @Test("Vlákno s nadpisem přehledu se nevypne")
    func doesNotJudgeThreadsByTheHeuristic() {
        let heading = comment(id: "x1", author: "Copilot", body: "## Pull request overview\n\nTady to chybí.")
        let threadWithHeading = ReviewThread(
            id: "t5",
            path: "Cart.swift",
            line: 12,
            originalLine: 12,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(items: [heading], total: 1, hasNextPage: false)
        )
        let result = selection(conversation: conversation(threads: [threadWithHeading]))

        #expect(result.groups.flatMap(\.picks).first?.exclusion == nil)
        #expect(result.prompt.included.total == 1)
    }

    // MARK: - Rozbalení položky

    /// Rozbalení drží `Policy`, ne view — a rozbalit se nedá to, co nic nenese: šipka nad prázdným
    /// textem je kliknutí, po kterém se nic nestane.
    @Test("Rozbalení: sbaleno, rozbaleno, a u prázdné položky nic")
    func decidesTheDisclosure() throws {
        let approval = review(state: .approved, body: "")
        let withProse = review(id: "r2", body: "Mez pojmenuj na jednom místě.")
        let result = selection(conversation: conversation(reviews: [approval, withProse]))
        let picks = result.groups.flatMap(\.picks)
        let empty = try #require(picks.first { $0.id == AgentPromptItem.review(approval).id })
        let full = try #require(picks.first { $0.id == AgentPromptItem.review(withProse).id })

        #expect(Policy.pickDisclosure(of: empty, toggled: []) == AgentPromptPickDisclosure.none)
        #expect(Policy.pickDisclosure(of: empty, toggled: [empty.id]) == AgentPromptPickDisclosure.none)
        #expect(Policy.pickDisclosure(of: full, toggled: []) == .collapsed)
        #expect(Policy.pickDisclosure(of: full, toggled: [full.id]) == .expanded)
    }

    /// Rozbalený text je **tentýž**, jaký jde do zadání — druhá cesta k němu by dřív nebo později
    /// ukázala něco jiného, než co odejde. U vlákna proto nese i odpovědi.
    @Test("Rozbalený text položky je ten, co jde do zadání")
    func showsTheSameTextAsThePrompt() {
        let items = [
            comment(id: "t1-1", author: "Copilot", body: "The timeout is read on every run."),
            comment(id: "t1-2", author: "ondrajodas", body: "Změřím to."),
        ]
        let discussion = ReviewThread(
            id: "t1",
            path: "Cart.swift",
            line: 12,
            originalLine: 12,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(items: items, total: 2, hasNextPage: false)
        )
        let result = selection(conversation: conversation(threads: [discussion]))
        let pick = result.groups.flatMap(\.picks).first

        #expect(pick?.text.contains("The timeout is read on every run.") == true)
        #expect(pick?.text.contains("Odpověď od ondrajodas: Změřím to.") == true)
        #expect(result.prompt.text.contains(pick?.text ?? "nic"))
    }

    /// Řádek nese autora a místo — podle toho se pozná, co je signál. Co místo nemá, ho **nemá
    /// vymyšlené**.
    @Test("Řádek nese autora a soubor s řádkem")
    func describesThePick() {
        let result = selection(
            findings: [makeFinding(file: "Cart.swift", line: 26, category: "correctness", summary: "sražení do mezí")],
            conversation: conversation(comments: [comment()])
        )
        let picks = result.groups.flatMap(\.picks)
        let finding = picks.first { $0.item.kind == .findings }
        let discussion = picks.first { $0.item.kind == .comments }

        #expect(finding?.place == "Cart.swift:26")
        #expect(finding?.author == "code-review")
        // Blokující nález to má napsané v titulku — je to ten jediný, kvůli kterému se nemerguje.
        #expect(finding?.title == "sražení do mezí — BLOKUJE")
        #expect(finding?.meta.hasPrefix("nález · code-review · ") == true)
        #expect(discussion?.place == nil)
        #expect(discussion?.author == "ErikZigo")
    }

    // MARK: - Zúžené zadání (#334)

    /// `Sestavit i tak (jen nové vlákno)` nabízí **jen ten materiál, ze kterého vzniklo**: nálezy
    /// proti staré hlavě do něj nepatří, takže v seznamu být nemají — nabízet zaškrtávátko
    /// u položky, kterou zadání nepřijme, by lhalo.
    @Test("Zúžené zadání má v seznamu jen svůj materiál")
    func narrowsTheListWithThePrompt() {
        let fresh = comment(id: "c9", author: "odinuv", body: "ještě tohle")
        let result = selection(
            findings: [makeFinding(file: "Cart.swift", line: 26)],
            conversation: conversation(comments: [fresh]),
            only: [AgentPromptItem.comment(fresh).id]
        )

        #expect(result.available == 1)
        #expect(result.selected == 1)
        #expect(result.only == [AgentPromptItem.comment(fresh).id])
        // Inventář zůstává celý (#334) — počty u voleb v panelu dál mluví o tom, co na PR je.
        #expect(result.prompt.inventory.total == 2)
    }

    // MARK: - Texty

    /// Odznak `vynecháno` se skloňuje i ve slovese — `1 vyřešené vynecháno` je střední rod,
    /// `1 odmítnutý vynechán` mužský. Jedna tabulka tvarů by z toho udělala češtinu, které si
    /// nikdo nevšimne dřív, než se podívá na obrazovku.
    @Test("Odznak vynechaných se skloňuje")
    func declinesTheOmittedPill() {
        #expect(AgentPromptExclusion.resolved.omittedLabel(1) == "1 vyřešené vynecháno")
        #expect(AgentPromptExclusion.resolved.omittedLabel(2) == "2 vyřešená vynechána")
        #expect(AgentPromptExclusion.resolved.omittedLabel(5) == "5 vyřešených vynecháno")
        #expect(AgentPromptExclusion.dismissed.omittedLabel(1) == "1 odmítnutý vynechán")
        #expect(AgentPromptExclusion.mine.omittedLabel(1) == "1 vlastní vynechán")
        #expect(AgentPromptExclusion.empty.omittedLabel(2) == "2 souhrny bez obsahu vynechány")
        #expect(AgentPromptExclusion.summarizesDiff.omittedLabel(1) == "1 souhrn diffu vynechán")
        // Vypnutý druh odznak z důvodu **nemá** — skládá se z volby, ať je vidět, který druh to je.
        #expect(AgentPromptExclusion.kindOff.omittedLabel(2) == nil)
    }

    /// Věta pod seznamem mluví jen o tom, co předvybrala **aplikace**. Vypnutý druh a vyřešená
    /// vlákna jsou moje volba a vysvětlovat mi vlastní rozhodnutí je šum.
    @Test("Věta o předvybraném mluví jen o tom, co poznala aplikace")
    func explainsOnlyWhatTheAppPreselected() {
        let mine = comment(id: "c2", author: "ondrajodas", body: "# Release Notes")
        let empty = review(id: "r2", state: .approved, body: "")
        let result = selection(
            conversation: conversation(threads: [thread(resolved: true)], comments: [mine], reviews: [empty])
        )

        let note = AgentPromptSheet.preselectionNote(result.groups)
        #expect(note == "Vypnuté jsem předvybral: 1 vlastní, 1 souhrn bez obsahu. Jdou zapnout.")
        #expect(note?.contains("vyřešené") == false)
    }

    /// Bez předvybírání se věta **nekreslí vůbec** — řádek, který říká „nepředvybral jsem nic“,
    /// zabírá místo a neřekne nic.
    @Test("Bez předvybraného se věta nekreslí")
    func staysQuietWithoutPreselection() {
        let result = selection(conversation: conversation(comments: [comment()]))

        #expect(AgentPromptSheet.preselectionNote(result.groups) == nil)
    }

    /// Věta pod nadpisem `Text` musí říct, že je náhled **funkcí výběru** — bez ní se souvislost
    /// mezi seznamem a textem z obrazovky nepozná.
    @Test("Věta nad textem říká, že se přepočítal podle výběru")
    func saysThatTheTextFollowsTheSelection() {
        let result = selection(conversation: conversation(comments: [comment(), comment(id: "c2")]))
        let note = AgentPromptSheet.recomputedNote(result.prompt)

        #expect(note.hasPrefix("Přepočítáno podle výběru — 2 položky, "))
        #expect(note.hasSuffix("Odškrtnuté v textu nejsou."))
    }

    /// Počet u volby v panelu: plný počet, dokud jde všechno, jinak `1 z 3`. `3 z 3` je šum,
    /// `3` nad textem se dvěma položkami je lež.
    @Test("Počet u volby v panelu")
    func labelsTheChoiceCount() {
        #expect(AgentPromptPanel.choiceCount(selected: 3, of: 3) == "3")
        #expect(AgentPromptPanel.choiceCount(selected: 1, of: 3) == "1 z 3")
        #expect(AgentPromptPanel.choiceCount(selected: 0, of: 1) == "0 z 1")
    }

    /// Nápověda u volby řekne, **kde** se s vypnutými položkami dá hýbat: v panelu k tomu není
    /// nic, protože jednotlivé položky bydlí v sheetu.
    @Test("Nápověda u volby pošle do sheetu, jen když je co přepínat")
    func pointsToTheSheetOnlyWhenNeeded() {
        let full = AgentPromptPanel.choiceHelp(.comments, selected: 2, of: 2)
        let partial = AgentPromptPanel.choiceHelp(.comments, selected: 1, of: 2)

        #expect(full == AgentPromptChoice.comments.explanation)
        #expect(partial.contains("v okně se zadáním"))
    }

    /// Nápověda u zaškrtávátka nese **důvod**, protože bez něj je předvybrání aplikace
    /// k nerozeznání od chyby.
    @Test("Nápověda u zaškrtávátka nese důvod vypnutí")
    func explainsTheCheckbox() {
        let pick = AgentPromptPick(
            item: .comment(comment()),
            isIncluded: false,
            exclusion: .mine,
            isBlocking: false,
            author: "ondrajodas"
        )
        let byHand = AgentPromptPick(
            item: .comment(comment()),
            isIncluded: false,
            exclusion: nil,
            isBlocking: false,
            author: "ErikZigo"
        )
        let on = AgentPromptPick(
            item: .comment(comment()),
            isIncluded: true,
            exclusion: nil,
            isBlocking: false,
            author: "ErikZigo"
        )

        #expect(AgentPromptPickList.checkboxHelp(pick).contains("napsal jsi to ty"))
        #expect(AgentPromptPickList.checkboxHelp(byHand).contains("Odškrtnul jsi to"))
        #expect(AgentPromptPickList.checkboxHelp(on).contains("V textu je"))
    }
}
