import Foundation

/// Persistence otevřených záložek — jeden JSON v kořeni cache slotu (#527).
///
/// **Není to aktor, na rozdíl od ostatních ledgerů, a je to rozhodnutí.** `AnnouncedPullRequests`
/// i `HandoffLedger` jsou aktory proto, že u nich je uložení **čtení, změna a zápis** téhož
/// souboru — tři kroky, které se nesmí prolnout. Tady je celý snímek v paměti store, takže je
/// zápis **jeden krok**: přepis souboru tím, co je právě otevřené. Nic se nečte, není co
/// prolnout.
///
/// A hlavně: **musí se dát zapsat synchronně**. Snímek se ukládá i při ukončení aplikace
/// (`applicationShouldTerminate` vrací `.terminateNow` **synchronně**, viz `AppDelegate`), a to
/// je zrovna ten okamžik, na kterém celé issue stojí — `bin/run.sh` po mergi aplikaci ukončí
/// Apple eventem. Aktor by v té cestě znamenal `await`, na který už nikdo nepočká.
///
/// Zápis je proto **synchronní I/O na hlavním vlákně**, a je to vědomá cena: je to pár set bajtů
/// atomicky, zapisuje se **při změně záložky** (tedy několikrát za minutu, ne za snímek) a nic
/// jiného na tom nečeká. Kdyby snímek začal být velký, znamenalo by to stovky otevřených záložek,
/// tedy jiný problém.
@MainActor final class OpenTabsStore {
    private let layout: CacheLayout
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(layout: CacheLayout = .applicationSupport) {
        self.layout = layout
        encoder = JSONEncoder()
        // Odsazení a řazení klíčů jako u nálezů: je to osobní nástroj a `tabs.json` se čte očima.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    /// Snímek z disku. Prázdný, když soubor není nebo se nedá přečíst.
    ///
    /// **Nečitelný soubor znamená prázdno, ne pád ani chybu v okně** — je to opačná volba než
    /// u nálezů a u značek `Prošlo`, a je to schválně: nejhorší následek je **jedno spuštění bez
    /// záložek**, tedy přesně stav, ve kterém aplikace startovala do #527. Není to ručně psaná
    /// práce, kterou by bylo čím nahradit; záložka se otevře kliknutím. Hlásit to do okna by
    /// znamenalo poruchu nad něčím, co se samo opraví prvním otevřením záložky.
    ///
    /// Platí to i pro **přejmenovaný případ `PullRequestTab`**: takový snímek se celý zahodí,
    /// protože jeden nečitelný tab by se `?? .standard` jinak tvářil jako volba člověka.
    func load() -> OpenTabs {
        // **Hranice cache napřed, čtení až po ní** — jako u `ReadMarkStore` a `AskStore`.
        // Odkaz na souboru by dovolil přečíst JSON mimo cache (tvrdá podmínka č. 3).
        guard CacheFile.refusal(for: layout.openTabsFile, in: layout) == nil,
              let data = try? Data(contentsOf: layout.openTabsFile),
              let stored = try? decoder.decode(OpenTabs.self, from: data)
        else { return .none }
        return stored
    }

    /// Přepíše snímek. **Selhání se spolkne** — za běhu platí paměť a po restartu se prostě
    /// neobnoví nic, tedy stav před #527. Příští změna záložky to zkusí znovu.
    ///
    /// **Prázdný snímek se maže, ne ukládá.** Jinak by v cache zůstal soubor s prázdným seznamem
    /// po každém zavření poslední záložky — a od „nikdy jsem nic neotevřel“ by se nedal rozeznat.
    func save(_ tabs: OpenTabs) {
        guard !tabs.isEmpty else {
            discard()
            return
        }
        guard CacheFile.refusal(for: layout.openTabsFile, in: layout) == nil else { return }
        try? FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        // Atomicky: půlka souboru se od celého nedá odlišit jinak než tím, že se nedekóduje —
        // a to by po restartu vypadalo jako „nic nebylo otevřené“.
        try? encoder.encode(tabs).write(to: layout.openTabsFile, options: .atomic)
    }

    /// Zahodí snímek. **Odkaz na souboru se tady neodmítá**, na rozdíl od čtení a zápisu — je to
    /// tentýž rozdíl jako u `ReadMarkStore.delete`: `removeItem` smaže **odkaz**, ne jeho cíl,
    /// takže je to jediná cesta, jak takovou anomálii z cache dostat pryč.
    private func discard() {
        guard CacheFile.isInsideCache(layout.openTabsFile, in: layout) else { return }
        try? FileManager.default.removeItem(at: layout.openTabsFile)
    }
}
