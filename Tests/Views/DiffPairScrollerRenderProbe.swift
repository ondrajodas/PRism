import AppKit
import Testing

@testable import PRism

/// **Jak pruh v bloku dvojic doopravdy vypadá** — sonda, ne test: bez `PRISM_RENDER_DIR` nedělá nic.
///
/// Existuje proto, že `DiffPairScrollerTests` měří **čísla** (šířka dokumentu, pás výšky) a na
/// otázku „nelže knob o tom, kolik obsahu je?“ číslo neodpoví tak, aby se to poznalo na první pohled.
///
/// **Dvě podmínky, bez kterých z bitmapy vyjde průhledno** (změřeno u #422 — a přesně na to naráží
/// poznámka v `docs/testovani.md`, že „offscreen render na pruh nedosáhne“): blok musí být
/// v **okně** (mimo obrazovku, protože vedle běží aplikace, kterou nemá co rušit) a plochám se musí
/// pro render **zapnout pozadí** — v aplikaci ho kreslí obal ve SwiftUI, takže bez něj v obrázku
/// není ani text, ani pruh. `CGWindowListCreateImage` na tohle použít nejde, je na macOS 26
/// nedostupné.
///
/// Legacy scroller si vynucuje `DiffPairScrollView` sám, takže na náladě systémového nastavení
/// posuvníků sonda nezávisí.
///
/// Proměnná se předává **s prefixem `TEST_RUNNER_`** — jen ten `xcodebuild` do testovacího procesu
/// pustí; bez něj sonda **tiše nenakreslí nic**:
///
/// ```bash
/// TEST_RUNNER_PRISM_RENDER_DIR=/tmp/render \
///     xcodebuild … test -only-testing:PRismTests/DiffPairScrollerRenderProbe
/// ```
@MainActor
@Suite("Kresba pruhu v bloku dvojic")
struct DiffPairScrollerRenderProbe {
    private static let gutter = DiffLineView.contentInset(for: .split)

    private func line(_ text: String, _ number: Int) -> DiffLine? {
        DiffLine(kind: .context, oldNumber: number, newNumber: number, text: text)
    }

    /// Blok jako v hlášení k #422: třináct řádků, vlevo převážně šrafování, vpravo dlouhé cesty.
    private var reported: DiffPairBlock {
        let right: [DiffLine?] = (1...13).map {
            line("RUN curl --fail --silent --show-error --no-interactive https://downloads.cloudera.com/cdh/\($0)/parcels.tar.gz", $0)
        }
        var left: [DiffLine?] = Array(repeating: nil, count: 13)
        left[4] = line("RUN yum install -y curl", 1)
        left[5] = line("RUN yum clean all", 2)
        left[9] = line("USER root", 3)
        return DiffPairBlock(left: left, right: right)
    }

    @Test("Blok z hlášení, blok s dlouhou jednou stranou a krátký blok")
    func drawTheReportedBlocks() throws {
        guard let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] else { return }

        let cases: [(name: String, block: DiffPairBlock)] = [
            ("hlaseni-sraf-vlevo", reported),
            (
                "vlevo-nic-vpravo-dlouhy",
                DiffPairBlock(
                    left: Array(repeating: nil, count: 4),
                    right: (1...4).map { line("let veryLongIdentifierName\($0) = configuration.resolvedValue(for: .some)", $0) }
                )
            ),
            (
                "kratky-blok",
                DiffPairBlock(
                    left: (1...3).map { line("let x = \($0)", $0) },
                    right: (1...3).map { line("let y = \($0)", $0) }
                )
            ),
        ]

        for item in cases {
            let container = DiffPairBlockContainer()
            container.show(
                item.block,
                style: DiffBlockStyle(language: Language(path: "Dockerfile"), colorScheme: .light),
                gutter: Self.gutter
            )
            let width = 900.0
            let height = container.height(forWidth: width)
            container.frame = NSRect(x: 0, y: 0, width: width, height: height)

            // Pozadí pod blok, ať se v kresbě pozná, kde má hranu — v aplikaci ho kreslí obal ve
            // SwiftUI, takže bez něj by render ukazoval jinou věc než okno.
            let backdrop = NSView(frame: container.frame)
            backdrop.wantsLayer = true
            backdrop.layer?.backgroundColor = NSColor(Palette.raised).cgColor
            backdrop.addSubview(container)

            let window = NSWindow(
                contentRect: backdrop.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = backdrop
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            backdrop.layoutSubtreeIfNeeded()

            let scrollers = container.subviews.compactMap { $0 as? DiffPairScrollView }
                .sorted { $0.frame.minX < $1.frame.minX }
            let report = scrollers.map { scroll -> String in
                let document = (scroll.documentView?.frame.width).map(Double.init) ?? 0
                let pane = Double(scroll.contentSize.width)
                let hidden = scroll.horizontalScroller?.isHidden ?? true
                // **`knobProportion` je to číslo z hlášení**: knob velikosti vlasu znamená, že plocha
                // tvrdí mnohonásobek obsahu, který v půlce je.
                let knob = scroll.horizontalScroller?.knobProportion ?? 0
                return "dokument \(document) / okýnko \(pane), pruh \(hidden ? "ne" : "ano"), knob \(knob)"
            }
            print("MĚŘENÍ \(item.name): výška \(height); " + report.joined(separator: "; "))

            let name = "dvojice-\(item.name).png"
            do {
                try write(backdrop, scrollers: scrollers, to: URL(filePath: directory).appending(path: name))
                print("MĚŘENÍ kresba → \(name)")
            } catch {
                // Selhání dumpu sondu nepokládá, ale mlčet se nesmí: „render se neuložil“ nesmí být
                // k nerozeznání od „nespustil jsem ho“.
                print("MĚŘENÍ kresba \(name) se neuložila: \(error.localizedDescription)")
            }
        }
    }

    /// Kresba bloku do PNG. **Plochám se na render zapne pozadí**, i když ho v aplikaci kreslí obal
    /// ve SwiftUI: bez něj z `cacheDisplay` vyjde průhledno bez textu i bez pruhu (změřeno u #422),
    /// takže by sonda ukazovala něco jiného než okno.
    ///
    /// **Samotný pruh v obrázku nebude, a je to změřené** — ne opomenutí: legacy scroller nevydá ani
    /// `cacheDisplay` nad plochou, ani `cacheDisplay` nad `NSScroller`em samotným, takže v tom pásu
    /// zůstane prázdno. Vidět je jedině na okně **na obrazovce** (`screencapture -l`, tak se u #422
    /// měřily jeho body). Odsud se posoudí to, co v obrázku je: šrafování, zarovnání řádků, ořez na
    /// hraně okýnka a rezervovaný pás; o knobu vypovídá `knobProportion` ve výpisu.
    private func write(_ view: NSView, scrollers: [DiffPairScrollView], to url: URL) throws {
        struct RenderFailed: LocalizedError {
            let errorDescription: String?
        }
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw RenderFailed(errorDescription: "blok nevydal bitmapu pro \(view.bounds)")
        }
        for scroll in scrollers {
            scroll.drawsBackground = true
            scroll.backgroundColor = NSColor(Palette.raised)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        for scroll in scrollers {
            scroll.drawsBackground = false
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderFailed(errorDescription: "bitmapa se nedala zakódovat do PNG")
        }
        try png.write(to: url)
    }
}
