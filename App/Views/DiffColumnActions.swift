import SwiftUI

/// Co smí automatika postranních kolon (#188, #503) přepnout u **levého** sloupce — a čím si
/// pamatuje, že to už udělala (#506, třetí a čtvrté kolo).
///
/// **`nil` znamená „vedle téhle plochy sloupec nestojí“**, takže se ho automatika nedotkne —
/// tatáž hranice jako u `DiffView.panelExpanded`. Diff commitu (#317) ani náhledy ho tedy
/// nedostanou a nemají čím přepsat stav, který kreslí někdo jiný.
///
/// **Proč dvě hodnoty a ne jedna.** Stav sloupce (`expanded`) drží od #506 detail PR, protože
/// sloupec stojí vedle všech osmi tabů. Stráž proti druhému uplatnění téhož rozhodnutí (`applied`)
/// musí žít **přesně tak dlouho jako ten stav** — a to je celý obsah opravy: do třetího kola #506
/// byla stráž v `@State` `DiffView`u, takže ji `switch tab` v detailu zahodil při každém odchodu
/// ze `Změněných souborů`. Návrat do diffu byl pak nový `DiffView` s prázdnou stráží, který
/// uloženou volbu člověka **přepsal** hodnotou z `Policy`.
///
/// Projevovalo se to „jen někdy“, protože se přepisuje jedině na hodnotu, která se od uložené
/// liší: ve `Vedle sebe` (`tree == false`) se ručně otevřený sloupec zavřel, v `Pod sebou`
/// (`tree == true`) se ručně složený otevřel, a ve stavu, jaký `Policy` chce, se nestalo nic.
///
/// **Čtvrté kolo, první polovina: `@State` detailu na to nestačil.** `PullRequestDetailView`
/// přežije přepnutí tabu uvnitř PR, ale **ne kliknutí na `Přehled`** — `switch store.activeTab`
/// v `ContentView` vybere jinou větev, takže se celý detail i s `@State` zahodí a návrat na
/// záložku PR je nová instance s prázdnou stráží. Stráž proto od #506/4 bydlí ve store
/// (`AppStore.appliedSideColumns`), tedy tam, kde přežije celé okno — jako `isReviewPanelExpanded`
/// (#242). Naměřeno v okně 1 512 × 882: `⌘1`, klik na `Přehled`, klik zpátky na záložku PR
/// → ve `Vedle sebe` sloupec zavřený, v `Pod sebou` otevřený.
///
/// **Čtvrté kolo, druhá polovina: ani stráž na správném místě nestačí, když se uplatní celé
/// rozhodnutí.** `DiffSideColumns` má tři pole a automatika sahá na dvě z nich, ale zapisovala
/// **obě**, jakmile se rozhodnutí změnilo v čemkoli — tedy i tehdy, když se změnil jen `margin`.
/// A `margin` se mění při kliknutí na `Nálezy pod řádky` v liště, při sbalení souboru i při odkrytí
/// kontextu, tedy při věcech, které se překlikávají běžně a se šířkou okna nemají nic společného.
/// Od #506/4 proto rozhoduje `Policy.sideColumnsToApply`: uplatní se **jen to pole, o kterém se
/// rozhodlo jinak než minule**. `applied` tím pádem přestal být „co jsem naposledy zapsal“ a je
/// „jak `Policy` naposledy rozhodla“ — posouvá se i tehdy, když se nezapíše nic.
struct DiffColumnActions {
    /// Rozložený levý sloupec s itinerářem (#506). Kreslí ho detail PR, ukládá se do
    /// `UserDefaults` pod klíčem z #197.
    var expanded: Binding<Bool>
    /// Jak `Policy.diffSideColumns` naposledy rozhodla. `nil` = ještě nijak, tedy „uplatni obojí“
    /// — přesně tak se pozná první průchod diffem po startu aplikace.
    ///
    /// **Není to „co se naposledy zapsalo“** (#506/4): posouvá se i u rozhodnutí, ze kterého nic
    /// nevyplynulo, protože `Policy.sideColumnsToApply` se ptá **na rozdíl proti minulému
    /// rozhodnutí**, ne proti nakreslenému stavu.
    var applied: Binding<DiffSideColumns?>
}
