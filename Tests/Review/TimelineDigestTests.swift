import Foundation
import Testing

@testable import PRism

/// Souhrn osy, počítaný **při zápisu** (#325, `ReviewerTimeline.Digest`).
///
/// Do #325 skládal `Policy.lanes` dráhu osmi průchody polem při každém překreslení tabu. Souhrn ty
/// průchody nahrazuje, a tím vzniká přesně ta věc, kterou `CLAUDE.md` u dvou kopií téhož popisuje:
/// **může se s osou rozejít, a potichu.** Tahle sada je to, co tomu brání.
///
/// Testuje se trojí:
/// - **shoda s průchodem polem** nad všemi druhy událostí i nad odpověďmi na kroky,
/// - **co ořezání osy nesmí zapomenout** (`reached`, nálezy, konec) a co naopak ubrat má
///   (`toolSteps`, případně `lastTool`),
/// - **odpověď na poslední krok se propíše i do souhrnu** — bez toho by věta „právě čte…“ tvrdila
///   `běží…` nad krokem, který už dávno odpověděl.
@Suite("Souhrn osy běhu")
struct TimelineDigestTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// Souhrn poskládaný **průchodem polem**, tedy tak, jak ho počítal `Policy.lanes` do #325.
    /// Je to ten druhý zdroj pravdy, proti kterému se přírůstkový souhrn poměřuje.
    private func scanned(_ timeline: ReviewerTimeline) -> ReviewerTimeline.Digest {
        var digest = ReviewerTimeline.Digest()
        for entry in timeline.entries {
            switch entry.kind {
            case .queued:
                digest.hadQueued = true
            case .started:
                digest.reached = max(digest.reached, 1)
            case .tool(let tool):
                digest.reached = max(digest.reached, 2)
                digest.toolSteps += 1
                digest.lastTool = tool
                if tool.name == "Skill", digest.loadedSkill == nil, let detail = tool.detail {
                    digest.loadedSkill = detail
                }
            case .findings(let count):
                digest.reached = max(digest.reached, 3)
                digest.reportedFindings = count
            case .intentGap(let gap):
                if digest.intentGap == nil { digest.intentGap = gap }
            case .finished(let outcome):
                digest.finish = .init(outcome: outcome, at: entry.at)
            }
        }
        return digest
    }

    /// Osa se vším, co do ní umí přijít — včetně odpovědí na kroky, protože ty souhrn **mění, aniž
    /// by osu prodloužily** (#326).
    private func everyKind() -> ReviewerTimeline {
        var timeline = ReviewerTimeline(skill: "code-review", worktree: URL(filePath: "/tmp/wt"))
        timeline.record(.queued, at: start)
        timeline.record(.intentGap(.toolNotConfigured), at: start + 1)
        timeline.record(.started(sessionID: "abc123"), at: start + 2)
        timeline.record(.attemptedTool(ToolAttempt(name: "Skill", detail: "code-review", id: "t0")), at: start + 3)
        timeline.record(.resolvedTool(ToolResolution(id: "t0", outcome: .init(kind: .passed))), at: start + 3.2)
        timeline.record(.attemptedTool(ToolAttempt(name: "Read", detail: "a.php", id: "t1")), at: start + 4)
        timeline.record(.resolvedTool(ToolResolution(id: "t1", outcome: .init(kind: .denied))), at: start + 4.1)
        timeline.record(.attemptedTool(ToolAttempt(name: "Bash", detail: "git log", id: "t2")), at: start + 5)
        timeline.record(.findings(count: 2), at: start + 6)
        timeline.finish(.finished, usage: nil, at: start + 7)
        return timeline
    }

    // MARK: - Shoda s průchodem polem

    @Test("Souhrn souhlasí s průchodem polem")
    func matchesAFullScan() {
        let timeline = everyKind()

        #expect(timeline.digest == scanned(timeline))
        #expect(timeline.digest.reached == 3)
        #expect(timeline.digest.hadQueued)
        #expect(timeline.digest.toolSteps == 3)
        #expect(timeline.digest.reportedFindings == 2)
        #expect(timeline.digest.loadedSkill == "code-review")
        #expect(timeline.digest.intentGap == .toolNotConfigured)
        #expect(timeline.digest.finish?.outcome == .finished)
        #expect(timeline.digest.finish?.at == start + 7)
    }

    /// Souhrn se počítá dvěma cestami: přírůstkově při zápisu a **jedním průchodem při načtení
    /// z disku**. Kdyby se ty dvě rozešly, tab by po restartu kreslil jinou dráhu než před ním.
    @Test("Načtená osa má stejný souhrn jako živá")
    func loadedTimelineMatchesTheLiveOne() {
        let live = everyKind()
        let run = makeStoredRun(
            skill: live.skill,
            outcome: .finished,
            calledReportFindings: true,
            timeline: live.stored(),
            sessionID: "abc123"
        )

        let loaded = ReviewerTimeline(run)

        #expect(loaded.digest == live.digest)
        #expect(loaded.digest == scanned(loaded))
    }

    /// **Nejcennější test téhle sady** (že se něco NEstalo): první `Skill` a první příznak zadání
    /// se pozdějším nepřepíšou. Je to pravda, na které stojí odznak `běžel …` v hlavičce dráhy —
    /// pravda je ta, se kterou session začala.
    @Test("Načtený skill a příznak zadání se nepřepisují")
    func keepsTheFirstSkillAndGap() {
        var timeline = ReviewerTimeline(skill: "code-review")
        timeline.record(.intentGap(.toolDenied), at: start)
        timeline.record(.attemptedTool(ToolAttempt(name: "Skill", detail: "první", id: "a")), at: start + 1)
        timeline.record(.attemptedTool(ToolAttempt(name: "Skill", detail: "druhý", id: "b")), at: start + 2)
        timeline.record(.intentGap(.noAnswer), at: start + 3)

        #expect(timeline.digest.loadedSkill == "první")
        #expect(timeline.digest.intentGap == .toolDenied)
        #expect(timeline.digest == scanned(timeline))
    }

    // MARK: - Odpověď na krok

    /// Odpověď osu neprodlouží (#326), takže souhrn se nemá čím aktualizovat sám — musí se do něj
    /// propsat. Bez toho by věta pod dráhou držela krok bez odpovědi a `Průběh` by tvrdil `běží…`
    /// nad krokem, který odpověděl.
    @Test("Odpověď na poslední krok se propíše do souhrnu")
    func resolutionReachesTheDigest() {
        var timeline = ReviewerTimeline(skill: "code-review")
        timeline.record(.attemptedTool(ToolAttempt(name: "Read", detail: "a.php", id: "t1")), at: start)
        #expect(timeline.digest.lastTool?.outcome == nil)

        timeline.record(.resolvedTool(ToolResolution(id: "t1", outcome: .init(kind: .passed))), at: start + 0.5)

        #expect(timeline.digest.lastTool?.outcome?.kind == .passed)
        #expect(timeline.digest.lastTool?.outcome?.after == .milliseconds(500))
        #expect(timeline.digest == scanned(timeline))
    }

    /// Odpověď na **starší** krok posledním nehýbe — jinak by věta „právě čte…“ ukazovala na
    /// soubor, který reviewer přečetl před pěti kroky.
    @Test("Odpověď na starší krok posledním nehýbe")
    func olderResolutionKeepsTheLastStep() {
        var timeline = ReviewerTimeline(skill: "code-review")
        timeline.record(.attemptedTool(ToolAttempt(name: "Read", detail: "a.php", id: "t1")), at: start)
        timeline.record(.attemptedTool(ToolAttempt(name: "Grep", detail: "vzor", id: "t2")), at: start + 1)

        timeline.record(.resolvedTool(ToolResolution(id: "t1", outcome: .init(kind: .passed))), at: start + 2)

        #expect(timeline.digest.lastTool?.name == "Grep")
        #expect(timeline.digest.lastTool?.outcome == nil)
        #expect(timeline.digest == scanned(timeline))
    }
}
