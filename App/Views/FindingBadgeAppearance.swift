import SwiftUI

/// Barva **konstatování** u nálezu (#309): odznak shody `2×` a značka `✓ v mém review`.
///
/// Na jednom místě, i když to sázejí dvě obrazovky — tabulka nálezů a bublina u kódu. Je to tatáž
/// úvaha jako u `RecheckAppearance` a `ReviewStateAppearance`: dvě barvy pro jedno sdělení by
/// z jednoho stavu udělaly dva. Tady navíc **ta barva to sdělení nese** — obojí stojí mezi akcemi
/// (`Převzít`, `Vrátit`, `⋯`) a jediné, čím se od nich liší, je právě ona.
///
/// Vlastní jméno, ne `Palette.mint` na čtyřech místech ve `@ViewBuilder`ech: takhle se dá tvrdit
/// testem, že se odznak nepřebarvil zpátky na akcent (`MintTokenTests`). Uvnitř `body` se to
/// tvrdit nedá a zrovna tahle záměna je celý důvod, proč #309 vzniklo.
enum FindingBadgeAppearance {
    /// **Nesmí to být `Palette.accent`.** Co je akcent a co mint, je u `Palette.mint`.
    static var stateTint: Color { Palette.mint }
}
