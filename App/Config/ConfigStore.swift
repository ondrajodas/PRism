import Foundation

/// `config.json` na disku.
///
/// Aktor ze stejného důvodu jako `ReviewStore`: čtení i zápis sahají na týž soubor
/// a nemají se potkat.
actor ConfigStore {
    /// Co načtení dalo. Selhání **není** vyhozená chyba: rozbitý soubor nesmí aplikaci
    /// položit, ale taky se nesmí spolknout — jinak uživatel hledá, proč mu nastavení
    /// nefunguje.
    struct Loaded: Equatable, Sendable {
        var configuration: Configuration
        var failure: String?
    }

    private let layout: CacheLayout
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(layout: CacheLayout = .applicationSupport) {
        self.layout = layout
        encoder = JSONEncoder()
        // Soubor se edituje ručně, takže na čitelnosti záleží víc než na bajtech.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    func load() -> Loaded {
        // Chybějící soubor a nečitelný soubor se rozlišují **předem**, ne selháním čtení.
        // Jinak by se soubor, který existuje a jen se nedá přečíst, založil znovu —
        // tedy přepsal výchozími hodnotami, což je přesně to, co se dole nesmí stát.
        guard FileManager.default.fileExists(atPath: layout.configFile.path(percentEncoded: false)) else {
            // První spuštění: soubor se založí, aby bylo co editovat. Když se to nepovede,
            // aplikace poběží na defaultech — psát o tom je šum bez akce.
            try? save(.standard)
            return Loaded(configuration: .standard)
        }

        do {
            let data = try Data(contentsOf: layout.configFile)
            return Loaded(configuration: try decoder.decode(Configuration.self, from: data))
        } catch {
            // Soubor se **nepřepisuje**. Uživatel ho psal a přijít o něj kvůli chybějící
            // čárce by bylo horší než ta chyba sama.
            return Loaded(
                configuration: .standard,
                failure: "Konfiguraci se nepodařilo přečíst, běží se na výchozích hodnotách. \(error.localizedDescription)"
            )
        }
    }

    func save(_ configuration: Configuration) throws {
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try encoder.encode(configuration).write(to: layout.configFile, options: .atomic)
    }
}
