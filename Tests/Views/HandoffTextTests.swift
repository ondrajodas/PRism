import Foundation
import Testing

@testable import PRism

/// Texty panelu o předání (#334) — razítko, věta o novinkách a varování po pushi.
///
/// Skládají se z hotových čísel, takže se testují **bez kreslení** (tatáž cesta jako
/// u `StaleHeadView.label(of:)`). Pokazit se dají potichu dvěma způsoby: **tvrdit počet commitů,
/// který nikdo nespočítal**, a **skloňovat česky špatně** — `1 commity` praští do očí hned, ale
/// jen tomu, kdo se na obrazovku podívá.
@Suite("Texty o předání (#334)")
struct HandoffTextTests {
    private func report(
        stage: HandoffReport.Stage,
        pending: Int = 0,
        commits: Int? = nil,
        head: String? = "9c1de02aaaa",
        staleFindings: Int = 0
    ) -> HandoffReport {
        HandoffReport(
            stage: stage,
            handoff: Handoff(at: Date(timeIntervalSince1970: 1_000_000), headSha: head, handed: []),
            pending: pending,
            freshDiscussion: [],
            staleFindings: staleFindings,
            commits: commits
        )
    }

    // MARK: - Razítko

    /// Dnešní předání se píše `dnes 14:20`, jak to má návrh — a nese **hlavu**, protože bez ní se
    /// razítko nedá spárovat s commitem.
    @Test("Dnešní razítko se pozná od staršího")
    func distinguishesTodayFromOlderStamps() {
        let today = Handoff(at: .now, headSha: "9c1de02aaaa", handed: [])
        let older = Handoff(
            at: Date(timeIntervalSince1970: 1_000_000),
            headSha: "9c1de02aaaa",
            handed: []
        )

        let todayLabel = AgentPromptPanel.stampLabel(of: today)
        let olderLabel = AgentPromptPanel.stampLabel(of: older)

        #expect(todayLabel.hasPrefix("dnes "))
        #expect(todayLabel.hasSuffix("· proti 9c1de02"))
        #expect(!olderLabel.hasPrefix("dnes "))
        #expect(olderLabel.hasSuffix("· proti 9c1de02"))
    }

    /// **Chybějící hlava se musí říct**, ne zamlčet: bez ní se neví, jestli zadání platí, a věta
    /// „proti “ bez sha by vypadala jako chyba kreslení.
    @Test("Razítko bez hlavy to napíše")
    func namesTheMissingHead() {
        let stamp = Handoff(at: Date(timeIntervalSince1970: 1_000_000), headSha: nil, handed: [])

        #expect(AgentPromptPanel.stampLabel(of: stamp).hasSuffix("· hlavu PR jsem tehdy neznal"))
    }

    // MARK: - Věta o novinkách

    @Test("Věta o novinkách se skloňuje", arguments: [
        (1, "přibyla 1 položka"),
        (2, "přibyly 2 položky"),
        (5, "přibylo 5 položek"),
    ])
    func inflectsThePendingNotice(count: Int, expected: String) {
        let text = AgentPromptPanel.pendingNotice(report(stage: .changed, pending: count))

        #expect(text.contains(expected))
    }

    /// Neznámá hlava má **vlastní věta**: nezbylo nic nového, jen se nedá potvrdit, že předané
    /// platí. Splynutí s předchozí by tvrdilo práci, která nepřišla.
    @Test("Neznámá hlava má vlastní věty")
    func explainsTheUnverifiedStamp() {
        let text = AgentPromptPanel.pendingNotice(report(stage: .unverified, pending: 1))

        #expect(text.contains("dřív, než dorazil detail PR"))
        #expect(!text.contains("přibyla"))
    }

    // MARK: - Varování po pushi

    @Test("Varování po pushi skloňuje commity", arguments: [
        (1, "mezitím přišel 1 commit"),
        (2, "mezitím přišly 2 commity"),
        (5, "mezitím přišlo 5 commitů"),
    ])
    func inflectsTheCommitCount(count: Int, expected: String) {
        let text = AgentPromptPanel.outdatedNotice(report(stage: .outdated, commits: count))

        #expect(text.contains("Předával jsi proti 9c1de02"))
        #expect(text.contains(expected))
        #expect(text.contains("pusť review znovu"))
    }

    /// **Tvrzení, že se něco netvrdí**: bez počtu commitů se napíše, že se hlava posunula — číslo
    /// se nevymýšlí. Po force pushi ani nad nenačteným seznamem se dopočítat nedá.
    @Test("Bez počtu commitů se číslo nevymýšlí")
    func staysSilentAboutUnknownCommitCount() {
        let text = AgentPromptPanel.outdatedNotice(report(stage: .outdated, commits: nil))

        #expect(text.contains("mezitím se hlava PR posunula"))
        #expect(!text.contains("commit"))
    }

    /// Nula commitů je tentýž případ jako `nil` — „mezitím přišlo 0 commitů“ by nad posunutou
    /// hlavou byla nesmyslná věta.
    @Test("Nula commitů se nepíše jako počet")
    func treatsZeroCommitsAsUnknown() {
        let text = AgentPromptPanel.outdatedNotice(report(stage: .outdated, commits: 0))

        #expect(text.contains("mezitím se hlava PR posunula"))
    }

    /// Bez známé hlavy se do varování napíše „proti starší hlavě“ — ne prázdné místo.
    @Test("Varování bez hlavy nemá prázdné místo")
    func namesTheMissingHeadInTheNotice() {
        let text = AgentPromptPanel.outdatedNotice(report(stage: .outdated, commits: 2, head: nil))

        #expect(text.contains("Předával jsi proti starší hlavě"))
    }
}
