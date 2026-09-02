import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// **Co stojí projíždění diffu s okrajem** (#503) — proti dnešnímu diffu s bublinami pod řádky.
///
/// Okraj přidává do rozvržení druhou vrstvu nad blokem kódu (karty, spojnice, pruhy na hraně
/// řádků), takže otázka není „je to rychlé“, ale **jestli je to horší než dneska**. Měří se proto
/// obě strany a **střídavě** (A/B/A/B): drift sezení je větší než hledaný rozdíl (#274).
///
/// Tři věci, bez kterých z toho nic není:
///
/// - **Gesto je skutečné** (`WheelGesture`) — programový posun živé scrollování nespustí (#361).
/// - **Scéna se nechá usadit `await`em, ne točením runloopu**: `RunLoop.current.run(until:)`
///   vyhladoví hlavní aktor, takže by rámečky řádků z `updateNSView` nedorazily a okraj by se
///   měřil s odhadem výšky místo se změřenou polohou (změřeno u #503 při stavbě sondy —
///   karty stály u horní hrany).
/// - **Naměří to rozdíl, kdyby zhoršení bylo?** (#478) Ano, a je to vidět z druhé strany:
///   varianta s bublinami má **jiný obsah** (bubliny rozrážejí bloky, obsah je o pár set bodů
///   vyšší), takže obě čísla nepopisují tutéž scénu — právě proto se srovnávají poměry mezi
///   variantami a ne absolutní hodnoty. Že by měřidlo drahou vrstvu nad blokem vidělo, je
///   změřené u #469 stejným gestem: mezi líným a pevným seznamem vyšel rozdíl řádově.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`.
@MainActor
@Suite(
    "Okraj: co stojí projíždění (#503)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil),
    .serialized
)
struct DiffMarginWheelProbe {
    /// Kolik řádků má měřený diff. Dost na to, aby se gestem projelo přes víc karet, a zároveň
    /// tolik, kolik mají skutečné soubory z fixtures.
    private static let lines = 2000
    /// Kolik nálezů se do diffu rozeseje. Deset je řádově tolik, kolik jich reviewer nahlásí na
    /// velkém PR — okraj s jednou kartou by o ceně neřekl nic.
    private static let findings = 10
    /// Kolik bloků smí ve usazeném okně zbýt. Pás je nejmíň o výřez širší na každou stranu (#469),
    /// takže do něj u okna 874 pt padne řádově deset bloků po šedesáti řádcích — čtyřiatřicet je
    /// „všechny“, tedy rozdělaná scéna.
    private static let settledBlocks = 14

    @Test("Kolik stojí projíždění s okrajem proti bublinám")
    func scrollingCost() async throws {
        let diff = DiffParser.parse(Self.material())
        let groups = Self.findingGroups()
        let defaults = try ScratchDefaults("diffMarginWheel")
        var costs: [String: [Double]] = [:]
        var facts: [String: String] = [:]

        // **Tři varianty, ne dvě.** Bez té třetí („bez nálezů“) se rozdíl mezi okrajem
        // a bublinami nedá přiřadit: obě scény se totiž liší i **obsahem** — bubliny rozrážejí
        // bloky a přidávají do dokumentu přes tisíc bodů, takže gesto o 150 krocích jde přes jinak
        // drahý kód. Čistý diff je základ, proti kterému se teprve pozná, co si která vrstva bere.
        for _ in 0..<2 {
            for variant in Variant.allCases {
                let slug = variant.rawValue
                defaults.store.set(variant == .bubbles, forKey: "showInlineFindingBubbles")
                let scene = try scene(
                    diff: diff,
                    findings: variant == .clean ? [] : groups,
                    store: defaults.store
                )
                defer { scene.window.orderOut(nil) }
                await ready(scene)

                let scroller = try #require(Self.tallestScroller(in: scene.host))
                let started = mainThreadCPUSeconds()
                let landed = WheelGesture.scroll(
                    over: scroller,
                    in: scene.window,
                    steps: 150,
                    step: 40
                )
                let cost = mainThreadCPUSeconds() - started
                costs[slug, default: []].append(cost)
                facts[slug] = String(
                    format: "dojelo na %.0f z obsahu %.0f, %d bloků kódu v okně",
                    landed,
                    scroller.documentView?.frame.height ?? 0,
                    Self.blocks(in: scene.host)
                )
                print(String(format: "MĚŘENÍ projíždění %@: %.2f s CPU — %@", slug, cost, facts[slug] ?? ""))
            }
        }

        for slug in Variant.allCases.map(\.rawValue) {
            let values = costs[slug] ?? []
            print("MĚŘENÍ projíždění \(slug): "
                + values.map { String(format: "%.2f", $0) }.joined(separator: " / ")
                + " s CPU — \(facts[slug] ?? "")")
        }
    }

    /// Co se poměřuje. Pořadí je pořadí měření — střídá se, ne měří po sériích (#274).
    private enum Variant: String, CaseIterable {
        /// Diff bez nálezů: základ, proti kterému se čte, co si vrstva navíc bere.
        case clean = "bez nálezů"
        /// Karty v okraji (#503).
        case margin = "okraj"
        /// Bubliny pod řádky, tedy stav do #503.
        case bubbles = "bubliny"
    }

    /// Nechá scénu **usadit**, ne jen rozvrhnout — a je to podmínka měření, ne opatrnost.
    ///
    /// Na první rozvržení se nasadí **všechny** bloky a hned nato se odpojí (#469), takže gesto
    /// vypálené do rozdělané scény projíždí přes desítky `NSTextView` místo přes pět. Změřeno:
    /// **9,2–9,5 s CPU proti 1,4–1,5 s** u téže varianty, tedy šestinásobek — a protože se to
    /// stane kterékoli variantě, vyjde z toho pořadí podle toho, která se chytila nerozvrženě.
    /// Jev je proto *počet nasazených bloků se přestal měnit*, ne odmlka.
    private func ready(_ scene: Scene, sourceLocation: SourceLocation = #_sourceLocation) async {
        await waitUntil("diff se rozvrhne", sourceLocation: sourceLocation) {
            (Self.tallestScroller(in: scene.host)?.documentView?.frame.height ?? 0)
                > scene.host.bounds.height
        }
        // **Pás se musí jednou zapsat**, jinak zůstane `0...0` z konstruktoru a bloky se nemají
        // podle čeho odpojit: zapisuje ho `onScrollGeometryChange`, a ten nad nehybným výřezem
        // nemusí přijít vůbec. Malé šťouchnutí posuvníkem ho vyvolá; měří se pak od nuly.
        if let scroller = Self.tallestScroller(in: scene.host) {
            scroller.contentView.scroll(to: NSPoint(x: 0, y: 1))
            scroller.reflectScrolledClipView(scroller.contentView)
            for _ in 0..<4 { await settle() }
            scroller.contentView.scroll(to: .zero)
            scroller.reflectScrolledClipView(scroller.contentView)
        }
        // Jev je **odpojení bloků**, ne odmlka: dokud jich v okně visí desítky, měří se první
        // rozvržení, ne projíždění (čísla jsou v dokumentaci té metody).
        await waitUntil("bloky mimo pás se odpojí", sourceLocation: sourceLocation) {
            Self.blocks(in: scene.host) <= Self.settledBlocks
        }
        var quiet = 0
        var previous = -1
        await waitUntil("nasazené bloky se usadí", sourceLocation: sourceLocation) {
            let now = Self.blocks(in: scene.host)
            quiet = now == previous ? quiet + 1 : 0
            previous = now
            return quiet >= 8
        }
        // A ještě odmlka navíc: usazená AppKitová hierarchie neznamená, že se dopočítaly polohy
        // karet — ty jdou přes `DispatchQueue.main` z `updateNSView`.
        for _ in 0..<4 { await settle() }
    }

    // MARK: - Scéna

    private struct Scene {
        let window: NSWindow
        let host: NSHostingView<DiffMarginProbe>
    }

    private func scene(diff: Diff, findings: [FindingGroup], store: UserDefaults) throws -> Scene {
        let host = NSHostingView(rootView: DiffMarginProbe(
            diff: diff,
            findings: findings,
            store: store
        ))
        // Tatáž velikost jako u ostatních měření v tomhle repu (#361), aby se čísla dala srovnat.
        host.frame = NSRect(x: 0, y: 0, width: 1512, height: 874)
        host.sizingOptions = [.minSize]
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.setContentSize(NSSize(width: 1512, height: 874))
        // **Okno musí být na obrazovce**, ne mimo ni: událost kolečka nese
        // `mouseEventWindowUnderMousePointer`, a nad oknem odloženým na −10 000 se gesto
        // nedoručí — změřeno, posuvník zůstal na nule u obou variant, tedy tatáž hodnota pro
        // funguje i nefunguje (#478). Tatáž konstrukce jako `DiffShapeProbe`.
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        window.level = .floating
        window.orderFrontRegardlessUnanimated()
        return Scene(window: window, host: host)
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

    private static func blocks(in view: NSView) -> Int {
        view.subviews.reduce(view is DiffPairBlockContainer || view is DiffTextView ? 1 : 0) {
            $0 + blocks(in: $1)
        }
    }

    // MARK: - Materiál

    /// Jeden soubor o `lines` řádcích v jednom hunku — tentýž tvar, jaký měří `DiffShapeProbe`,
    /// takže se čísla dají porovnat s #469.
    private static func material() -> String {
        var out = "diff --git a/src/Vault/Encryptor.php b/src/Vault/Encryptor.php\n"
        out += "index 1111111..2222222 100644\n"
        out += "--- a/src/Vault/Encryptor.php\n"
        out += "+++ b/src/Vault/Encryptor.php\n"
        out += "@@ -1,\(lines) +1,\(lines) @@ final class Encryptor\n"
        for line in 0..<lines {
            out += "     $value = $this->compute(\(line), $ttl, $key);\n"
        }
        return out
    }

    /// Nálezy rozeseté po diffu, dva z nich na **sousedních** řádcích — tedy i s odstrkováním.
    private static func findingGroups() -> [FindingGroup] {
        var reported: [Finding] = []
        for index in 0..<findings {
            let line = 40 + index * (lines / findings)
            reported.append(finding(line: line, category: index.isMultiple(of: 3) ? "correctness" : "style"))
            if index == 1 { reported.append(finding(line: line + 1, category: "style")) }
        }
        return Policy.groups(of: reported)
    }

    private static func finding(line: Int, category: String) -> Finding {
        Finding(
            reported: ReportedFinding(
                file: "src/Vault/Encryptor.php",
                line: line,
                category: category,
                verdict: .confirmed,
                shortSummary: nil,
                summary: "Řádek \(line) počítá TTL bez horní meze — u tenantů s vlastní politikou "
                    + "rotace to znamená, že se secret nikdy nepřečte znovu.",
                failureScenario: nil
            ),
            reviewer: "security-review",
            headSha: "aaaa1111"
        )
    }
}
