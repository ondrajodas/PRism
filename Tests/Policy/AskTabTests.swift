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

    // MARK: - Co je na obrazovce

    /// Bez jediné zprávy se kreslí tři otázky k odpíchnutí — prázdná plocha by u rozhovoru
    /// znamenala „a co se mám ptát“.
    @Test("Bez zpráv jsou na ploše otázky k odpíchnutí")
    func emptyOffersTips() {
        #expect(Policy.askTab(conversation: nil, isAnswering: false) == .empty(tips: Policy.askTips))
        #expect(
            Policy.askTab(conversation: AskConversation(pullRequest: Self.pr), isAnswering: false)
                == .empty(tips: Policy.askTips)
        )
        #expect(Policy.askTips.count == 3)
    }

    /// **Tvrdí, že se něco NEstalo**: běh bez jediné zprávy prstýnek nad prázdnem nenakreslí.
    ///
    /// Je to rozpor, ne stav — otázka se do rozhovoru zapisuje **dřív**, než se session spustí,
    /// takže „běží a nikdo se na nic nezeptal“ nemá jak nastat. Kdyby nastalo (přerušený zápis),
    /// je nabídka otázek pravdivější než prstýnek u prázdna.
    @Test("Běh bez zpráv nekreslí prstýnek nad prázdnem")
    func runningWithoutMessagesStaysEmpty() {
        #expect(Policy.askTab(conversation: nil, isAnswering: true) == .empty(tips: Policy.askTips))
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
