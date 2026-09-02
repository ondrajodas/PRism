import Foundation
import Testing

@testable import PRism

/// Odkud je PR a co z toho záložka nakreslí (#531).
///
/// Dva výčty, obojí vyčerpávající: `origin` má **dvě** odpovědi a `tabContent` **čtyři** —
/// a nejcennější tvrzení celé sady je to, že se `loading` a `gone` nesmí slít. „Pull request
/// zmizel ze seznamu“ nad PR, který se právě dotahuje, je porucha hlášená nad stavem, ve kterém
/// se nic nepokazilo.
@Suite("Policy — PR mimo zdroje (#531)")
struct PullRequestOriginTests {
    private let vault = PRIdentifier("keboola/vault#85")!
    private let cli = PRIdentifier("cli/cli#1")!

    private func summary(_ id: PRIdentifier) -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: "titulek",
            author: "autor",
            url: Policy.githubURL(of: id),
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func detail(_ id: PRIdentifier) -> PullRequest {
        PullRequest(
            id: id,
            title: "titulek",
            author: "autor",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            url: Policy.githubURL(of: id),
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    @Test("PR ze seznamu je ze zdrojů, i když si ho člověk otevřel odkazem")
    func aListedPullRequestComesFromSources() {
        // Tohle je ta věta, kvůli které `origin` nečte jen značku: PR otevřený odkazem, na kterém
        // si mezitím někdo vyžádal moje review, přijde do fronty přes zdroje — a pilulka
        // `mimo zdroje` na něm musí zmizet, protože by lhala.
        #expect(Policy.origin(of: vault, adopted: [vault], sources: [vault, cli]) == .sources)
        #expect(Policy.origin(of: vault, adopted: [], sources: [vault]) == .sources)
    }

    @Test("PR, který v seznamu není a otevřel se odkazem, je mimo zdroje")
    func anAdoptedPullRequestIsOutsideSources() {
        #expect(Policy.origin(of: vault, adopted: [vault], sources: [cli]) == .outsideSources)
    }

    /// **Nejtišší chyba téhle funkce**: PR ze zdrojů, který zrovna vypadl z tiku (mergnul se,
    /// odebral se request na review), by bez značky dostal pilulku `mimo zdroje` — tedy tvrzení,
    /// že si ho člověk otevřel odkazem.
    @Test("PR, který ze zdrojů vypadl, pilulku nedostane")
    func aPullRequestThatFellOutOfTheListIsNotAdopted() {
        #expect(Policy.origin(of: vault, adopted: [], sources: []) == .sources)
    }

    /// Řádek `Odkaz` se ptá na něco jiného než pilulka, a je to ta past, kterou tahle sada chytila
    /// při prvním běhu: `origin(of:)` u neznámého PR vrací `sources` (nikdo ho odkazem neotevřel),
    /// takže by odkaz na cizí repo tvrdil `je ve tvých zdrojích` — a člověk by ho čekal ve frontě.
    @Test("Odkaz na PR, o kterém store neví, je mimo zdroje")
    func anUnknownLinkIsOutsideSources() {
        #expect(Policy.linkOrigin(of: vault, sources: []) == .outsideSources)
        #expect(Policy.linkOrigin(of: vault, sources: [cli]) == .outsideSources)
        #expect(Policy.linkOrigin(of: vault, sources: [vault, cli]) == .sources)
    }

    @Test("Pilulka se kreslí jen mimo zdroje")
    func onlyTheOutsidePillIsDrawn() {
        #expect(Policy.originNote(.sources) == nil)
        #expect(Policy.originNote(.outsideSources) == "mimo zdroje · jen ke čtení")
    }

    @Test("Se shrnutím se kreslí detail, ať je PR odkudkoli")
    func aKnownSummaryWins() {
        for origin in [PullRequestOrigin.sources, .outsideSources] {
            #expect(
                Policy.tabContent(summary: summary(vault), detail: nil, origin: origin)
                    == .detail(summary(vault))
            )
        }
    }

    @Test("Bez shrnutí se PR ze zdrojů hlásí jako zmizelý")
    func aMissingSourcePullRequestIsGone() {
        // I nad rozdělaným načítáním: u PR ze zdrojů je shrnutí ze seznamu, takže nenačtený
        // detail znamená jen chybějící větve v hlavičce, ne prázdnou obrazovku.
        #expect(Policy.tabContent(summary: nil, detail: .loading, origin: .sources) == .gone)
        #expect(Policy.tabContent(summary: nil, detail: nil, origin: .sources) == .gone)
    }

    @Test("Záložka mimo zdroje rozlišuje načítání od poruchy")
    func anAdoptedTabTellsLoadingFromFailure() {
        #expect(Policy.tabContent(summary: nil, detail: nil, origin: .outsideSources) == .loading)
        #expect(
            Policy.tabContent(summary: nil, detail: .loading, origin: .outsideSources) == .loading
        )
        #expect(
            Policy.tabContent(summary: nil, detail: .failed("HTTP 404"), origin: .outsideSources)
                == .failed("HTTP 404")
        )
        // Dotažený detail bez shrnutí se v aplikaci nestane (shrnutí se z něj skládá), ale
        // odpověď na to musí být čekání, ne porucha.
        let loaded = DetailState.loaded(detail(vault), updatedAt: Date(timeIntervalSince1970: 100))
        #expect(Policy.tabContent(summary: nil, detail: loaded, origin: .outsideSources) == .loading)
    }

    /// Shrnutí pro pruh záložek nesmí nic tvrdit: pruh z něj čte `repo#číslo`, titulek je v něm
    /// jen jako tooltip.
    @Test("Rozdělané shrnutí říká, že se načítá, a nic si nevymýšlí")
    func thePendingSummaryClaimsNothing() {
        let pending = Policy.pendingSummary(for: vault)

        #expect(pending.id == vault)
        #expect(pending.title == "Načítá se…")
        #expect(pending.author.isEmpty)
        #expect(pending.updatedAt == .distantPast)
        #expect(pending.url == Policy.githubURL(of: vault))
    }
}
