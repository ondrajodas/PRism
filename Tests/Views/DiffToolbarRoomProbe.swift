import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// **Jak vypadá lišta diffu, které se místa nedostává** (#524, rozšířeno #593) — sonda k tomu, co
/// `fittingSize` říct neumí.
///
/// `DiffToolbarRoomTests` měří, oč si lišta **říká**, a `DiffToolbarLadderTests` vyčerpává
/// rozhodnutí. Tahle sonda ukazuje, co z toho **zbyde** — a to je jiná otázka: pořadí ustupování
/// se dá tvrdit nad čísly, ale že sražená lišta pořád vypadá jako lišta, se pozná jedině tak, že
/// se kresba vyfotí a podívá se na ni člověk.
///
/// Kreslí se do bitmapy přes `cacheDisplay`, ne přes okno: lišta je jedna řádka chromu bez
/// `ScrollView`u, takže offscreen render stačí (u dashboardu nestačil — viz `docs/testovani.md`).
///
/// **Pouští se ručně**: `PRISM_MEASURE=1`, kresba do `PRISM_RENDER_DIR`.
///
/// Co se naměřilo u #593 (podlaha 700 b → štěrbina **572 b**, oba sloupce složené):
///
/// | šířka | oč si lišta říká | co ustoupí |
/// |---|---|---|
/// | 572 | 923 | popis změn, hledání, sbalení, ukazatel šířky a **přepínač pohledu** (na ikony) |
/// | 700 | 923 | popis změn, hledání, sbalení, ukazatel šířky — **přepínač zůstane celý** |
/// | 900 | 923 | jen popis změn |
/// | 1200 | 923 | nic |
@MainActor
@Suite(
    "Jak vypadá lišta diffu v úzkém okně (#524, #593)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil),
    .serialized
)
struct DiffToolbarRoomProbe {
    /// **572 je štěrbina podlahového okna**, ne kulaté číslo: 700 − rail 52 − dva složené proužky
    /// po 38. 900 je stav, ve kterém se zbytek lišty vejde a nedostává se jen na popisek akce,
    /// a 1200 je běžné okno.
    private static let widths = [572.0, 700.0, 900.0, 1_200.0]

    @Test("Vyfoť lištu na pásmu šířek, s akcí i bez ní")
    func drawTheToolbar() throws {
        let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"]
        for width in Self.widths {
            for annotated in [true, false] {
                let slug = "lista-\(Int(width))-\(annotated ? "s-akci" : "bez-akce")"
                try draw(bare(annotated: annotated, width: width), width: width, slug: slug, directory: directory)
            }
        }
    }

    /// **Lišta se všemi osmi prvky** — s oběma vzácnými varováními. Je to ten jediný stav, ve
    /// kterém se lišta nevejde ani po celém ustoupení, takže se z ní ubírá; jak takové ubírání
    /// vypadá, nad čísly tvrdit nejde.
    @Test("Vyfoť lištu se vzácnými varováními")
    func drawTheWorstCase() throws {
        let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"]
        for width in Self.widths {
            try draw(
                bare(state: .idle, width: width, unreadable: 3, missing: 2),
                width: width,
                slug: "lista-\(Int(width))-varovani",
                directory: directory
            )
        }
    }

    /// **Tři stavy vedle sebe** — klid, běh, selhání. Je to ta část opravy z #524, kterou nejde
    /// tvrdit nad daty: že se po kliknutí na tomtéž místě **něco změní**, se dá ukázat jedině
    /// kresbou.
    @Test("Vyfoť všechny tři stavy ovladače")
    func drawTheStates() throws {
        let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"]
        let states: [(String, Policy.AnnotationControl)] = [
            ("klid", .idle),
            ("beh", .running),
            ("selhani", .failed(detail: "Popis změn neproběhl. Session skončila s návratovým kódem 1.")),
        ]
        for (slug, state) in states {
            try draw(bare(state: state, width: 1_200), width: 1_200, slug: "stav-\(slug)", directory: directory)
        }
    }

    /// **Kolik si který prvek bere a na co se srazí** — tabulka do `docs/testovani.md`, měřená
    /// tou cestou, kterou prvky měří `DiffToolbarLayout`.
    @Test("Vypiš, kolik si který prvek bere")
    func printTheItemCosts() {
        let bar = bare(state: .idle, width: 572, unreadable: 3, missing: 2)
        for entry in DiffToolbarMeasuring.entries(of: {
            bar.layoutPicker
            bar.findingNavigation
            bar.warnings
            bar.annotateButton
            bar.searchButton
            bar.foldMenu
        }) {
            let item = entry.item
            let floor = item.map { "\(Policy.diffToolbarFloor($0))" } ?? "—"
            print("SONDA prvek \(item?.rawValue ?? "—"): celý \(entry.full), sražený \(entry.floor) (\(floor))")
        }
        let plain = bare(state: .idle, width: 572, menu: false)
        for entry in DiffToolbarMeasuring.entries(of: { plain.foldMenu }) {
            print("SONDA prvek fold bez nabídky: celý \(entry.full), sražený \(entry.floor)")
        }
    }

    /// **Co to stojí navíc** — druhý konec měření (#275): vlastní `Layout` se každý prvek ptá
    /// **dvakrát** (celý a sražený), kdežto `HStack` se ptal jednou. Kdyby se tím přerovnání
    /// lišty prodražilo, bylo by to zlevnění, které práci jen přesune jinam.
    ///
    /// Měří se **střídavě A/B/A/B** (#274) a na dvou šířkách, aby se rozvrhovalo doopravdy —
    /// `layoutSubtreeIfNeeded` nad nezměněnou šířkou nemá co dělat.
    @Test("Změř, co stojí přerovnání lišty proti HStacku")
    func measureRelayout() {
        let bar = bare(state: .idle, width: 900)
        var layoutTime = Duration.zero
        var stackTime = Duration.zero
        for _ in 0..<4 {
            layoutTime += Self.relayout(AnyView(bar))
            stackTime += Self.relayout(AnyView(Self.stacked(bar)))
        }
        print("SONDA přerovnání 400× — Layout \(layoutTime), HStack \(stackTime)")
    }

    /// Lišta složená starým způsobem: `HStack` se `Spacer`em. Je tu **jen k měření** — aplikace
    /// ji takhle nekreslí od #593.
    private static func stacked(_ bar: DiffToolbar) -> some View {
        HStack(spacing: 9) {
            bar.layoutPicker
            bar.findingNavigation
            Spacer(minLength: 9)
            bar.widthGauge
            bar.annotateButton
            bar.searchButton
            bar.foldMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
    }

    /// Sto přerovnání mezi dvěma šířkami. Vrací **čas bez přípravy** — hostitel i první rozvržení
    /// jsou mimo měřidlo (#274).
    private static func relayout(_ view: AnyView) -> Duration {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 34)
        host.layoutSubtreeIfNeeded()
        let clock = ContinuousClock()
        return clock.measure {
            for step in 0..<100 {
                host.setFrameSize(NSSize(width: step.isMultiple(of: 2) ? 572 : 900, height: 34))
                host.layoutSubtreeIfNeeded()
            }
        }
    }

    // MARK: - Kresba

    private func draw(
        _ bar: DiffToolbar,
        width: Double,
        slug: String,
        directory: String?
    ) throws {
        // **Hostitel je širší než lišta**, aby bylo vidět i to, co by přeteklo za hranu — do
        // bitmapy široké jako lišta by se přetečení oříznulo.
        let overhang = 120.0
        let host = NSHostingView(
            rootView: HStack(spacing: 0) {
                bar.frame(width: width)
                Spacer(minLength: 0)
            }
        )
        host.frame = NSRect(x: 0, y: 0, width: width + overhang, height: 34)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            Issue.record("bitmapu se nepodařilo založit")
            return
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        print("SONDA \(slug): vyžádáno \(NSHostingView(rootView: bar).fittingSize.width), k dispozici \(width)")
        if let directory, let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(filePath: directory).appending(path: "\(slug).png"))
        }
    }

    // MARK: - Scéna

    private func bare(annotated: Bool, width: Double) -> DiffToolbar {
        bare(state: annotated ? .idle : nil, width: width)
    }

    /// Lišta v **plné výbavě**: procházení nálezů, varování o šířce, hledání i sbalení.
    /// `state` `nil` = akce se nekreslí vůbec.
    private func bare(
        state: Policy.AnnotationControl?,
        width: Double,
        unreadable: Int = 0,
        missing: Int = 0,
        menu: Bool = true
    ) -> DiffToolbar {
        DiffToolbar(
            diff: Diff(
                files: (0..<3).map { index in
                    FileDiff(
                        oldPath: "src/Soubor\(index).swift",
                        newPath: "src/Soubor\(index).swift",
                        change: .modified,
                        isBinary: false,
                        hunks: [
                            DiffHunk(oldStart: 1, oldCount: 3, newStart: 1, newCount: 5, heading: "", lines: [])
                        ]
                    )
                },
                unrecognizedLines: unreadable
            ),
            layout: .constant(.split),
            navigation: FindingNavigation(
                position: 2,
                total: 7,
                hasPrevious: true,
                hasNext: true,
                isComplete: false,
                withoutPlace: 0
            ),
            onlyBlocking: .constant(false),
            stepFinding: { _ in },
            showBubbles: .constant(true),
            hasFindings: menu,
            folding: DiffFoldingActions(
                isFolded: { _ in false },
                toggle: { _ in },
                foldAll: { _ in },
                unfoldAll: {}
            ),
            collapseExpansion: menu ? {} : nil,
            missingThreads: missing,
            contentWidth: width,
            openSearch: {},
            isSearching: false,
            annotation: state.map { DiffAnnotationActions(state: $0, start: {}, cancel: {}) }
        )
    }
}
