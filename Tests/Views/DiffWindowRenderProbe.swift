import AppKit
import SwiftUI
import Testing

@testable import PRism

/// **Jak diff doopravdy vypadá, když ho neskládá líný seznam** (#469) — sonda, ne test: bez
/// `PRISM_RENDER_DIR` nedělá nic.
///
/// Existuje proto, že #469 vyměnilo způsob, jakým se diff skládá (pevný `VStack` a vlastní
/// nasazování bloků), a čísla o tom nic neřeknou. Ptá se na čtyři věci, které se rozbijí potichu:
///
/// 1. **Zůstal diff celý?** Blok mimo pás kolem výřezu se odpojí a zbyde po něm rezervovaná výška —
///    kdyby se ta výška lišila od skutečné, byla by v obrázku prázdná díra nebo přeteklý text.
/// 2. **Drží se hlavička souboru nahoře?** Ukotvení dělal do #469 `LazyVStack(pinnedViews:)`; od
///    #469 se kreslí jednou přes výřez (`DiffPinnedHeader`).
/// 3. **Vysune se hlavička na konci svého souboru?** To je ten rozdíl mezi `position: sticky`
///    a plovoucím pruhem.
/// 4. **Platí obojí i v pohledu vedle sebe**, kde je blok dvojice a `NSTextView` jsou dva.
///
/// Renderuje se **z okna mimo obrazovku** (`cacheDisplay`), protože blok kódu je AppKitové view
/// a `ImageRenderer` na něj nedosáhne — tatáž konstrukce jako `DiffPairScrollerRenderProbe`.
///
/// ```bash
/// TEST_RUNNER_PRISM_MEASURE=1 TEST_RUNNER_PRISM_RENDER_DIR=/tmp/render \
///     xcodebuild … test -only-testing:PRismTests/DiffWindowRenderProbe
/// ```
@MainActor
@Suite(
    "Kresba diffu bez líného seznamu (#469)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct DiffWindowRenderProbe {
    @Test("Diff nahoře, odscrollovaný a na konci souboru")
    func drawTheDiff() throws {
        guard let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] else { return }
        let diff = DiffParser.parse(DiffMaterial.text(lines: 2000))
        for layout in [DiffLayout.unified, .split] {
            let host = NSHostingView(rootView: ProbeDiff(diff: diff, layout: layout))
            host.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
            let window = NSWindow(
                contentRect: host.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderFrontUnanimated()
            defer { window.orderOut(nil) }
            _ = spinMainRunLoop(seconds: 1.5)

            let scroller = try #require(Self.tallestScroller(in: host))
            let slug = layout == .split ? "vedle" : "podsebou"
            for offset in Self.offsets(in: scroller) {
                scroller.contentView.scroll(to: NSPoint(x: 0, y: offset.value))
                scroller.reflectScrolledClipView(scroller.contentView)
                _ = spinMainRunLoop(seconds: 0.6)
                print(String(
                    format: "SONDA %@ %@: obsah %.0f pt, výřez na %.0f, %d bloků kódu v okně",
                    slug,
                    offset.name,
                    scroller.documentView?.frame.height ?? 0,
                    scroller.documentVisibleRect.origin.y,
                    Self.blocks(in: host)
                ))
                Self.write(host, to: URL(filePath: directory).appending(path: "diff-\(slug)-\(offset.name).png"))
            }
        }
    }

    /// Kam se odscrolluje. **Konec prvního souboru** je tam, kde se ukotvená hlavička vysouvá —
    /// bez toho snímku by sonda o tom rozdílu netvrdila nic.
    private static func offsets(in scroller: NSScrollView) -> [(name: String, value: Double)] {
        let content = scroller.documentView?.frame.height ?? 0
        return [
            ("vrsek", 0),
            ("uprostred", content / 3),
            ("dole", max(content - scroller.contentSize.height - 40, 0)),
        ]
    }

    private static func write(_ view: NSView, to url: URL) {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("SONDA kresba \(url.lastPathComponent): view nevydalo bitmapu")
            return
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            print("SONDA kresba \(url.lastPathComponent): bitmapa se nedala zapsat")
            return
        }
        // Selhání zápisu sondu nepokládá, ale mlčet se nesmí: „render se neuložil“ nesmí být
        // k nerozeznání od „nespustil jsem ho“.
        do {
            try data.write(to: url)
            print("SONDA kresba → \(url.lastPathComponent)")
        } catch {
            print("SONDA kresba \(url.lastPathComponent) se neuložila: \(error.localizedDescription)")
        }
    }

    private static func blocks(in view: NSView) -> Int {
        view.subviews.reduce(view is DiffPairBlockContainer || view is DiffTextView ? 1 : 0) {
            $0 + blocks(in: $1)
        }
    }

    private static func tallestScroller(in view: NSView) -> NSScrollView? {
        var best = view as? NSScrollView
        for child in view.subviews {
            guard let found = tallestScroller(in: child) else { continue }
            let height = found.documentView?.frame.height ?? 0
            if height > (best?.documentView?.frame.height ?? 0) { best = found }
        }
        return best
    }
}

/// `DiffView` se vším, co k němu patří — jen bez store. Sonda kreslí **skutečný** view, ne jeho
/// kopii: kdyby se lišil, netvrdil by obrázek nic.
struct ProbeDiff: View {
    let diff: Diff
    let layout: DiffLayout

    @State private var target: String?
    @State private var expansions: [String: FileExpansion] = [:]
    @State private var folded: Set<String> = []
    @State private var chosenLayout: DiffLayout = .unified

    var body: some View {
        DiffView(
            diff: diff,
            subject: "cli/cli#13084",
            scrollTarget: $target,
            expansion: DiffExpansionActions(
                state: { expansions[$0.id] ?? FileExpansion() },
                reveal: { _, _ in },
                collapse: nil
            ),
            folding: DiffFoldingActions(
                isFolded: { folded.contains($0.id) },
                toggle: { file in
                    if folded.contains(file.id) { folded.remove(file.id) } else { folded.insert(file.id) }
                },
                foldAll: { folded = Set($0.map(\.id)) },
                unfoldAll: { folded = [] }
            ),
            layout: $chosenLayout
        )
        .background(Palette.background)
        .task { chosenLayout = layout }
    }
}
