import Foundation

/// Který tab pull requestu je vidět — jako na GitHubu.
///
/// Je to **volba pohledu**, ne údaj o PR, a přesto nežije ve view: `PullRequestDetailView` si
/// SwiftUI mezi pull requesty ponechá (stejná pozice ve stromu), takže `@State` by přetekl
/// z jednoho PR na druhý. Drží se proto per PR ve `AppStore`, stejně jako výběr řádku.
///
/// Jako `ReviewVerdict` **není `Codable`** — neukládá se. Kdyby se ukládal, znamenalo by to
/// pamatovat si napříč restarty, na co se člověk koukal minulý týden.
enum PullRequestTab: Hashable, Sendable, CaseIterable {
    /// Popis PR a konverzace, která se neváže k žádnému řádku. **Výchozí** — viz `standard`.
    case overview
    /// Diff s bublinami.
    case filesChanged
    /// Commity pull requestu — co se stalo v kterém kroku (#316).
    ///
    /// **Vedle `Změněných souborů` schválně.** Obojí odpovídá na „co se v kódu změnilo“, jen
    /// jednou naráz a jednou po krocích, takže se ta dvojice čte jako pár a přepíná se jedním
    /// skokem. Slitý diff ukazuje výsledek, ne cestu; otázka „proč tenhle řádek zmizel“ nebo „kdy
    /// se sem dostala ta migrace“ má odpověď v jednotlivých commitech a dneska se hledá
    /// v prohlížeči — tentýž pohyb jako u `Konverzace` (#183) a `Kontrol` (#215).
    ///
    /// **Vložení doprostřed dělič neposune** — kreslí se z `isReviewerOutput`, ne z indexu (#215,
    /// #242). Přesně tuhle situaci ta vlastnost předvídala doslova.
    ///
    /// Stojí to **šířku pruhu záložek**, a je to jediné, co to stojí: sedm záložek se všemi odznaky
    /// by potřebovalo okno ~1049 bodů proti tehdejším 937. Zaplatila to pilulka `+X −Y`, která se
    /// v úzkém pruhu nekreslí, takže hranice zůstala na 939. Od #318 se pod ní pruh přepíná na
    /// **ikony s popiskem jen u aktivní záložky** a nezalomí se ani v nejužším okně —
    /// viz `PullRequestTabBar`.
    case commits
    /// Časová osa toho, co se na PR dělo (#183).
    ///
    /// **Vlastní tab, ne sekce v `Přehledu`.** Jsou to dvě různé otázky: `Přehled` odpovídá na
    /// „jak to teď stojí“ (popis, fakta, co se změnilo od minule), konverzace na „co se dělo“.
    /// V jednom scrollu se přitom to druhé čte tak, že se přes první přeroluje.
    case conversation
    /// Kontroly z GitHub Actions — seznam checků a detail toho, který spadl (#215).
    ///
    /// **Vlastní tab, ne blok v `Přehledu`.** Se souhrnem to v `Přehledu` sedělo, ale detail
    /// spadlého checku (#214) přidává anotace a konec logu, a tím ten blok vyroste natolik, že
    /// vytlačí popis PR mimo obrazovku. `Přehled` má odpovídat na „jak to teď stojí“, ne být
    /// místem, kde se scrolluje log — je to tentýž pohyb jako u `Konverzace` (#183): co začne
    /// růst, přestane být kontextem a stane se obsahem.
    ///
    /// **Kreslí se vždycky, i u PR bez CI** (#306) — a u něj v tabu zůstane hláška, že kontroly
    /// nejsou. Do #306 se u PR bez CI nekreslil (`Policy.tabs(hasChecks:)`), protože prázdný tab
    /// s nadpisem `Kontroly` by o něm tvrdil, že se něco nepovedlo. Otočilo to problikávání pruhu
    /// při **každém** otevření PR (nejdřív pět záložek, pak šest) a hláška, která ten prázdný stav
    /// vysvětlí. Co v tabu je, rozhoduje `Policy.checksTab(checks:failure:)` — čtyři stavy, ze
    /// kterých „ještě nedorazily“ o CI netvrdí nic.
    case checks
    /// Všechno, co reviewery nahlásily — tabulka přes celou šířku (#242).
    ///
    /// **Vlastní tab, i když nálezy zůstávají i v panelu vpravo.** Ve 300 bodech se nález nedá
    /// nasázet jako tabulka, takže z něj #175 udělal karty a řazení podle sloupců zahodil; přes
    /// celou šířku se na jeden řádek vejde závažnost, shrnutí, místo, reviewer i akce. Tab
    /// odpovídá na jinou otázku než panel — *co všechno se na tomhle PR našlo* — a ta je na celou
    /// obrazovku.
    case findings
    /// Co reviewery dělaly — dráha na revieweera s fázemi (#242).
    ///
    /// **Záznam běhu, ne něco, co se čte vedle kódu.** V panelu to byly karty pod sebou, ze
    /// kterých se nedalo porovnat, kdo kde je — a u spadlé session se důvod ani konec logu
    /// neměly kam vejít.
    case progress

    /// Se kterým tabem se PR otevírá.
    ///
    /// **Změna proti zadání #72**, které předepisovalo `filesChanged` s tím, že kvůli diffu je
    /// aplikace otevřená. Vyžádané při zkoušení a je to správně: popis PR a diskuze je to, co
    /// se čte **než** se člověk podívá na kód — a stejně to má GitHub, kde je `Overview`
    /// vstupní tab. Diff je jedno kliknutí daleko a volba se pamatuje per PR.
    static let standard = PullRequestTab.overview

    /// Jak se tab jmenuje v okně.
    ///
    /// Česky, jako zbytek UI — anglické `Files changed` by bylo jediné anglické místo v okně.
    /// „Soubory“ samo by se přitom pletlo se stromem souborů v liště diffu, takže je z názvu
    /// vidět, že jde o **změny**.
    var czechLabel: String {
        switch self {
        case .overview: "Přehled"
        case .filesChanged: "Změněné soubory"
        case .commits: "Commity"
        case .conversation: "Konverzace"
        case .checks: "Kontroly"
        case .findings: "Nálezy"
        case .progress: "Průběh"
        }
    }

    /// Je to výstup **našich** reviewerů, ne něco, co je na PR?
    ///
    /// Podle toho se v pruhu záložek kreslí dělič (#242): nalevo je to, co má i GitHub, napravo
    /// to, co s PR udělaly reviewery. Bez něj by pět záložek vypadalo jako jeden dlouhý seznam.
    ///
    /// Je to vlastnost tabu, ne pozice v poli: `Kontroly` (#215) sedí **nalevo** doprostřed,
    /// takže dělič spočítaný z indexu by se tím tiše posunul na špatné místo. Do #306 se navíc
    /// index měnil podle dat, protože se `Kontroly` u PR bez CI nekreslily — to už neplatí, ale
    /// první důvod stačí: vlastnost přežije i sedmou záložku vloženou doprostřed, zadrátovaná
    /// pozice ne.
    var isReviewerOutput: Bool {
        switch self {
        case .overview, .filesChanged, .commits, .conversation, .checks: false
        case .findings, .progress: true
        }
    }

    /// Je v tomhle tabu vidět panel s nálezy a mým review (#294)?
    ///
    /// Panel odpovídá na otázku „co k tomu, co právě čtu, nahlásily reviewery“, a ta má smysl jen
    /// tam, kde se vedle něj čte **něco jiného**: popis PR, diff, diskuze. Ve zbylých čtyřech tabech
    /// je buď **duplikát** (`Nálezy` jsou tytéž nálezy přes celou šířku, `Průběh` je záznam týchž
    /// běhů), nebo **ukrajuje šířku obsahu, který ji potřebuje** — detail spadlého checku
    /// v `Kontrolách` nese konec logu (#214). Složený proužek je úzký, ale ne zdarma: bere šířku,
    /// a v úzkém okně je to zrovna to místo, kde se obsah láme.
    ///
    /// **`Commity` mají důvod navíc** (#316), a je silnější než šířka: nálezy jsou klíčované
    /// `headSha` (tvrdá podmínka č. 5), takže by panel vedle staršího commitu ukazoval nálezy
    /// k **jinému kódu**. Není to duplikát, je to tvrzení, které by neplatilo.
    ///
    /// **Změna proti #242**, kde stálo, že panel je vidět ve všech tabech včetně `Nálezů` — s
    /// odůvodněním, že smyčka nález → `Převzít` → text v mém review je ta hlavní práce a musí se
    /// stát naráz. Ta smyčka se nezahazuje, jen se přestěhovala: `AppStore.revealDraft(in:)` si
    /// z tabu, ve kterém panel není, **přepne do tabu, ve kterém je** — jinak by rozepsaná věta
    /// spadla někam, kde ji nikdo nehledá, což je přesně to, co #242 řešil.
    ///
    /// **Není to `isReviewerOutput`** a nesmí se na něj ohnout: `Kontroly` jsou fakt o PR
    /// (`isReviewerOutput == false`), a panel tam přesto být nemá. Jedna vlastnost pro dvě otázky
    /// by posunula dělič v pruhu záložek — kreslí se z týchž příznaků, takže by `Kontroly` skočily
    /// do pravé skupiny a chyba by byla vidět jinde, než by vznikla.
    ///
    /// Vlastnost tabu, ne funkce v `Policy`: není co vážit ani z čeho počítat — je to konstantní
    /// fakt o každém ze sedmi případů, tedy tentýž druh věci jako `czechLabel`
    /// a `isReviewerOutput`. `Policy` by na totéž potřebovala týž `switch` a druhé místo, kam se
    /// chodit podívat.
    var showsReviewPanel: Bool {
        switch self {
        case .overview, .filesChanged, .conversation: true
        case .commits, .checks, .findings, .progress: false
        }
    }
}
