import Foundation

/// Spuštění po přihlášení (#529, návrh sekce 49) — **jedna čistá funkce na celý ten řádek**.
///
/// Přepínač musí odpovědět na tři různé otázky naráz (v jaké poloze být, jestli jde vůbec
/// cvaknout, a co k tomu napsat), a odpovědi se křižují: slotová instance, cesta mimo
/// `/Applications`, zákaz v Nastavení systému a nepovedený zápis. Ve view by z toho byly čtyři
/// `if`y a pátý stav by se zapomněl — tady se to projde výčtem.
extension Policy {
    /// Smí tahle instalace zakládat přihlašovací položku?
    enum LoginItemAvailability: Equatable, Sendable {
        case available
        /// Instance pro paralelní vývoj (`PRism-d`). Nesou jméno v `CFBundleName`, tedy totéž,
        /// z čeho se bere kořen cache (#228).
        case slotInstance(String)
        /// Bundle neleží v `/Applications`.
        case outsideApplications(String)

        var isAvailable: Bool { self == .available }
    }

    /// Jak vypadá řádek `Spustit po přihlášení`.
    struct LoginItemRow: Equatable, Sendable {
        /// V jaké poloze je přepínač.
        var isOn: Bool
        /// Jde s ním cvaknout?
        var isEnabled: Bool
        /// Věta pod ním. **Nikdy prázdná** — přepínač, který nejde cvaknout a neřekne proč, je
        /// k nerozeznání od rozbité aplikace, a ten, který jde, potřebuje říct, kam vlastně píše.
        var note: String
        /// Má se nabídnout odskok do Nastavení systému? Jen tam, kde je to **další krok**, ne
        /// u každé věty — vzor z #414.
        var offersSystemSettings: Bool
    }

    /// Rozhodne o instalaci **dřív, než se sáhne na systém**.
    ///
    /// **Slot se posuzuje první**, i když by o pár řádků dál padl i na cestě: je to zákaz, který
    /// se nedá spravit (slotová instance zmizí s worktree), kdežto „nainstaluj to do
    /// `/Applications`“ je pokyn, po kterém to půjde. Věta má odpovídat tomu, co je s tím k
    /// dělání.
    ///
    /// Jméno se porovnává s `MainWindow.title`, ne s vlastním literálem — drží to pravidlo
    /// „jeden název všude“ z `CLAUDE.md`.
    static func loginItemAvailability(_ installation: AppInstallation) -> LoginItemAvailability {
        guard installation.name == MainWindow.title else {
            return .slotInstance(installation.name)
        }
        guard installation.path.hasPrefix("/Applications/") else {
            return .outsideApplications(installation.path)
        }
        return .available
    }

    /// Poloha, zašednutí a věta k nim.
    ///
    /// **Poloha se bere ze systému, ne z `config.json`** (poznámka 180 v návrhu): přihlašovací
    /// položka žije v systému, takže druhá kopie v konfiguraci by po ručním vypnutí v Nastavení
    /// systému ukazovala v okně opak toho, co platí. Volba odznaku naopak do konfigurace patří —
    /// to je preference, ne stav systému.
    ///
    /// **Po nepovedeném zápisu vyhraje poloha, o kterou si člověk řekl** (poznámka 181): tichý
    /// návrat do vypnuté polohy vypadá, jako by kliknutí nedošlo, a to je horší než věta. Odskok
    /// do Nastavení systému se přitom nabízí **podle stavu, ne podle selhání** — po zákazu
    /// v systému je to další krok bez ohledu na to, jestli se do něj zápis zrovna trefil.
    ///
    /// **Selhání, kterému stav přestal odporovat, se zahazuje tady, ne ve storu.** Jinak by nad
    /// položkou, která se napodruhé zapsat povedla, zůstala viset stará chybová věta — a to je
    /// tentýž druh lži jako přepínač, který se tiše vrátí, jen obrácený. Je to `if` nad daty,
    /// takže patří sem: druhá kopie ve storu by znamenala dvě pravdy o jedné větě.
    static func loginItem(
        availability: LoginItemAvailability,
        status: LoginItemStatus,
        failure: LoginItemFailure?
    ) -> LoginItemRow {
        let standing = failure.flatMap { (status == .enabled) == $0.requested ? nil : $0 }
        return LoginItemRow(
            isOn: standing?.requested ?? (status == .enabled),
            isEnabled: availability.isAvailable,
            note: loginItemNote(availability: availability, status: status, failure: standing),
            offersSystemSettings: availability.isAvailable && status == .requiresApproval
        )
    }

    private static func loginItemNote(
        availability: LoginItemAvailability,
        status: LoginItemStatus,
        failure: LoginItemFailure?
    ) -> String {
        // Nedostupnost je silnější než stav i než selhání: nad zašedlým přepínačem je věta
        // o tom, **proč se s ním nedá cvaknout**, jediná, po které jde něco udělat.
        switch availability {
        case .slotInstance(let name):
            return """
                Tohle je \(name), tedy instance pro paralelní vývoj. Přihlašovací položku zakládá \
                jedině \(MainWindow.title) — jinak by po slotu zůstala v systému věc, kterou \
                bin/slot-cleanup.sh neumí sundat.
                """
        case .outsideApplications(let path):
            return """
                Aplikace běží z \(path). Přihlašovací položka by ukazovala na cestu, která zmizí \
                s dalším buildem — nainstaluj ji do /Applications (dělá to bin/run.sh).
                """
        case .available:
            break
        }
        if let failure { return failure.message }
        switch status {
        case .enabled:
            return """
                \(MainWindow.title) se spustí po přihlášení. Vypnout to jde i v Nastavení systému \
                a je to vidět tady.
                """
        case .requiresApproval:
            return """
                Položka je zapsaná, ale vypnutá v Nastavení systému — aplikace tam nedosáhne.
                """
        case .notFound:
            return """
                Systém přihlašovací položku téhle aplikace nenašel. Bývá to přesunutá nebo \
                rozbitá instalace — přeinstaluj ji do /Applications (dělá to bin/run.sh).
                """
        case .notRegistered:
            return """
                Přes systémovou přihlašovací položku, ne přes vlastní launch agent. Přepínač čte \
                stav ze systému, ne z config.json: kdo si položku vypne v Nastavení systému, má \
                to vidět tady.
                """
        }
    }
}
