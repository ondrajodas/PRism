import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#278): vykreslí stránku `Vzhled` přes `NSHostingView`, aby se dala **vidět**.
///
/// Je tu ze dvou důvodů. Za prvé stránku nese `Form` se `.formStyle(.grouped)`, tedy AppKitová
/// tabulka — a ta se v `ImageRenderer`u nevykreslí vůbec (viz `docs/testovani.md`), takže jinak než
/// takhle se na ni podívat nedá. Za druhé se na ní rozhodovalo mezi **radio groupem
/// a segmentovaným přepínačem**; obojí se dá odsud vyrendrovat i přeměřit — stačí ve
/// `AppearanceSettingsView` prohodit `pickerStyle`.
///
/// Kreslí se v **obou režimech** a ve dvou šířkách: nejužší stránka nastavení (okno 720 minus
/// navigace 210) a ta při výchozí velikosti (880 minus 210).
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes
/// `TEST_RUNNER_PRISM_RENDER_DIR` — `xcodebuild` posílá do testovacího procesu jen proměnné
/// s tímhle prefixem, bez něj se suita tiše přeskočí.
@MainActor
@Suite(
    "Sonda vzhledu (#278)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct AppearanceRenderProbe {
    private let widths: [CGFloat] = [509, 669]

    @Test("Vyrendrovat stránku Vzhled do PNG")
    func rendersTheAppearancePage() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
        for width in widths {
            for dark in [false, true] {
                let url = directory.appending(path: "vzhled-\(Int(width))-\(dark ? "tmavy" : "svetly").png")
                try write(width: width, dark: dark, to: url)
                print("SONDA \(url.path)")
            }
        }
    }

    /// Kolik místa si který styl přepínače vezme — `fittingSize`, tedy to, o co si prvek řekne
    /// bez ohledu na to, jak široké je zrovna okno.
    ///
    /// Naměřeno **110 bodů u radio groupu a 330 u segmentovaného**. Ta stovka je za svislý sloupec
    /// tří voleb, který formulář v řádku rozloží vodorovně, takže v okně je rozdíl menší než
    /// trojnásobek — a hlavně se vejdou oba, i na nejužší stránce nastavení. Šířka tedy volbu
    /// prvku nerozhodla; rozhodla shoda se stránkou `Diff`, viz komentář u `pickerStyle`.
    @Test("Změřit šířku obou stylů přepínače")
    func measuresBothPickerStyles() {
        for (name, width) in [("radioGroup", fittingWidth(.radioGroup)), ("segmented", fittingWidth(.segmented))] {
            print("SONDA \(name) šířka \(width)")
        }
    }

    private func fittingWidth(_ style: some PickerStyle) -> CGFloat {
        let picker = Picker("Vzhled okna", selection: .constant(AppearanceMode.system)) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                Text(verbatim: mode.displayName).tag(mode)
            }
        }
        .pickerStyle(style)
        .labelsHidden()

        return NSHostingView(rootView: picker).fittingSize.width
    }

    /// **Barevný režim se nastavuje dvakrát**: `NSAppearance` kvůli paletě (dynamické `NSColor`)
    /// a `colorScheme` kvůli `.primary`/`.secondary`. S jedním z toho vyjde tmavý text na tmavém.
    private func write(width: CGFloat, dark: Bool, to url: URL) throws {
        var configuration = Configuration.standard
        configuration.global.appearance = dark ? .dark : .light
        let settings = SettingsModel(configuration: configuration) { _ in }
        let scene = AppearanceSettingsView(settings: settings)
            .frame(width: width, height: 260, alignment: .topLeading)
            .environment(\.colorScheme, dark ? .dark : .light)

        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var thrown: Error?
        appearance.performAsCurrentDrawingAppearance {
            do {
                try capture(scene, width: width, to: url)
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako u `Přehledu`
    /// (#291) a u bloku kódu (#236).
    private func capture(_ scene: some View, width: CGFloat, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: hosting.fittingSize.height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — v paralelním běhu stojí vedle sebe víc
        // instancí a cizí okno je poslední, co má sonda rušit.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        // Hierarchie se doskládá až po jednom kole smyčky, takže se výška bere znovu až za ní.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        hosting.frame.size.height = hosting.fittingSize.height
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }
}
