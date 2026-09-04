import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Že stránka `Systém` (#529) v okně **doopravdy je** a že se na ní stav pozná.
///
/// Zavírá tutéž mezeru jako `SettingsFieldsRenderTests` u #389: `AppStoreSystemTests` tvrdí, co
/// z hodnoty plyne, ale jde na to přes store — takže by prošly i nad stránkou, na které přepínač
/// vůbec není nakreslený nebo není napojený. Tady se proto **kreslí**.
///
/// **Rozdíl bitmap, ne čtení textu**: accessibility tree se v hostovaném okně nenaplní, takže „je
/// to vidět“ se dá tvrdit jedině z pixelů. Tvrzení je slabší (neříká *co* se změnilo), ale
/// nenapojený přepínač chytá stejně dobře.
///
/// `NSHostingView` v okně, ne `ImageRenderer`: `Form` je `ScrollView`, jehož obsah se offscreen
/// nerasterizuje. Okno se ukazuje **bez animace** (#462).
@MainActor
@Suite("Nastavení — stránka Systém je v okně nakreslená (#529)")
struct SystemSettingsRenderTests {
    /// Obsahová část okna nastavení při `minWidth` 720: navigace 210 bodů a dělič 1. Užší
    /// z možných šířek je ta zajímavá — do ní se popisky vejdou nejhůř.
    private static let width: CGFloat = 509
    /// Vyšší než okno: obě sekce plus věty pod nimi.
    private static let height: CGFloat = 900
    /// Pás s řádkem `Spustit po přihlášení`, v pixelech bitmapy (odshora). Sekce nad ním je
    /// v obou renderech totožná, takže se do pásu nedostane věta, která se u slotu liší — a věta
    /// **pod** řádkem začíná až za jeho spodní hranou.
    private static let toggleBand = 450...540

    /// Hlavní instalace. Cesta se skládá z `MainWindow.title` — viz `LoginItemPolicyTests`.
    private let main = AppInstallation(
        name: MainWindow.title,
        path: "/Applications/\(MainWindow.title).app"
    )
    private let slot = AppInstallation(name: "PRism-d", path: "/Applications/PRism-d.app")

    // MARK: - Odznak v Docku

    /// Volba se musí z okna poznat — jinak by se přepínač dal napsat i tak, že do konfigurace
    /// nepíše, a nic by na to neupozornilo.
    @Test("Vybraný segment je v okně vidět")
    func theSelectedSegmentIsDrawn() throws {
        let waiting = try render("odznak-cekajici", badge: .waiting)
        let off = try render("odznak-nic", badge: .off)

        #expect(waiting != off)
    }

    @Test("Blokující se od čekajících pozná")
    func theBlockingSegmentDiffersFromWaiting() throws {
        let blocking = try render("odznak-blokujici", badge: .blocking)
        let waiting = try render("odznak-cekajici2", badge: .waiting)

        #expect(blocking != waiting)
    }

    // MARK: - Spuštění po přihlášení

    /// **Nejcennější render téhle sady**: zašedlý přepínač u slotové instance. Kdyby se kreslil
    /// jako u hlavní instance, vypadalo by to, že se ve slotu položka zapsat dá — a zjistilo by
    /// se to teprve tím, že v systému zůstane po worktree, který zmizel.
    @Test("Slotová instance kreslí zašedlý přepínač s vlastní větou")
    func theSlotInstanceIsDrawnDisabled() throws {
        let available = try render("spusteni-hlavni", installation: main)
        let disabled = try render("spusteni-slot", installation: slot)

        #expect(available != disabled)
    }

    /// **A že je zašedlý doopravdy zašedlý.** Věta pod přepínačem se u slotu liší, takže rozdíl
    /// bitmap celé stránky by prošel i tehdy, kdyby řádek vypadal jako povolený — proto se
    /// porovnává **jen pás s tím řádkem**, ve kterém je nad ním všechno stejné.
    ///
    /// Bez toho by tvrzení nic neznamenalo: samotné `.disabled(_:)` se v hostovaném okně projeví
    /// jen odstínem přepínače a popiska zůstane plná (proto `SystemSettingsView.disabledOpacity`).
    @Test("Zakázaný řádek je i nakreslený jako zakázaný")
    func theDisabledRowIsDrawnDimmed() throws {
        let available = try render("spusteni-pas-hlavni", installation: main, band: Self.toggleBand)
        let disabled = try render("spusteni-pas-slot", installation: slot, band: Self.toggleBand)

        #expect(available != disabled)
    }

    /// Zapnutá položka se musí poznat od nezapsané, jinak by přepínač, který se nenapojil na stav
    /// systému, vypadal správně.
    @Test("Zapnutá položka se od nezapsané pozná")
    func theEnabledItemDiffersFromTheMissingOne() throws {
        let on = try render("spusteni-zapnuto", status: .enabled)
        let off = try render("spusteni-vypnuto", status: .notRegistered)

        #expect(on != off)
    }

    /// Zákaz v Nastavení systému má **vlastní větu a k tomu tlačítko** — bez rozdílu v bitmapě by
    /// se dal odskok zapomenout nakreslit a stav by zůstal bez dalšího kroku.
    @Test("Zákaz v Nastavení systému kreslí větu i odskok")
    func theApprovalStateDrawsTheJump() throws {
        let approval = try render("spusteni-zakaz", status: .requiresApproval)
        let missing = try render("spusteni-vypnuto2", status: .notRegistered)

        #expect(approval != missing)
    }

    /// Nepovedený zápis musí být vidět — a přepínač u toho zůstává v požadované poloze.
    @Test("Nepovedený zápis je v okně vidět")
    func theFailureIsDrawn() throws {
        let failed = try render("spusteni-chyba", status: .notRegistered, failing: true)
        let clean = try render("spusteni-vypnuto3", status: .notRegistered)

        #expect(failed != clean)
    }

    // MARK: - Kreslení

    private func render(
        _ name: String,
        badge: DockBadgeMode = .waiting,
        installation: AppInstallation? = nil,
        status: LoginItemStatus = .notRegistered,
        failing: Bool = false,
        band: ClosedRange<Int>? = nil
    ) throws -> Data {
        var configuration = Configuration.standard
        configuration.global.dockBadge = badge
        let service = FakeLoginItem(status: status)
        if failing { service.failure = FakeLoginItemError() }
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            time: FakeTimeSource(),
            loginItems: service,
            installation: installation ?? main
        )
        // Nepovedený zápis se do stavu dostane **tou cestou, kterou jde doopravdy** — kliknutím na
        // přepínač, ne přiřazením do pole. Jinak by render tvrdil něco o stavu, který v provozu
        // nevznikne.
        if failing { store.setLoginItem(true) }
        return try bitmap(name, band: band) {
            SystemSettingsView(
                settings: SettingsModel(configuration: configuration) { _ in },
                store: store
            )
        }
    }

    /// **Vzhled se nastavuje na svém okně**, ne na `NSApp` (#367) — a `performAsCurrentDrawingAppearance`
    /// je tu proto, že paleta je dynamická `NSColor`.
    ///
    /// - Parameter name: jméno souboru, když je nastavené `PRISM_RENDER_DIR`. Bitmapy jsou tady
    ///   **tvrzení**, ale koukat se na ně je pořád ta jediná cesta, jak si zkontrolovat sazbu.
    /// - Parameter band: svislý výřez v **pixelech** bitmapy. `nil` = celá stránka. Existuje kvůli
    ///   tvrzení o zašedlém řádku: v pásu je nad porovnávaným řádkem všechno stejné, takže rozdíl
    ///   nemůže přijít z věty, která se u slotu liší.
    private func bitmap<Content: View>(
        _ name: String,
        band: ClosedRange<Int>? = nil,
        _ content: () -> Content
    ) throws -> Data {
        let appearance = try #require(NSAppearance(named: .darkAqua))
        var result: Result<Data, any Error>?
        appearance.performAsCurrentDrawingAppearance {
            do {
                let scene = content()
                    .frame(width: Self.width, height: Self.height)
                    .environment(\.colorScheme, .dark)
                    .tint(Palette.accent)
                let hosting = NSHostingView(rootView: scene)
                hosting.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
                let window = NSWindow(
                    contentRect: hosting.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hosting
                // Mimo obrazovku, ať test nikomu neskočí před oči — v paralelním běhu stojí vedle
                // sebe víc instancí.
                window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
                window.orderFrontUnanimated()
                defer { window.orderOut(nil) }
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                let png = try #require(try Self.png(of: rep, band: band))
                if let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] {
                    let url = URL(filePath: directory).appending(path: "system-\(name).png")
                    try png.write(to: url)
                    print("RENDER \(url.path)")
                }
                result = .success(png)
            } catch {
                result = .failure(error)
            }
        }
        return try #require(result).get()
    }

    /// Bitmapa jako PNG, případně jen její svislý pás.
    private static func png(of rep: NSBitmapImageRep, band: ClosedRange<Int>?) throws -> Data? {
        guard let band else { return rep.representation(using: .png, properties: [:]) }
        let image = try #require(rep.cgImage)
        let cropped = try #require(
            image.cropping(
                to: CGRect(
                    x: 0,
                    y: band.lowerBound,
                    width: image.width,
                    height: band.count
                )
            )
        )
        return NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])
    }
}
