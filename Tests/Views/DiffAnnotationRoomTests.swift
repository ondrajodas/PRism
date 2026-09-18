import AppKit
import SwiftUI
import Testing

@testable import PRism

/// **Kolik místa v diffu vezme věta *proč*** (#525) — a hlavně, že si ho **nebere z bloku kódu**.
///
/// Tvrdá mez #525 zní: řádek nad hunkem **nesmí měnit geometrii bloků kódu** (#469). Dá se
/// splnit napůl — věta jako vlastní řádek geometrii nemění, kdežto věta vložená do `NSTextView`
/// nebo řádek posazený mezi souvislé řádky kódu ji mění, a v obou případech by se to poznalo
/// teprve podle toho, že skok na nález (`DiffRow.blockSpot`) míří vedle. Proto se to **měří na
/// nakresleném bloku**, ne tvrdí nad modelem: `DiffAnnotationRowTests` hlídají složení bloků,
/// tady se ptáme layout manageru na výšku.
///
/// **Druhá polovina je, že věta v okně doopravdy je.** Samotná nezměněná výška bloku by platila
/// i tehdy, kdyby se věta nenakreslila vůbec (#478) — proto je vedle měření rozdíl bitmap.
@MainActor
@Suite("Místo pro větu proč v diffu (#525)", .serialized)
struct DiffAnnotationRoomTests {
    private static let width = 900.0
    private static let height = 700.0

    // MARK: - Geometrie bloků

    /// **Výšky bloků kódu se anotacemi nemění.** Měří se `DiffTextView`, tedy to, co kód doopravdy
    /// kreslí — a jsou to tytéž hodnoty, o které si blok říká v `sizeThatFits`.
    @Test("Věta nad hunkem nezmění výšku bloků kódu")
    func theSentenceDoesNotChangeTheBlockHeights() async throws {
        let plain = try await heights(annotated: false)
        let annotated = try await heights(annotated: true)

        #expect(!plain.isEmpty, "měřidlo: v hostované hierarchii není ani jeden blok kódu")
        #expect(plain == annotated, "bloky bez anotací \(plain), s anotacemi \(annotated)")
    }

    /// **Bloků je stejně** — tedy věta žádný z nich nerozťala na dva. Vyplývá to z rovnosti výšek
    /// výš jen zdánlivě: dva bloky o poloviční výšce by dávaly týž součet.
    @Test("Věta nad hunkem blok kódu nerozdělí")
    func theSentenceDoesNotSplitABlock() async throws {
        let plain = try await heights(annotated: false)
        let annotated = try await heights(annotated: true)

        #expect(plain.count == annotated.count)
    }

    /// **Věta obsah odsune dolů, ne zmenší blok.** Kdyby se věta nekreslila, měřidlo výš by vyšlo
    /// zeleně z toho nejhoršího důvodu: neměřilo by nic (#478). Měří se poloha **prvního** bloku,
    /// tedy toho hned pod první souřadnicí hunku.
    @Test("Věta odsune blok kódu pod sebou dolů")
    func theSentencePushesTheBlockDown() async throws {
        let plain = try await tops(annotated: false)
        let annotated = try await tops(annotated: true)

        let first = try #require(plain.first)
        let pushed = try #require(annotated.first)
        #expect(pushed > first, "blok se o větu neodsunul (\(first) → \(pushed))")
    }

    // MARK: - Že je věta vidět

    /// Rozdíl bitmap, ne čtení textu: accessibility tree se v hostovaném okně nenaplní (změřeno
    /// u `DashboardCountdownRedrawTests`), takže „je vidět“ se dá tvrdit jedině z pixelů. Tatáž
    /// cesta jako u `EditorButtonRenderTests`.
    @Test("Věta se v diffu nakreslí")
    func theSentenceIsDrawn() async throws {
        let plain = try await bitmap(annotated: false, name: "bez-anotaci")
        let annotated = try await bitmap(annotated: true, name: "s-anotacemi")

        #expect(plain != annotated)
    }

    /// **Kapsle druhu změny v hlavičce souboru se kreslí, a bez druhu se nekreslí** — tvrzení
    /// o tom, co na obrazovce **není**, tedy to, co se rozbije potichu.
    @Test("Kapsle druhu změny přibude, jen když druh je")
    func theKindPillAppearsOnlyWithAKind() throws {
        let without = try headerBitmap(kind: nil, name: "hlavicka-bez-druhu")
        let behaviour = try headerBitmap(kind: .behaviour, name: "hlavicka-zmena-chovani")
        let generated = try headerBitmap(kind: .generated, name: "hlavicka-generovane")

        #expect(without != behaviour)
        // A akcent není totéž co tichý tón: `změna chování` se od `generované` musí poznat i jinak
        // než délkou slova, jinak je z pěti druhů jedna kapsle v pěti šířkách.
        #expect(behaviour != generated)
    }

    // MARK: - Scéna

    private struct Scene {
        let window: NSWindow
        let host: NSHostingView<AnnotatedDiffProbe>
    }

    private func scene(annotated: Bool) async throws -> Scene {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))
        let file = try #require(diff.files.first { $0.displayPath == "CLAUDE.md" })
        let viewport = DiffViewport()
        // Pás přes celý obsah, ať se bloky nasadí — o nasazování tahle sada netvrdí nic (#469).
        viewport.band = -100_000...100_000
        let host = NSHostingView(rootView: AnnotatedDiffProbe(
            file: file,
            annotations: annotated ? Self.annotations(of: file) : [:],
            viewport: viewport
        ))
        host.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        await waitUntil("blok kódu se rozvrhne") {
            host.firstDescendant(ofType: DiffTextView.self)?.frame(ofLine: 0) != nil
        }
        await settle()
        return Scene(window: window, host: host)
    }

    /// Výšky **všech** bloků kódu v hierarchii, seshora dolů.
    ///
    /// Řadí se podle **změřené polohy**, ne podle pořadí podviews: to je věc SwiftUI a tvrzení
    /// „výšky jsou stejné“ by se tím dalo splnit i přeskládáním.
    private func heights(annotated: Bool) async throws -> [Double] {
        let rects = try await blocks(annotated: annotated)
        return rects.map { Double($0.height) }
    }

    /// Horní hrany bloků kódu v souřadnicích hostovaného view, seshora dolů.
    private func tops(annotated: Bool) async throws -> [Double] {
        let rects = try await blocks(annotated: annotated)
        return rects.map { Double($0.minY) }
    }

    /// Plochy bloků v souřadnicích hostovaného view, **srovnané na osu shora dolů**.
    ///
    /// `NSHostingView` převrácený je, ale neptat se na to znamená mít v testu pravidlo, které se
    /// s AppKitem umí rozejít potichu — tatáž úvaha jako v `DiffMarginPlacementTests`.
    private func blocks(annotated: Bool) async throws -> [CGRect] {
        let scene = try await scene(annotated: annotated)
        defer { scene.window.orderOut(nil) }
        let host: NSView = scene.host
        var rects: [CGRect] = []
        for text in Self.descendants(ofType: DiffTextView.self, in: host) {
            let rect: CGRect = host.convert(text.bounds, from: text)
            if host.isFlipped {
                rects.append(rect)
            } else {
                rects.append(CGRect(
                    x: rect.minX,
                    y: host.bounds.height - rect.maxY,
                    width: rect.width,
                    height: rect.height
                ))
            }
        }
        return rects.sorted { $0.minY < $1.minY }
    }

    private static func descendants<V: NSView>(ofType type: V.Type, in view: NSView) -> [V] {
        var result: [V] = []
        if let match = view as? V { result.append(match) }
        for child in view.subviews {
            result += descendants(ofType: type, in: child)
        }
        return result
    }

    /// Věta ke každému hunku souboru. Znění je jedno — měří se místo, ne text.
    private static func annotations(of file: FileDiff) -> [Int: HunkAnnotation] {
        Dictionary(uniqueKeysWithValues: file.hunks.indices.map { index in
            (
                index,
                HunkAnnotation(
                    file: file.displayPath,
                    hunk: index + 1,
                    why: "Rozepisuje tvrdou podmínku, aby se dala kontrolovat grepem.",
                    source: "z commitu docs: rozepsat podmínku"
                )
            )
        })
    }

    // MARK: - Bitmapy

    private func bitmap(annotated: Bool, name: String) async throws -> Data {
        let scene = try await scene(annotated: annotated)
        defer { scene.window.orderOut(nil) }
        return try Self.png(of: scene.host, name: name)
    }

    private func headerBitmap(kind: FileChangeKind?, name: String) throws -> Data {
        let file = FileDiff(
            oldPath: "src/Vault/SecretClient.php",
            newPath: "src/Vault/SecretClient.php",
            change: .modified,
            isBinary: false,
            hunks: []
        )
        let scene = DiffFileHeaderView(
            file: file,
            isFolded: false,
            findings: [],
            blockingCategories: [],
            toggle: {},
            changeKind: kind
        )
        .frame(width: 720, height: 40)
        .background(Palette.surface)
        let host = NSHostingView(rootView: scene)
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 40)
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        return try Self.png(of: host, name: name)
    }

    /// Bitmapa, která se dá pustit i na disk (`PRISM_RENDER_DIR`) — tatáž cesta jako
    /// u `EditorButtonRenderTests`.
    private static func png(of view: NSView, name: String) throws -> Data {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        if let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] {
            let url = URL(filePath: directory).appending(path: "anotace-\(name).png")
            try png.write(to: url)
            print("RENDER \(url.path)")
        }
        return png
    }
}

/// Řádky jednoho souboru diffu tak, jak je skládá `DiffView` — **pevný `VStack`** (#469), bloky
/// slité jako v okně a v pojmenovaném prostoru obsahu.
///
/// Je to opis výrazu z `DiffView.rows(of:)` (ten je uvnitř `some View`, tedy odsud nedosažitelný),
/// stejně jako v `DiffRenderedRowsTests` — a o kus vedle je tatáž sonda nad okrajem
/// (`BlockMarginProbe`).
struct AnnotatedDiffProbe: View {
    let file: FileDiff
    let annotations: [Int: HunkAnnotation]
    let viewport: DiffViewport

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(DiffRow.blocked(DiffRow.rows(of: file, annotations: annotations)), id: \.id) { row in
                DiffRowView(row: row)
            }
            Spacer(minLength: 0)
        }
        .coordinateSpace(.named(DiffView.contentSpace))
        .environment(viewport)
    }
}
