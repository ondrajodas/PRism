import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Šířka tabů, ze kterých #294 schovala panel (`Kontroly`, `Nálezy`, `Průběh`): **obsah se roztáhl
/// a nic se nekreslí mimo tab.**
///
/// Skrytí panelu je jednoduché; **riskantní je šířka.** Tab dostane o panel víc místa (38 bodů po
/// složeném proužku, 306 po rozloženém na výchozí šířce, až 526 po vytaženém), takže se v něm
/// najednou sází to, co se do té doby sázelo v užším. Přesně na takové změně se rozbila #291 — jen
/// obráceně: tam se šířka nezúžila o odsazení a obsah přetekl o 42 bodů ve **všech** šířkách, což
/// `NSScrollView` ukrojil, takže to v okně vypadalo jako chybějící hrana, ne jako přetečení.
///
/// **Jak se to měří, drží `OverflowProbe`** — jedno místo pro tuhle suitu i pro `Přehled`.
///
/// **Pásmo šířek, ne jedna:** obsah se v každé zalomí jinak, takže jediná šířka umí projít náhodou.
@MainActor
@Suite("Šířka tabů bez panelu (#294)")
struct PanelFreeTabWidthTests {
    /// Šířky, ve kterých tyhle tři taby po #294 doopravdy stojí. Spodní kraj je **648 bodů** a je
    /// spočítaný: okno má podlahu 700 a rail bere 52. Panel se do toho už nepočítá — a právě proto
    /// je to pásmo jiné než u `Přehledu`, kde se pořád začíná na 128.
    private let widths: [CGFloat] = [648, 720, 900, 1100, 1400, 1800]

    @Test("Kontroly nepřetečou v žádné šířce")
    func checksStayInside() throws {
        for width in widths {
            let probe = OverflowProbe(width: width, name: "kontroly-\(Int(width))")
            let overflow = try probe.overflow(of: ChecksView(checks: Self.checks).content)
            #expect(overflow == 0, "šířka \(Int(width)): Kontroly přetekly o \(overflow) bodů")
        }
    }

    /// `Commity` (#316) jsou čtvrtý tab bez panelu a v šířce se perou o dvě věci naráz: **dlouhá
    /// první řádka zprávy** (typicky `Merge branch 'main' into …`) a pilulka se sha u pravé hrany.
    /// Zpráva se řeže, sha ne — takže kdyby se řez ztratil, přeteče to vpravo.
    @Test("Commity nepřetečou v žádné šířce")
    func commitsStayInside() throws {
        for width in widths {
            let probe = OverflowProbe(width: width, name: "commity-\(Int(width))")
            let list = CommitListView(commits: Self.commits, head: Self.commits.last?.sha)
            let overflow = try probe.overflow(of: list.content)
            #expect(overflow == 0, "šířka \(Int(width)): Commity přetekly o \(overflow) bodů")
        }
    }

    /// Hlavička rozkliknutého commitu (#317). V šířce se pere o čtyři věci naráz: **dlouhá první
    /// řádka zprávy**, kapsle se sha s odkazem na GitHub, počty ze staženého diffu a tichá věta
    /// o tom, že tu není kam kliknout. Návrh je má na jednom řádku s `flex-wrap`, který SwiftUI
    /// nemá — proto `ViewThatFits`, a proto se to musí měřit **přes pásmo**: podoba na jeden řádek
    /// se v úzkém okně nesmí zvolit a přetéct.
    ///
    /// **Commit bez těla zprávy**, takže sbalený a rozbalený stav dají tentýž podstrom — sbalování
    /// se u něj nekreslí vůbec. Oba stavy měří test pod ním, na commitu, který tělo má.
    @Test("Hlavička commitu nepřeteče v žádné šířce")
    func theCommitHeaderStaysInside() throws {
        for width in widths {
            let probe = OverflowProbe(width: width, name: "commit-hlavicka-\(Int(width))")
            let header = CommitHeaderView(
                commit: Self.commits[1],
                position: "2 ze 7",
                facts: CommitDiffFacts(files: "3 soubory", additions: 64, deletions: 18),
                url: Policy.commitURL(of: Self.commits[1].sha, in: RepoID(owner: "cli", name: "cli")),
                isMessageExpanded: .constant(true),
                back: {},
                showFiles: {}
            )
            let overflow = try probe.overflow(of: header)
            #expect(overflow == 0, "šířka \(Int(width)): hlavička commitu přetekla o \(overflow) bodů")
        }
    }

    /// Tělo zprávy se od #317 dá **sbalit**, takže hlavička má dvě podoby — a obě musí obstát
    /// v celém pásmu. Sbalená není „ta samá o kus nižší“: místo odstavců v ní stojí přepínač
    /// s počtem řádků, tedy jiný řádek s jiným zalomením.
    ///
    /// Fixture nese to, co tělo umí do hlavičky přinést a co se nikde jinde neměří: **odstavce**,
    /// **odrážky** a hlavně **dlouhý nezlomitelný token** (URL na issue), který se do úzkého tabu
    /// nemá kam vejít. Tělo se zalamuje, netrunkuje — takže kdyby se ztratila šířka, přeteče vpravo.
    @Test("Hlavička s tělem zprávy nepřeteče ani sbalená, ani rozbalená", arguments: [true, false])
    func theCommitHeaderWithBodyStaysInside(expanded: Bool) throws {
        let state = expanded ? "rozbalena" : "sbalena"
        for width in widths {
            let probe = OverflowProbe(width: width, name: "commit-telo-\(state)-\(Int(width))")
            let header = CommitHeaderView(
                commit: Self.commitWithBody,
                position: "3 ze 7",
                facts: CommitDiffFacts(files: "12 souborů", additions: 640, deletions: 188),
                url: Policy.commitURL(of: Self.commitWithBody.sha, in: RepoID(owner: "cli", name: "cli")),
                isMessageExpanded: .constant(expanded),
                back: {},
                showFiles: {}
            )
            let overflow = try probe.overflow(of: header)
            #expect(overflow == 0, "šířka \(Int(width)), \(state) hlavička přetekla o \(overflow) bodů")
        }
    }

    /// Prázdný diff je jiný podstrom (věta místo diffu) a hlavička v něm stojí **bez počtů**,
    /// takže se v ní řádek sází jinak — měří se proto zvlášť. Text věty je od `Policy`, tedy ten,
    /// který uvidí člověk.
    @Test("Prázdný diff commitu nepřeteče ani s vysvětlením")
    func theEmptyCommitDiffStaysInside() throws {
        for width in widths {
            let probe = OverflowProbe(width: width, name: "commit-prazdny-\(Int(width))")
            let view = CommitDiffView(
                commit: Self.commits[1],
                state: .nothing(Policy.emptyCommitDiff(isMerge: true)),
                position: "2 ze 7",
                url: nil,
                isMessageExpanded: .constant(true),
                expansion: DiffExpansionActions(state: { _ in FileExpansion() }, reveal: { _, _ in }, collapse: nil),
                folding: DiffFoldingActions(isFolded: { _ in false }, toggle: { _ in }, foldAll: { _ in }, unfoldAll: {}),
                layout: .constant(.unified),
                back: {},
                showFiles: {},
                retry: {}
            )
            let overflow = try probe.overflow(of: view)
            #expect(overflow == 0, "šířka \(Int(width)): prázdný diff commitu přetekl o \(overflow) bodů")
        }
    }

    /// Tabulka nálezů je z těch tří jediná, která si šířku **počítá** (`Policy.findingTableLayout`),
    /// takže je to jediné místo, kde se dá spočítat špatně. Sloupec `reviewer · kategorie` navíc
    /// v pásmu přeskočí prahovou hodnotu 900, takže se měří obě sazby.
    ///
    /// **Rendruje se celý tab s `scrolls: false`**, ne jeho vytažený podstrom: šířku si bere
    /// z prostředí, a to dorazí jedině do view, které SwiftUI doopravdy skládá — viz
    /// `FindingsTabView.scrolls`.
    @Test("Tabulka nálezů nepřeteče v žádné šířce")
    func findingsStayInside() throws {
        for width in widths {
            let probe = OverflowProbe(width: width, name: "nalezy-\(Int(width))")
            let overflow = try probe.overflow(of: Self.findingsTab)
            #expect(overflow == 0, "šířka \(Int(width)): Nálezy přetekly o \(overflow) bodů")
        }
    }

    /// Prázdný stav je jiný podstrom než tabulka (věta o tom, proč nálezy nejsou), takže se měří
    /// zvlášť — a je v něm text od `claude`, který se musí zalomit, ne přetéct.
    @Test("Prázdné Nálezy nepřetečou ani s textem od reviewera")
    func emptyFindingsStayInside() throws {
        let record = makeRecord(runs: [makeStoredRun(outcome: .failed(detail: Self.stderr))])
        for width in widths {
            let probe = OverflowProbe(width: width, name: "nalezy-prazdne-\(Int(width))")
            let tab = FindingsTabView(
                record: record,
                pullRequest: Self.pullRequest,
                jump: { _ in },
                scrolls: false
            )
            let overflow = try probe.overflow(of: tab)
            #expect(overflow == 0, "šířka \(Int(width)): prázdné Nálezy přetekly o \(overflow) bodů")
        }
    }

    @Test("Průběh nepřeteče v žádné šířce")
    func progressStaysInside() throws {
        for width in widths {
            let probe = OverflowProbe(width: width, name: "prubeh-\(Int(width))")
            let overflow = try probe.overflow(of: ReviewProgressView(
                lanes: Self.lanes,
                rerun: { _ in },
                copyCommand: { _ in }
            ).content)
            #expect(overflow == 0, "šířka \(Int(width)): Průběh přetekl o \(overflow) bodů")
        }
    }

    /// Prázdný `Průběh` (repo bez nastaveného revieweera) je vysvětlivka mimo `ScrollView`, takže se
    /// měří přímo z `body`.
    @Test("Prázdný Průběh nepřeteče")
    func emptyProgressStaysInside() throws {
        for width in widths {
            let probe = OverflowProbe(width: width, name: "prubeh-prazdny-\(Int(width))")
            let overflow = try probe.overflow(of: ReviewProgressView(lanes: []))
            #expect(overflow == 0, "šířka \(Int(width)): prázdný Průběh přetekl o \(overflow) bodů")
        }
    }

    // MARK: - Data

    private static let pullRequest = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013)

    /// Checky ze skutečného PR (`keboola/platform-libraries#557` má 28 checků, z toho 22
    /// přeskočených), zkrácené na jeden od každého druhu — a s dlouhým jménem jobu, protože to je
    /// to, co se do řádku nemá kam vejít.
    private static let checks: [PullRequestCheck] = [
        PullRequestCheck(
            name: "phpstan (level 8) / analyse — libs/storage-api-client + libs/service-client",
            outcome: .failed,
            link: URL(string: "https://github.com/cli/cli/actions/runs/1/job/2"),
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 134)
        ),
        PullRequestCheck(
            name: "phpunit / 8.4 / with-snowflake-and-bigquery",
            outcome: .running,
            link: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: nil
        ),
        PullRequestCheck(
            name: "phpcs",
            outcome: .passed,
            link: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 41)
        ),
        PullRequestCheck(name: "deploy", outcome: .skipped, link: nil, startedAt: nil, completedAt: nil),
    ]

    /// Commity ze skutečného PR (`cli/cli#13899`, sedm commitů a mezi nimi tři sloučení), zkrácené
    /// na jeden od každého druhu — a s nejdelší zprávou, jakou tam GitHub sám vyrobil: `Merge
    /// branch 'trunk' into fix/13804-…` je ten řádek, který se do úzkého okna nemá kam vejít.
    private static let commits: [PullRequestCommit] = [
        PullRequestCommit(
            sha: "c82266c2dcc3285033605501837434af1faeddfe",
            message: "Warn instead of failing when issue fields can't be set\n\nTělo, které se v seznamu nekreslí.",
            authorName: "imkp1",
            authorLogin: "imkp1",
            avatarURL: URL(string: "https://avatars.githubusercontent.com/u/28646172?v=4"),
            committedAt: Date(timeIntervalSince1970: 1_784_230_763),
            isMerge: false
        ),
        PullRequestCommit(
            sha: "96a469b6bd159d4cff137d5eab4d13ceee4c9807",
            message: "Merge branch 'trunk' into fix/13804-gh-issue-create-errors-after-successful",
            authorName: "Kumar Prateek",
            authorLogin: "imkp1",
            avatarURL: URL(string: "https://avatars.githubusercontent.com/u/28646172?v=4"),
            committedAt: Date(timeIntervalSince1970: 1_784_636_710),
            isMerge: true
        ),
        // Bez účtu na GitHubu — `author: null`, tedy monogram místo obrázku (změřeno na
        // `keboola/job-queue-daemon#858`, kde je `null` u všech commitů).
        PullRequestCommit(
            sha: "0834fedb0a1c2d3e4f50617283940516273849a0",
            message: "fix(daemon): AJDA-2719 return job mock from createNewJob callback in per-row retry tests",
            authorName: "Jiří Novák",
            authorLogin: nil,
            avatarURL: nil,
            committedAt: Date(timeIntervalSince1970: 1_784_637_072),
            isMerge: false
        ),
    ]

    /// Commit s **dlouhým tělem zprávy** — to jediné v hlavičce, co roste bez omezení, a proto to
    /// jediné, co se od #317 dá sbalit. Odstavce, odrážka a odkaz na issue, který se nedá zalomit.
    private static let commitWithBody = PullRequestCommit(
        sha: "745dc68b1c2d3e4f5061728394a5b6c7d8e9f012",
        message: """
            Resolve deferred issue fields before creating the issue

            Fields that need triage access were resolved after the issue was created, so a failure
            left an issue with half the fields set.

            - the picker is skipped without triage access
            - the retry no longer creates a second issue

            Refs https://github.com/cli/cli/issues/13804#issuecomment-2847193055
            """,
        authorName: "Kumar Prateek",
        authorLogin: nil,
        avatarURL: nil,
        committedAt: Date(timeIntervalSince1970: 1_784_637_072),
        isMerge: false
    )

    /// Konec logu, jak ho vrátí spadlá session: dlouhé nezlomitelné cesty jsou to nejtvrdší, co má
    /// blok o šířku poprosit.
    private static let stderr = """
        Error: Cannot find skill „code-review“ in \
        /Users/ondra/Library/Application Support/PRism/checkouts/cli-cli/worktrees/pr-14013/.claude/skills
        """

    /// Nálezy s dlouhým shrnutím i dlouhou cestou — sloupce `shrnutí` a `místo` jsou ty, které se
    /// o šířku perou.
    private static var findings: [Finding] {
        [
            makeFinding(
                file: "libs/storage-api-client/src/Client/BranchAwareClient.php",
                line: 1284,
                category: "correctness",
                summary: "Návratová hodnota se zahazuje přes `try?`, takže selhání zápisu vypadá v UI jako „nic tu nebylo“.",
                reviewer: "code-review"
            ),
            makeFinding(
                file: "libs/service-client/src/ServiceClient.php",
                line: 42,
                category: "security",
                summary: "Token se loguje v plain textu.",
                reviewer: "security-review"
            ),
            makeFinding(
                file: nil,
                line: nil,
                category: "tests",
                summary: "Chybí test na to, že se nic neodešle.",
                reviewer: "code-review"
            ),
        ]
    }

    private static var findingsTab: FindingsTabView {
        // Jedno pole na všechna tři použití: `findings` je computed, takže dva přístupy dají dvě
        // různé instance a odmítnutí by se klíčovalo proti jiné z nich.
        let findings = Self.findings
        let record = makeRecord(runs: [makeStoredRun(findings: findings.map(\.reported))])
        return FindingsTabView(
            record: record,
            pullRequest: pullRequest,
            findings: findings,
            dismissals: makeDismissals([findings[1]]),
            clear: {},
            jump: { _ in },
            // Bez `ScrollView`u, jinak by `NSScrollView` přesah ukrojil a měřilo by se prázdno.
            scrolls: false
        )
    }

    /// Dráhy: jedna doběhlá, jedna spadlá (kvůli bloku s koncem logu) a jedna nespuštěná. Skládají
    /// se **tou cestou, kterou vznikají doopravdy** (`Policy.lanes` nad osami), ne vlastním initem.
    private static var lanes: [ReviewerLane] {
        var finished = ReviewerTimeline(skill: "code-review", worktree: nil)
        let clock = Date(timeIntervalSince1970: 1_000_000)
        finished.record(.queued, at: clock)
        finished.record(.started(sessionID: "6f1c2b7a-2c1e-4c3a-9a55-9f2b1a0c7d10"), at: clock)
        finished.record(.attemptedTool(ToolAttempt(name: "Read", detail: "libs/service-client/src/ServiceClient.php")), at: clock)
        finished.record(.findings(count: 3), at: clock)
        finished.finish(.finished, at: clock)

        var failed = ReviewerTimeline(skill: "security-review", worktree: nil)
        failed.record(.queued, at: clock)
        failed.finish(.failed(detail: stderr), at: clock)

        return Policy.lanes(
            of: [finished, failed],
            skills: ["code-review", "security-review", "architecture-review"]
        )
    }
}
