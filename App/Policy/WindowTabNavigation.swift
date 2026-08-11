import Foundation

extension Policy {
    /// Pruh záložek v tom pořadí, v jakém je v okně vidět (#245): **domácí první**, za ní otevřená
    /// review v pořadí otevření.
    ///
    /// Domácí záložka do pruhu patří, protože ji pruh kreslí a chodí se na ni nejčastěji — je za ní
    /// fronta. Bez ní by `⌃Tab` nad jediným otevřeným PR nedělal nic.
    static func tabStrip(open: [PRIdentifier]) -> [WindowTab] {
        [.home] + open.map(WindowTab.pullRequest)
    }

    /// Sousední záložka v pruhu, **dokola** — kam vede `⌃Tab` (`.forward`) a `⌃⇧Tab` (`.backward`).
    ///
    /// Pořadí je **pořadí pruhu, ne pořadí použití**: MRU cyklení je u dvou záložek nerozeznatelné
    /// a u pěti překvapivé, kdežto `openTabs` drží to, co je vidět.
    ///
    /// `nil` znamená **nikam se nehýbe** a jsou to dva případy. Jediná záložka (samotná domácí,
    /// tedy nic otevřeného) je ten očekávaný — nemá kam skočit, takže se nemá dít vůbec nic, ani
    /// pípnutí, ani propadnutí domů. Druhý je aktivní záložka, která v pruhu není; to se stát nemá,
    /// protože `openTab` je jediná cesta k `activeTab` na PR, ale hádat za takového stavu sousedy
    /// by znamenalo odnést člověka od toho, co má na obrazovce.
    static func tab(
        _ step: NavigationStep,
        after active: WindowTab,
        open: [PRIdentifier]
    ) -> WindowTab? {
        let strip = tabStrip(open: open)
        guard strip.count > 1, let index = strip.firstIndex(of: active) else { return nil }
        // Zpátky se jde o kolo bez jednoho, ne o `-1`: zbytek po dělení je ve Swiftu u negativního
        // dělence negativní, takže by `(0 - 1) % count` vyšlo `-1` a index by spadl mimo pole.
        let offset = step == .forward ? 1 : strip.count - 1
        return strip[(index + offset) % strip.count]
    }
}
