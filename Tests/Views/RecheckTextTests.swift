import Foundation
import Testing

@testable import PRism

/// Texty kolem kontroly nálezů (#150). Čisté funkce, takže se dají vyčerpat bez kreslení.
///
/// Hlídá se hlavně to, aby věta **netvrdila víc, než data unesou**: „3 vyřešené“ nad pěti nálezy
/// by se čtlo jako čisto, a spadlá kontrola nesmí vypadat jako kontrola, která nic nenašla.
@Suite("Sazba kontroly nálezů")
struct RecheckTextTests {
    private let finished = Date(timeIntervalSince1970: 1_700_000_000)

    private func tally(
        resolved: Int = 0,
        stillApplies: Int = 0,
        unclear: Int = 0,
        unanswered: Int = 0,
        outcome: ReviewRunOutcome = .finished
    ) -> Policy.RecheckTally {
        Policy.RecheckTally(
            statuses: [:],
            resolved: resolved,
            stillApplies: stillApplies,
            unclear: unclear,
            unanswered: unanswered,
            outcome: outcome,
            finishedAt: finished
        )
    }

    @Test("Věta vyjmenuje jen to, co se stalo")
    func theLabelListsWhatHappened() {
        #expect(StaleHeadView.label(of: tally(resolved: 3, stillApplies: 1))
            == "Kontrola nálezů: 3 vyřešené, 1 pořád platí")
        #expect(StaleHeadView.label(of: tally(resolved: 1))
            == "Kontrola nálezů: 1 vyřešený")
    }

    /// Bez nezodpovězených by „3 vyřešené“ nad pěti nálezy vypadalo, že o zbylých dvou kontrola
    /// něco řekla.
    @Test("Nezodpovězené nálezy jsou ve větě")
    func unansweredFindingsAreNamed() {
        #expect(StaleHeadView.label(of: tally(resolved: 3, unanswered: 2))
            == "Kontrola nálezů: 3 vyřešené, 2 bez odpovědi")
    }

    /// Prázdná věta by vypadala jako chybějící sazba, ne jako běh, ze kterého nic nepřišlo.
    @Test("Kontrola bez jediné odpovědi to řekne")
    func anEmptyRecheckSaysSo() {
        #expect(StaleHeadView.label(of: tally()) == "Kontrola nálezů neodpověděla na nic")
    }

    /// Zabitý běh mluví jen za odpovědi, které stihl poslat — v nápovědě to musí být, protože do
    /// věty se to nevejde.
    @Test("Nápověda řekne, že kontrola nedoběhla")
    func theHintNamesTheOutcome() {
        #expect(StaleHeadView.hint(of: tally(resolved: 1, outcome: .timedOut)).hasPrefix("Kontrola nedoběhla"))
        #expect(StaleHeadView.hint(of: tally(resolved: 1, outcome: .interrupted))
            .hasPrefix("Kontrola skončila s aplikací"))
        #expect(StaleHeadView.hint(of: tally(outcome: .failed(detail: "spadlo to")))
            .contains("spadlo to"))
        // U doběhlé zbývá to, co platí vždycky: je to tvrzení, ne fakt.
        #expect(StaleHeadView.hint(of: tally(resolved: 1)).hasPrefix("Tvrzení kontroly"))
        #expect(StaleHeadView.hint(of: tally(resolved: 1)).contains("odmítnutí"))
    }

    /// Kontrola je session za peníze, takže nápověda u tlačítka musí říct **kolik nálezů a proti
    /// čemu** — a že se tím žádný nález nezahodí.
    @Test("Nápověda u tlačítka řekne rozsah i cenu")
    func theButtonHintNamesTheScope() {
        let hint = PullRequestDetailView.recheckHint(for: RecheckMaterial(
            headSha: "old1111aaaa",
            findings: [makeFinding(summary: "první"), makeFinding(summary: "druhý")]
        ))

        #expect(hint.contains("2 nálezy"))
        #expect(hint.contains("old1111"))
        #expect(!hint.contains("old1111aaaa"))
        #expect(hint.contains("Nálezy tím nemizí"))
    }

    /// Odznak nese v sobě, **odkud to je**: samotné „vyřešeno“ vedle nálezu by se čtlo jako fakt.
    @Test("Odznak říká, kdo to tvrdí")
    func theBadgeNamesItsSource() {
        for verdict in RecheckStatus.Verdict.allCases {
            #expect(verdict.label.hasPrefix("kontrola: "))
        }
    }

    /// Věta od kontroly se do sbalené značky nevejde, takže je v nápovědě — bez ní by u odznaku
    /// nebylo poznat, jak k verdiktu došel.
    @Test("Nápověda odznaku nese větu od kontroly")
    func theBadgeHintCarriesTheNote() {
        let status = RecheckStatus(verdict: .resolved, note: "commit abc přidal kontrolu")

        #expect(status.help.contains("commit abc přidal kontrolu"))
        #expect(status.help.contains("nález zůstává"))
        #expect(RecheckStatus(verdict: .resolved).help == RecheckStatus.Verdict.resolved.explanation)
    }
}
