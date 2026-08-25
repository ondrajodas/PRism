import Foundation
import Testing

@testable import PRism

/// Hledání v nabídkách panelu (#392) — čisté funkce, takže vyčerpávající výčet bez kreslení.
///
/// **Pravidlo se dělí s paletou ⌘K** (#184) a je na to vlastní tvrzení: dvě jinak se chovající
/// hledání v jednom okně by byla horší volba než sdílení, a rozejít se můžou potichu.
@Suite("Hledání v nabídkách panelu")
struct PickerSearchTests {
    private let people = ["adam", "BagToad", "dasa-novakova", "halina", "odinuv", "sergiou87"]

    // MARK: - Váha shody

    @Test("Prázdný dotaz sedne na všechno a nemíchá pořadí")
    func anEmptyQueryKeepsEverything() {
        #expect(Policy.filteredPicker(people, query: "", text: { $0 }) == people)
        #expect(Policy.filteredPicker(people, query: "   ", text: { $0 }) == people)
    }

    /// Tři stupně váhy: začátek, hranice slova, vnitřek — jako u titulku v paletě.
    @Test(
        "Váha rozlišuje začátek, hranici slova a vnitřek",
        arguments: [
            ("ajda", "ajda-swimlane", 0),
            ("swimlane", "ajda-swimlane", 1),
            ("wimlane", "ajda-swimlane", 2),
        ]
    )
    func rankOrdersByHowCertainTheMatchIs(query: String, text: String, rank: Int) {
        #expect(Policy.pickerRank(of: text, query: query) == rank)
    }

    @Test("Co nesedí, dostane nil")
    func noMatchIsNil() {
        #expect(Policy.pickerRank(of: "ajda-swimlane", query: "platform") == nil)
    }

    /// **Bez ohledu na velikost písmen a na diakritiku** — aplikace je česká, takže `dasa` musí
    /// najít `Dáša`. Kdyby ne, dalo by se hledat jen s přepnutou klávesnicí.
    @Test(
        "Hledá se bez diakritiky a bez ohledu na velikost písmen",
        arguments: ["dasa", "DÁŠA", "Dasa"]
    )
    func ignoresCaseAndDiacritics(query: String) {
        #expect(Policy.pickerRank(of: "Dáša Nováková", query: query) == 0)
    }

    /// Víc slov je **a zároveň**, váha je z nich **nejlepší** — tatáž úvaha jako v paletě.
    @Test("Víc slov musí sednout všechno, váha je nejlepší z nich")
    func everyTokenMustMatch() {
        #expect(Policy.pickerRank(of: "ajda-swimlane-platform", query: "ajda platform") == 0)
        #expect(Policy.pickerRank(of: "ajda-swimlane", query: "ajda platform") == nil)
    }

    /// **Sdílí se pravidlo s paletou, ne kopie.** Kdyby se rozešlo, chová se jedno okno na dvě
    /// strany — a pozná se to jedině tímhle tvrzením.
    @Test("Pravidlo je totéž jako v paletě")
    func sharesTheRuleWithTheCommandPalette() {
        // Tytéž primitivy, tedy tatáž odpověď na „sedne to?“ a „je to hranice slova?“.
        let text = "ajda-swimlane"
        let range = try? #require(Policy.searchRange(of: "swimlane", in: text))
        #expect(range != nil)
        if let range { #expect(Policy.searchStartsWord(at: range, in: text)) }
        // A totéž dělení dotazu na slova.
        #expect(Policy.paletteTokens(in: "ajda  platform") == ["ajda", "platform"])
    }

    /// **Shoda na začátku textu je hranice slova, ne pád** (nález Copilota). Do #392 to byla
    /// `private` funkce palety s jediným volajícím, který se na `startIndex` ptal dřív; jako sdílená
    /// by na něm padala na `index(before:)`. Test je proto na tu funkci **přímo** — přes `pickerRank`
    /// se k té větvi nedostane, protože ten si `startIndex` ošetřuje sám.
    @Test("Hranice slova na začátku textu nepadá")
    func startsWordIsTotal() throws {
        let text = "ajda-swimlane"
        let range = try #require(Policy.searchRange(of: "ajda", in: text))

        #expect(range.lowerBound == text.startIndex)
        #expect(Policy.searchStartsWord(at: range, in: text))
    }

    /// A totéž nad **prázdným textem**: `startIndex` je v něm zároveň `endIndex`, takže by
    /// `index(before:)` padl i na tom. Prázdný rozsah `range(of: "")` cesta není — Swift na prázdný
    /// dotaz vrací `nil` (změřeno), takže se ta větev musí vyrobit takhle.
    @Test("Hranice slova v prázdném textu nepadá")
    func startsWordIsTotalOnEmptyText() {
        let text = ""

        #expect(Policy.searchStartsWord(at: text.startIndex..<text.endIndex, in: text))
    }

    // MARK: - Pořadí

    /// Řadí se podle váhy; **při shodě podle původního pořadí**, protože Swiftové `sorted` není
    /// stabilní — bez toho by položky přeskakovaly mezi stisky klávesy.
    @Test("Silnější shoda jde nahoru, při shodě rozhoduje původní pořadí")
    func sortsByRankThenOriginalOrder() {
        let items = ["prism-server", "server", "web-server", "serverless"]

        // `server` a `serverless` mají shodu na začátku (váha 0), `prism-server` a `web-server`
        // na hranici slova za pomlčkou (váha 1) — a mezi těmi dvěma rozhoduje **pořadí, ve kterém
        // přišly**, ne abeceda.
        #expect(Policy.filteredPicker(items, query: "server", text: { $0 })
            == ["server", "serverless", "prism-server", "web-server"])
    }

    /// **Tvrdí, že se něco NEstalo**: dvě položky se stejnou váhou se mezi dvěma průchody
    /// nepřehodí. Bez `order` v kritériu to je závislé na implementaci `sorted`.
    @Test("Dvě stejné váhy nepřeskakují mezi průchody")
    func isStableAcrossRuns() {
        let items = ["ada", "adam", "adamec"]
        let first = Policy.filteredPicker(items, query: "ad", text: { $0 })

        for _ in 0..<20 {
            #expect(Policy.filteredPicker(items, query: "ad", text: { $0 }) == first)
        }
    }

    // MARK: - Kurzor

    @Test("Šipka posune kurzor")
    func arrowsMoveTheCursor() {
        #expect(Policy.pickerSelection(from: 0, step: 1, count: 3) == 1)
        #expect(Policy.pickerSelection(from: 2, step: -1, count: 3) == 1)
    }

    /// **Ořezává, necyklí.** V nabídce, která se pod rukama filtruje, je přeskok z konce na začátek
    /// k nerozeznání od „šipka nic neudělala“.
    @Test("Na krajích se kurzor zastaví, neproskočí na druhý konec")
    func clampsAtTheEdges() {
        #expect(Policy.pickerSelection(from: 0, step: -1, count: 3) == 0)
        #expect(Policy.pickerSelection(from: 2, step: 1, count: 3) == 2)
    }

    /// Kurzor z předchozího dotazu smí být **za koncem** — filtr se mění pod rukama, takže se
    /// ořezává i bez pohybu (`step: 0`).
    @Test("Kurzor za koncem se srazí na poslední řádek")
    func clampsAStaleCursor() {
        #expect(Policy.pickerSelection(from: 12, step: 0, count: 3) == 2)
    }

    /// Prázdná nabídka nemá co vybírat — a `nil` je jediná odpověď, která nesvádí ke čtení
    /// z prázdného pole.
    @Test("Nad prázdnou nabídkou není co vybrat")
    func noSelectionWithoutRows() {
        #expect(Policy.pickerSelection(from: 0, step: 1, count: 0) == nil)
    }

    // MARK: - Kdy se pole vůbec kreslí

    /// **Vyčerpávající výčet kolem hranice.** Práh je jediné, co se o hledacím poli dá tvrdit
    /// číslem — jestli v něm **je fokus**, je stav skutečného okna a v harnessu se změřit nedá
    /// (testovací host nedostane aktivaci, takže nemá key okno; postup a naměřené varianty jsou
    /// v `docs/testovani.md`). Tím spíš se má hlídat to, co číslo je.
    @Test(
        "Pole se kreslí nad šesti položkami, ne dřív",
        arguments: [
            (0, false), (1, false), (2, false), (3, false), (4, false), (5, false), (6, false),
            (7, true), (8, true), (34, true),
        ]
    )
    func drawsTheSearchFieldOnlyAboveSix(count: Int, shows: Bool) {
        #expect(Policy.pickerShowsSearch(count: count) == shows)
    }

    /// **Jeden práh pro obě nabídky** (#392): do téhle změny měl `LabelPickerView`
    /// i `ReviewerPickerView` vlastní `searchFrom = 6`, takže se mohly rozejít potichu — a bylo by
    /// z toho vidět jen to, že jedna nabídka pole má a druhá ne. Tvrzení je na tu jednu hodnotu,
    /// protože víc než jedno místo se z testu ověřit nedá.
    @Test("Práh je jedna hodnota, ne konstanta v každé nabídce")
    func theThresholdIsOneValue() {
        #expect(Policy.searchFrom == 6)
        #expect(!Policy.pickerShowsSearch(count: Policy.searchFrom))
        #expect(Policy.pickerShowsSearch(count: Policy.searchFrom + 1))
    }

    /// Záporný počet nemá odkud přijít, ale funkce je totální a **nemá mít skrytou precondition** —
    /// tatáž úvaha, kvůli které se u `searchStartsWord` opravoval `index(before:)`.
    @Test("Nesmyslný počet nepadá")
    func doesNotTrapOnNonsense() {
        #expect(!Policy.pickerShowsSearch(count: -1))
        #expect(Policy.pickerShowsSearch(count: .max))
    }

    // MARK: - Kdy se kreslí patka s nápovědou kláves (#434)

    /// **Nad prázdným výsledkem patka není** — návrh ji tak kreslí (sekce 24) a je to i jediné
    /// možné chování: ze tří jejích položek by nad prázdnem dvě lhaly.
    @Test(
        "Patka se kreslí jedině nad neprázdným seznamem",
        arguments: [(0, false), (1, true), (2, true), (34, true)]
    )
    func drawsTheKeyHintsOnlyOverRows(count: Int, shows: Bool) {
        #expect(Policy.pickerShowsKeyHints(rowCount: count) == shows)
    }

    /// **Tvrzení o tom, že se něco NEstane**: právě v tom stavu, ve kterém patka není, taky není
    /// co vybrat — `↑↓ vybírá` a `↵ …` by tedy byly dvě věty o klávesách, po kterých se nic
    /// nestane. Ty dvě funkce se **musí shodnout** a rozejít se můžou potichu: patka je stav okna,
    /// kdežto tohle je číslo.
    @Test("Kde není co vybrat, tam se nápověda nekreslí")
    func neverPromisesKeysThatDoNothing() {
        for count in [-1, 0, 1, 7] {
            let selectable = Policy.pickerSelection(from: 0, step: 0, count: count) != nil
            #expect(Policy.pickerShowsKeyHints(rowCount: count) == selectable, "počet \(count)")
        }
    }

    // MARK: - Nabídka reviewerů a labelů

    /// **Filtruje se podle toho, co je v řádku vidět** — u člověka login, u týmu slug. Kdyby filtr
    /// sedl na něco, co v řádku není, vypadal by výsledek jako chyba.
    @Test("Nabídka reviewerů se filtruje podle jména i slugu")
    func filtersReviewersByWhatIsVisible() {
        let candidates: [ReviewerCandidate] = [
            .person("odinuv"), .person("sergiou87"), .team("ajda-swimlane"), .team("platform"),
        ]

        #expect(Policy.filteredPicker(candidates, query: "swim") { $0.name } == [.team("ajda-swimlane")])
        #expect(Policy.filteredPicker(candidates, query: "odin") { $0.name } == [.person("odinuv")])
        #expect(Policy.filteredPicker(candidates, query: "xyz") { $0.name }.isEmpty)
    }

    @Test("Nabídka labelů se filtruje podle jména")
    func filtersLabelsByName() {
        let labels = [
            PullRequestLabel(name: "bug", color: "d73a4a"),
            PullRequestLabel(name: "needs-design-review", color: "d4c5f9"),
            PullRequestLabel(name: "dependencies", color: "0366d6"),
        ]

        #expect(Policy.filteredPicker(labels, query: "design", text: \.name).map(\.name)
            == ["needs-design-review"])
    }

    /// **Z hledání se nedá vyrobit label**, který repo nezná: filtr je podmnožina nabídky, nikdy
    /// ne dotaz sám. Je to tatáž uzavřenost, na které stojí `Policy.toggledLabels`.
    @Test("Filtr nikdy nevrátí něco, co v nabídce nebylo")
    func neverInventsAnItem() {
        let labels = [PullRequestLabel(name: "bug", color: "d73a4a")]
        let names = Set(labels.map(\.name))

        for query in ["vymyšlený", "bu", "", "bug"] {
            let filtered = Policy.filteredPicker(labels, query: query, text: \.name)
            #expect(filtered.allSatisfy { names.contains($0.name) })
        }
    }
}
