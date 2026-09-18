import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// **Jak vypadá lišta diffu, které se místa nedostává** (#524) — sonda k tomu, co `fittingSize`
/// říct neumí.
///
/// `DiffToolbarRoomTests` měří, oč si lišta **říká**. Tahle sonda ukazuje, co z toho **zbyde**,
/// když je místa míň — a to je jiná otázka: `HStack` přetečení nehlásí, jen ho nakreslí, takže se
/// na ně dá přijít jedině tak, že se kresba vyfotí a podívá se na ni člověk.
///
/// Kreslí se do bitmapy přes `cacheDisplay`, ne přes okno: lišta je jedna řádka chromu bez
/// `ScrollView`u, takže offscreen render stačí (u dashboardu nestačil — viz `docs/testovani.md`).
///
/// **Pouští se ručně**: `PRISM_MEASURE=1`, kresba do `PRISM_RENDER_DIR`.
///
/// Co se naměřilo u #524 (podlaha 700 b → štěrbina **572 b**, oba sloupce složené):
///
/// | šířka | bez akce | s akcí |
/// |---|---|---|
/// | 572 | přetéká, `Sbalit vše` useknuté | totéž, akce zbyla na ikonu |
/// | 900 | vejde se | vejde se, akce zbyla na ikonu |
/// | 1200 | vejde se | vejde se i s popiskem |
@MainActor
@Suite(
    "Jak vypadá lišta diffu v úzkém okně (#524)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil),
    .serialized
)
struct DiffToolbarRoomProbe {
    /// **572 je štěrbina podlahového okna**, ne kulaté číslo: 700 − rail 52 − dva složené proužky
    /// po 38. 900 je stav, ve kterém se zbytek lišty vejde a nedostává se jen na popisek akce,
    /// a 1200 je běžné okno.
    private static let widths = [572.0, 900.0, 1200.0]

    @Test("Vyfoť lištu na třech šířkách, s akcí i bez ní")
    func drawTheToolbar() throws {
        let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"]
        for width in Self.widths {
            for annotated in [true, false] {
                let host = NSHostingView(rootView: toolbar(annotated: annotated, width: width))
                host.frame = NSRect(x: 0, y: 0, width: width, height: 34)
                host.layoutSubtreeIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                    Issue.record("bitmapu se nepodařilo založit")
                    return
                }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let slug = "lista-\(Int(width))-\(annotated ? "s-akci" : "bez-akce")"
                print("SONDA \(slug): vyžádáno \(NSHostingView(rootView: bare(annotated: annotated, width: width)).fittingSize.width), k dispozici \(width)")
                if let directory, let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: URL(filePath: directory).appending(path: "\(slug).png"))
                }
            }
        }
    }

    /// **Tři stavy vedle sebe** — klid, běh, selhání. Je to ta část opravy, kterou nejde tvrdit
    /// nad daty: že se po kliknutí na tomtéž místě **něco změní**, se dá ukázat jedině kresbou.
    @Test("Vyfoť všechny tři stavy ovladače")
    func drawTheStates() throws {
        let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"]
        let states: [(String, Policy.AnnotationControl)] = [
            ("klid", .idle),
            ("beh", .running),
            ("selhani", .failed(detail: "Popis změn neproběhl. Session skončila s návratovým kódem 1.")),
        ]
        for (slug, state) in states {
            let host = NSHostingView(rootView: bare(state: state, width: 1200).frame(width: 1200))
            host.frame = NSRect(x: 0, y: 0, width: 1200, height: 34)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                Issue.record("bitmapu se nepodařilo založit")
                return
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            print("SONDA stav-\(slug)")
            if let directory, let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: URL(filePath: directory).appending(path: "stav-\(slug).png"))
            }
        }
    }

    // MARK: - Scéna

    private func toolbar(annotated: Bool, width: Double) -> some View {
        bare(annotated: annotated, width: width).frame(width: width)
    }

    private func bare(annotated: Bool, width: Double) -> some View {
        bare(state: annotated ? .idle : nil, width: width)
    }

    /// Lišta v **plné výbavě**: procházení nálezů, varování o šířce, hledání i sbalení.
    /// `state` `nil` = akce se nekreslí vůbec.
    private func bare(state: Policy.AnnotationControl?, width: Double) -> some View {
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
                unrecognizedLines: 0
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
            hasFindings: true,
            folding: DiffFoldingActions(
                isFolded: { _ in false },
                toggle: { _ in },
                foldAll: { _ in },
                unfoldAll: {}
            ),
            collapseExpansion: {},
            missingThreads: 0,
            contentWidth: width,
            openSearch: {},
            isSearching: false,
            annotation: state.map { DiffAnnotationActions(state: $0, start: {}, cancel: {}) }
        )
    }
}
