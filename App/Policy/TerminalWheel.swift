import CoreGraphics
import Foundation

/// Hlášení kolečka pro aplikaci běžící v terminálu (#478).
///
/// **Počet je součást hlášení, ne detail odeslání.** Hlášení myši nese jen „kolečko cvaklo“, takže
/// rychlost rolování v aplikaci je dána tím, **kolikrát** se to cvaknutí pošle. Kdyby se posílalo
/// jedno na událost, rolovalo by se v `vi` nebo `htop` o řádek na zatočení, kdežto vlastní historie
/// terminálu jede po `lines` — dvě různé rychlosti v jedné ploše.
struct TerminalWheelReport: Equatable, Sendable {
    /// Číslo tlačítka, jak ho čeká kódování v `xterm`u: `4` nahoru, `5` dolů.
    let button: Int

    /// Kolik hlášení odeslat — tolik řádků, o kolik by se posunula vlastní historie.
    let count: Int
}

extension Policy {
    // MARK: - Kolečko nad plochou terminálu (#478)

    /// Nahoru je `4`, dolů `5` — čísla „tlačítek“ kolečka podle `xterm`u.
    static let terminalWheelUpButton = 4
    static let terminalWheelDownButton = 5

    /// Co poslat aplikaci v terminálu, když se zatočí kolečkem. `nil` = **nehlásit nic** a nechat
    /// knihovnu rolovat vlastní historii.
    ///
    /// **Rozhoduje se při každé události**, ne jednou při vzniku plochy: `mouseMode` je stav
    /// emulátoru, který si mění aplikace pod ním — celoobrazovkové TUI si o myš řekne při startu
    /// a při odchodu ji zase vypne. Proto to sem chodí jako parametr.
    ///
    /// **Nula se nehlásí.** Trackpad umí poslat událost s nulovým posunem (dojezd setrvačnosti)
    /// a hlášení z ní by v aplikaci bylo cvaknutí, které nikdo neudělal.
    static func terminalWheelReport(
        deltaY: CGFloat,
        reportsMouse: Bool,
        rows: Int
    ) -> TerminalWheelReport? {
        guard reportsMouse, deltaY != 0, deltaY.isFinite else { return nil }
        return TerminalWheelReport(
            button: deltaY > 0 ? terminalWheelUpButton : terminalWheelDownButton,
            count: terminalWheelLines(deltaY: deltaY, rows: rows)
        )
    }

    /// O kolik řádků se roluje jedním zatočením.
    ///
    /// **Opsané ze `SwiftTermu`** (`calcScrollingVelocity`, `private`), a je to schválně: hlášení
    /// myši a rolování historie se v jedné ploše střídají podle toho, co zrovna běží, takže dvě
    /// různé křivky by znamenaly, že tatáž otočka kolečka jede v `zsh` jinak rychle než v `claude`.
    /// Když se knihovní křivka změní, rozejde se to — proto na tu shodu existuje test.
    static func terminalWheelLines(deltaY: CGFloat, rows: Int) -> Int {
        let delta = Int(abs(deltaY))
        if delta > 9 { return max(rows, 20) }
        if delta > 5 { return 10 }
        if delta > 1 { return 3 }
        return 1
    }

    // MARK: - Kde výřez zůstane, když přiteče výstup

    /// Kam se výřez zaklesne po zatočení kolečkem. `nil` = **jedeme s výstupem**, jako dosud.
    ///
    /// Existuje proto, že `SwiftTerm` má na tohle vlastní příznak (`Terminal.userScrolling`), ale
    /// **nikdy ho nenastaví** — v `1.11.2` se do něj nepíše z jediného místa, takže každý řádek,
    /// který přiteče, srovná výřez zpátky dolů (`buffer.yDisp = buffer.yBase`). Nad programem,
    /// který si překresluje spodek plochy — tedy nad `claude` —, to znamená, že se odrolovaný
    /// pohled vrátí dřív, než ho stačí kdo přečíst.
    ///
    /// **Dole se nezaklesává**, protože tam je „jet s výstupem“ ta správná odpověď: nový řádek se
    /// má objevit. Zaklesnutí se proto ruší tím, že se člověk vrátí úplně dolů.
    static func terminalViewportPin(row: Int, atBottom: Bool) -> Int? {
        atBottom ? nil : row
    }

    /// O kolik řádků vrátit výřez zpátky nahoru, když ho výstup stáhl dolů. `0` = nedělat nic.
    ///
    /// **Jen dolů se vrací**, nikdy nahoru: výřez nad zaklesnutým řádkem znamená, že se mezitím
    /// rolovalo, a ta poloha je novější než uložená.
    static func terminalViewportRewind(pinned: Int?, current: Int) -> Int {
        guard let pinned, current > pinned else { return 0 }
        return current - pinned
    }
}
