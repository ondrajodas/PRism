import Foundation
import Testing

@testable import PRism

/// Texty přesázené hlavičky PR (#218) — pruh běhu, kapsle reviewerů a stav pracovní kopie.
/// Všechno čisté funkce, takže se dá vyčerpat výčtem bez kreslení.
@Suite("Sazba hlavičky PR")
struct PullRequestHeaderTextTests {
    private let started = Date(timeIntervalSince1970: 1_700_000_000)

    private func now(after seconds: TimeInterval) -> Date {
        started.addingTimeInterval(seconds)
    }

    // MARK: - Popisek pruhu běhu

    @Test("Popisek běhu je jméno, poměr a stopky")
    func runbarLabel() {
        let progress = ReviewRunProgress(
            stage: .running(finished: 2, total: 3),
            running: ["test-coverage"],
            startedAt: started
        )

        #expect(ReviewRunbarView.label(progress, names: [:], at: now(after: 72))
            == "test-coverage · 2 z 3 hotovo · 1:12")
    }

    /// Zkrácené jméno je totéž, které nese kapsle vedle (#182) — dvě různá zkrácení téhož
    /// skillu v jednom řádku by vypadala jako dva reviewery.
    @Test("Popisek bere zkrácené jméno, když ho kapsle nese taky")
    func runbarLabelShortensNames() {
        let progress = ReviewRunProgress(
            stage: .running(finished: 0, total: 1),
            running: ["superpowers:requesting-code-review"],
            startedAt: started
        )

        #expect(ReviewRunbarView.label(
            progress,
            names: ["superpowers:requesting-code-review": "requesting-code-review"],
            at: now(after: 5)
        ) == "requesting-code-review · 0 z 1 hotovo · 0:05")
    }

    @Test("Víc běžících reviewerů se vyjmenuje")
    func runbarLabelListsEveryRunningReviewer() {
        let progress = ReviewRunProgress(
            stage: .running(finished: 1, total: 3),
            running: ["docs", "php-review"],
            startedAt: started
        )

        #expect(ReviewRunbarView.label(progress, names: [:], at: now(after: 65))
            == "docs, php-review · 1 z 3 hotovo · 1:05")
    }

    /// Nastane mezi doběhnutím posledního revieweera a úklidem běhu. Věta o tom, kolik je
    /// hotovo, dává smysl i bez jmen — prázdná mezera před `·` by vypadala jako chyba.
    @Test("Bez běžícího revieweera zbude poměr a stopky")
    func runbarLabelWithoutRunningReviewers() {
        let progress = ReviewRunProgress(
            stage: .running(finished: 3, total: 3),
            running: [],
            startedAt: started
        )

        #expect(ReviewRunbarView.label(progress, names: [:], at: now(after: 100))
            == "3 z 3 hotovo · 1:40")
    }

    /// Během přípravy se počty neví, takže se **netvrdí** — a stopky říkají, že se něco děje.
    @Test("Příprava kopie se pojmenuje, ne počítá")
    func runbarLabelWhilePreparing() {
        let progress = ReviewRunProgress(stage: .preparing, running: [], startedAt: started)

        #expect(ReviewRunbarView.label(progress, names: [:], at: now(after: 4))
            == "připravuji pracovní kopii · 0:04")
    }

    // MARK: - Kapsle revieweera

    /// Počet je **jen tam, kde běh doběhl a dopočítal se**. `0` u nedoběhlého běhu by
    /// znamenalo „nic nenašel“ — a to je přesně tvrzení, které data neunesou.
    @Test("Číslo nesou jen doběhlé stavy, ostatní zůstávají slovem")
    func chipLabels() {
        #expect(ReviewerChipsView.label(.findings(2)) == "2")
        #expect(ReviewerChipsView.label(.clean) == "0")
        #expect(ReviewerChipsView.label(.notStarted) == "neběželo")
        #expect(ReviewerChipsView.label(.failed("spadlo")) == "selhalo")
        #expect(ReviewerChipsView.label(.inconclusive("nenahlásil")) == "nejisté")
        #expect(ReviewerChipsView.label(.timedOut(findings: 0)) == "timeout")
        #expect(ReviewerChipsView.label(.timedOut(findings: 2)) == "timeout 2")
        #expect(ReviewerChipsView.label(.interrupted(findings: 0)) == "přerušeno")
        #expect(ReviewerChipsView.label(.interrupted(findings: 1)) == "přerušeno 1")
    }

    /// U běžícího revieweera mluví spinner. Číslo by u něj nemělo co říct — nálezy ještě
    /// chodí.
    @Test("Běžící reviewer nemá za jménem nic")
    func chipLabelWhileRunning() {
        #expect(ReviewerChipsView.label(.running) == nil)
    }

    /// Od #218 nenese stav ani slovo, takže odečítání je jediné místo, kde se `čisté` pozná
    /// od `selhalo`. Barva puntíku sama nestačí.
    @Test("Odečítání dostane stav slovem u každého stavu")
    func chipStatesAreSpoken() {
        #expect(ReviewerChipsView.spokenState(.clean) == "čisté, žádný nález")
        #expect(ReviewerChipsView.spokenState(.findings(1)) == "1 nález")
        #expect(ReviewerChipsView.spokenState(.findings(3)) == "3 nálezy")
        #expect(ReviewerChipsView.spokenState(.running) == "běží")
        #expect(ReviewerChipsView.spokenState(.failed("spadlo")) == "selhalo")
        #expect(ReviewerChipsView.spokenState(.timedOut(findings: 2)) == "timeout, 2 nálezy")
        #expect(ReviewerChipsView.spokenState(.interrupted(findings: 0)) == "přerušeno")
    }

    // MARK: - Pracovní kopie ve stavovém řádku

    @Test("Připravená kopie nese hlavu PR")
    func workingCopyWithHead() {
        #expect(WorkingCopyStatusView.text(.ready(URL(filePath: "/tmp/x")), head: "4f2ac91")
            == "Pracovní kopie připravená · HEAD 4f2ac91")
    }

    /// Dokud detail nedorazil, sha se **nehádá**: věta zůstane bez ní.
    @Test("Bez známé hlavy zbude jen stav kopie")
    func workingCopyWithoutHead() {
        #expect(WorkingCopyStatusView.text(.ready(URL(filePath: "/tmp/x")), head: nil)
            == "Pracovní kopie připravená")
        #expect(WorkingCopyStatusView.text(.preparing, head: nil) == "Připravuji pracovní kopii…")
        #expect(WorkingCopyStatusView.text(.absent, head: nil) == "Pracovní kopie zatím není")
    }

    /// **Selhání se do pruhu nekreslí** — zůstává bannerem v hlavičce, protože se u něj musí
    /// vypsat celý výstup `gitu`, a z něj se teprve pozná, co dělat dál.
    @Test("Selhaný checkout se ve stavovém řádku neukazuje")
    func workingCopyHidesFailures() {
        #expect(WorkingCopyStatusView.text(.failed("fatal: repository not found"), head: "4f2ac91") == nil)
    }
}
