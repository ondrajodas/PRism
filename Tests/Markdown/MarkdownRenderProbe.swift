import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#279): vyrendruje sazbu Markdownu offscreen do PNG, aby se dala **vidět**.
///
/// Existuje proto, že u sazby je otázka „jak to vypadá“ a ta se z `#expect` nedozví. Skutečné okno
/// na to nestačí: komentář od bota s výstrahou musí být zrovna na PR, které je ve frontě. Fixture
/// je proti tomu vždycky po ruce a render je deterministický.
///
/// **Oba režimy naráz.** Barvy palety jsou `NSColor` s dynamickým providerem, takže se řídí
/// `NSAppearance.currentDrawingAppearance`, ne prostředím SwiftUI — a `colorScheme` v prostředí
/// zase řídí `.primary` a `.secondary`. Nastavit se proto musí **obojí**; s jedním z toho vyjde
/// tmavý text na tmavém podkladu a vypadá to jako chyba v sazbě.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@Suite(
    "Sonda sazby Markdownu (#279)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct MarkdownRenderProbe {
    /// Ukázka, na které je vidět všechno, co #279 mění: šest úrovní nadpisů, citace s nadpisem
    /// a zaškrtávátkem, vnořená citace, pět druhů výstrahy, **neznámý** druh a inline kód.
    private let sample = """
        # Nadpis první úrovně
        ## Nadpis druhé úrovně
        ### Třetí
        #### Čtvrtá
        ##### Pátá
        ###### Šestá

        Odstavec s **tučným**, `inline kódem` a [odkazem](https://github.com).

        > citace od kolegy
        > ## nadpis v citaci
        > - [ ] a zaškrtávátko
        >
        > > vnořená citace

        > [!NOTE]
        > Poznámka.

        > [!TIP]
        > Rada.

        > [!IMPORTANT]
        > ## Review skipped
        >
        > - [ ] 🔍 Trigger review

        > [!WARNING]
        > Upozornění — nesmí splynout se zastaráním.

        > [!CAUTION]
        > Pozor — nesmí splynout s blokujícím nálezem.

        > [!NEZNÁMÉ]
        > Neznámý druh zůstane citací.
        """

    @MainActor
    @Test("Vyrendrovat sazbu do PNG")
    func rendersSamples() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
        let bot = try Fixture.text("gh/comment-coderabbit.md")

        for (name, text) in [("ukazka", sample), ("bot", bot)] {
            for dark in [false, true] {
                let url = directory.appending(path: "markdown-\(name)-\(dark ? "tmavy" : "svetly").png")
                try write(text, dark: dark, to: url)
                print("SONDA \(url.path)")
            }
        }
    }

    @MainActor
    private func write(_ text: String, dark: Bool, to url: URL) throws {
        let width: CGFloat = 420
        // Odsazení se musí **odečíst z předávané šířky**, jako to dělají skutečná volající views
        // (`narrowingWidth(by:)` před `padding`em). Bez toho sazba věří, že má celých 420 bodů,
        // a v renderu přeteče vpravo mimo obrázek — vypadá to jako chyba v sazbě, a přitom je
        // v sondě.
        let content = MarkdownText(text: text, size: 12.5)
            .narrowingWidth(by: 24)
            .padding(12)
            .frame(width: width, alignment: .leading)
            .availableWidth(width)
            .background(Palette.chrome)
            .environment(\.colorScheme, dark ? .dark : .light)

        var image: NSImage?
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            image = renderer.nsImage
        }

        let rendered = try #require(image)
        let data = try #require(rendered.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(data.representation(using: .png, properties: [:])).write(to: url)
    }
}
