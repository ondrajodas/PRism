import CoreGraphics
import Observation

/// Kde je výřez v obsahu diffu (#469).
///
/// **Jediné místo, kam se scrollování zapisuje** — a to je celá pointa. Do #469 kreslil diff
/// `LazyVStack` a laznost obstarávalo rozvržení; od #469 je stack pevný, takže si o nasazení bloku
/// rozhoduje aplikace sama a potřebuje k tomu vědět, kde výřez je.
///
/// **Dvě hodnoty, ne jedna, a je to výkonové rozhodnutí.** `@Observable` sleduje **po
/// vlastnostech**, takže:
///
/// - `band` se mění **jednou za výřez** (je kvantovaný, viz `Policy.mountBand(visible:)`), a čtou
///   ho **všechny** sloty bloků. Kdyby se měnil při každém otočení kolečka, překládalo by se při
///   každém snímku tělo každého bloku v diffu.
/// - `top` se mění při **každém** otočení kolečka a čte ho **jediné view** — ukotvená hlavička
///   souboru. Cena je tím ohraničená na jednu malou hlavičku.
///
/// Změřeno, proč to takhle je (`DiffShapeProbe`, 6000 řádků, projetí 150 × 40 pt): první podoba
/// se ptala **každého bloku a každé hlavičky** na jeho rámeček v souřadnicích výřezu, tedy na
/// hodnotu, která se scrollováním mění — a stálo to 3,5 s CPU proti 0,19 s u seznamu bez těch
/// dotazů. Rámečky v souřadnicích **obsahu** se scrollováním nemění, takže se za ně neplatí; co se
/// mění, se čte na jednom místě.
@Observable final class DiffViewport {
    /// Pás v souřadnicích obsahu, ve kterém jsou bloky kódu nasazené.
    var band: ClosedRange<Double> = 0...0
    /// Horní hrana výřezu v souřadnicích obsahu.
    var top = 0.0
    /// Kolikátý diff se v tomhle view kreslí (#469). Mění se s `DiffView.subject`, tedy při
    /// přepnutí záložky — a slot bloku podle toho pozná, že jeho změřená výška je **z cizího PR**.
    ///
    /// Je to tentýž důvod jako `subject` u `DiffRowFrames`: `@State` detailu přetéká mezi pull
    /// requesty a řádek se stejnou identitou (`CLAUDE.md|174`) má kdejaký PR, takže by si blok
    /// odnesl výšku, která nikdy nepatřila tomu, co je zrovna na obrazovce.
    var generation = 0
}
