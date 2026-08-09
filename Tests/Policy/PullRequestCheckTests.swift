import Foundation
import Testing

@testable import PRism

/// Checky z GitHub Actions (#209).
///
/// Dvě věci se dají pokazit potichu: **počítat přeskočený check jako úspěch** (hlavička by pak
/// svítila zeleně nad přeskočeným testem) a **počítat většinu místo nejhoršího** (dvanáct
/// zelených a jeden červený je červený stav, ne „skoro hotovo“).
@Suite("Checky na PR")
struct PullRequestCheckTests {
    private func check(
        _ name: String,
        _ bucket: String,
        started: TimeInterval? = nil,
        completed: TimeInterval? = nil
    ) -> PullRequestCheck {
        PullRequestCheck(
            name: name,
            outcome: .init(bucket: bucket),
            link: nil,
            startedAt: started.map { Date(timeIntervalSince1970: $0) },
            completedAt: completed.map { Date(timeIntervalSince1970: $0) }
        )
    }

    // MARK: - Překlad kbelíků

    @Test("Kbelíky se překládají na stavy")
    func mapsBuckets() {
        #expect(PullRequestCheck.Outcome(bucket: "pass") == .passed)
        #expect(PullRequestCheck.Outcome(bucket: "fail") == .failed)
        #expect(PullRequestCheck.Outcome(bucket: "skipping") == .skipped)
        #expect(PullRequestCheck.Outcome(bucket: "cancel") == .cancelled)
        #expect(PullRequestCheck.Outcome(bucket: "pending") == .running)
    }

    /// Neznámý kbelík je **běžící**, ne úspěch: je to jediný stav, který o výsledku netvrdí nic,
    /// a hádat by lhalo oběma směry.
    @Test("Neznámý kbelík je běžící")
    func treatsAnUnknownBucketAsRunning() {
        #expect(PullRequestCheck.Outcome(bucket: "co je tohle") == .running)
    }

    // MARK: - Souhrn

    /// **Nejcennější test téhle sady.** Přeskočený check není prošlý — jinak by hlavička nad
    /// přeskočeným testem svítila zeleně.
    @Test("Přeskočený se nepočítá jako prošlý")
    func doesNotCountSkippedAsPassed() {
        let summary = Policy.summary(of: [check("a", "pass"), check("b", "skipping")])

        #expect(summary.passed == 1)
        #expect(summary.skipped == 1)
        #expect(summary.worst == .passed)
    }

    @Test("Nejhorší stav rozhoduje, ne většina")
    func takesTheWorstNotTheMajority() {
        let checks = (0..<12).map { check("ok\($0)", "pass") } + [check("bad", "fail")]

        #expect(Policy.summary(of: checks).worst == .failed)
    }

    @Test("Běžící přebije prošlé, ale ne spadlé")
    func rankTheRunningState() {
        #expect(Policy.summary(of: [check("a", "pass"), check("b", "pending")]).worst == .running)
        #expect(Policy.summary(of: [check("a", "fail"), check("b", "pending")]).worst == .failed)
    }

    /// Zrušený běh o kódu nevypovídá — počítá se ke spadlým, protože z obojího plyne, že se PR
    /// nemá čím pochlubit.
    @Test("Zrušený se počítá ke spadlým")
    func countsCancelledAsFailed() {
        #expect(Policy.summary(of: [check("a", "cancel")]).failed == 1)
    }

    @Test("Bez checků není co shrnovat")
    func handlesNoChecks() {
        #expect(Policy.summary(of: []).isEmpty)
        #expect(Policy.summary(of: []).worst == nil)
    }

    // MARK: - Pořadí

    /// Na skutečném PR je přes dvacet checků a většina přeskočená (změřeno na
    /// `keboola/platform-libraries#557`: 28 z toho 22 přeskočených). Bez pořadí by ten jeden
    /// spadlý ležel někde uprostřed.
    @Test("Spadlé nahoru, přeskočené dolů")
    func sortsBySeverity() {
        let sorted = Policy.sorted([
            check("skip", "skipping"),
            check("ok", "pass"),
            check("bad", "fail"),
            check("run", "pending"),
        ])

        #expect(sorted.map(\.name) == ["bad", "run", "ok", "skip"])
    }

    @Test("Při shodě rozhoduje jméno, ať pořadí neposkakuje")
    func breaksTiesByName() {
        #expect(Policy.sorted([check("b", "pass"), check("a", "pass")]).map(\.name) == ["a", "b"])
    }

    // MARK: - Trvání

    @Test("Trvání se počítá z časů, dokud běh neskončil je nil")
    func measuresTheDuration() {
        #expect(check("a", "pass", started: 100, completed: 160).duration == 60)
        #expect(check("b", "pending", started: 100).duration == nil)
    }
}
