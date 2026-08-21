import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#278): **přepne vzhled za běhu** nad složenou hierarchií a kouká, co se stane.
///
/// Odpovídá na tu jedinou otázku, kterou se z kódu přečíst nedá — jestli se obě cesty k barvám
/// pohnou naráz. `Palette` se ptá `appearance.bestMatch(from:)` v uzávěru dynamického `NSColor`,
/// kdežto obarvení kódu jde přes `@Environment(\.colorScheme)`. Kdyby `NSApp.appearance` hýbal jen
/// jednou z nich, vznikne okno s tmavým chromem a světlým kódem.
///
/// Kreslí se **skutečný blok diffu** (`DiffBlockRowView` → `NSTextView`), takže to není otázka na
/// pozadí okna: co se v PNG mění, je i obarvená syntaxe. Cache obarvení je klíčovaná podpisem, ve
/// kterém režim je (`DiffBlockSignature`), takže by ji přepnutí muselo minout — a to je zrovna to,
/// co se dá pokazit potichu.
///
/// **Přepíná se na vlastním okně, ne na `NSApp`** (#367). Do té doby to šlo přes `NSApp.appearance`
/// a vracelo se `defer`em — jenže to je jedna hodnota na celý proces, takže ta vynucená tma
/// přetékala do všeho, co v tu chvíli kreslilo, a hostitel testů si ji navíc **sám přepisuje** (živý
/// store uplatní volbu z konfigurace asi 300 ms po startu, změřeno). Okno je vlastní, takže vynucený
/// režim nikoho jiného nezastihne a **z kódu je vidět, jaký režim se měří** — ne jaký zdědil stroj.
/// Odpověď se tím nemění: `NSApp.appearance` se k barvám dostane tou samou cestou, tedy skrz
/// efektivní vzhled okna, na které se kreslí.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda přepnutí vzhledu (#278)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct AppearanceSwitchProbe {
    /// Kam si view zapíše režim, ve kterém ho SwiftUI zrovna kreslí.
    @MainActor
    private final class Observed {
        var schemes: [ColorScheme] = []
    }

    /// Hlásí režim z prostředí — tedy tu cestu, na které visí obarvení kódu.
    private struct SchemeReporter: View {
        let observed: Observed
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            Text(verbatim: colorScheme == .dark ? "tmavý" : "světlý")
                .font(.caption)
                .foregroundStyle(Palette.ink2)
                .onChange(of: colorScheme, initial: true) { observed.schemes.append(colorScheme) }
        }
    }

    @Test("Přepnutí vzhledu okna pohne chromem i kódem")
    func switchesBothPathsAtOnce() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())

        let observed = Observed()
        let hosting = NSHostingView(rootView: scene(observed: observed))
        let window = offscreenWindow(for: hosting)
        defer { window.orderOut(nil) }

        // Vynucený světlý, ať sonda nezávisí na tom, jak je nastavený systém — bez toho by na
        // tmavém stroji „změnilo se to“ znamenalo pravdu i tehdy, kdyby se nic nepřepnulo.
        window.appearance = try #require(AppearanceMode.light.nsAppearance)
        let light = try capture(hosting, to: directory.appending(path: "prepnuti-svetly.png"))
        #expect(observed.schemes.last == .light)

        window.appearance = try #require(AppearanceMode.dark.nsAppearance)
        let dark = try capture(hosting, to: directory.appending(path: "prepnuti-tmavy.png"))

        // Prostředí SwiftUI se pohnulo — na tomhle visí `SyntaxPalette.forScheme(_:)`.
        #expect(observed.schemes.last == .dark)
        // A okno se doopravdy překreslilo, ne jen změnilo hodnotu ve stavu.
        #expect(light != dark)
        print("SONDA \(directory.appending(path: "prepnuti-svetly.png").path)")
        print("SONDA \(directory.appending(path: "prepnuti-tmavy.png").path)")
    }

    /// Blok kódu, hlavička a pár barev z palety — dohromady to, co je v okně nad diffem vidět.
    private func scene(observed: Observed) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SchemeReporter(observed: observed)
            DiffBlockRowView(block: Self.block, language: Language(path: "Cart.swift"))
        }
        .padding(12)
        .frame(width: 520, alignment: .topLeading)
        .background(Palette.surface)
    }

    private func offscreenWindow(for hosting: NSHostingView<some View>) -> NSWindow {
        hosting.frame = NSRect(x: 0, y: 0, width: 520, height: hosting.fittingSize.height)
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
        return window
    }

    /// Nechá proběhnout runloop (hierarchie se doskládá i překreslí až za ním) a vezme bitmapu.
    private func capture(_ hosting: NSHostingView<some View>, to url: URL) throws -> Data {
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        hosting.frame.size.height = hosting.fittingSize.height
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
        return data
    }

    private static let block = DiffBlock(lines: [
        DiffLine(kind: .context, oldNumber: 12, newNumber: 12, text: "func total(of items: [Item]) -> Int {"),
        DiffLine(kind: .removed, oldNumber: 13, newNumber: nil, text: "    return items.count // starý součet"),
        DiffLine(kind: .added, oldNumber: nil, newNumber: 13, text: "    return items.reduce(0) { $0 + $1.price }"),
        DiffLine(kind: .context, oldNumber: 14, newNumber: 14, text: "}"),
    ])
}
