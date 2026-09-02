import Foundation

/// Seznamy repozitářů organizací na disku (#532) — `catalogs/<org>.json`.
///
/// **Aktor, ne funkce na hlavním vlákně**, ze stejného důvodu jako `ReviewStore`: jeden snímek
/// `keboola` má ~100 kB a při otevření nastavení by se četly všechny organizace naráz. Hlavní
/// vlákno v tu chvíli kreslí okno.
///
/// Hranici cache drží `CacheFile`, tedy **tatáž kontrola jako jinde v repu** (tvrdá podmínka
/// č. 3) — jméno organizace se do cesty dostane z pole v nastavení, takže se ověřuje
/// (`Policy.organizationName(from:)`) a pak se ještě kouká, jestli výsledná cesta doopravdy leží
/// v cache.
actor RepositoryCatalogStore {
    private let layout: CacheLayout
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(layout: CacheLayout = .applicationSupport) {
        self.layout = layout
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Co z cache vyjde pro vyjmenované organizace.
    ///
    /// **Nečitelný soubor se přeskočí a je to bezpečný směr**: organizace bez snímku vypadá jako
    /// nedotažená, takže se dotáhne znovu — a `Policy.repositoryCatalogStatus` ji do součtu
    /// nezapočítá. Opačná volba (položit celé čtení) by kvůli jednomu souboru schovala i ty
    /// ostatní, které jsou v pořádku.
    func snapshots(for organizations: [String]) -> [String: RepositorySnapshot] {
        var found: [String: RepositorySnapshot] = [:]
        for organization in organizations {
            guard let snapshot = snapshot(for: organization) else { continue }
            found[organization] = snapshot
        }
        return found
    }

    /// Uloží snímek. **Vyhazuje**, protože tiché selhání zápisu znamená, že se `keboola` bude
    /// tahat tři čtvrtě minuty při každém otevření nastavení a nikdo se nedozví proč.
    func save(_ snapshot: RepositorySnapshot) throws {
        guard let name = Policy.organizationName(from: snapshot.organization) else {
            throw CheckoutError.cacheUnavailable("Jméno organizace „\(snapshot.organization)“ se nedá použít.")
        }
        let file = try CacheFile.checked(layout.catalogFile(for: name), in: layout)
        try FileManager.default.createDirectory(at: layout.catalogs, withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: file, options: .atomic)
    }

    /// Zahodí snímky organizací, které v nastavení **už nejsou**.
    ///
    /// Bez toho by v cache ležela stovka kilobajtů za organizaci, kterou jsem před měsícem
    /// smazal z konfigurace — a eviction sem nechodí (viz `CacheLayout.catalogs`), takže by je
    /// neuklidil nikdo. Selhání se **spolkne**: neuklizený soubor nikomu nevadí a příští otevření
    /// nastavení to zkusí znovu; hlásit to je šum bez akce.
    ///
    /// Maže se **jen uvnitř cache** (`CacheFile.isInsideCache`) — je to tatáž ochrana, jakou má
    /// mazání nálezů a draftů, a tady na ní záleží o to víc, že jméno souboru vzniklo z textu,
    /// který někdo napsal do pole.
    func discard(keeping organizations: [String]) {
        let kept = Set(organizations.compactMap(Policy.organizationName(from:)))
        let files = (try? FileManager.default.contentsOfDirectory(
            at: layout.catalogs,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in files where file.pathExtension == "json" {
            let organization = file.deletingPathExtension().lastPathComponent
            guard !kept.contains(organization) else { continue }
            guard CacheFile.isInsideCache(file, in: layout) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func snapshot(for organization: String) -> RepositorySnapshot? {
        guard let name = Policy.organizationName(from: organization) else { return nil }
        let file = layout.catalogFile(for: name)
        guard CacheFile.refusal(for: file, in: layout) == nil else { return nil }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? decoder.decode(RepositorySnapshot.self, from: data)
    }
}
