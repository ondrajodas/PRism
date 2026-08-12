import Foundation
import Testing

@testable import PRism

/// Co je v tabu `Kontroly` a jaký nad ním svítí odznak (#215, přepnuto #306).
///
/// Tři věci se dají pokazit potichu:
///
/// - **říct, že PR nemá CI, dokud se čeká na odpověď.** Prázdno a nenačteno jsou dva různé stavy
///   a jen to první o CI něco tvrdí — je to tentýž rozdíl jako mezi `čisté` a `failed` u review;
/// - **udělat z poruchy prázdno**, tedy z chyby sítě tvrzení „tenhle PR nemá CI“;
/// - **spočítat odznak podle většiny místo nejhoršího** (dvanáct zelených a jeden červený je
///   červený stav) — nebo ho nakreslit tam, kde se ještě nic nespočítalo.
@Suite("Tab Kontroly a jeho odznak")
struct ChecksTabStateTests {
    private func check(_ name: String, _ bucket: String) -> PullRequestCheck {
        PullRequestCheck(
            name: name,
            outcome: .init(bucket: bucket),
            link: nil,
            startedAt: nil,
            completedAt: nil
        )
    }

    private func badge(_ buckets: [String]) -> PullRequestTabBadge? {
        let checks = buckets.enumerated().map { check("c\($0.0)", $0.1) }
        return Policy.checksBadge(of: Policy.checksTab(checks: checks, failure: nil))
    }

    private let one = [
        PullRequestCheck(name: "phpcs", outcome: .passed, link: nil, startedAt: nil, completedAt: nil),
    ]

    // MARK: - Čtyři stavy tabu, vyčerpávajícím výčtem

    /// Vstupy jsou dva a jejich kombinací je šest — `checks` nenačtené / prázdné / neprázdné krát
    /// `failure` je / není. Tady je celá ta mřížka, protože právě v ní se ty čtyři odpovědi dají
    /// splést: každé prázdno vypadá zvenku stejně.
    @Test("Šest kombinací vstupů dá čtyři odpovědi")
    func coversEveryCombination() {
        #expect(Policy.checksTab(checks: nil, failure: nil) == .loading)
        #expect(Policy.checksTab(checks: [], failure: nil) == .empty)
        #expect(Policy.checksTab(checks: one, failure: nil) == .list(one, failure: nil))
        #expect(Policy.checksTab(checks: nil, failure: "gh spadl") == .failed("gh spadl"))
        #expect(Policy.checksTab(checks: [], failure: "gh spadl") == .failed("gh spadl"))
        #expect(Policy.checksTab(checks: one, failure: "gh spadl") == .list(one, failure: "gh spadl"))
    }

    /// **Nejcennější test téhle sady.** Dokud se čeká na odpověď, nesmí z tabu vyjít tvrzení o CI —
    /// a nenačteno je zvenku k nerozeznání od prázdna, takže se to musí rozhodovat z chybějícího
    /// klíče, ne z počtu prvků.
    @Test("Nenačteno není prázdno")
    func neverClaimsMissingCIWhileLoading() {
        #expect(Policy.checksTab(checks: nil, failure: nil) == .loading)
        #expect(Policy.checksTab(checks: nil, failure: nil) != .empty)
    }

    /// Porucha přebíjí obě prázdna: prázdno je z **předchozího** načtení, kdežto chyba je to, co
    /// víme teď. Bez toho by z chyby sítě vyšlo „tenhle PR nemá CI“, tedy zrovna ta záměna, kvůli
    /// které `checkFailures` vznikly.
    @Test("Z poruchy se prázdno nestane")
    func failureBeatsEmptiness() {
        #expect(Policy.checksTab(checks: nil, failure: "timeout") == .failed("timeout"))
        #expect(Policy.checksTab(checks: [], failure: "timeout") == .failed("timeout"))
    }

    /// Zastaralá sada s větou nad sebou je lepší než plocha s chybou místo checků, které se před
    /// chvílí načetly (#215) — takže neprázdný seznam poruchu **přebíjí**, jen si ji nese s sebou.
    @Test("Seznam přežije poruchu a nese si důvod")
    func keepsTheListAndTheReason() {
        #expect(Policy.checksTab(checks: one, failure: "timeout") == .list(one, failure: "timeout"))
    }

    // MARK: - Odznak podle nejhoršího stavu

    @Test("Spadlé dávají červený počet, ne tichou kapsli")
    func marksFailuresAsBlocking() {
        #expect(badge(["fail"]) == .blocking(1))
        #expect(badge(["fail", "fail", "pass"]) == .blocking(2))
    }

    /// Tatáž úvaha jako u chipu v hlavičce (#209): dvanáct zelených a jeden červený je červený
    /// stav, ne „skoro hotovo“.
    @Test("Nejhorší stav rozhoduje, ne většina")
    func takesTheWorstNotTheMajority() {
        let buckets = Array(repeating: "pass", count: 12) + ["fail"]

        #expect(badge(buckets) == .blocking(1))
    }

    /// Zrušený běh se počítá ke spadlým (`Policy.summary`), takže odznak je červený i nad ním —
    /// z obojího plyne, že se PR nemá čím pochlubit.
    @Test("Zrušený check je taky červený odznak")
    func marksCancelledAsBlocking() {
        #expect(badge(["cancel"]) == .blocking(1))
        #expect(badge(["cancel", "fail"]) == .blocking(2))
    }

    /// „Běží“ je **stav, ne množství**: u dvou běžících jobů by dvojka o průběhu neřekla nic.
    /// Tentýž puntík jako u `Průběhu`.
    @Test("Běžící checky dávají puntík, ne číslo")
    func marksRunningAsLive() {
        #expect(badge(["pending"]) == .live)
        #expect(badge(["pending", "pending", "pass"]) == .live)
    }

    @Test("Spadlé přebijí běžící")
    func failuresOutrankRunning() {
        #expect(badge(["pending", "fail"]) == .blocking(1))
    }

    /// **Zelené CI odznak nedostane.** Je to výchozí stav a číslo u něj by byl šum, kvůli
    /// kterému by se přestaly čít i ty ostatní dva odznaky.
    @Test("Zelené ani přeskočené checky odznak nemají")
    func staysQuietWhenNothingNeedsAttention() {
        #expect(badge(["pass"]) == nil)
        #expect(badge(Array(repeating: "pass", count: 12)) == nil)
        #expect(badge(["skipping"]) == nil)
        #expect(badge(["pass", "skipping"]) == nil)
    }

    /// **Tohle je ten test, který tvrdí, že se něco NEstalo** (#306): dokud není seznam, odznak
    /// není. Do #306 to platilo jen shodou okolností — tab u prázdných checků vůbec nebyl, takže
    /// se odznak neměl kde nakreslit; teď je to jediné, co drží prázdnou kapsli a nulu mimo pruh
    /// záložek nad tabem, ve kterém se zrovna čeká na odpověď.
    @Test("Bez seznamu není odznak: ani nenačteno, ani prázdno, ani porucha")
    func staysQuietWithoutAList() {
        #expect(Policy.checksBadge(of: .loading) == nil)
        #expect(Policy.checksBadge(of: .empty) == nil)
        #expect(Policy.checksBadge(of: .failed("gh spadl")) == nil)
    }

    /// Zastaralý seznam odznak **má** — mluví o tom, co je pod ním k vidění, a to je ten seznam.
    @Test("Zastaralý seznam odznak má")
    func marksAStaleList() {
        let failed = [check("phpstan", "fail")]

        #expect(Policy.checksBadge(of: .list(failed, failure: "timeout")) == .blocking(1))
    }
}
