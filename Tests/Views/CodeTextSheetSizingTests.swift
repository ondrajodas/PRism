import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Velikost sheetu s kódem: **otevře se v ideální šířce, je roztahovatelný a velikost si pamatuje
/// zvlášť pro hunk a zvlášť pro log** (#417).
///
/// Testuje se to nad **skutečným oknem sheetu**, ne nad hodnotami v `Policy`, protože zrovna tady
/// rozhoduje SwiftUI a jeho chování se z dokumentace přečíst nedalo. Tři věci, které se bez tohohle
/// testu rozbijí potichu:
///
/// - **Bez `presentationSizing(.fitted)` se `idealWidth` zahodí** a sheet je široký jako `minWidth`
///   — tedy 560 místo 1 180 u hunku a 1 360 u logu, ať je okno za ním jak chce velké. Přesně takhle
///   byl sheet do #417, a proto v něm log měl 66 znaků na řádek, z nichž 29 sní timestamp.
/// - **Sheet se rozvrhuje dvakrát a v prvním průchodu má podlahu** (#327). Zápis velikosti bez
///   odmlky by proto při každém otevření uložil podlahu a od druhého otevření by se sheet otevíral
///   nejmenší možný — tedy zpátky do té vady, kterou #417 opravuje.
/// - **Jeden klíč pro obě velikosti** by znamenal, že roztažený log otevírá takhle i hunk o devíti
///   řádcích. To je ten test, který tvrdí, že se něco **nestalo**.
///
/// **`UserDefaults` procesu se nepoužívá, a je to tvrdá podmínka, ne zdvořilost** (#367):
/// `@AppStorage` dostane **v každém testu** vlastní suite přes `defaultAppStorage(_:)`, protože
/// testovací host má bundle ID **hlavní instance** (slotová přípona vzniká až v `bin/run.sh`, ne při
/// buildu). Zápis odsud by tedy šel do nastavení, které uživatel doopravdy používá. Suite se na
/// konci maže.
@Suite("Velikost sheetu s kódem v okně", .serialized)
@MainActor
struct CodeTextSheetSizingTests {
    /// Kolik se čeká na to, že se **nic** neuloží. Odmlka ve view plus rezerva — a bere se z té
    /// odmlky, aby se ta hodnota v repu nerozdvojila.
    private var beyondSettling: Duration { CodeTextSheet.resizeSettle * 3 }

    // MARK: - Roztahovatelnost

    @Test("Sheet má tažný okraj a podlahu svého profilu", arguments: [CodeText.Kind.hunk, .log])
    func theSheetIsResizable(kind: CodeText.Kind) async throws {
        let store = try scratchStore()
        defer { UserDefaults().removePersistentDomain(forName: Self.suite) }

        let scene = try await open(kind: kind, store: store)
        defer { scene.close() }

        let floor = Policy.codeSheetSizing(kind: kind, screen: NSScreen.main?.visibleFrame.size).floor
        #expect(
            scene.sheet.styleMask.contains(.resizable),
            "Sheet nemá `.resizable`, takže se nedá roztáhnout — styleMask \(scene.sheet.styleMask.rawValue)."
        )
        #expect(scene.sheet.contentMinSize.width == floor.width)
        #expect(scene.sheet.contentMinSize.height == floor.height)
    }

    /// Ideální šířka se **uplatní**. Bez `presentationSizing(.fitted)` by tady u obou druhů stálo
    /// číslo podlahy.
    @Test("Bez uložené velikosti se sheet otevře v ideální šířce", arguments: [CodeText.Kind.hunk, .log])
    func opensAtTheIdealWidth(kind: CodeText.Kind) async throws {
        let store = try scratchStore()
        defer { UserDefaults().removePersistentDomain(forName: Self.suite) }

        let scene = try await open(kind: kind, store: store)
        defer { scene.close() }

        let expected = Policy.codeSheetSizing(kind: kind, screen: NSScreen.main?.visibleFrame.size).ideal
        try await scene.wait(forWidth: expected.width)
        #expect(scene.sheet.frame.width == expected.width)
        #expect(scene.sheet.frame.width > Policy.codeSheetHunkFloor.width, "Sheet zůstal v podlaze.")
    }

    // MARK: - Pamatování

    /// Tažení okrajem AppKit provádí `setFrame`em na okně sheetu, takže se dá napodobit — a je to
    /// jediná cesta, jak tažení v testu vyvolat (syntetické myší události se k tomu nedostanou,
    /// změřeno u #358).
    @Test("Natažená velikost se uloží a příští otevření ji vezme")
    func remembersTheDraggedSize() async throws {
        let store = try scratchStore()
        defer { UserDefaults().removePersistentDomain(forName: Self.suite) }

        let first = try await open(kind: .hunk, store: store)
        let opened = first.sheet.frame
        let dragged = CGSize(
            width: max(opened.width - 180, Policy.codeSheetHunkFloor.width),
            height: max(opened.height - 90, Policy.codeSheetHunkFloor.height)
        )
        first.drag(to: dragged)
        // Čeká se **na tu hodnotu**, ne na „něco se zapsalo“ (#269): mezi průchody rozvržení může
        // v nastavení chvíli ležet jiné číslo.
        let stored = await waitUntil("velikost se uložila") {
            store.double(forKey: CodeTextSheet.StorageKey.hunkWidth) == dragged.width.rounded()
                && store.double(forKey: CodeTextSheet.StorageKey.hunkHeight) == dragged.height.rounded()
        }
        #expect(stored, """
            V nastavení leží \(store.double(forKey: CodeTextSheet.StorageKey.hunkWidth)) × \
            \(store.double(forKey: CodeTextSheet.StorageKey.hunkHeight)) místo \(dragged).
            """)
        first.close()

        let second = try await open(kind: .hunk, store: store)
        defer { second.close() }
        try await second.wait(forWidth: dragged.width.rounded())
        #expect(second.sheet.frame.width == dragged.width.rounded())
    }

    /// **Dva klíče, a je to podmínka, ne pohodlí.** Roztažený log nesmí otevírat takhle i hunk
    /// o devíti řádcích — a naopak stažený hunk nesmí zúžit log.
    @Test("Hunk nezdědí velikost natažená u logu")
    func keepsTheTwoProfilesApart() async throws {
        let store = try scratchStore()
        defer { UserDefaults().removePersistentDomain(forName: Self.suite) }

        let log = try await open(kind: .log, store: store)
        let widened = CGSize(width: log.sheet.frame.width - 240, height: log.sheet.frame.height - 60)
        log.drag(to: widened)
        let stored = await waitUntil("velikost logu se uložila") {
            store.double(forKey: CodeTextSheet.StorageKey.logWidth) == widened.width.rounded()
        }
        #expect(stored, "Velikost logu se neuložila, takže tvrzení níž nic neznamená.")
        log.close()

        let hunk = try await open(kind: .hunk, store: store)
        defer { hunk.close() }

        let ideal = Policy.codeSheetSizing(kind: .hunk, screen: NSScreen.main?.visibleFrame.size).ideal
        try await hunk.wait(forWidth: ideal.width)
        #expect(
            hunk.sheet.frame.width == ideal.width,
            "Hunk se otevřel na \(hunk.sheet.frame.width) — vzal si velikost logu."
        )
        #expect(store.object(forKey: CodeTextSheet.StorageKey.hunkWidth) == nil)
    }

    /// **Otevřít a zavřít není volba velikosti.** Kdyby se zapisoval každý naměřený rozměr, uložil
    /// by se první průchod rozvržení — tedy podlaha — a sheet by se od druhého otevření otevíral
    /// nejmenší možný.
    @Test("Otevření bez tažení neuloží nic", arguments: [CodeText.Kind.hunk, .log])
    func openingAloneStoresNothing(kind: CodeText.Kind) async throws {
        let store = try scratchStore()
        defer { UserDefaults().removePersistentDomain(forName: Self.suite) }

        let scene = try await open(kind: kind, store: store)
        let ideal = Policy.codeSheetSizing(kind: kind, screen: NSScreen.main?.visibleFrame.size).ideal
        try await scene.wait(forWidth: ideal.width)
        try await Task.sleep(for: beyondSettling)
        scene.close()

        for key in [
            CodeTextSheet.StorageKey.hunkWidth, CodeTextSheet.StorageKey.hunkHeight,
            CodeTextSheet.StorageKey.logWidth, CodeTextSheet.StorageKey.logHeight,
        ] {
            #expect(store.object(forKey: key) == nil, "Uložilo se `\(key)`, o které nikdo nežádal.")
        }
    }

    // MARK: - Písmo, ze kterého se počítá kapacita řádku

    /// Kapacita řádku se počítá z odsazení a `lineFragmentPadding`u — **obojí se tedy musí potkat se
    /// skutečným textovým view**, jinak patička tvrdí jiný počet zalomených řádků, než kolik je
    /// vidět. `lineFragmentPadding` není naše volba, je to default TextKitu.
    @Test("Odsazení a padding v Policy sedí s textovým view")
    func theMathMatchesTheTextView() throws {
        // **Plocha z aplikace, ne její kopie** (#303): staví ji tatáž továrnička, kterou jde
        // `makeNSView`.
        let scroll = SelectableCodeView.makeScrollView()
        let textView = try #require(scroll.documentView as? NSTextView)

        #expect(textView.textContainerInset.width == Policy.codeSheetTextInset)
        #expect(textView.textContainer?.lineFragmentPadding == Policy.codeSheetFragmentPadding)
        #expect(SelectableCodeView.characterWidth == SelectableCodeView.font.maximumAdvancement.width)
    }

    // MARK: - Scéna

    private static let suite = "cz.prism.tests.codeSheetSizing"

    /// Kam se postaví hostitelské okno — pod dolní hranu **té obrazovky, ze které si sheet počítá
    /// ideál**. Viz `open(kind:store:)`.
    private static var origin: NSPoint {
        guard let main = NSScreen.main else { return NSPoint(x: -10_000, y: -10_000) }
        return NSPoint(x: main.visibleFrame.minX, y: main.visibleFrame.minY - 10_000)
    }

    private func content(kind: CodeText.Kind) -> CodeText {
        switch kind {
        case .hunk:
            CodeText(
                kind: .hunk,
                id: "src/Vault/SecretClient.php#@@ -78,9 +78,21 @@",
                title: CodeSheetText.hunkTitle(path: "src/Vault/SecretClient.php"),
                slug: CodeSheetText.hunkSlug(header: "@@ -78,9 +78,21 @@", subject: "keboola/vault#412"),
                note: CodeSheetText.hunkNote(code: "    return $row['value'] ?? '';\n"),
                path: "src/Vault/SecretClient.php",
                code: "    return $row['value'] ?? '';\n",
                link: nil
            )
        case .log:
            CodeText(
                kind: .log,
                id: "log:phpstan (level 8)",
                title: CodeSheetText.logTitle(check: "phpstan (level 8)"),
                slug: CodeSheetText.logSlug(
                    JobLog(
                        text: "2026-08-23T21:09:45.9930712Z  [ERROR] Found 2 errors",
                        lineCount: 1,
                        byteCount: 55,
                        fetchedAt: Date(timeIntervalSince1970: 1_787_000_000)
                    ),
                    subject: "keboola/vault#412"
                ),
                note: CodeSheetText.logNote(outcome: .failed, duration: 134, at: Date()),
                path: nil,
                code: "2026-08-23T21:09:45.9930712Z  [ERROR] Found 2 errors",
                link: URL(string: "https://github.com/keboola/vault/actions/runs/1/job/2")
            )
        }
    }

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
    /// Okno je za dolní hranou obrazovky a je **užší, než jak se sheet otevírá**, aby bylo vidět, že
    /// o šířce nerozhoduje okno za ním.
    ///
    /// **Umisťuje se podle `NSScreen.main`, ne „daleko od všeho“, a je to podmínka na stroji s dvěma
    /// displeji** (změřeno): sheet se kreslí na obrazovce **hostitelského okna** a AppKit ho na ni
    /// **ořízne**, kdežto `CodeTextSheet` si ideál počítá z `NSScreen.main` — tedy z obrazovky
    /// s klávesovým oknem. S origin `(-10 000, -10 000)` skončilo okno na notebooku (1 512 b),
    /// zatímco `NSScreen.main` byl externí monitor (3 440 b), takže sheet o šířku 2 700 požádal
    /// a dostal 1 512. Test pak měřil **ořez**, ne aplikaci — a rozdíl proti požadované velikosti
    /// vypadal jako tažení, takže se uložil. V aplikaci ta situace nenastane: sheet vyjede nad
    /// klávesovým oknem, tedy na téže obrazovce, ze které se ideál počítal.
    private func open(kind: CodeText.Kind, store: UserDefaults) async throws -> Scene {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: Host(content: content(kind: kind), store: store))
        window.setFrameOrigin(Self.origin)
        window.orderFront(nil)

        let attached = await waitUntil("sheet se otevřel") { window.attachedSheet != nil }
        #expect(attached, "Sheet se v okně neotevřel.")
        return Scene(window: window, sheet: try #require(window.attachedSheet))
    }

    /// Hostitel, který sheet otevře sám — `CodeTextSheet` se prezentuje stejně jako v aplikaci
    /// (`sheet(item:)` v diffu i v detailu PR), takže se měří ta cesta, kterou kód doopravdy jde.
    ///
    /// Vlastní `UserDefaults` se nasazují **na obsah sheetu**, ne na hostitele: sheet je vlastní
    /// prezentace a spoléhat na to, že se do ní environment protáhne, by znamenalo testovat SwiftUI
    /// místo aplikace.
    private struct Host: View {
        let content: CodeText
        let store: UserDefaults
        @State private var open = true

        var body: some View {
            Color.clear
                .frame(width: 1_000, height: 700)
                .sheet(isPresented: $open) {
                    CodeTextSheet(content: content).defaultAppStorage(store)
                }
        }
    }
}
