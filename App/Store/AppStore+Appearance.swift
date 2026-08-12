import Foundation

/// Vzhled okna (#278) — přepnutí z railu.
extension AppStore {
    /// Zapíše volbu vzhledu do konfigurace a odtud ji `apply(_:)` uplatní.
    ///
    /// **Píše se do souboru, ne jen do paměti** — na rozdíl od pohledu na diff, který se v liště
    /// přepíná jen do zavření aplikace. Vzhled je předvolba člověka, takže musí přežít restart;
    /// a je to tatáž hodnota, kterou pak vidí rail, protože ten si žádnou kopii nedrží.
    ///
    /// Shodná hodnota se **zahazuje**: nabídka v railu hlásí i výběr toho, co už platí, a zápis
    /// beze změny by přepsal ručně editovaný soubor.
    func setAppearance(_ mode: AppearanceMode) async {
        guard mode != configuration.global.appearance else { return }
        var updated = configuration
        updated.global.appearance = mode
        do {
            try await updateConfiguration(updated)
            appearanceFailure = nil
        } catch {
            // Selhání se **nespolkne**. Vzhled se totiž nepřepnul — `apply(_:)` jde až po
            // úspěšném zápisu —, takže bez hlášky vypadá rail jako rozbitý: klik, a nic.
            appearanceFailure = "Vzhled okna se nepodařilo uložit. \(error.localizedDescription)"
        }
    }
}
