import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Že ta dvě pole z #389 v okně **doopravdy jsou** a že se v nich hodnota mění.
///
/// Existuje kvůli jedné mezeře: `SettingsFieldEffectTests` tvrdí, co z hodnoty plyne, ale jde na
/// to přes `SettingsModel` — takže by prošlo i nad stránkou, na které to pole vůbec není nakreslené
/// nebo není napojené na binding. Tady se proto **kreslí**: stránka se vyrendruje se dvěma
/// různými hodnotami a porovnají se bitmapy.
///
/// **Rozdíl bitmap, ne čtení textu**: accessibility tree se v hostovaném okně nenaplní (změřeno
/// u `DashboardCountdownRedrawTests`: `accessibilityChildren` vrací prázdno), takže „je vidět“ se dá
/// tvrdit jedině z pixelů. Tvrzení je slabší (neříká *co* se změnilo), ale to silnější tady
/// neexistuje a nenapojené pole chytá stejně dobře.
///
/// `NSHostingView` v okně, ne `ImageRenderer`: `Form` je `ScrollView`, jehož obsah se offscreen
/// nerasterizuje. Okno se ukazuje **bez animace** (#462).
@MainActor
@Suite("Nastavení — pole z #389 jsou v okně nakreslená")
struct SettingsFieldsRenderTests {
    /// Obsahová část okna nastavení při `minWidth` 720: navigace 210 bodů a dělič 1. Užší
    /// z možných šířek je ta zajímavá — do ní se popisky vejdou nejhůř.
    private static let width: CGFloat = 509
    /// Vyšší než okno: obě sekce jsou až za těmi, které na stránce byly dřív.
    private static let height: CGFloat = 1600

    // MARK: - Text issue z trackeru

    @Test("Jméno nástroje se na stránce Review a skilly kreslí")
    func theToolNameIsDrawn() throws {
        let blank = try render("nastroj-prazdny") { $0.global.issueTextTool = nil }
        let filled = try render("nastroj-vyplneny") {
            $0.global.issueTextTool = "mcp__claude_ai_Linear__get_issue"
        }

        #expect(blank != filled)
    }

    /// Věta pod polem se mění se stavem — jinak by prázdno vypadalo stejně jako vyplněné jméno
    /// a `netahat` by z okna nebylo poznat.
    @Test("Věta pod polem se mění s hodnotou")
    func theNoteChangesWithTheValue() throws {
        let fetching = try render("nastroj-taha-se") {
            $0.global.issueTextTool = "mcp__claude_ai_Linear__get_issue"
        }
        let warned = try render("nastroj-varovani") { $0.global.issueTextTool = "get_issue" }

        #expect(fetching != warned)
    }

    // MARK: - Moje loginy

    @Test("Seznam loginů se na stránce Zdroje PR kreslí")
    func theLoginListIsDrawn() throws {
        let empty = try renderSources("loginy-prazdne", logins: [], viewer: "ondrajodas")
        let filled = try renderSources(
            "loginy-vyplnene",
            logins: ["github-actions[bot]"],
            viewer: "ondrajodas"
        )

        #expect(empty != filled)
    }

    /// Řádek s přihlášeným účtem musí být vidět, a nenačtený viewer se od načteného musí lišit —
    /// je to ten stav, ve kterém je každý pull request cizí.
    @Test("Přihlášený účet je vidět a nenačtený se od načteného liší")
    func theSignedInAccountIsVisible() throws {
        let known = try renderSources("ucet-znamy", logins: [], viewer: "ondrajodas")
        let unknown = try renderSources("ucet-nezjisteny", logins: [], viewer: "")

        #expect(known != unknown)
    }

    // MARK: - Kreslení

    private func render(_ name: String, _ edit: (inout Configuration) -> Void) throws -> Data {
        var configuration = Configuration.standard
        edit(&configuration)
        return try bitmap(name) {
            ReviewSettingsView(settings: SettingsModel(configuration: configuration) { _ in })
        }
    }

    private func renderSources(_ name: String, logins: [String], viewer: String) throws -> Data {
        var configuration = Configuration.standard
        configuration.global.ownLogins = logins
        return try bitmap(name) {
            SourcesSettingsView(
                settings: SettingsModel(configuration: configuration) { _ in },
                viewer: viewer
            )
        }
    }

    /// **Vzhled se nastavuje na svém okně**, ne na `NSApp` (#367) — a `performAsCurrentDrawingAppearance`
    /// je tu proto, že paleta je dynamická `NSColor`.
    ///
    /// - Parameter name: jméno souboru, když je nastavené `PRISM_RENDER_DIR`. Bitmapy jsou tady
    ///   **tvrzení**, ale koukat se na ně je pořád ta jediná cesta, jak si zkontrolovat sazbu —
    ///   proto se dají pustit i na disk, touž cestou jako sondy.
    private func bitmap<Content: View>(_ name: String, _ content: () -> Content) throws -> Data {
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
                let png = try #require(rep.representation(using: .png, properties: [:]))
                if let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] {
                    let url = URL(filePath: directory).appending(path: "nastaveni-\(name).png")
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
}
