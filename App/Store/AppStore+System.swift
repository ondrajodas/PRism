import Foundation
import Observation

/// Systém kolem okna (#529) — odznak v Docku a spuštění po přihlášení.
///
/// Obojí sahá **mimo okno**, takže obojí patří do storu a ne do view: dlaždice v Docku je vidět
/// zrovna tehdy, když se do aplikace nikdo nedívá, a přihlašovací položka žije v systému i po
/// zavření okna. Kreslení ani zápis do systému ale store nedělá sám — obojí jde přes protokol
/// (`DockBadgeApplying`, `LoginItemControlling`), aby `App/Store/` nemusel na AppKit ani na
/// `ServiceManagement` vidět a aby na to testy sáhly fakem.
extension AppStore {

    // MARK: - Odznak v Docku (#529)

    /// Co má stát na dlaždici. `nil` = prázdná dlaždice.
    ///
    /// **Tatáž množina jako odznak fronty v railu** (`railQueueCount`), tedy cizí PR **po
    /// filtru** — a `nil`, dokud tik neprošel. Kdyby si blokující číslo bralo ze souhrnu fronty
    /// (`queueSummary`), který filtr ignoruje, umělo by přepnutí volby ukázat **větší** číslo:
    /// invariant „blokující ≤ čekající“ drží jedině nad jednou množinou. Rozhoduje
    /// `Policy.dockBadge`.
    var dockBadgeLabel: String? {
        Policy.dockBadge(
            configuration.global.dockBadge,
            queue: lastSuccess == nil ? nil : visibleQueuePullRequests,
            isBlocking: hasBlockingFinding(_:)
        )
    }

    /// Nasadí odznak a **přihlásí se o další změnu**.
    ///
    /// Volá se **jednou, ze složení storu**, a dál se drží sám: `withObservationTracking` je
    /// jednorázové, takže se z `onChange` zapíše nové kolo. Je to jediná konstrukce, u které se
    /// nedá zapomenout na místo, které tu hodnotu mění — a těch je sedm jen u uložených nálezů
    /// (`reviewRecords`), k tomu tik, filtr a konfigurace. Rozeseté `refreshDockBadge()` by byla
    /// přesně ta „kontrola, která jinde v repu je, a tady chybí“.
    ///
    /// **Nevyrábí to smyčku**: `applyBadge` je zápis do dlaždice, ne do sledovaného stavu, a zápis
    /// téže hodnoty toolchain nehlásí (pinuje to `PollObservationTests`), takže tichý tik odznak
    /// neprobudí. Přiřazuje se **bezpodmínečně** — viz `DockBadgeTile`.
    ///
    /// **Ve výchozí volbě se nesleduje ani mapa nálezů**: `Policy.dockBadge` se u `waiting`
    /// a `off` na `isBlocking` nezavolá, takže se `reviewRecords` v tom průchodu vůbec nepřečtou.
    ///
    /// **Bez cíle nedělá nic** (`dock == nil`, tedy v testech, které si o odznak neřekly). Odznak
    /// je globální stav procesu, a to je zrovna ta třída, která v tomhle repu pětkrát vyrobila
    /// falešný test — po skončení běhu by navíc zůstal viset v Docku hostitele.
    func trackDockBadge() {
        guard let dock else { return }
        let label = withObservationTracking {
            dockBadgeLabel
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackDockBadge() }
        }
        dock.applyBadge(label)
    }

    // MARK: - Spuštění po přihlášení (#529)

    /// Jak vypadá řádek `Spustit po přihlášení` na stránce `Systém`.
    ///
    /// Poloha se bere **ze systému**, ne z `config.json`: přihlašovací položka je stav systému,
    /// takže druhá kopie v konfiguraci by po ručním vypnutí v Nastavení systému ukazovala v okně
    /// opak toho, co platí. Rozhoduje `Policy.loginItem`.
    var loginItem: Policy.LoginItemRow {
        Policy.loginItem(
            availability: Policy.loginItemAvailability(installation),
            status: loginItemStatus,
            failure: loginItemFailure
        )
    }

    /// Přečte stav ze systému. Volá to stránka `Systém` při každém zobrazení — vypnout položku
    /// jde i v Nastavení systému a přepínač, který o tom neví, tvrdí opak.
    ///
    /// **Jen čtení, nikdy zápis**, takže se to smí pustit i ve slotové instanci: `status` se ptá,
    /// `register()` zakládá. Cesta k zápisu je jedna a je zavřená (`setLoginItem`).
    func refreshLoginItem() {
        guard let loginItems else { return }
        loginItemStatus = loginItems.status
    }

    /// Zapíše nebo odebere přihlašovací položku.
    ///
    /// **Nedostupná instalace se sem nedostane, a rozhoduje se to tady, ne zašedlým přepínačem ve
    /// view** — view je jedna cesta a stačí přidat druhou (zkratka, paleta, test), aby ochrana
    /// zmizela. Zašedlý přepínač zůstává, ale je to **popis**, ne stráž.
    ///
    /// **Selhání se nespolkne a přepínač se sám nevrátí** (poznámka 181 v návrhu): drží se
    /// i poloha, o kterou si člověk řekl, protože tichý návrat do vypnuté polohy vypadá, jako by
    /// kliknutí nedošlo. Věta zmizí sama, jak jí stav systému přestane odporovat — rozhoduje
    /// o tom `Policy.loginItem`.
    func setLoginItem(_ on: Bool) {
        guard Policy.loginItemAvailability(installation).isAvailable else { return }
        guard let loginItems else { return }
        do {
            if on {
                try loginItems.register()
            } else {
                try loginItems.unregister()
            }
            loginItemFailure = nil
        } catch {
            loginItemFailure = LoginItemFailure(
                requested: on,
                message: """
                    Přihlašovací položku se nepodařilo \(on ? "zapsat" : "odebrat"). \
                    \(error.localizedDescription)
                    """
            )
        }
        // **Až po pokusu, a v obou případech**: co se doopravdy stalo, ví jedině systém —
        // `register()`, který nespadl, umí skončit stavem `requiresApproval`.
        loginItemStatus = loginItems.status
    }
}
