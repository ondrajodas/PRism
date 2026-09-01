import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test: vyrenderuje **pruh hledání** (#152) a k němu blok kódu se zvýrazněnými výskyty,
/// aby se dalo koukat na to, co se doopravdy nakreslí — a srovnat to se zákresem (sekce 39).
///
/// Vypnutá schválně (`.disabled`) — pouští se ručně, když se na hledání sahá. Render nezastupuje
/// tvrzení: co má platit, tvrdí `DiffSearchTests`, `DiffSearchNavigationTests`,
/// `DiffSearchHighlightTests` a `AppStoreDiffSearchTests`.
///
/// **Blok kódu se renderuje `NSHostingView`em, ne `ImageRenderer`em** — `DiffCodeBlockView` je
/// `NSViewRepresentable` a ten `ImageRenderer` nakreslí prázdný (změřeno u #483 na jiné komponentě,
/// tady vyšlo totéž: obrázek bez textu). Pruh sám by `ImageRenderer` zvládl, ale renderuje se týmž
/// způsobem, aby se obojí dalo položit vedle sebe ve stejném měřítku.
///
/// Postup a co se z renderu nedozvíš je v [`docs/testovani.md`](../../docs/testovani.md),
/// *Jak si zkontrolovat, jak view vypadá*.
@Suite("Sonda — hledání v diffu", .disabled("sonda, pouští se ručně"))
@MainActor
struct DiffSearchRenderProbe {
    private static let output = URL(filePath: NSTemporaryDirectory())
        .appending(path: "prism-diff-search")

    /// Šířka je ta skutečná: okno 1 512 minus rail a panel, tedy kolik na diff v okně zbývá.
    private static let contentWidth = 900.0

    @Test("Vyrenderuj pruh hledání i zvýraznění")
    func renderStates() throws {
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            try render(bar(.hits), to: "01-vyskyty-\(suffix).png", dark: dark, height: 34)
            try render(bar(.empty), to: "02-nic-\(suffix).png", dark: dark, height: 34)
            try render(bar(.idle), to: "03-prazdne-pole-\(suffix).png", dark: dark, height: 34)
            try render(codeBlock(current: 1), to: "04-kod-\(suffix).png", dark: dark, height: 150)
            try render(header(), to: "05-hlavicka-\(suffix).png", dark: dark, height: 40)
        }
        print("Hledání v diffu vyrenderované do \(Self.output.path)")
    }

    private enum Stage {
        case idle
        case hits
        case empty
    }

    // MARK: - Scény

    private func state(_ stage: Stage) -> DiffSearchState {
        let state = DiffSearchState()
        state.isOpen = true
        switch stage {
        case .idle:
            state.query = ""
        case .hits:
            state.query = "FLUSH_TIMEOUT"
            state.hits = Self.hits
            state.counts = DiffSearch.counts(of: Self.hits)
            // Druhý výskyt ze tří — pozice uprostřed je ta, na které se pozná, že šipky svítí obě.
            state.current = 1
        case .empty:
            state.query = "DEFAULT_BACKEND"
        }
        return state
    }

    private func bar(_ stage: Stage) -> some View {
        DiffSearchBar(search: state(stage), actions: DiffSearchActions(), step: { _ in })
            .frame(width: Self.contentWidth)
    }

    /// Blok kódu s výskyty — včetně toho, který leží **uvnitř** změněného slova, protože právě na
    /// něm se pozná, že hledání vyhrává nad word-level vrstvou.
    private func codeBlock(current: Int) -> some View {
        let lines = Self.codeLines
        let hit = DiffSearchHit(path: Self.path, line: lines[current], occurrence: 0)
        return DiffCodeBlockView(
            block: DiffBlock(lines: lines),
            language: Language(path: Self.path),
            colorScheme: .light,
            search: DiffSearchHighlight(
                query: DiffSearchQuery(text: "FLUSH_TIMEOUT"),
                current: hit
            )
        )
        .frame(width: Self.contentWidth, height: 130)
    }

    /// Hlavička souboru s kapslí `3 výskyty` vedle kapsle nálezu — dvě kapsle vedle sebe jsou
    /// zrovna to, na co se u téhle změny kouká.
    private func header() -> some View {
        DiffFileHeaderView(
            file: Self.file,
            isFolded: false,
            findings: [],
            blockingCategories: Policy.defaultBlockingCategories,
            toggle: {}
        )
        .frame(width: Self.contentWidth)
        .environment(state(.hits))
    }

    // MARK: - Render

    private func render(_ content: some View, to name: String, dark: Bool, height: Double) throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        let host = NSHostingView(
            rootView: content
                .environment(\.colorScheme, dark ? .dark : .light)
                .background(Palette.chrome)
        )
        host.appearance = appearance
        host.frame = NSRect(x: 0, y: 0, width: Self.contentWidth, height: height)
        host.layoutSubtreeIfNeeded()

        // Okno je potřeba, aby `NSTextView` v bloku vůbec vysázel text — a **bez animace** (#462).
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.contentView = host
        window.orderFrontUnanimated()
        host.layoutSubtreeIfNeeded()

        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: Self.output.appending(path: name))
        window.orderOut(nil)
    }

    // MARK: - Data

    private static let path = "src/Vault/SecretClient.php"

    private static let codeLines: [DiffLine] = [
        DiffLine(kind: .context, oldNumber: 96, newNumber: 96, text: "    private const FLUSH_TIMEOUT = 5;"),
        DiffLine(
            kind: .removed,
            oldNumber: 103,
            newNumber: nil,
            text: "        $this->client->put($key, $value, ['timeout' => self::FLUSH_TIMEOUT]);"
        ),
        DiffLine(
            kind: .added,
            oldNumber: nil,
            newNumber: 105,
            text: "        $this->client->putMultiple($chunk, ['timeout' => self::FLUSH_TIMEOUT_MS]);"
        ),
        DiffLine(kind: .context, oldNumber: 106, newNumber: 106, text: "    }"),
    ]

    private static let hits: [DiffSearchHit] = codeLines
        .filter { $0.text.contains("FLUSH_TIMEOUT") }
        .map { DiffSearchHit(path: path, line: $0, occurrence: 0) }

    private static let file = FileDiff(
        oldPath: path,
        newPath: path,
        change: .modified,
        isBinary: false,
        hunks: [
            DiffHunk(
                oldStart: 96,
                oldCount: 4,
                newStart: 96,
                newCount: 5,
                heading: "final class SecretClient",
                lines: codeLines
            )
        ]
    )
}
