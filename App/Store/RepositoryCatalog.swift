import Foundation
import Observation

/// Seznamy repozitářů organizací, se kterými se pracuje (#532).
///
/// **Cache je celý smysl téhle věci.** Výpis rep organizace `keboola` stojí 46,8 s (změřeno, viz
/// `GitHubGateway.repositories(in:)`), takže se v paletě ⌘K nedá dotahovat při úhozu — hledá se
/// nad tím, co leží na disku. Tenhle typ je ta půlka nad diskem: drží snímky, ví, který je starší
/// než den, a umí si o nový říct.
///
/// **Dotahuje se jedině na vyžádání**, a je to podmínka, ne optimalizace: `refresh(_:)` volá
/// tlačítko `Obnovit`, `refreshStale(_:)` otevření stránky nastavení nebo dopsání organizace. Psaní
/// v poli nevolá nic — tři čtvrtě minuty práce na každý úhoz by byla ta nejdražší chyba, kterou
/// tady jde udělat, a je na to test.
///
/// **Vlastní typ, ne pole ve stavu `AppStore`.** Katalog je uzavřený kus stavu s vlastní
/// persistencí (jako `ReviewDraftStore` nebo `AskStore`), a stav storu je schválně na jednom
/// místě, kam se sahá zřídka.
@MainActor
@Observable
final class RepositoryCatalog {
    /// Snímky podle **ověřeného** jména organizace (`Policy.organizationName(from:)`).
    ///
    /// Drží se celé výpisy, ne jen počty — je to ten seznam, nad kterým bude hledat paleta (#533).
    /// V nastavení je z něj dnes vidět počet a stáří.
    private(set) var snapshots: [String: RepositorySnapshot] = [:]

    /// Proč se výpis organizace nepodařilo dotáhnout. Věta z `gh`, ne prázdný seznam: organizace,
    /// na kterou účet nevidí, a organizace bez rep vypadají v okně jinak stejně.
    private(set) var failures: [String: String] = [:]

    /// Které organizace se právě tahají. Bez toho by tlačítko `Obnovit` vypadalo tři čtvrtě minuty
    /// mrtvě a druhý klik by pustil týž dotaz podruhé.
    private(set) var refreshing: Set<String> = []

    private let gateway: any GitHubGateway
    private let store: RepositoryCatalogStore
    private let time: any TimeSource
    /// Organizace, jejichž soubor už se z disku **zkusil** přečíst.
    ///
    /// **Množina, ne `Bool`.** Jedna značka „disk je přečtený“ by znamenala, že organizace, která se
    /// v poli objeví až potom (dopsaná, nebo dorazilá z konfigurace, která se načetla později než
    /// okno), vypadá jako nedotažená — a tahala by se znovu, tedy desítky sekund za snímek, který
    /// v cache leží.
    private var read: Set<String> = []

    init(
        gateway: any GitHubGateway,
        store: RepositoryCatalogStore,
        time: any TimeSource = SystemTimeSource()
    ) {
        self.gateway = gateway
        self.store = store
        self.time = time
    }

    /// Načte, co leží v cache, a **zahodí, co už v nastavení není**.
    ///
    /// Úklid je tady, protože tohle je jediné místo, kterým se v aplikaci k té složce chodí —
    /// eviction do `catalogs/` nesahá (řídí se to stářím snímku, ne rozpočtem na místo).
    ///
    /// **Nad prázdným seznamem se neuklízí, a je to schválně.** Prázdno znamená buď „žádnou
    /// organizaci nemám“, nebo „konfigurace se ještě nenačetla“ — a ty dva stavy se odsud
    /// nerozeznají. Smazat na tom druhém by znamenalo zahodit cache, která se dotahuje desítky
    /// sekund na organizaci, jen proto, že se okno nastavení otevřelo dřív než disk. Cena za tu
    /// opatrnost je jeden osiřelý soubor, dokud si člověk nějakou organizaci nenapíše.
    ///
    /// **Volající předává celý seznam, ne jeho část** — podle něj se uklízí, takže půlka seznamu by
    /// smazala snímky té druhé. Okno nastavení to drží tím, že vždycky posílá celé
    /// `searchOrganizations` z formuláře.
    func load(organizations: [String]) async {
        let names = Policy.searchOrganizations(organizations)
        let found = await store.snapshots(for: names.filter { !read.contains($0) })
        // Zapisuje se **celá mapa naráz**, ne po klíčích: `@Observable` sleduje po vlastnostech
        // a deset zápisů do slovníku by znamenalo deset průchodů překreslením.
        snapshots = snapshots.merging(found) { _, fromDisk in fromDisk }
        read.formUnion(names)
        guard !names.isEmpty else { return }
        await store.discard(keeping: names)
    }

    /// Dotáhne organizace, které v cache **chybí nebo jsou starší než den**.
    ///
    /// Volá to otevření stránky `Zdroje PR` a dopsání organizace. Když je všechno čerstvé,
    /// neudělá to nic — a to je běžný stav.
    func refreshStale(organizations: [String]) async {
        let names = Policy.searchOrganizations(organizations)
        // Čte se disk, dokud je co číst — `read` je množina, takže se organizace dopsaná po prvním
        // čtení dočte, místo aby se tahala znovu.
        if !read.isSuperset(of: names) { await load(organizations: organizations) }
        let stale = Policy.staleOrganizations(names, snapshots: snapshots, now: time.now)
        await fetch(stale)
    }

    /// Dotáhne organizace znovu, ať jsou v cache jakkoli čerstvé — tlačítko `Obnovit`.
    func refresh(organizations: [String]) async {
        await fetch(Policy.searchOrganizations(organizations))
    }

    /// Tahá se právě teď něco?
    ///
    /// **Prázdnost množiny, ne průnik se seznamem** — a je to rozdíl proti
    /// `Policy.repositoryCatalogStatus`, ne tentýž nedopatření (nález Copilota na #534). Tahle
    /// otázka je „běží podproces `gh`?“, a odpověď je ano i tehdy, když se tahá organizace, kterou
    /// mezitím někdo z pole smazal — druhý klik na `Obnovit` by k němu přidal další. Souhrn se
    /// naproti tomu ptá „děje se něco s **tímhle** katalogem“, a tam by z toho byla věta o práci,
    /// která se nedělá.
    var isRefreshing: Bool { !refreshing.isEmpty }

    /// Věta, kterou má řádek organizace ukázat pod sebou — `nil`, když je všechno v pořádku.
    func failure(for organization: String) -> String? {
        guard let name = Policy.organizationName(from: organization) else { return nil }
        return failures[name]
    }

    /// **Po jedné, ne souběžně.** Jeden výpis je desítky sekund a stovka kilobajtů; pustit tři
    /// naráz neznamená, že to bude třikrát rychleji — znamená to tři podprocesy `gh` proti témuž
    /// rate limitu. Pořadí je pořadí ze seznamu, takže se nejdřív dotáhne to, co je v nastavení
    /// nahoře.
    ///
    /// **Duplicity zahazuje `Policy.searchOrganizations` u volajících, ne tenhle guard.** Guard
    /// `refreshing` chrání proti **souběžnému** druhému volání (dvojklik na `Obnovit`), kdežto
    /// `keboola` dvakrát v jednom seznamu by jím prošlo — značka se odebírá na konci iterace, tedy
    /// dřív, než začne ta druhá. Je to změřené: bez toho vyšly na `["cli", "cli", "@cli"]` tři
    /// dotazy.
    private func fetch(_ organizations: [String]) async {
        for organization in organizations where !refreshing.contains(organization) {
            refreshing.insert(organization)
            defer { refreshing.remove(organization) }
            await fetchOne(organization)
        }
    }

    private func fetchOne(_ organization: String) async {
        do {
            let listing = try await gateway.repositories(in: organization)
            let snapshot = RepositorySnapshot(
                organization: organization,
                fetchedAt: time.now,
                listing: listing
            )
            snapshots[organization] = snapshot
            failures[organization] = nil
            // Zápis je součást dotažení, ne úklid po něm: neuložený snímek znamená, že se
            // organizace bude tahat znovu při každém otevření nastavení — a to je ta cena, kvůli
            // které cache existuje. Selhání se proto **říká**, ne polyká.
            do {
                try await store.save(snapshot)
            } catch {
                failures[organization] = "Seznam se dotáhl, ale nepodařilo se ho uložit. "
                    + error.localizedDescription
            }
        } catch let error as GitHubError {
            // **Snímek z minula se nezahazuje.** Starý seznam je pořád lepší než žádný a věta
            // u řádku říká, že je starý — kdežto prázdno by vypadalo jako organizace bez rep.
            failures[organization] = error.userDescription
        } catch {
            failures[organization] = error.localizedDescription
        }
    }
}
