import Foundation
import Testing

@testable import PRism

/// Kdy se **nabídne** založení nového labelu a kdy ne (#413).
///
/// Nejcennější tvrzení tady jsou ta, ve kterých akce **není**: nabídka byla do #413 uzavřená proto,
/// že z volného textu se dá omylem vyrobit label, a ten už z repozitáře sám nezmizí. Zakládání to
/// nahrazuje krokem, ne odemčeným polem — takže výčet důvodů, proč se akce nekreslí, je to jediné,
/// co z původní ochrany zbylo, a musí být vyčerpaný.
@Suite("Policy — založení nového labelu")
struct NewLabelOfferTests {
    private let known = [
        PullRequestLabel(name: "bug", color: "d73a4a"),
        PullRequestLabel(name: "bug-ui-legacy", color: "d73a4a"),
        PullRequestLabel(name: "nález", color: "0366d6"),
    ]

    private func offer(
        _ query: String,
        known: [PullRequestLabel]? = nil,
        isLoaded: Bool = true,
        editing: Policy.MetadataEditing = .allowed
    ) -> PullRequestLabel? {
        Policy.newLabelOffer(
            query: query,
            known: known ?? self.known,
            isLoaded: isLoaded,
            editing: editing
        )
    }

    // MARK: - Kdy se nenabízí

    /// **Prázdné jméno.** Jméno se bere z dotazu, takže bez napsaného textu není co zakládat —
    /// a bílé znaky se za text nepočítají.
    @Test("Prázdný dotaz nenabízí nic", arguments: ["", " ", "\t", "\n", "   \n "])
    func refusesBlankNames(query: String) {
        #expect(offer(query) == nil)
    }

    /// **Label toho jména už v repozitáři je.** Shoda se posuzuje **týmž pravidlem jako hledání**,
    /// takže `Bug` se nezaloží vedle `bug` — skoroduplikát je ten odpad, který by z tohohle
    /// v repozitáři zbyl nejčastěji.
    @Test(
        "Existující jméno nabídku nedostane",
        arguments: ["bug", "Bug", "BUG", "bUg", " bug ", "nález", "nalez", "NALEZ"]
    )
    func refusesExistingNames(query: String) {
        #expect(offer(query) == nil, "\(query) je tentýž label jako něco v repozitáři")
    }

    /// **Cizí PR.** Přeštítkovat frontu někoho jiného se odsud nedělá nikdy, takže tam není odkud
    /// zakládat — a `.absent` je ten stav, ve kterém se akce nekreslí **vůbec**, ne zašedle.
    @Test("Na cizím PR se nezakládá")
    func refusesOnForeignPullRequests() {
        #expect(offer("design-debt", editing: .absent) == nil)
    }

    /// **Vypnutá brána.** `+ label` je v tu chvíli zašedlé a důvod stojí v panelu (#392), takže se
    /// do nabídky nedá ani dostat — a kdyby se to změnilo, nemá se odsud dát založit nic.
    @Test("S vypnutou bránou se nezakládá")
    func refusesWithoutThePublishingGate() {
        let reason = PublishError.publishingNotAllowed(RepoID(owner: "keboola", name: "vault"))
        #expect(offer("design-debt", editing: .blocked(reason.userDescription)) == nil)
    }

    /// **Nenačtená nabídka.** Bez seznamu z repozitáře se nedá poznat, jestli label toho jména už
    /// existuje — takže by se `Bug` dal založit vedle `bug` jen proto, že se nabídka nestihla
    /// dotáhnout. To je zrovna ten odpad, kvůli kterému byla nabídka uzavřená.
    @Test("Dokud nabídka nedorazila, nezakládá se")
    func refusesBeforeTheListArrives() {
        #expect(offer("design-debt", known: [], isLoaded: false) == nil)
    }

    // MARK: - Kdy se nabízí

    /// **Prázdný načtený seznam je odpověď, ne nedostatek.** Repo, které labely nezná, je zrovna to,
    /// kde se první štítek musí dát založit.
    @Test("Repo bez labelů se dá založit cokoli")
    func offersInAnEmptyRepository() {
        #expect(offer("design-debt", known: [], isLoaded: true)?.name == "design-debt")
    }

    /// **Nabídne se i tehdy, když seznam něco našel.** `bug-ui` v repu, který zná `bug-ui-legacy`,
    /// se založit musí — jinak by taková jména nešla zakládat vůbec. Rozdíl proti `Bug`: podřetězec
    /// není tentýž label.
    @Test("Podřetězec existujícího jména zakládání nebrání")
    func offersNextToASubstringMatch() {
        #expect(offer("bug-ui")?.name == "bug-ui")
        #expect(offer("bug-ui-legacy") == nil, "tady už je to tentýž label")
    }

    /// Jméno se **ořeže o bílé znaky**: v poli zůstane po psaní mezera častěji než ne, a label
    /// s koncovou mezerou by v repozitáři vypadal jako druhý stejný.
    @Test("Jméno se ořeže o bílé znaky")
    func trimsTheName() {
        #expect(offer("  design-debt \n")?.name == "design-debt")
    }

    // MARK: - Barva

    /// **Stejné jméno dá vždycky stejnou barvu**, a to i mezi dvěma spuštěními procesu — proto to
    /// není `hashValue`, který je zasetý náhodně při každém startu. Hodnoty jsou zapsané
    /// **literálem**: kdyby se počítaly v testu tou samou funkcí, tvrdilo by to jen „funkce se rovná
    /// sama sobě“, a přesazení hashe by test nechytil.
    @Test("Barva je z jména, a je pořád stejná")
    func picksAStableColor() {
        #expect(Policy.labelColor(for: "design-debt") == "d4c5f9")
        #expect(Policy.labelColor(for: "bug-ui") == "fef2c0")
        #expect(Policy.labelColor(for: "tech-debt") == "f9d0c4")
        #expect(Policy.labelColor(for: "") == "1d76db")
    }

    /// Barva v nabídce je **ta samá**, jakou dá `labelColor` — jinak by náhled v potvrzení ukazoval
    /// jinou barvu, než jaká odejde.
    @Test("Nabídka nese barvu z palety")
    func theOfferCarriesTheColor() {
        let label = offer("design-debt")
        #expect(label?.color == Policy.labelColor(for: "design-debt"))
        #expect(Policy.labelColors.contains(label?.color ?? ""))
    }

    /// Paleta je **šestnáct šestimístných hexů bez `#`** — tak, jak je chce API a jak je drží
    /// `PullRequestLabel`. Bílá v ní schválně není: puntík by na světlém podkladu splynul.
    @Test("Paleta je šestnáct hexů bez mřížky")
    func thePaletteIsWellFormed() {
        #expect(Policy.labelColors.count == 16)
        for color in Policy.labelColors {
            #expect(color.count == 6, "\(color) není šestimístný")
            #expect(UInt32(color, radix: 16) != nil, "\(color) není hex")
            #expect(color == color.lowercased(), "\(color) není malými písmeny")
            #expect(color != "ffffff", "bílá v paletě být nemá")
        }
    }

    /// Každé jméno padne **do palety**, ne mimo — modulo nesmí přetéct ani u dlouhých jmen.
    @Test("Každé jméno dostane barvu z palety")
    func everyNameLandsInThePalette() {
        for name in ["a", "bug", String(repeating: "x", count: 500), "výkon", "🐛", "0"] {
            #expect(Policy.labelColors.contains(Policy.labelColor(for: name)), "\(name)")
        }
    }

    // MARK: - Hledací pole

    /// **U labelů je pole vždycky** (#413): jméno se bere z dotazu, takže bez pole není kam ho
    /// napsat — v repu se třemi labely by se nedalo založit nic. U reviewerů se práh nemění, protože
    /// tam se nic nezakládá.
    @Test("Nabídka, ve které se zakládá, má pole vždycky", arguments: [0, 1, 3, 6, 7, 40])
    func alwaysShowsSearchWhereSomethingIsCreated(count: Int) {
        #expect(Policy.pickerShowsSearch(count: count, canCreate: true))
        #expect(Policy.pickerShowsSearch(count: count) == (count > Policy.searchFrom))
    }

    /// Pravidlo shody je **jedno** a používá ho hledání i kontrola duplikátu.
    @Test("Shoda jména je bez ohledu na velikost písmen a diakritiku")
    func nameMatchingSharesTheSearchRule() {
        #expect(Policy.pickerSameName("bug", "BUG"))
        #expect(Policy.pickerSameName("nález", "nalez"))
        #expect(!Policy.pickerSameName("bug", "bug-ui"))
        #expect(!Policy.pickerSameName("bug", " bug"))
    }
}
