import AppKit

/// Kdo umí napsat na dlaždici v Docku (#529).
///
/// Protokol je tu ze **stejného důvodu jako `AppearanceApplying`** (#278): živý cíl je `NSApp`,
/// což je v testech hostitel testů. Odznak je globální stav procesu, tedy zrovna ta třída, která
/// v tomhle repu už pětkrát vyrobila falešně červený `main` (#367 vzhled, #411 `UserDefaults`,
/// #462 okno s animací, #490 `CGEvent`, #550 stráže nad surovým textem) — a odznak by k tomu
/// zůstal viset v Docku i po skončení běhu.
@MainActor
protocol DockBadgeApplying: AnyObject {
    /// `nil` = prázdná dlaždice, tedy ikona bez odznaku. Zvlášť od prázdného řetězce se to
    /// rozlišovat nemusí — `Policy.dockBadge` prázdný řetězec nevydá —, ale kresba na něj sáhne
    /// stejně jako na `nil`, protože odznak bez číslice netvrdí nic.
    func applyBadge(_ label: String?)
}

/// Odznak se nastavuje **dlaždici aplikace**, ne oknu — a proto to nemůže dělat view.
///
/// Celý smysl odznaku je, že je vidět, když se do aplikace nikdo nedívá. Ve view by se hodnota
/// uplatnila jedině tehdy, když je okno na obrazovce, tedy právě tehdy, kdy odznak nikdo
/// nepotřebuje.
///
/// **`badgeLabel` se tady nepoužívá, a je to změřená slepá ulička, ne opomenutí** (#529):
/// nasadit ho jde, přečíst zpátky taky, jenže Dock ho u aplikace, která si o `.badge`
/// v `requestAuthorization` neřekla, **potichu zahodí**. Odznak si proto kreslíme sami do
/// `contentView` (`DockBadgeTileView`) — jediná cesta, kterou to číslo doopravdy jde vidět, a
/// jediná, o které jde tvrdit test. Hlídá to `DockBadgeWiringTests`, čísla jsou
/// v [`docs/testovani.md`](../../docs/testovani.md).
///
/// **Přiřazuje se bezpodmínečně, i když se hodnota nezměnila**, ze stejného důvodu jako u vzhledu:
/// podmínka „jen když se to změnilo“ by byla druhé místo, kde se o odznaku rozhoduje, výměnou za
/// nic — je to jedno přiřazení a jedno překreslení dlaždice.
extension NSApplication: DockBadgeApplying {
    func applyBadge(_ label: String?) {
        guard let label, !label.isEmpty else {
            // **Vlastní kresbu je potřeba sundat, ne jen vyprázdnit** — `contentView`, který
            // kreslí ikonu bez odznaku, sice vypadá stejně, ale nechal by dlaždici napořád
            // v naší režii včetně toho, čím ji systém kreslí jinak (třeba průběh při stahování).
            dockTile.contentView = nil
            dockTile.display()
            return
        }
        // **Ikona se čte při každém nasazení**, ne jednou při složení: mění ji `bin/make-icon.swift`,
        // takže je to jediná hodnota, ze které se dá poznat, že kreslíme právě tu ikonu, kterou má
        // bundle teď.
        //
        // **Bez ikony se dlaždice nepřebírá, a to je vědomá výměna**: `contentView` kresbu dlaždice
        // **nahrazuje**, takže bychom místo ikony s odznakem nakreslili prázdno — a zmizelá ikona
        // je horší než chybějící odznak. Radši tedy o odznak přijít; systémová kresba zůstane.
        guard let icon = applicationIconImage else {
            dockTile.contentView = nil
            dockTile.display()
            return
        }
        let tile = dockTile.contentView as? DockBadgeTileView ?? DockBadgeTileView()
        tile.icon = icon
        tile.label = label
        if dockTile.contentView !== tile {
            dockTile.contentView = tile
        }
        // Bez tohohle se dlaždice překreslí až při nějaké další příležitosti — změna `label` sama
        // Dock nebudí, protože kresbu drží náš view, ne systém.
        dockTile.display()
    }
}

/// Živý cíl pro `AppStore`.
///
/// Existuje proto, aby `App/Store/` nemusel importovat AppKit: store o odznaku rozhoduje (má
/// frontu i konfiguraci), ale kreslení není jeho práce. Hlídá to `DockBadgeWiringTests`.
enum DockBadgeTile {
    @MainActor static var application: any DockBadgeApplying { NSApplication.shared }
}
