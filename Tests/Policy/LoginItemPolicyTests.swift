import Foundation
import Testing

@testable import PRism

/// Spuštění po přihlášení (#529) — **rozhodnutí o jednom řádku, výčtem**.
///
/// Ten řádek odpovídá na tři otázky naráz (poloha, zašednutí, věta) a odpovědi se křižují:
/// slotová instance, cesta mimo `/Applications`, zákaz v Nastavení systému a nepovedený zápis.
/// Sada je celá o tom, že se z toho nesmí stát přepínač, který **tiše nezabere**.
@Suite("Policy — spuštění po přihlášení (#529)")
struct LoginItemPolicyTests {
    /// Hlavní instalace. Cesta se **skládá z `MainWindow.title`**, ne z literálu, a jsou k tomu dva
    /// důvody: stráž z #411 zakazuje testům jmenovat nainstalovaný bundle hlavní instance (tady je
    /// to jen argument čisté funkce, ale ban je na literál a obcházet ho vlastním zápisem téhož by
    /// bylo horší), a pravidlo „jeden název všude“ říká, že jméno aplikace se v repu píše jednou.
    private let main = AppInstallation(
        name: MainWindow.title,
        path: "/Applications/\(MainWindow.title).app"
    )
    private let slot = AppInstallation(name: "PRism-d", path: "/Applications/PRism-d.app")
    private let built = AppInstallation(
        name: MainWindow.title,
        path: "/Users/kdokoli/Projects/PRism/build.noindex/Build/Products/Debug/PRism.app"
    )

    // MARK: - Která instalace to smí

    @Test("Hlavní instalace v /Applications to smí")
    func allowsTheMainInstallation() {
        #expect(Policy.loginItemAvailability(main) == .available)
    }

    /// **Nejcennější tvrzení téhle sady**: slotová instance přihlašovací položku nenabídne.
    /// `bin/slot-cleanup.sh` o systémových položkách nic neví, takže by po slotu zůstala
    /// v systému věc, kterou nikdo neumí sundat — a bundle, na který ukazuje, mezitím zmizí.
    @Test("Slotová instance to nesmí, i když leží v /Applications")
    func refusesASlotInstance() {
        #expect(Policy.loginItemAvailability(slot) == .slotInstance("PRism-d"))
    }

    /// Instalace mimo `/Applications` je zakázaná z jiného důvodu než slot: cesta zmizí s dalším
    /// buildem. **Tvrzení o systému za tím není změřené** — je z decku, ne z pokusu; tady se
    /// tvrdí jen to, jak se aplikace rozhodne.
    @Test("Bundle mimo /Applications to nesmí")
    func refusesABundleOutsideApplications() {
        #expect(Policy.loginItemAvailability(built) == .outsideApplications(built.path))
    }

    /// Slot se posuzuje **první**, i když padne i na cestě: je to zákaz, který se nedá spravit,
    /// kdežto „nainstaluj to do `/Applications`“ je pokyn, po kterém to půjde. Věta má odpovídat
    /// tomu, co je s tím k dělání.
    @Test("Slot mimo /Applications hlásí slot, ne cestu")
    func prefersTheSlotReasonOverThePath() {
        let both = AppInstallation(name: "PRism-a", path: "/Users/kdokoli/x/PRism-a.app")

        #expect(Policy.loginItemAvailability(both) == .slotInstance("PRism-a"))
    }

    /// Prázdné `CFBundleName` (rozbitý plist) se bere jako **ne**, ne jako hlavní instance. Je to
    /// tatáž bezpečná strana jako u slotu, jen se k ní jde přes chybějící údaj.
    @Test("Bundle bez jména to nesmí")
    func refusesANamelessBundle() {
        let broken = AppInstallation(name: "", path: main.path)

        #expect(Policy.loginItemAvailability(broken) == .slotInstance(""))
    }

    // MARK: - Jak vypadá řádek

    private func row(
        _ installation: AppInstallation,
        status: LoginItemStatus,
        failure: LoginItemFailure? = nil
    ) -> Policy.LoginItemRow {
        Policy.loginItem(
            availability: Policy.loginItemAvailability(installation),
            status: status,
            failure: failure
        )
    }

    /// **Věta je vždycky**, u všech kombinací — přepínač, který nejde cvaknout a neřekne proč, je
    /// k nerozeznání od rozbité aplikace.
    @Test(
        "Věta pod přepínačem není nikdy prázdná",
        arguments: [LoginItemStatus.notRegistered, .enabled, .requiresApproval, .notFound]
    )
    func alwaysExplainsItself(_ status: LoginItemStatus) {
        for installation in [main, slot, built] {
            #expect(!row(installation, status: status).note.isEmpty)
        }
    }

    @Test("Zapsaná a povolená položka drží přepínač zapnutý")
    func showsTheEnabledItemAsOn() {
        let row = row(main, status: .enabled)

        #expect(row.isOn)
        #expect(row.isEnabled)
        #expect(!row.offersSystemSettings)
    }

    @Test("Nezapsaná položka drží přepínač vypnutý")
    func showsAMissingItemAsOff() {
        let row = row(main, status: .notRegistered)

        #expect(!row.isOn)
        #expect(row.isEnabled)
        #expect(!row.offersSystemSettings)
    }

    /// Zákaz v Nastavení systému je **jediný stav s dalším krokem**: `register()` znovu ho
    /// nezvrátí, takže odskok je to jediné, co se dá nabídnout (vzor z #414). Přepínač je u toho
    /// vypnutý, protože se aplikace po přihlášení doopravdy nespustí.
    @Test("Zákaz v Nastavení systému nabídne odskok")
    func offersTheSystemSettingsJumpAfterAnApproval() {
        let row = row(main, status: .requiresApproval)

        #expect(!row.isOn)
        #expect(row.isEnabled)
        #expect(row.offersSystemSettings)
        #expect(row.note.contains("Nastavení systému"))
    }

    /// Odskok se nabízí **jen tam, kde je to další krok** — ne u zašedlého přepínače, se kterým
    /// v Nastavení systému nikdo nic neudělá.
    @Test("Nedostupná instalace odskok nenabídne", arguments: [LoginItemStatus.requiresApproval, .enabled])
    func offersNoJumpForAnUnavailableInstallation(_ status: LoginItemStatus) {
        #expect(!row(slot, status: status).offersSystemSettings)
        #expect(!row(built, status: status).offersSystemSettings)
    }

    @Test("Zašedlý přepínač u slotu vysvětlí, že položku zakládá jedině PRism")
    func explainsTheSlotInstance() {
        let row = row(slot, status: .notRegistered)

        #expect(!row.isEnabled)
        #expect(row.note.contains("PRism-d"))
        #expect(row.note.contains("slot-cleanup.sh"))
    }

    @Test("Zašedlý přepínač mimo /Applications vypíše cestu a další krok")
    func explainsTheBundleOutsideApplications() {
        let row = row(built, status: .notRegistered)

        #expect(!row.isEnabled)
        #expect(row.note.contains(built.path))
        #expect(row.note.contains("/Applications"))
    }

    // MARK: - Nepovedený zápis

    /// **Přepínač se po selhání nesmí tiše vrátit** (poznámka 181 v návrhu): vypadalo by to, jako
    /// by kliknutí nedošlo. Drží se tedy poloha, o kterou si člověk řekl, a k ní věta.
    @Test("Po nepovedeném zápisu zůstane přepínač v požadované poloze")
    func keepsTheRequestedPositionAfterAFailedWrite() {
        let failure = LoginItemFailure(requested: true, message: "Nepovedlo se to. Nemáš práva.")
        let row = row(main, status: .notRegistered, failure: failure)

        #expect(row.isOn)
        #expect(row.note == failure.message)
    }

    /// A totéž opačným směrem: nepovedené **odebrání** nesmí přepínač skokem zapnout.
    @Test("Nepovedené odebrání drží přepínač vypnutý")
    func keepsTheOffPositionAfterAFailedRemoval() {
        let failure = LoginItemFailure(requested: false, message: "Nepovedlo se to.")
        let row = row(main, status: .enabled, failure: failure)

        #expect(!row.isOn)
        #expect(row.note == failure.message)
    }

    /// **Věta o selhání zmizí sama, jak jí stav systému přestane odporovat.** Bez toho by nad
    /// položkou, která se napodruhé zapsat povedla, zůstala viset stará chyba — a to je tentýž
    /// druh lži jako přepínač, který se tiše vrátí, jen obrácený.
    @Test("Selhání, kterému stav přestal odporovat, se zahodí")
    func dropsAFailureTheStatusNoLongerContradicts() {
        let failure = LoginItemFailure(requested: true, message: "stará chyba")
        let row = row(main, status: .enabled, failure: failure)

        #expect(row.isOn)
        #expect(row.note != failure.message)
        #expect(row.note.contains("po přihlášení"))
    }

    /// Nedostupnost je **silnější než selhání**: nad zašedlým přepínačem je věta o tom, proč se
    /// s ním nedá cvaknout, jediná, po které jde něco udělat.
    @Test("U nedostupné instalace vyhraje důvod nedostupnosti")
    func prefersTheUnavailableReasonOverAFailure() {
        let failure = LoginItemFailure(requested: true, message: "stará chyba")

        #expect(row(slot, status: .notRegistered, failure: failure).note.contains("PRism-d"))
        #expect(row(built, status: .notRegistered, failure: failure).note.contains(built.path))
    }

    // MARK: - Adresa panelu

    /// Adresa panelu je jediné, co se na odskoku dá pokazit — a **bez parametru s aplikací**, ze
    /// stejného důvodu jako u notifikací (#414): parametr, který se změní s verzí systému,
    /// znamená odkaz, který jednoho dne otevře prázdno.
    @Test("Odskok míří na panel Položky při přihlášení")
    func pointsAtTheLoginItemsPane() throws {
        let url = try #require(SystemSettings.loginItems)

        #expect(url.scheme == "x-apple.systempreferences")
        #expect(url.absoluteString == "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        #expect(url.query == nil)
    }
}
