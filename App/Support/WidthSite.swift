import Foundation

/// Šířky, na kterých se v diffu rozhoduje o sazbě (#546).
///
/// ## Proč to je v diagnostice a ne v testu
///
/// #546 je vada, kterou **hostované okno nereprodukuje**: v testu se scéna staví najednou, kdežto
/// v okně se boční kolony rozvrhnou až po prvním měření. Jediné místo, kde se dá zjistit, na jakou
/// šířku se diff doopravdy sází, je tedy **běžící aplikace** — a `print` do konzole se z GUI
/// aplikace spuštěné z Finderu nikam nedostane.
///
/// Diagnostika kreslení (`PRISM_DIAGNOSE=1`, `./bin/run.sh --diagnose`) je na to už postavená:
/// vypnutá stojí jeden load `Optional`u, vypíná se sama dalším spuštěním bez přepínače a zapisuje
/// mimo hlavní vlákno. Viz `RenderDiagnostics`.
///
/// ## Čím to nesmí být
///
/// - **Není to vstup do rozvržení.** Hodnota se jen zapíše do slovníku pod zámkem; nic se z ní
///   nepočítá a nic se jí nepřekresluje (#252 — zápis do observable stavu při každém průchodu je
///   zrovna ta chyba, kterou tohle hledá).
/// - **Drží se poslední hodnota, ne řada.** Hledá se, na čem scéna **stojí**, ne kudy se tam
///   dostala; řada hodnot by za sekundu hoření zaplnila soubor.
enum WidthSite: String, Sendable, CaseIterable {
    /// Šířka, kterou dostal `DiffView` — okno bez railu a bez panelu vpravo (`\.availableWidth`).
    case diffSlot = "DiffView.slot"
    /// Šířka kolony kódu, jak ji spočítal `Policy.diffCodeColumnWidth` — tedy plocha, na kterou se
    /// **má** sázet.
    case diffCodeColumn = "DiffView.code"
    /// Šířka, kterou `DiffView` doopravdy **naměřil** na ploše se sazbou. Rozdíl proti
    /// `diffCodeColumn` je celá #546.
    case diffMeasuredContent = "DiffView.measured"
}
