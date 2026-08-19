import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#381): vykreslí bublinu nálezu **před opravou a po ní vedle sebe** nad tou
/// samou fixturou z provozu — nahoře dvě položky, dole jedna.
///
/// Proč sonda: „je v bublině nález jednou?“ se v jeho vlastní aplikaci ověřit nedá, protože
/// záznam s duplikátem leží v **jeho** cache a do té se ve slotu nesahá. Počty tvrdí
/// `StreamParserTests` a `FindingMergeTests`; tohle je ten obrázek, ze kterého je vidět, že
/// duplikát v okně vypadal jako dva samostatné blokující nálezy.
///
/// Stav „před“ se skládá tak, že se **každé volání `ReportFindings` sečte zvlášť** — přesně to
/// dělal parser do #381, takže obě bubliny vycházejí z týchž dat, ne z ručně napsaného vstupu.
///
/// `NSHostingView`, ne `ImageRenderer` — tatáž cesta jako `FindingActionColourProbe`, viz
/// `docs/testovani.md`.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda duplicitního nálezu (#381)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct FindingDuplicateProbe {
    private let width: CGFloat = 900
    private let parser = StreamParser()

    @Test("Vyrendrovat bublinu před opravou a po ní")
    func rendersTheBubbleBeforeAndAfter() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
        // Nálezy se čtou **před** kreslením a chyba se nese ven: prázdná bublina by v sondě
        // vypadala jako „nic tu nebylo“, tedy jako výsledek, ne jako nepřečtená fixture.
        let before = try beforeFindings()
        let after = try afterFindings()
        #expect(before.count == 2)
        #expect(after.count == 1)

        for dark in [false, true] {
            let url = directory.appending(path: "nalez-duplikat-\(dark ? "tmavy" : "svetly").png")
            let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
            var thrown: (any Error)?
            appearance.performAsCurrentDrawingAppearance {
                do {
                    try capture(scene(before: before, after: after, dark: dark), to: url)
                } catch {
                    thrown = error
                }
            }
            if let thrown { throw thrown }
            print("SONDA \(url.path)")
        }
    }

    private func scene(before: [ReportedFinding], after: [ReportedFinding], dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label("před #381 — dvě volání `ReportFindings` = dva nálezy na jednom řádku")
            bubble(of: before)
            label("po #381 — pozdější volání přepsalo dřívější, v bublině je nález jednou")
            bubble(of: after)
        }
        .frame(width: width, alignment: .topLeading)
        .background(Palette.surface)
        .tint(Palette.accent)
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private func bubble(of findings: [ReportedFinding]) -> some View {
        let group = FindingGroup(
            file: findings.first?.file,
            line: findings.first?.line,
            findings: findings.map {
                Finding(reported: $0, reviewer: "code-review:code-review", headSha: Self.headSha)
            }
        )
        return FindingBubbleView(group: group, indent: 0, toggle: {})
            .padding(.horizontal, FindingTableLayout.inset)
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption2)
            .foregroundStyle(Palette.ink3)
            .padding(.horizontal, FindingTableLayout.inset)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    // MARK: - Materiál z fixture

    private static let headSha = "8292182754b50d1867049b1617d37bdee55324aa"

    /// **`TextLines`, ne `split(separator: "\n")`** — pravidlo repa (#292, #295) platí i v testech:
    /// `"\r\n"` je ve Swiftu jeden `Character`, takže by `split` na fixtuře s `CRLF` nerozdělil
    /// vůbec a sonda by kreslila prázdnou bublinu.
    private func fixtureLines() throws -> [String] {
        TextLines.content(try Fixture.text("stream-json/report-findings-corrected.jsonl")).map(String.init)
    }

    /// Co v okně leželo do #381: každé volání zvlášť a výsledky za sebou.
    private func beforeFindings() throws -> [ReportedFinding] {
        try fixtureLines().flatMap { parser.summarize([$0]).findings }
    }

    private func afterFindings() throws -> [ReportedFinding] {
        parser.summarize(try fixtureLines()).findings
    }

    // MARK: - Kreslení

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako
    /// `FindingActionColourProbe`, viz `docs/testovani.md`.
    private func capture(_ scene: some View, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: hosting.fittingSize.height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        // Hierarchie se doskládá až po jednom kole smyčky, takže se výška bere znovu až za ní.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        hosting.frame.size.height = hosting.fittingSize.height
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }
}
