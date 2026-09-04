import SwiftUI

/// Co smí automatika postranních kolon (#188, #503) přepnout u **levého** sloupce — a čím si
/// pamatuje, že to už udělala (#506, třetí kolo).
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
struct DiffColumnActions {
    /// Rozložený levý sloupec s itinerářem (#506). Kreslí ho detail PR, ukládá se do
    /// `UserDefaults` pod klíčem z #197.
    var expanded: Binding<Bool>
    /// Které rozhodnutí `Policy.diffSideColumns` už automatika uplatnila. `nil` = ještě žádné,
    /// tedy „uplatni ho“ — přesně tak se pozná první průchod od změny pohledu nebo šířky.
    var applied: Binding<DiffSideColumns?>
}
