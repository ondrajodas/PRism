import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Že tlačítko `Otevřít v <editoru>` (#530) v okně **doopravdy je** — a že se **bez zvoleného
/// editoru nekreslí**.
///
/// Druhá půlka je to podstatné: „nekreslí se, ne zašedle“ je tvrzení o tom, co na obrazovce
/// **není**, a takové se rozbije potichu. Nad `EditorActions` samotným se ověřit nedá — `nil`
/// v modelu ještě neznamená, že se view zachovalo správně.
///
/// **Rozdíl bitmap, ne čtení textu**: accessibility tree se v hostovaném okně nenaplní (změřeno
/// u `DashboardCountdownRedrawTests`), takže „je vidět“ se dá tvrdit jedině z pixelů. Tatáž cesta
/// i tytéž meze jako u `SettingsFieldsRenderTests`; okno se ukazuje **bez animace** (#462).
@MainActor
@Suite("Tlačítko Otevřít v editoru se kreslí, jen když je editor zvolený (#530)")
struct EditorButtonRenderTests {
    private static let width: CGFloat = 720

    private var actions: EditorActions {
        EditorActions(
            title: Policy.openInEditorTitle(.cursor),
            note: Policy.editorNote(.cursor, ownership: .mine),
            open: { _, _ in }
        )
    }

    // MARK: - Hlavička souboru

    @Test("V hlavičce souboru tlačítko přibude, jen když je editor zvolený")
    func theHeaderButtonAppearsWithAnEditor() throws {
        let without = try bitmap("hlavicka-bez-editoru", height: 40) { header(editor: nil) }
        let with = try bitmap("hlavicka-s-editorem", height: 40) { header(editor: actions) }

        #expect(without != with)
    }

    // MARK: - Karta nálezu

    /// Karta je ta obrazovka, kvůli které #530 vzniklo — z nálezu se skáče do kódu, aby se opravil.
    @Test("Na kartě nálezu tlačítko přibude, jen když je editor zvolený")
    func theCardButtonAppearsWithAnEditor() throws {
        let without = try bitmap("karta-bez-editoru", width: 300, height: 120) { card(editor: nil) }
        let with = try bitmap("karta-s-editorem", width: 300, height: 120) { card(editor: actions) }

        #expect(without != with)
    }

    /// **Nález bez souboru tlačítko nedostane ani se zvoleným editorem**: otevřít se nemá co, a
    /// tlačítko, které by ohlásilo „soubor v kopii není“, by slibovalo akci, která nikdy nevyjde.
    @Test("Nález bez souboru tlačítko nedostane ani se zvoleným editorem")
    func aFindingWithoutAFileGetsNoButton() throws {
        let without = try bitmap("karta-bez-souboru-bez-editoru", width: 300, height: 120) {
            card(editor: nil, file: nil)
        }
        let with = try bitmap("karta-bez-souboru-s-editorem", width: 300, height: 120) {
            card(editor: actions, file: nil)
        }

        #expect(without == with)
    }

    // MARK: - Nastavení

    /// Že volba `Otevírat soubory v` na stránce `Systém` **je nakreslená a napojená na binding** —
    /// bez toho by se dala nastavit jedině ručně v `config.json`.
    @Test("Volba editoru se na stránce Systém kreslí")
    func theEditorChoiceIsDrawnInSettings() throws {
        let none = try settings(editor: nil, name: "nastaveni-editor-nic")
        let cursor = try settings(editor: .cursor, name: "nastaveni-editor-cursor")

        #expect(none != cursor)
    }

    // MARK: - Scény

    private func header(editor: EditorActions?) -> some View {
        DiffFileHeaderView(
            file: Self.file,
            isFolded: false,
            findings: [],
            blockingCategories: [],
            toggle: {},
            editor: editor
        )
    }

    private func card(editor: EditorActions?, file: String? = "src/Vault/SecretClient.php") -> some View {
        let finding = Finding(
            reported: ReportedFinding(
                file: file,
                line: file == nil ? nil : 81,
                category: "correctness",
                verdict: .confirmed,
                shortSummary: nil,
                summary: "`?? ''` schová chybějící secret jako prázdnou hodnotu",
                failureScenario: nil
            ),
            reviewer: "php-review",
            headSha: "aaaa1111"
        )
        let row = FindingRow.rows(of: [finding])[0]
        return FindingCardView(row: row, editor: editor, jump: {}).padding(10)
    }

    private func settings(editor: ExternalEditor?, name: String) throws -> Data {
        var configuration = Configuration.standard
        configuration.global.externalEditor = editor
        let model = SettingsModel(configuration: configuration) { _ in }
        return try bitmap(name, width: 509, height: 900) {
            SystemSettingsView(
                settings: model,
                store: AppStore(
                    gateway: FakeGitHubGateway(always: .success([])),
                    configuration: configuration,
                    time: FakeTimeSource()
                )
            )
        }
    }

    private static let file = FileDiff(
        oldPath: "src/Vault/SecretClient.php",
        newPath: "src/Vault/SecretClient.php",
        change: .modified,
        isBinary: false,
        hunks: []
    )

    /// **Vzhled se nastavuje na svém okně**, ne na `NSApp` (#367). Tatáž cesta jako
    /// u `SettingsFieldsRenderTests` — bitmapa je tvrzení, ale dá se pustit i na disk.
    private func bitmap<Content: View>(
        _ name: String,
        width: CGFloat = EditorButtonRenderTests.width,
        height: CGFloat,
        _ content: () -> Content
    ) throws -> Data {
        let appearance = try #require(NSAppearance(named: .darkAqua))
        var result: Result<Data, any Error>?
        appearance.performAsCurrentDrawingAppearance {
            do {
                let scene = content()
                    .frame(width: width, height: height)
                    .environment(\.colorScheme, .dark)
                    .tint(Palette.accent)
                    .background(Palette.surface)
                let hosting = NSHostingView(rootView: scene)
                hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
                let window = NSWindow(
                    contentRect: hosting.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hosting
                window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
                window.orderFrontUnanimated()
                defer { window.orderOut(nil) }
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                if let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] {
                    let url = URL(filePath: directory).appending(path: "editor-\(name).png")
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
