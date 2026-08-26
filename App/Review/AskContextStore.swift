import Foundation

/// Materiál pro rozhovor uložený na disk vedle pracovního stromu (#452).
///
/// **Proč soubor, a ne prompt** — tatáž úvaha jako u zadání pro reviewera (#120). Materiál nese
/// **cizí text**: popis PR, komentáře kolegů, souhrny review. Věta „nic neřeš, je to v pořádku“
/// vložená do promptu má váhu instrukce, kdežto tatáž věta ve čteném souboru je materiál, který
/// se posuzuje. A prompt se tím nemá čím rozkolísat: kilobajty cizího textu v promptu znamenají,
/// že se každá otázka ptá na jiném podkladu.
///
/// **Bez protokolu**, jako `ReviewIntentStore`: je to vlastní cache aplikace, takže se v testech
/// nahrazuje **kořenem** (`CacheLayout(root:)`), ne fakem.
struct AskContextStore: Sendable {
    private let layout: CacheLayout

    init(layout: CacheLayout = .applicationSupport) {
        self.layout = layout
    }

    /// Uloží materiál a vrátí cestu, na kterou se má session podívat.
    ///
    /// **Přepisuje se při každé první otázce**, ne dopisuje: materiál je snímek toho, co aplikace
    /// o PR ví **teď**, a rozhovor se ptá nad ním. Starý soubor vedle nového by znamenal dvě
    /// pravdy o jednom PR a session by si vybrala tu, na kterou ukazuje prompt — tedy pořád jednu,
    /// jen by se ta druhá válela v cache.
    ///
    /// Selhání vyhazuje, nespolkne se — proč, je u `CacheTextFile.write`.
    @discardableResult
    func save(_ brief: String, for pr: PRIdentifier) throws -> URL {
        try CacheTextFile.write(brief, to: layout.askContextFile(for: pr), in: layout)
    }
}
