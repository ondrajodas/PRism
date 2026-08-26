import Foundation

/// **Hranice cache na jednom místě** (#452): smí aplikace na tuhle cestu sáhnout?
///
/// Tvrdá podmínka č. 3 zní „aplikace pracuje výhradně ve své cache“ a do #452 se držela tím, že si
/// ji **každý store opsal sám** — a pokaždé jinak: `ReviewStore` a `ReviewDraftStore` kontrolovaly
/// hranici jen u mazání a odkaz jen u čtení, `CacheTextFile` obojí, `AskStore` u mazání. Přesně ten
/// vzor, na který si `CLAUDE.md` stěžuje: *kontrola, která jinde v repu je, a tady chybí*. Pravidlo
/// proto bydlí tady a stores z něj berou **verdikt**, ne kopii dvou `guardů`.
///
/// Kontroly jsou dvě a **žádná nenahrazuje druhou**:
///
/// - `CacheLayout.contains` rozbaluje symlinky v **rodiči**, protože čtení, zápis i mazání přes
///   odkaz v cestě sáhnou na cíl, ne na odkaz;
/// - `CacheLayout.isSymbolicLink` odmítá odkaz na **samotném souboru**. `contains` ho nezachytí,
///   protože rozbaluje symlinky na obou stranách a cíl vyjde rovný cíli — a u čtení na tom záleží
///   nejvíc: `Data(contentsOf:)` by přečetl soubor mimo cache.
///
/// **Mazání chce jen tu první, a je to rozdíl, ne nedůslednost.** `removeItem` nad odkazem smaže
/// **odkaz**, ne to, kam ukazuje, takže je neškodné — a hlavně je to jediná cesta, jak takovou
/// anomálii z cache dostat pryč. Kdyby ji mazání odmítalo taky, zůstal by odkaz v cache navždycky
/// a `Nový rozhovor` by ho neuklidil.
enum CacheFile {
    /// Proč se na cestu nesmí sáhnout. `nil` = smí.
    ///
    /// Vrací se **důvod**, ne `Bool`, aby si každý store mohl přeložit odmítnutí do své vlastní
    /// čitelné chyby — věta v okně má říkat, co se stalo s **rozhovorem** nebo s **draftem**, ne
    /// obecné „cesta je mimo“.
    enum Refusal: Equatable, Sendable {
        /// Cesta po rozbalení symlinků neleží pod kořenem cache.
        case outsideCache
        /// Na samotném souboru je symbolický odkaz.
        case symbolicLink
    }

    /// Verdikt pro **čtení a zápis**: obě kontroly.
    static func refusal(for url: URL, in layout: CacheLayout) -> Refusal? {
        guard layout.contains(url) else { return .outsideCache }
        guard !layout.isSymbolicLink(url) else { return .symbolicLink }
        return nil
    }

    /// Leží cesta uvnitř cache? Verdikt pro **mazání** — viz úvod, odkaz se u něj neodmítá.
    static func isInsideCache(_ url: URL, in layout: CacheLayout) -> Bool {
        layout.contains(url)
    }

    /// Cesta ověřená na obojí, nebo chyba — pro volající, kteří **vlastní chybu nemají**.
    ///
    /// Selhání **vyhazuje**, nespolkne se: tichý návrat by u čtení znamenal „nic tu nebylo“
    /// a u zápisu „uloženo“, a obojí je lež o datech.
    @discardableResult
    static func checked(_ url: URL, in layout: CacheLayout) throws -> URL {
        switch refusal(for: url, in: layout) {
        case .outsideCache:
            throw CheckoutError.cacheUnavailable(
                "Cesta \(url.path(percentEncoded: false)) vede mimo cache aplikace."
            )
        case .symbolicLink:
            throw CheckoutError.cacheUnavailable(
                "Na cestě \(url.path(percentEncoded: false)) leží symbolický odkaz."
            )
        case nil:
            return url
        }
    }
}
