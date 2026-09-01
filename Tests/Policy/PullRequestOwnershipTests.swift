import Foundation
import Testing

@testable import PRism

/// Rozřazení pull requestů podle autora (#330).
///
/// **Nejcennější je tady ten první test: prázdný viewer znamená „nevím“, ne „to jsem já“.** Tvrdí,
/// že se něco NEstalo — že se seznam při startu nepřehodil do „moje“ —, a rozbije se to potichu:
/// obrácené výchozí chování nic neshodí, jen na okamžik po spuštění zmizí fronta cizích PR, a to
/// vypadá jako „ještě se to nenačetlo“.
///
/// Vyčerpává se výčtem, protože jsou to čisté funkce.
@Suite("Rozřazení PR podle autora (#330)")
struct PullRequestOwnershipTests {
    private func summary(author: String, _ identifier: String = "cli/cli#1") -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    // MARK: - Dokud se neví, kdo se dívá, je všechno cizí

    /// Tohle je ta věta, na které celé issue stojí.
    @Test("Bez viewera je i vlastní PR cizí")
    func emptyViewerMeansEverythingIsTheirs() {
        let mine = Policy.ownLogins(viewer: "")

        #expect(mine.isEmpty)
        #expect(Policy.ownership(of: summary(author: "ondrajodas"), mine: mine) == .theirs)
        #expect(Policy.ownership(of: summary(author: "kolega"), mine: mine) == .theirs)
    }

    @Test("Nenačtený viewer (nil) je totéž jako prázdný")
    func missingViewerMeansEverythingIsTheirs() {
        #expect(Policy.ownLogins(viewer: nil).isEmpty)
        #expect(Policy.ownership(of: summary(author: "ondrajodas"), mine: Policy.ownLogins(viewer: nil)) == .theirs)
    }

    /// `gh` by prázdný login nevrátil (gateway na něj vyhazuje), ale bílé znaky se do konfigurace
    /// napsat dají — a `"  "` se nesmí stát loginem, kterému by se dal někdo rovnat.
    @Test("Bílé znaky loginem nejsou")
    func whitespaceIsNotALogin() {
        #expect(Policy.ownLogins(viewer: "   ").isEmpty)
        #expect(Policy.ownLogins(viewer: "", configured: ["", "  ", "\n"]).isEmpty)
        #expect(Policy.ownership(ofAuthor: "  ", mine: ["ondrajodas"]) == .theirs)
    }

    /// Autor, kterého ještě neznáme (detail nedorazil), spadá na tutéž stranu jako neznámý viewer.
    @Test("Neznámý autor je cizí")
    func missingAuthorIsTheirs() {
        #expect(Policy.ownership(ofAuthor: nil, mine: ["ondrajodas"]) == .theirs)
    }

    // MARK: - Se známým viewerem

    @Test("Vlastní PR je moje")
    func viewerOwnsItsPullRequests() {
        let mine = Policy.ownLogins(viewer: "ondrajodas")

        #expect(Policy.ownership(of: summary(author: "ondrajodas"), mine: mine) == .mine)
        #expect(Policy.ownership(of: summary(author: "kolega"), mine: mine) == .theirs)
    }

    /// GitHub je na velikost písmen necitlivý: `gh` vrací kanonický tvar, kdežto do konfigurace si
    /// login člověk píše, jak ho zrovna vidí. Bez normalizace by se to tiše minulo.
    @Test("Velikost písmen v loginu nerozhoduje")
    func loginComparisonIgnoresCase() {
        #expect(Policy.ownership(of: summary(author: "OndraJodas"), mine: Policy.ownLogins(viewer: "ondrajodas")) == .mine)
        #expect(Policy.ownership(of: summary(author: "ondrajodas"), mine: Policy.ownLogins(viewer: "OndraJodas")) == .mine)
    }

    /// Login zapsaný do konfigurace s mezerou navíc se pořád má poznat — soubor se edituje ručně.
    @Test("Mezery okolo loginu nerozhodují")
    func loginComparisonTrimsWhitespace() {
        #expect(Policy.ownLogins(viewer: " ondrajodas ") == ["ondrajodas"])
    }

    // MARK: - Množina, ne jeden řetězec

    /// Druhá polovina zadání: agent s vlastním účtem nespadne do `.mine` podle viewera, takže se
    /// jeho login musí dát dopsat. Kdyby `ownership` brala jeden řetězec, dolepovalo by se to
    /// později do všech míst, která se ptají „je to moje“.
    @Test("Agent z konfigurace se počítá za mě")
    func configuredLoginsCountAsMine() {
        let mine = Policy.ownLogins(viewer: "ondrajodas", configured: ["github-actions[bot]"])

        #expect(mine == ["ondrajodas", "github-actions[bot]"])
        #expect(Policy.ownership(of: summary(author: "github-actions[bot]"), mine: mine) == .mine)
        #expect(Policy.ownership(of: summary(author: "ondrajodas"), mine: mine) == .mine)
        #expect(Policy.ownership(of: summary(author: "dependabot[bot]"), mine: mine) == .theirs)
    }

    /// Konfigurace **nenahrazuje** viewera, přidává se k němu — a sama bez viewera taky funguje
    /// (agent běží, člověk se ještě nepřihlásil).
    @Test("Konfigurace bez viewera pořád platí")
    func configuredLoginsWorkWithoutViewer() {
        let mine = Policy.ownLogins(viewer: "", configured: ["Copilot"])

        #expect(mine == ["copilot"])
        #expect(Policy.ownership(of: summary(author: "copilot"), mine: mine) == .mine)
        #expect(Policy.ownership(of: summary(author: "ondrajodas"), mine: mine) == .theirs)
    }

    // MARK: - Rozhoduje autor, ne zdroj

    /// Jeden PR umí splňovat víc dotazů naráz, takže rozřazení odvozené od zdroje by záviselo na
    /// tom, jak si člověk dotazy poskládal. `ownership` proto o zdroji neví vůbec — což je vidět
    /// z toho, že dva PR z téhož seznamu vyjdou různě.
    @Test("Dva PR ze stejného zdroje se rozřadí každý podle svého autora")
    func ownershipFollowsTheAuthorNotTheSource() {
        let mine = Policy.ownLogins(viewer: "ondrajodas")
        let merged = [
            summary(author: "ondrajodas", "keboola/vault#85"),
            summary(author: "kolega", "cli/cli#7"),
        ]

        #expect(merged.map { Policy.ownership(of: $0, mine: mine) } == [.mine, .theirs])
    }

    // MARK: - Zdroj vlastních PR mezi zdroji

    @Test("Výchozí zdroje vlastní PR sledují")
    func standardSourcesTrackOwnPullRequests() {
        #expect(Configuration.standard.global.sources == [.reviewRequested, .mine])
        #expect(Source.mine.query == "author:@me is:open")
        #expect(Policy.tracksOwnPullRequests(in: Configuration.standard.activeSources, mine: []))
    }

    /// Tohle je ta situace na mém stroji: `sources` je v `config.json` už uložené, takže nový
    /// výchozí zdroj se nedoplní a sekce `Moje PR` by zůstala navždycky prázdná. Poznat se to
    /// musí bez viewera — hned, ne až se login načte.
    @Test("Uložená konfigurace bez vlastního zdroje se pozná")
    func recognizesConfigurationWithoutOwnSource() {
        #expect(!Policy.tracksOwnPullRequests(in: [.reviewRequested], mine: []))
        #expect(!Policy.tracksOwnPullRequests(in: [], mine: ["ondrajodas"]))
    }

    /// Rozpoznává se **token `author:`**, ne jméno zdroje: přejmenovaný řádek nesmí rozpoznání
    /// vypnout a cizí dotaz ho nesmí zapnout.
    @Test("Poznává se dotaz, ne jméno zdroje")
    func recognitionReadsTheQuery() {
        let renamed = Source(name: "Co jsem nasekal", query: "author:@me is:open")
        #expect(Policy.tracksOwnPullRequests(in: [renamed], mine: []))

        let named = Source(name: "Moje PR", query: "review-requested:@me is:open")
        #expect(!Policy.tracksOwnPullRequests(in: [named], mine: []))
    }

    /// Negace a příbuzné kvalifikátory jsou **jiné dotazy** a žádné vlastní PR nepřinesou.
    @Test("Negace ani involves se za vlastní zdroj nepočítá")
    func negationAndInvolvesDoNotCount() {
        #expect(!Policy.tracksOwnPullRequests(in: [Source(name: "Bez mých", query: "-author:@me is:open")], mine: []))
        #expect(!Policy.tracksOwnPullRequests(in: [Source(name: "Kde jsem", query: "involves:@me")], mine: []))
        #expect(!Policy.tracksOwnPullRequests(in: [Source(name: "Prázdný", query: "author:")], mine: []))
    }

    /// Kdo si login vypíše ručně, dostane rozpoznání podle svých loginů — velikost písmen
    /// nerozhoduje ani tady.
    @Test("Vypsaný login se pozná podle mých loginů")
    func recognizesExplicitLogin() {
        let explicit = [Source(name: "Moje", query: "author:OndraJodas is:open")]

        #expect(Policy.tracksOwnPullRequests(in: explicit, mine: Policy.ownLogins(viewer: "ondrajodas")))
        // Bez známého viewera se vypsaný login poznat nedá — je to jen slovo v dotazu.
        #expect(!Policy.tracksOwnPullRequests(in: explicit, mine: []))
        // A cizí autor se za vlastní zdroj nepočítá, ať je viewer znám, nebo ne.
        #expect(!Policy.tracksOwnPullRequests(
            in: [Source(name: "Kolegovy", query: "author:kolega is:open")],
            mine: Policy.ownLogins(viewer: "ondrajodas")
        ))
    }

    /// Rozepsaný řádek v nastavení (`activeSources` ho zahazuje) nesmí vypadat jako sledování
    /// vlastních PR — a taky nesmí rozpoznání pokazit, když je zdroj vedle něj v pořádku.
    @Test("Rozepsaný zdroj rozpoznání nezapíná ani nekazí")
    func blankSourceChangesNothing() {
        var configuration = Configuration.standard
        configuration.global.sources = [.reviewRequested, Source(name: "Rozepsaný", query: "  ")]
        #expect(!Policy.tracksOwnPullRequests(in: configuration.activeSources, mine: []))

        configuration.global.sources = [Source(name: "Rozepsaný", query: " "), .mine]
        #expect(Policy.tracksOwnPullRequests(in: configuration.activeSources, mine: []))
    }

    // MARK: - Přihlášený účet v nastavení (#389)

    /// Řádek nad seznamem vlastních loginů. Existuje proto, aby se **prázdný seznam** (běžný stav)
    /// nedal splést s **nenačteným viewerem** (stav, ve kterém je každý PR cizí) — je to tentýž
    /// rozdíl, na kterém stojí první test v téhle sadě.
    @Test("Nenačtený viewer se v nastavení pojmenuje, ne zamlčí")
    func anUnknownViewerIsNamedInSettings() {
        for login in [nil, "", "   ", "\n"] as [String?] {
            #expect(Policy.viewerAccount(login: login) == .unknown, "\(String(describing: login))")
        }
        // A **řekne se, co to znamená**: „nic tu není“ by u tohohle stavu bylo tvrzení, které
        // neunese, proč je fronta plná a vlastní PR nikde.
        let note = ViewerAccount.unknown.note
        #expect(note != nil)
        #expect(note?.contains("cizí") == true)
    }

    /// Login se ukazuje v tom tvaru, ve kterém se pak porovnává — jinak by okno tvrdilo něco
    /// jiného, než podle čeho se rozřazuje.
    @Test("Známý účet se ukáže v porovnatelném tvaru a bez poznámky")
    func aKnownAccountShowsItsLogin() {
        #expect(Policy.viewerAccount(login: "OndraJodas") == .known(login: "ondrajodas"))
        #expect(Policy.viewerAccount(login: " ondrajodas ") == .known(login: "ondrajodas"))
        #expect(ViewerAccount.known(login: "ondrajodas").label == "ondrajodas")
        #expect(ViewerAccount.known(login: "ondrajodas").note == nil)
        // Tvar je týž, jaký vydá množina, podle které se rozřazuje.
        #expect(Policy.ownLogins(viewer: "OndraJodas").contains("ondrajodas"))
    }

    /// Loginy z konfigurace jsou ty **navíc**, ne nahrazující — proto je řádek s účtem nad nimi
    /// a proto je prázdný seznam v pořádku.
    @Test("Prázdný seznam loginů rozřazení nemění")
    func anEmptyListChangesNothing() {
        let onlyViewer = Policy.ownLogins(viewer: "ondrajodas", configured: [])
        #expect(onlyViewer == ["ondrajodas"])
        #expect(Policy.ownership(ofAuthor: "ondrajodas", mine: onlyViewer) == .mine)
        // A přidaný login viewera nevytlačí.
        let both = Policy.ownLogins(viewer: "ondrajodas", configured: ["github-actions[bot]"])
        #expect(both == ["ondrajodas", "github-actions[bot]"])
    }
}
