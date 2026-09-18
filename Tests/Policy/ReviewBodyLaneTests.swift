import Foundation
import Testing

@testable import PRism

/// Co je o těle návrhu review vidět (#521) — **vyčerpávajícím výčtem**, protože o obojím
/// (věta v pruhu, dráha v `Průběhu`) rozhoduje čistá funkce.
///
/// **Nejcennější tvrzení: nad neutrálně napsaným tělem pruh netvrdí, že je podle mého hlasu.**
/// Rozbilo by se to potichu — nic by nespadlo, jen by okno tvrdilo víc, než data unesou.
@Suite("Policy — tělo review v okně (#521)")
struct ReviewBodyLaneTests {
    // MARK: - Věta v pruhu

    @Test("Napsané tělo řekne, z kolika review se bralo")
    func notesTheVoice() {
        #expect(
            Policy.reviewBodyNote(AutoDraftBody(samples: 7))
                == "Tělo je podle tvých posledních review (7)."
        )
    }

    /// **Nula vzorků má vlastní větu.** „Podle tvých posledních review (0)“ by tvrdilo pravý opak
    /// toho, co se stalo — a neutrálně napsané tělo je legitimní výsledek, ne polovičatý.
    @Test("Bez uložených review pruh řekne, že je tělo neutrální")
    func notesTheNeutralFallback() {
        #expect(
            Policy.reviewBodyNote(AutoDraftBody(samples: 0))
                == "Tělo je napsané neutrálně — žádné tvoje odeslané review se ještě neuložilo."
        )
    }

    /// Spadlá session = **prázdný composer, a pruh to řekne** (zadání #521). Bez věty je prázdný
    /// composer k nerozeznání od návrhu, u kterého se tělo nepsalo vůbec.
    @Test("Spadlá session se v pruhu přizná i s důvodem")
    func notesTheFailure() {
        let note = Policy.reviewBodyNote(
            AutoDraftBody(samples: 3, failure: .session(detail: "Tělo review nedoběhlo v limitu 3 minuty."))
        )

        #expect(note == "Tělo se nenapsalo, composer zůstal prázdný. Tělo review nedoběhlo v limitu 3 minuty.")
    }

    /// Ruční text má **vlastní** větu, ne větu o selhání: session doběhla, jen se její odstavec
    /// nepoužil — a tvrdit u toho poruchu by posílalo hledat něco, co se nepokazilo.
    @Test("Můj vlastní text má v pruhu vlastní větu")
    func notesTheHandWrittenBody() {
        #expect(
            Policy.reviewBodyNote(AutoDraftBody(samples: 3, failure: .handWritten))
                == "Tělo si píšeš sám — automat do composeru nesáhl."
        )
    }

    /// Razítko z doby před #521 tělo nemá, a pruh o něm proto **mlčí** — prázdná řádka by z něj
    /// udělala zprávu bez obsahu.
    @Test("Bez razítka o těle pruh mlčí")
    func saysNothingWithoutABody() {
        #expect(Policy.reviewBodyNote(nil) == nil)
    }

    // MARK: - Dráha v Průběhu

    @Test("Bez razítka a bez běhu se dráha nekreslí")
    func drawsNoLaneWithoutARun() {
        #expect(Policy.reviewBodyLane(isRunning: false, body: nil) == nil)
    }

    /// **Dvě fáze, ne tři** — a je to tvrzení, ne zkratka: osmá session nemá jediný nástroj, takže
    /// fáze `prochází kód` by u ní byla krok, který se nemá jak stát.
    @Test("Dráha má dvě fáze, protože session nemá nástroje")
    func hasTwoPhases() throws {
        let lane = try #require(Policy.reviewBodyLane(isRunning: false, body: AutoDraftBody(samples: 2)))

        #expect(lane.phases.map(\.title) == [ReviewerLane.Title.session, ReviewerLane.Title.body])
        #expect(!lane.phases.contains { $0.title == ReviewerLane.Title.code })
    }

    /// **`reportedFindings` zůstává navěky `nil`**: odstavec není nález, takže dráha nesmí nést
    /// číslo, které se čte jako „tolik toho našla“.
    @Test("Dráha nikdy nehlásí nálezy a nemá kam otevřít session")
    func neverReportsFindings() throws {
        let lane = try #require(Policy.reviewBodyLane(isRunning: false, body: AutoDraftBody(samples: 2)))

        #expect(lane.reportedFindings == nil)
        // Bez pracovního stromu nemá `Policy.rawSessionTarget` ani `Policy.terminalSession` z čeho
        // cíl složit — a tlačítko, které slibuje přepis, ke kterému se nedá dojít, je horší než
        // žádné.
        #expect(lane.sessionID == nil)
        #expect(lane.worktree == nil)
        #expect(Policy.rawSessionTarget(of: lane, slug: "cli/cli#42") == nil)
        #expect(Policy.terminalSession(of: lane) == nil)
    }

    /// **Běh má přednost před uloženým výsledkem**, jako u anotací: dokud session píše, je pravdou
    /// o tom PR ona.
    @Test("Běžící dráha přebíjí uložený výsledek")
    func theRunWins() throws {
        let lane = try #require(
            Policy.reviewBodyLane(
                isRunning: true,
                body: AutoDraftBody(samples: 1, failure: .session(detail: "staré selhání")),
                samples: 4
            )
        )

        #expect(lane.state == .running)
        #expect(lane.kind == .reviewBody(samples: 4, used: true))
    }

    @Test("Doběhlá dráha nese cenu i počet vzorků")
    func carriesTheCost() throws {
        let lane = try #require(
            Policy.reviewBodyLane(
                isRunning: false,
                body: AutoDraftBody(
                    samples: 5,
                    usage: RunUsage(cost: 0.12),
                    finishedAt: Date(timeIntervalSince1970: 100)
                )
            )
        )

        #expect(lane.state == .finished)
        #expect(lane.kind == .reviewBody(samples: 5, used: true))
        #expect(lane.usage?.cost == 0.12)
        #expect(lane.finishedAt == Date(timeIntervalSince1970: 100))
    }

    @Test("Spadlá session je červená dráha s důvodem")
    func failedLane() throws {
        let lane = try #require(
            Policy.reviewBodyLane(
                isRunning: false,
                body: AutoDraftBody(samples: 5, failure: .session(detail: "Session nevrátila žádný text."))
            )
        )

        #expect(lane.state == .failed(detail: "Session nevrátila žádný text."))
        #expect(lane.failure == "Session nevrátila žádný text.")
        #expect(lane.phases.allSatisfy { $0.state == .failed })
    }

    /// **`handWritten` je doběhlá dráha, ne spadlá**, a je to rozdíl, na kterém záleží: červená
    /// dráha by o běhu tvrdila, že se pokazil.
    @Test("Můj vlastní text nechává dráhu doběhlou, jen nepoužitou")
    func handWrittenIsFinished() throws {
        let lane = try #require(
            Policy.reviewBodyLane(isRunning: false, body: AutoDraftBody(samples: 5, failure: .handWritten))
        )

        #expect(lane.state == .finished)
        #expect(lane.kind == .reviewBody(samples: 5, used: false))
        #expect(lane.failure == nil)
    }
}
