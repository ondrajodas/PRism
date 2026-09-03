import Foundation

/// Šířky, na kterých se v diffu rozhoduje o sazbě (#546).
///
/// ## Proč to je v diagnostice, když na to je i test
///
/// **Hostované okno tu vadu vyrobit umí** — `DiffCodeColumnWidthTests` ji hlídá —, ale zjistilo se
/// to **až tímhle měřidlem**. Do #546 sonda z #503 stavěla scénu, ve které ta vada nastat nemůže
/// (chybělo v ní vlákno s kotvou v diffu), takže z hostovaného okna vycházela pořád tatáž hodnota
/// pro „funguje“ i „nefunguje“ (#478); rozdíl proti živému oknu neměl kdo změřit.
///
/// Zůstává to tady ze dvou důvodů, a ani jeden test nenahradí: **bisekce** (na kterou úroveň se
/// šířka propsala) a **živé okno** — `print` do konzole se z GUI aplikace spuštěné z Finderu nikam
/// nedostane a scéna, kterou má člověk zrovna na obrazovce, v testu není.
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
