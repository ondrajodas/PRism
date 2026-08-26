import Foundation
import Testing

@testable import PRism

/// Co se v tabu `Zeptat se` kreslí a jestli je zkratka volná (#452).
@Suite("Tab Zeptat se (#452)")
struct AskTabTests {
    private static let pr = PRIdentifier(repo: RepoID("keboola/vault")!, number: 85)

    private static func message(_ speaker: AskMessage.Speaker, _ text: String) -> AskMessage {
        AskMessage(speaker: speaker, text: text, at: Date(timeIntervalSince1970: 0))
    }

    /// Chipy, jak je skládá pruh `ví o tomhle PR:` — nabídka otázek vychází **z nich**, ne
    /// z vlastního počítání.
    private static func chips(findings: Int) -> [AskContextChip] {
        Policy.askContextChips(
            diffFiles: 8,
            findings: findings,
            blockingFindings: 0,
            comments: 12,
            checks: 6
        )
    }

    // MARK: - Co je na obrazovce

    /// Bez jediné zprávy se kreslí otázky k odpíchnutí — prázdná plocha by u rozhovoru znamenala
    /// „a co se mám ptát“.
    @Test("Bez zpráv jsou na ploše otázky k odpíchnutí")
    func emptyOffersTips() {
        #expect(Policy.askTab(conversation: nil, isAnswering: false) == .empty(tips: Policy.askTips(context: [])))
        #expect(
            Policy.askTab(conversation: AskConversation(pullRequest: Self.pr), isAnswering: false)
                == .empty(tips: Policy.askTips(context: []))
        )
    }

    /// **Tvrdí, že se něco NEstalo**: běh bez jediné zprávy prstýnek nad prázdnem nenakreslí.
    ///
    /// Je to rozpor, ne stav — otázka se do rozhovoru zapisuje **dřív**, než se session spustí,
    /// takže „běží a nikdo se na nic nezeptal“ nemá jak nastat. Kdyby nastalo (přerušený zápis),
    /// je nabídka otázek pravdivější než prstýnek u prázdna.
    @Test("Běh bez zpráv nekreslí prstýnek nad prázdnem")
    func runningWithoutMessagesStaysEmpty() {
        #expect(Policy.askTab(conversation: nil, isAnswering: true) == .empty(tips: Policy.askTips(context: [])))
    }

    @Test("Se zprávami je na ploše rozhovor a prstýnek jde s během")
    func threadCarriesTheMessages() {
        let conversation = AskConversation(
            pullRequest: Self.pr,
            messages: [Self.message(.mine, "proč?"), Self.message(.claude, "protože")]
        )

        #expect(
            Policy.askTab(conversation: conversation, isAnswering: false)
                == .thread(messages: conversation.messages, isAnswering: false)
        )
        #expect(
            Policy.askTab(conversation: conversation, isAnswering: true)
                == .thread(messages: conversation.messages, isAnswering: true)
        )
    }

    /// `Nový rozhovor` se kreslí **jen tam, kde je co zahodit** — vyčerpávající výčet obou stavů.
    ///
    /// Tvrdí to hlavně tu druhou půlku: tlačítko, které v prázdném tabu nemá co dělat, by po
    /// stisknutí smazalo prázdno a zaplatilo se za to potvrzovacím dialogem.
    @Test("Nový rozhovor je jen tam, kde je co zahodit")
    func onlyANonEmptyThreadOffersAReset() {
        let conversation = AskConversation(pullRequest: Self.pr, messages: [Self.message(.mine, "proč?")])

        #expect(Policy.askTab(conversation: nil, isAnswering: false).offersReset == false)
        #expect(Policy.askTab(conversation: nil, isAnswering: true).offersReset == false)
        #expect(Policy.askTab(conversation: conversation, isAnswering: false).offersReset)
        #expect(Policy.askTab(conversation: conversation, isAnswering: true).offersReset)
    }

    // MARK: - Nabídka otázek

    /// **Nabídka se řídí tím, co na PR je.** Bez nálezů se otázka na ně nenabízí — ptala by se na
    /// nic a session by za dolar odpověděla „žádné tam nejsou“.
    @Test("Bez nálezů se na nálezy nenabízí ptát")
    func noFindingsMeansNoFindingsTip() {
        let tips = Policy.askTips(context: Self.chips(findings: 0))

        #expect(tips.count == 2)
        #expect(tips.contains { $0.contains("nález") } == false)
    }

    /// Vyčerpávající výčet přes hranice skloňování — a hlavně: **počet v otázce je týž, jaký hlásí
    /// pruh `ví o tomhle PR:`**. Dvě různá čísla o jedné věci na jedné obrazovce jsou přesně ta
    /// třída chyby, která se u tohohle tabu už jednou stala (materiál se skládal jinde než pruh).
    @Test("Otázka na nálezy nese týž počet jako chip")
    func theFindingsTipMatchesTheChip() {
        for count in [2, 3, 5, 12] {
            let chips = Self.chips(findings: count)
            let tips = Policy.askTips(context: chips)
            let tip = tips.first { $0.contains("nález") }
            let chip = chips.first { $0.kind == .findings }

            #expect(tips.count == 3)
            // Chip říká `3 nálezy`, otázka `Který z těch 3 nálezů…` — je to **totéž číslo**
            // a tvrdí se to z obou konců, aby se nedaly rozejít.
            #expect(tip == "Který z těch \(count) nálezů je doopravdy problém?", "u \(count): \(tip ?? "—")")
            #expect(chip?.label.hasPrefix("\(count) ") == true, "chip u \(count): \(chip?.label ?? "—")")
        }
        // **Jediný nález dostane vlastní větu a číslici v ní nemá** — „Který z těch 1 nálezů“ je
        // česky nesmysl a „Který z těch nálezů“ by u jednoho tvrdilo, že je z čeho vybírat.
        #expect(Policy.askTips(context: Self.chips(findings: 1))[1] == "Je ten jediný nález doopravdy problém?")
        #expect(Self.chips(findings: 1).first { $0.kind == .findings }?.label == "1 nález")
    }

    /// Pořadí je z návrhu: otázka na nálezy stojí **uprostřed**, mezi „co nejvíc riskuje“ a „co
    /// prověřit“. Bez nálezů se ty dvě jen slepí, nevznikne mezera.
    @Test("Otázka na nálezy stojí uprostřed")
    func theFindingsTipSitsInTheMiddle() {
        let with = Policy.askTips(context: Self.chips(findings: 2))
        let without = Policy.askTips(context: Self.chips(findings: 0))

        #expect(with.first == without.first)
        #expect(with.last == without.last)
        #expect(with[1].contains("nález"))
    }

    /// Nabídka nezávisí na tom, co je v pruhu **vedle** nálezů — komentáře ani checky vlastní
    /// otázku nemají, takže je nesmí ani přidat, ani ubrat.
    @Test("Komentáře a checky nabídku nemění")
    func otherChipsDoNotChangeTheTips() {
        let bare = Policy.askContextChips(diffFiles: 0, findings: 2, blockingFindings: 0, comments: 0, checks: 0)
        let busy = Policy.askContextChips(diffFiles: 9, findings: 2, blockingFindings: 2, comments: 40, checks: 7)

        #expect(Policy.askTips(context: bare) == Policy.askTips(context: busy))
    }

    // MARK: - Chipy `ví o tomhle PR:`

    /// **Nula chip nedostane.** „0 checků“ je pravdivé, ale v pruhu, který odpovídá na „co o PR
    /// ví“, se čte jako selhání.
    @Test("Chip se kreslí jen tomu, čeho je aspoň jedno")
    func skipsEmptyChips() {
        let chips = Policy.askContextChips(
            diffFiles: 8,
            findings: 0,
            blockingFindings: 0,
            comments: 12,
            checks: 0
        )

        #expect(chips.map(\.kind) == [.diff, .comments])
        #expect(chips.map(\.label) == ["8 souborů diffu", "12 komentářů"])
    }

    /// Puntík má **jen** chip s blokujícím nálezem — u počtu komentářů by z údaje o množství
    /// udělal upozornění.
    @Test("Puntík dostane jedině blokující nález")
    func onlyBlockingFindingsGetADot() {
        let blocking = Policy.askContextChips(
            diffFiles: 1,
            findings: 3,
            blockingFindings: 1,
            comments: 2,
            checks: 6
        )
        #expect(blocking.filter(\.isBlocking).map(\.kind) == [.findings])

        let quiet = Policy.askContextChips(
            diffFiles: 1,
            findings: 3,
            blockingFindings: 0,
            comments: 2,
            checks: 6
        )
        #expect(quiet.contains { $0.isBlocking } == false)
    }

    /// Skloňování se kontroluje na hranicích, ne na jednom příkladu: `1 nález`, `3 nálezy`,
    /// `5 nálezů`.
    @Test("Počty se skloňují")
    func labelsAreDeclined() {
        func label(_ count: Int) -> String? {
            Policy.askContextChips(
                diffFiles: 0,
                findings: count,
                blockingFindings: 0,
                comments: 0,
                checks: 0
            ).first?.label
        }

        #expect(label(1) == "1 nález")
        #expect(label(3) == "3 nálezy")
        #expect(label(5) == "5 nálezů")
    }

    // MARK: - Řádek u prstýnku

    /// Sloveso podle nástroje, ne jméno nástroje: `Read` v okně nic neřekne.
    @Test("Řádek u prstýnku říká, co session dělá")
    func activityNamesTheAction() {
        let worktree = URL(filePath: "/cache/worktrees/o/r/42-abc")

        func line(_ name: String, _ detail: String?) -> String {
            Policy.askActivity(
                of: ToolAttempt(name: name, detail: detail),
                inside: worktree
            )
        }

        #expect(line("Read", "\(worktree.path)/App/A.swift") == "čte App/A.swift")
        #expect(line("Grep", "mutex") == "hledá mutex")
        #expect(line("Glob", "**/*.php") == "hledá soubory **/*.php")
        #expect(line("Bash", "git diff abc...HEAD") == "pouští git diff abc...HEAD")
        // Neznámý nástroj dostane obecnou větu, ne své jméno.
        #expect(line("Cokoli", "x") == "pracuje…")
        // A bez detailu se nepíše prázdno.
        #expect(line("Read", nil) == "čte soubor…")
        #expect(line("Read", "") == "čte soubor…")
    }

    /// Než session řekne, co dělá, stojí u prstýnku věta — **ne prázdný řádek**, který v té
    /// několikasekundové mezeře vypadá jako zaseknuté okno.
    @Test("Dokud session mlčí, u prstýnku stojí věta")
    func startingActivityIsNotEmpty() {
        #expect(!Policy.askStartingActivity.isEmpty)
    }

    // MARK: - Zkratka

    /// **Vyčerpávající výčet**: `⏎` si bere jedině `Zeptat se`. Kdyby si ho vzal i jiný tab,
    /// znamenalo by to, že se v něm zakáže potvrzení odeslání — tedy že se review nedá odeslat
    /// zkratkou z tabu, kde na to nikdo nečeká.
    @Test("Klávesu ⏎ si bere jedině tab Zeptat se")
    func onlyTheAskTabClaimsReturn() {
        let claiming = PullRequestTab.allCases.filter(Policy.claimsReturnShortcut)

        #expect(claiming == [.ask])
    }
}
