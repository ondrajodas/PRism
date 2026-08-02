import Foundation
import Observation

/// Rozepsané nastavení a jeho cesta do `config.json`.
///
/// Existuje kvůli dvěma věcem, které by se ve view dělaly špatně: **ukládá se se zpožděním**
/// (jinak by každý úhoz v textovém poli znamenal zápis na disk) a **rozpozná změnu zvenčí**
/// od té vlastní, protože soubor jde pořád editovat ručně.
@MainActor
@Observable
final class SettingsModel {
    /// Co kreslí formulář. Každá **změna** se odloženě uloží.
    ///
    /// Zápis se stejnou hodnotou se zahazuje schválně: pole ve formuláři si při zobrazení
    /// zapíšou zpátky, co v nich je (`TextField(value:format:)` normalizuje, `nil` model
    /// se vrací jako prázdný řetězec), takže bez téhle podmínky by samotné otevření okna
    /// přepsalo ručně editovaný soubor a ohlásilo „Uloženo“, aniž by se cokoli změnilo.
    var draft: Configuration {
        get { storage }
        set {
            guard newValue != storage else { return }
            storage = newValue
            scheduleSave()
        }
    }

    /// Proč se nastavení nepodařilo uložit. Neuložená změna, o které se mlčí, vypadá v okně
    /// jako uložená — a po restartu je pryč.
    private(set) var saveFailure: String?

    /// Kdy naposledy něco doopravdy odešlo na disk. `nil` = od otevření okna se nic
    /// neměnilo.
    private(set) var lastSaved: Date?

    private var storage: Configuration
    /// Poslední podoba, na které se okno a soubor shodly. Rozeznává „přepsal to někdo
    /// jinde“ od „to jsem uložil já“.
    @ObservationIgnored private var settled: Configuration
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let time: any TimeSource
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let write: @MainActor (Configuration) async throws -> Void

    /// - Parameter delay: jak dlouho se čeká na další úhoz, než se sáhne na disk.
    init(
        configuration: Configuration,
        time: any TimeSource = SystemTimeSource(),
        delay: Duration = .milliseconds(600),
        write: @escaping @MainActor (Configuration) async throws -> Void
    ) {
        storage = configuration
        settled = configuration
        self.time = time
        self.delay = delay
        self.write = write
    }

    /// Srovná formulář s konfigurací, kterou drží aplikace.
    ///
    /// Volá se při otevření okna a pak při každé změně ve store. Vlastní uložení se sem
    /// vrátí taky — proto se porovnává se `settled` a ne s `draft`: bez toho by se
    /// rozepsaný text přepsal sám sebou pokaždé, když zápis doběhne.
    func sync(with configuration: Configuration) {
        guard configuration != settled else { return }
        settled = configuration
        storage = configuration
    }

    /// Uloží hned, bez čekání. Pro zavření okna — rozepsaná změna se nesmí ztratit proto,
    /// že jsem byl rychlejší než zpoždění.
    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        guard storage != settled else { return }
        await save(storage)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard let self else { return }
            // Zrušené uspání vyhodí — a je to jediná cesta, jak se sem dostat s dalším
            // úhozem na cestě. Uložit po něm by zapsalo mezistav, který už neplatí.
            try? await time.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await save(storage)
        }
    }

    private func save(_ configuration: Configuration) async {
        // Nastavuje se **před** zápisem schválně: `write` propíše konfiguraci do store,
        // odkud se vrátí zpátky do `sync` — a to nesmí přepsat, co uživatel mezitím
        // napsal.
        let previous = settled
        settled = configuration
        do {
            try await write(configuration)
            saveFailure = nil
            lastSaved = time.now
        } catch {
            // Po selhání se to musí vrátit. Se `settled` na neuložené hodnotě by
            // `flush()` viděl `storage == settled` a nezkusil to znovu — a hlavně by
            // `sync(with:)` se **starou** konfigurací ze store (ta se nezměnila, zápis
            // selhal) vypadal jako změna zvenčí a přepsal by rozepsanou práci.
            settled = previous
            saveFailure = error.localizedDescription
        }
    }
}
