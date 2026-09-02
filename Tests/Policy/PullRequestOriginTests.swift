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
        #expect(Policy.origin(of: vault, adopted: [vault: .link], sources: [vault, cli]) == .sources)
        #expect(Policy.origin(of: vault, adopted: [:], sources: [vault]) == .sources)
    }

    @Test("PR, který v seznamu není a otevřel se odkazem, je mimo zdroje")
    func anAdoptedPullRequestIsOutsideSources() {
        #expect(Policy.origin(of: vault, adopted: [vault: .link], sources: [cli]) == .outsideSources)
    }

    /// **Nejtišší chyba téhle funkce**: PR ze zdrojů, který zrovna vypadl z tiku (mergnul se,
    /// odebral se request na review), by bez značky dostal pilulku `mimo zdroje` — tedy tvrzení,
    /// že si ho člověk otevřel odkazem.
    @Test("PR, který ze zdrojů vypadl, pilulku nedostane")
    func aPullRequestThatFellOutOfTheListIsNotAdopted() {
        #expect(Policy.origin(of: vault, adopted: [:], sources: []) == .sources)

        // **A obnovená záložka pilulku nedostane taky** (#527), i když v seznamu není: obnovení
        // běží před prvním tikem, takže by `mimo zdroje` bliklo u každé z nich — a u mergnutého
        // PR by tvrdilo „otevřel jsi ho odkazem“, což není pravda.
        #expect(Policy.origin(of: vault, adopted: [vault: .restored], sources: []) == .sources)
        #expect(Policy.origin(of: vault, adopted: [vault: .restored], sources: [cli]) == .sources)
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
        for adoption in [nil, TabAdoption.link, .restored] {
            #expect(
                Policy.tabContent(summary: summary(vault), detail: nil, adoption: adoption)
                    == .detail(summary(vault))
            )
        }
    }

    @Test("Bez shrnutí se PR ze zdrojů hlásí jako zmizelý")
    func aMissingSourcePullRequestIsGone() {
        // I nad rozdělaným načítáním: u PR ze zdrojů je shrnutí ze seznamu, takže nenačtený
        // detail znamená jen chybějící větve v hlavičce, ne prázdnou obrazovku.
        #expect(Policy.tabContent(summary: nil, detail: .loading, adoption: nil) == .gone)
        #expect(Policy.tabContent(summary: nil, detail: nil, adoption: nil) == .gone)
    }

    /// **Oba důvody přijetí, ne jen odkaz** (#527): obnovená záložka je nad mergnutým PR ten
    /// případ, na kterém to celé stojí — `gone` by nad ní byla věta „pull request zmizel“ nad
    /// obrazovkou, kterou si aplikace zrovna sama načítá.
    @Test("Přijatá záložka rozlišuje načítání od poruchy", arguments: [TabAdoption.link, .restored])
    func anAdoptedTabTellsLoadingFromFailure(adoption: TabAdoption) {
        #expect(Policy.tabContent(summary: nil, detail: nil, adoption: adoption) == .loading)
        #expect(
            Policy.tabContent(summary: nil, detail: .loading, adoption: adoption) == .loading
        )
        #expect(
            Policy.tabContent(summary: nil, detail: .failed("HTTP 404"), adoption: adoption)
                == .failed("HTTP 404")
        )
        // Dotažený detail bez shrnutí se v aplikaci nestane (shrnutí se z něj skládá), ale
        // odpověď na to musí být čekání, ne porucha.
        let loaded = DetailState.loaded(detail(vault), updatedAt: Date(timeIntervalSince1970: 100))
        #expect(Policy.tabContent(summary: nil, detail: loaded, adoption: adoption) == .loading)
    }

    /// **Věta u načítání nesmí tvrdit víc, než co data unesou** (#527). Do #527 stála ve
    /// `ContentView` jediná — `není ve zdrojích` —, a u obnovené záložky by lhala: obnovení běží
    /// před prvním tikem, takže se v tu chvíli **neví**, jestli PR ve zdrojích je.
    @Test("Věta u načítání i u poruchy se liší podle důvodu přijetí")
    func theNotesTellTheAdoptionApart() {
        let linked = Policy.loadingTabNote(for: vault, adoption: .link)
        let restored = Policy.loadingTabNote(for: vault, adoption: .restored)

        #expect(linked.contains("není ve zdrojích"))
        #expect(!restored.contains("není ve zdrojích"))
        #expect(restored.contains("restartu"))
        // Identifikátor je v obou: bez něj by věta nešla přiřadit k záložce.
        #expect(linked.contains(vault.description))
        #expect(restored.contains(vault.description))

        // U poruchy je rozdíl v radě: adresu u obnovené záložky nikdo nepsal, takže „zkontroluj
        // adresu“ by posílalo člověka hledat chybu, kterou neudělal.
        #expect(Policy.failedTabNote(for: vault, adoption: .link).contains("Zkontroluj adresu"))
        #expect(!Policy.failedTabNote(for: vault, adoption: .restored).contains("Zkontroluj adresu"))
        #expect(Policy.failedTabNote(for: vault, adoption: .restored).contains("vidíš"))
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
