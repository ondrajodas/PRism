import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Že pole a sekce z #389 a #532 v okně **doopravdy jsou** a že se v nich hodnota mění.
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
@Suite("Nastavení — pole z #389 a sekce z #532 jsou v okně nakreslené")
struct SettingsFieldsRenderTests {
    /// Obsahová část okna nastavení při `minWidth` 720: navigace 210 bodů a dělič 1. Užší
    /// z možných šířek je ta zajímavá — do ní se popisky vejdou nejhůř.
    private static let width: CGFloat = 509
    /// Vyšší než okno: nové sekce jsou až za těmi, které na stránce byly dřív.
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
    func theLoginListIsDrawn() async throws {
        let empty = try await renderSources("loginy-prazdne", logins: [], viewer: "ondrajodas")
        let filled = try await renderSources(
            "loginy-vyplnene",
            logins: ["github-actions[bot]"],
            viewer: "ondrajodas"
        )

        #expect(empty != filled)
    }

    /// Řádek s přihlášeným účtem musí být vidět, a nenačtený viewer se od načteného musí lišit —
    /// je to ten stav, ve kterém je každý pull request cizí.
    @Test("Přihlášený účet je vidět a nenačtený se od načteného liší")
    func theSignedInAccountIsVisible() async throws {
        let known = try await renderSources("ucet-znamy", logins: [], viewer: "ondrajodas")
        let unknown = try await renderSources("ucet-nezjisteny", logins: [], viewer: "")

        #expect(known != unknown)
    }

    // MARK: - Organizace k prohledávání (#532)

    /// Že sekce v okně **doopravdy je** a je napojená na konfiguraci. Bez tohohle by prošla
    /// i stránka, na které se `searchOrganizations` nikde nekreslí — a nastavení by se dalo
    /// napsat jedině ručně do souboru, tedy přesně ten stav, ze kterého #389 sekce vyváděl.
    @Test("Seznam organizací se na stránce Zdroje PR kreslí")
    func theOrganizationListIsDrawn() async throws {
        let empty = try await renderSources("organizace-prazdne", logins: [], viewer: "ondrajodas")
        let filled = try await renderSources(
            "organizace-vyplnene",
            logins: [],
            viewer: "ondrajodas",
            organizations: ["keboola"]
        )

        #expect(empty != filled)
    }

    /// Nedotažená a dotažená organizace **se od sebe musí poznat** — jinak by `zatím nenačteno`
    /// vypadalo stejně jako `412 rep · obnoveno 7:58` a z okna by nebylo poznat, jestli cache je.
    @Test("Dotažený katalog se od nedotaženého v okně liší")
    func theFetchedCatalogLooksDifferent() async throws {
        let pending = try await renderSources(
            "organizace-nenacteno",
            logins: [],
            viewer: "ondrajodas",
            organizations: ["keboola"]
        )
        let loaded = try await renderSources(
            "organizace-nactene",
            logins: [],
            viewer: "ondrajodas",
            organizations: ["keboola", "ondrajodas"],
            catalog: ["keboola": 412, "ondrajodas": 37]
        )

        #expect(pending != loaded)
    }

    /// **Věta u řádku je jediné, co organizaci bez přístupu odlišuje od organizace bez repozitářů**
    /// — obojí je jinak prázdný seznam. Text je skutečná hláška `gh repo list` na neznámé jméno.
    @Test("Nedostupná organizace má u řádku větu")
    func theFailureSentenceIsDrawn() async throws {
        let ok = try await renderSources(
            "organizace-bez-chyby",
            logins: [],
            viewer: "ondrajodas",
            organizations: ["keboola"],
            catalog: ["keboola": 412]
        )
        let failed = try await renderSources(
            "organizace-chyba",
            logins: [],
            viewer: "ondrajodas",
            organizations: ["keboola", "tajna-organizace"],
            catalog: ["keboola": 412],
            failing: [
                "tajna-organizace":
                    "the owner handle \"tajna-organizace\" was not recognized as either a GitHub user or an organization"
            ]
        )

        #expect(ok != failed)
    }

    // MARK: - Kreslení

    private func render(_ name: String, _ edit: (inout Configuration) -> Void) throws -> Data {
        var configuration = Configuration.standard
        edit(&configuration)
        return try bitmap(name) {
            ReviewSettingsView(settings: SettingsModel(configuration: configuration) { _ in })
        }
    }

    /// - Parameter catalog: kolik rep má která organizace v cache. Prázdná mapa = nic dotaženého,
    ///   tedy stav `zatím nenačteno`.
    private func renderSources(
        _ name: String,
        logins: [String],
        viewer: String,
        organizations: [String] = [],
        catalog snapshots: [String: Int] = [:],
        failing: [String: String] = [:]
    ) async throws -> Data {
        var configuration = Configuration.standard
        configuration.global.ownLogins = logins
        configuration.global.searchOrganizations = organizations
        let catalog = await catalog(snapshots, failing: failing)
        return try bitmap(name) {
            SourcesSettingsView(
                settings: SettingsModel(configuration: configuration) { _ in },
                viewer: viewer,
                catalog: catalog,
                time: FakeTimeSource()
            )
        }
    }

    /// Katalog, ve kterém už něco leží — přes fake gateway, tedy touž cestou, jakou se plní
    /// doopravdy. Míří do dočasné složky (drží ji suite), takže render nesáhne na skutečnou cache.
    private func catalog(
        _ snapshots: [String: Int],
        failing: [String: String] = [:]
    ) async -> RepositoryCatalog {
        let gateway = FakeGitHubGateway(always: .success([]))
        for (organization, message) in failing {
            gateway.organizationFailures[organization] = GitHubError.commandFailed(
                exitCode: 1,
                message: message
            )
        }
        for (organization, count) in snapshots {
            gateway.organizationRepositories[organization] = OrganizationRepositories(
                repositories: (0..<count).map {
                    OrganizationRepository(
                        repo: RepoID(owner: organization, name: "r\($0)"),
                        openPullRequests: $0 % 5,
                        lastPushedAt: nil
                    )
                },
                hitLimit: false
            )
        }
        let catalog = RepositoryCatalog(
            gateway: gateway,
            store: RepositoryCatalogStore(layout: CacheLayout(root: workspace.url)),
            time: FakeTimeSource()
        )
        await catalog.refresh(organizations: Set(snapshots.keys).union(failing.keys).sorted())
        return catalog
    }

    /// Dočasná cache pro katalog v renderu. `TemporaryDirectory` se maže v `deinit`, takže se
    /// musí držet po celý test.
    private let workspace = try! TemporaryDirectory()

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
