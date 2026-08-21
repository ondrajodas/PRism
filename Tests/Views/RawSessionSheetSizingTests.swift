import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Velikost sheetu s přepisem: **je roztahovatelný, otevře se v ideální šířce a velikost si pamatuje**
/// (#327 follow-up).
///
/// Testuje se to nad **skutečným oknem sheetu**, ne nad hodnotami v `Policy`, protože zrovna tady
/// rozhoduje SwiftUI a jeho chování se z dokumentace přečíst nedalo. Dvě věci, které tenhle test
/// změřil a bez kterých by změna vypadala hotová:
///
/// - **Bez `presentationSizing(.fitted)` se `idealWidth` zahodí** a sheet je široký jako `minWidth`
///   — tedy 720 místo nakreslených 940, ať je okno za ním jak chce velké (změřeno i s oknem 2 000
///   bodů). Tak byl sheet do téhle změny, a proto vypadal moc úzký.
/// - **Sheet se rozvrhuje dvakrát a v prvním průchodu má podlahu.** Zápis velikosti bez odmlky by
///   proto při každém otevření uložil 720×420 a od druhého otevření by se sheet otevíral nejmenší
///   možný. To je ten test, který tvrdí, že se něco **nestalo**.
///
/// **`UserDefaults` procesu se nepoužívá, a je to tady tvrdá podmínka, ne zdvořilost** (#367):
/// `@AppStorage` dostane **v každém testu** vlastní suite přes `defaultAppStorage(_:)`, protože
/// testovací host má bundle ID **hlavní instance** (slotová přípona vzniká až v `bin/run.sh`, ne při
/// buildu). Zápis odsud tedy jde do nastavení, které uživatel doopravdy používá — a jednou už tak
/// skončil: uložená velikost z jednoho běhu shodila tenhle test v tom příštím a `SlotCleanupTests`
/// nahlásily, že se změnil plist hlavní instance. Suite se na konci maže.
@Suite("Velikost sheetu s přepisem", .serialized)
@MainActor
struct RawSessionSheetSizingTests {
    private let target = RawSessionTarget(
        sessionID: "4b90c7e2-1d55-4f0a-9c3e-77b0a2e41d6f",
        worktree: URL(filePath: "/tmp/cache/worktrees/keboola/connection-php-client/412-9c1de02"),
        skill: "security-review",
        slug: "keboola/connection-php-client#412"
    )

    /// Kolik se čeká na to, že se **nic** neuloží. Odmlka ve view plus rezerva — a bere se z té
    /// odmlky, aby se ta hodnota v repu nerozdvojila.
    private var beyondSettling: Duration { RawSessionSheet.resizeSettle * 3 }

    // MARK: - Roztahovatelnost

    @Test("Sheet má tažný okraj a podlahu z Policy")
    func theSheetIsResizable() async throws {
        let store = try scratchStore()
        defer { UserDefaults().removePersistentDomain(forName: Self.suite) }

        let scene = try await open(store: store)
        defer { scene.close() }

        #expect(
            scene.sheet.styleMask.contains(.resizable),
            "Sheet nemá `.resizable`, takže se nedá roztáhnout — styleMask \(scene.sheet.styleMask.rawValue)."
        )
        #expect(scene.sheet.contentMinSize.width == Policy.rawSessionSheetMinWidth)
        #expect(scene.sheet.contentMinSize.height == Policy.rawSessionSheetMinHeight)
    }

    /// Ideální šířka se **uplatní**. Bez `presentationSizing(.fitted)` by tady stálo 720.
    @Test("Bez uložené velikosti se sheet otevře v ideální šířce")
    func opensAtTheIdealWidth() async throws {
        let store = try scratchStore()
        defer { UserDefaults().removePersistentDomain(forName: Self.suite) }

        let scene = try await open(store: store)
        defer { scene.close() }

        let expected = Policy.rawSessionSheetSize(
            storedWidth: 0,
            storedHeight: 0,
            screen: NSScreen.main?.visibleFrame.size
        )
        try await scene.wait(forWidth: expected.width)
        #expect(scene.sheet.frame.width == expected.width)
    }

    // MARK: - Pamatování

    /// Tažení okrajem AppKit provádí `setFrame`em na okně sheetu, takže se dá napodobit — a je to
    /// jediná cesta, jak tažení v testu vyvolat (syntetické myší události se k tomu nedostanou,
    /// změřeno u #358).
    @Test("Natažená velikost se uloží a příští otevření ji vezme")
    func remembersTheDraggedSize() async throws {
        let store = try scratchStore()
        defer { UserDefaults().removePersistentDomain(forName: Self.suite) }

        let first = try await open(store: store)
        let opened = first.sheet.frame
        let dragged = CGSize(
            width: max(opened.width - 180, Policy.rawSessionSheetMinWidth),
            height: max(opened.height - 90, Policy.rawSessionSheetMinHeight)
        )
        first.drag(to: dragged)
        // Čeká se **na tu hodnotu**, ne na „něco se zapsalo“ (#269): mezi průchody rozvržení může
        // v nastavení chvíli ležet jiné číslo, takže „> 0“ by test uzavřel dřív, než se tažení
        // usadí — a padal by na hodnotě, která se o chvíli později srovná.
        let stored = await waitUntil("velikost se uložila") {
            store.double(forKey: "rawSessionSheetWidth") == dragged.width.rounded()
                && store.double(forKey: "rawSessionSheetHeight") == dragged.height.rounded()
        }
        let found = CGSize(
            width: store.double(forKey: "rawSessionSheetWidth"),
            height: store.double(forKey: "rawSessionSheetHeight")
        )
        #expect(stored, "V nastavení leží \(found) místo \(dragged).")
        first.close()

        let second = try await open(store: store)
        defer { second.close() }
        try await second.wait(forWidth: dragged.width.rounded())
        #expect(second.sheet.frame.width == dragged.width.rounded())
    }

    /// **Otevřít a zavřít není volba velikosti.** Kdyby se zapisoval každý naměřený rozměr, uložil
    /// by se první průchod rozvržení — tedy podlaha — a sheet by se od druhého otevření otevíral
    /// nejmenší možný.
    @Test("Otevření bez tažení neuloží nic")
    func openingAloneStoresNothing() async throws {
        let store = try scratchStore()
        defer { UserDefaults().removePersistentDomain(forName: Self.suite) }

        let scene = try await open(store: store)
        let expected = Policy.rawSessionSheetSize(
            storedWidth: 0,
            storedHeight: 0,
            screen: NSScreen.main?.visibleFrame.size
        )
        try await scene.wait(forWidth: expected.width)
        try await Task.sleep(for: beyondSettling)
        scene.close()

        #expect(store.object(forKey: "rawSessionSheetWidth") == nil, "Uložila se šířka, o kterou nikdo nežádal.")
        #expect(store.object(forKey: "rawSessionSheetHeight") == nil, "Uložila se výška, o kterou nikdo nežádal.")
    }

    // MARK: - Scéna

    private static let suite = "cz.prism.tests.rawSessionSheetSizing"

    /// Prázdná suita pro `@AppStorage`. **Maže se cizí instancí**, ne tou vrácenou: instance, která
    /// si smaže vlastní doménu, si ji odebere i z prohledávaného seznamu a hodnoty pak nedrží.
    private func scratchStore() throws -> UserDefaults {
        UserDefaults().removePersistentDomain(forName: Self.suite)
        return try #require(UserDefaults(suiteName: Self.suite))
    }

    /// Okno s otevřeným sheetem. Drží se v něm i hostitelské okno, aby ho nikdo neuklidil dřív, než
    /// se doměří.
    @MainActor
    private struct Scene {
        let window: NSWindow
        let sheet: NSWindow

        /// Napodobí tažení okrajem: velikost okna sheetu se mění zvenčí, přesně jak to dělá AppKit.
        func drag(to size: CGSize) {
            sheet.setFrame(
                NSRect(x: sheet.frame.origin.x, y: sheet.frame.origin.y, width: size.width, height: size.height),
                display: true
            )
        }

        func wait(forWidth width: CGFloat) async throws {
            let reached = await waitUntil("sheet je \(width) bodů široký") { sheet.frame.width == width }
            #expect(reached, "Sheet zůstal \(sheet.frame.width) bodů široký místo \(width).")
        }

        func close() {
            window.endSheet(sheet)
            window.orderOut(nil)
        }
    }

    /// Postaví okno, otevře v něm sheet a počká, až ho AppKit připojí.
    ///
    /// Okno je **mimo obrazovku**, jako u ostatních sond v `Tests/Views/` — sheet se má změřit, ne
    /// ukázat.
    private func open(store: UserDefaults) async throws -> Scene {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: Host(target: target, store: store))
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)

        let attached = await waitUntil("sheet se otevřel") { window.attachedSheet != nil }
        #expect(attached, "Sheet se v okně neotevřel.")
        return Scene(window: window, sheet: try #require(window.attachedSheet))
    }

    /// Hostitel, který sheet otevře sám — `RawSessionSheet` se prezentuje stejně jako v aplikaci
    /// (`sheet(item:)` v detailu PR), takže se měří ta cesta, kterou kód doopravdy jde.
    ///
    /// Vlastní `UserDefaults` se nasazují **na obsah sheetu**, ne na hostitele: sheet je vlastní
    /// prezentace a spoléhat na to, že se do ní environment protáhne, by znamenalo testovat SwiftUI
    /// místo aplikace.
    private struct Host: View {
        let target: RawSessionTarget
        let store: UserDefaults
        @State private var open = true

        var body: some View {
            Color.clear
                .frame(width: 1_000, height: 700)
                .sheet(isPresented: $open) { sheet }
        }

        private var sheet: some View {
            RawSessionSheet(
                target: target,
                state: .loading,
                growth: nil,
                path: URL(filePath: "/tmp/\(target.sessionID).jsonl"),
                reload: {},
                refreshSize: {}
            )
            .defaultAppStorage(store)
        }
    }
}
