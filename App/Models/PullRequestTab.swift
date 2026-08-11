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
    /// **Nekreslí se, když checky nejsou** — viz `Policy.tabs(hasChecks:)`. PR bez CI je běžná
    /// věc a prázdný tab s nadpisem by o něm tvrdil, že se něco nepovedlo.
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
    /// takže dělič spočítaný z indexu by se tím tiše posunul na špatné místo. A protože se
    /// `Kontroly` u PR bez CI vůbec nekreslí, index by se navíc měnil podle dat.
    var isReviewerOutput: Bool {
        switch self {
        case .overview, .filesChanged, .conversation, .checks: false
        case .findings, .progress: true
        }
    }
}
