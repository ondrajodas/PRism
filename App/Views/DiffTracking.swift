import Observation

/// Kde diff právě je — **sdílené mezi `DiffView`em a mapou PR** (#501).
///
/// Existuje proto, že mapa leží **nad pruhem záložek**, tedy mimo `DiffView`, a přesto se ptá na
/// tutéž věc jako ukotvená hlavička souboru a `⌥V`: který soubor je pod výřezem. Do #501 si
/// `DiffView` obě krabice držel sám ve `@State`; od #501 mu je **předává detail PR** a bez nich
/// (diff commitu, náhled) si drží vlastní — proto je parametr `DiffView.tracking` optional.
///
/// Není to `@Observable` třída, jen držák: sledované vlastnosti jsou v tom, co drží, a každou
/// z nich čte někdo jiný a jinak často. Kdyby byl observable celý, překreslila by změna výřezu
/// i to, co se ptá jen na cestu souboru.
@MainActor final class DiffTracking {
    /// Pás nasazených bloků a horní hrana výřezu (#469).
    let viewport = DiffViewport()
    /// Kde v obsahu leží který soubor (#469).
    let extents = DiffFileExtents()
    /// Cesta souboru pod výřezem (#501).
    let cursor = DiffFileCursor()
}

/// Cesta souboru, který je zrovna pod výřezem diffu (#501).
///
/// **Vlastní krabice, ne vlastnost `DiffViewport`u** — a je to totéž výkonové rozhodnutí, jaké
/// #469 udělalo mezi `band` a `top`: `top` se mění při **každém** otočení kolečka, kdežto tahle
/// hodnota se mění **jen na hranici souborů**. Kdyby se pás ptal na `top`, přeložilo by se při
/// každém snímku jeho tělo i se všemi segmenty; takhle se překresluje jedno neviditelné view,
/// které do krabice zapisuje (`PullRequestMapProbe`).
///
/// Cesta, ne index: pás skládá `Policy` ze souborů toho diffu, který je zrovna v tabu, a index
/// z rozsahů by po přepnutí na `Od tvé poslední návštěvy` chvíli ukazoval na cizí soubor. Cesta,
/// která v pásu není, prostě nikde nesvítí.
@Observable final class DiffFileCursor {
    var path: String?
}
