import AppKit
import SwiftUI
import Testing

@testable import PRism

/// **Kde blok kódu hlásí řádek, ke kterému se v okraji váže karta** (#503).
///
/// Karta stojí tam, kam ukáže tohle hlášení (`Policy.marginTops` z něj jen dopočítá odstrčení,
/// a to je vyčerpané výčtem v `DiffMarginTests`). Rozbít se to dá čtyřmi způsoby a všechny
/// potichu: zapomenutý počátek bloku, přečtené staré číslo řádku místo nového, spodní hrana místo
/// horní a klíč, na kterém se okraj s blokem nepotkají.
///
/// **Měří se dvěma různými cestami, ne jednou dvakrát** (#478): hodnota z okraje jde ze SwiftUI
/// (pojmenovaný prostor obsahu), kontrolní hodnota z AppKitu (`DiffTextView.frame(ofLine:)`
/// převedený do hostovaného view). Blok proto **nezačíná na nule** — pod sebou má odsazení, takže
/// zapomenutý počátek nemá kde zmizet.
@MainActor
@Suite("Okraj: kde blok hlásí svůj řádek (#503)", .serialized)
struct DiffMarginPlacementTests {
    /// Odsazení nad blokem. Nenulové schválně — na nule by se zapomenutý počátek bloku neprojevil.
    private static let padding = 137.0
    private static let width = 900.0
    private static let height = 700.0
    /// Nové číslo řádku, na kterém nález je — **přidaný** řádek, takže staré číslo nemá vůbec.
    private static let line = DiffMarginMaterial.line

    /// **Karta stojí na výšce svého řádku.** Tolerance je jeden bod: obě čísla popisují tutéž
    /// hranu, jen se k ní došlo jinou cestou.
    @Test("Ohlášená poloha sedí na horní hranu svého řádku")
    func theReportedSpotSitsOnTheRow() async throws {
        let scene = try scene()
        defer { scene.window.orderOut(nil) }
        let spot = try await reported(scene)
        let measured = try Self.rowTop(in: scene)
        #expect(
            abs(spot.top - measured) <= 1,
            "okraj hlásí \(spot.top), řádek leží na \(measured)"
        )
        // A výška je výška řádku, ne bloku: spojnice míří na střed řádku, takže by z výšky bloku
        // mířila do jeho poloviny.
        let row = try #require(Self.rowFrame(in: scene))
        #expect(abs(spot.height - row.height) <= 1, "výška \(spot.height) proti řádku \(row.height)")
    }

    /// **Počátek bloku se do polohy počítá.** Bez něj by karta ležela o odsazení výš — a v aplikaci
    /// o celý soubor, protože bloky leží pod sebou.
    @Test("Poloha je v souřadnicích obsahu, ne bloku")
    func theSpotIsInContentCoordinates() async throws {
        let scene = try scene()
        defer { scene.window.orderOut(nil) }
        let spot = try await reported(scene)
        #expect(
            spot.top >= Self.padding,
            "poloha \(spot.top) je nad odsazením \(Self.padding), tedy v souřadnicích bloku"
        )
    }

    /// **Značka se hledá podle nového čísla řádku, ne starého.** Číslo `56` má v tomhle hunku
    /// jedině stará strana (odebralo se pět řádků a přidal jeden), takže kdyby se čtla, hlášení by
    /// přišlo — a karta by v okraji stála u řádku, o kterém nález nemluví.
    ///
    /// Je to tvrzení o tom, že se něco **nestalo**, a je ověřené i obráceně: tatáž scéna se
    /// značkou na novém čísle (`theReportedSpotSitsOnTheRow`) hlášení dostane.
    @Test("Značka na starém čísle řádku se nechytí")
    func theOldLineNumberDoesNotMatch() async throws {
        let scene = try scene(markedLine: DiffMarginMaterial.oldOnlyLine)
        defer { scene.window.orderOut(nil) }
        // Nechá se blok rozvrhnout a **teprve pak** se tvrdí prázdno: bez toho by tvrzení platilo
        // jen proto, že se ještě nic nestalo (#478).
        await waitUntil("blok se rozvrhne") {
            scene.host.firstDescendant(ofType: DiffTextView.self)?.frame(ofLine: 0) != nil
        }
        await settle()
        #expect(scene.anchors.spots.isEmpty, "okraj dostal polohu řádku, který novou stranu nemá")
    }

    /// **Blok mimo nasazený pás o svou polohu nepřijde** (#469). Karta se veze s řádkem i tehdy,
    /// když se blok odpojí — jinak by nález zmizel z okraje pokaždé, když se od něj odscrolluje.
    ///
    /// Je to tvrzení o tom, že se něco **nestalo**, tedy ta cennější polovina.
    @Test("Odpojený blok polohu karty nesmaže")
    func theUnmountedBlockKeepsItsSpot() async throws {
        let scene = try scene()
        defer { scene.window.orderOut(nil) }
        let spot = try await reported(scene)
        // Pás pryč od bloku — blok se odpojí a `Color.clear` na jeho místě nic nehlásí.
        scene.viewport.band = 100_000...200_000
        await settle()
        #expect(scene.anchors.spots.count == 1, "poloha se s odpojením bloku ztratila")
        #expect(scene.anchors.spots.values.first == spot, "odpojený blok polohu přepsal")
    }

    /// **Krabice se při přepnutí toho, co se kreslí, vyprázdní** (#274 nad polohami karet): klíč
    /// `CLAUDE.md|174` má kdejaký PR, takže by karta v novém PR chvíli stála tam, kde byl řádek
    /// v tom předchozím.
    @Test("Vyprázdnění krabice polohy sundá")
    func theResetDropsTheSpots() async throws {
        let scene = try scene()
        defer { scene.window.orderOut(nil) }
        _ = try await reported(scene)
        scene.anchors.reset()
        #expect(scene.anchors.spots.isEmpty)
    }

    // MARK: - Sonda

    /// **Jak okraj vypadá** — sonda, ne test: bez `PRISM_RENDER_DIR` nedělá nic.
    ///
    /// Kreslí se **skutečný `DiffView`** s nálezy: karty v okraji (široké okno), **složená hrana
    /// se značkami** (#505, úzké okno, oba pohledy), bubliny pod řádky (stav za přepínačem) a ke
    /// každému odscrollovaná podoba, ze které se pozná, že se karty i značky vezou s řádkem.
    /// Čísla o tom neřeknou nic.
    ///
    /// ```bash
    /// TEST_RUNNER_PRISM_MEASURE=1 TEST_RUNNER_PRISM_RENDER_DIR=/tmp/render \
    ///     xcodebuild … test -only-testing:PRismTests/DiffMarginPlacementTests
    /// ```
    @Test("Sonda — jak okraj vypadá",
          .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil))
    func drawTheMargin() async throws {
        guard let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] else { return }
        let diff = DiffParser.parse(DiffMarginMaterial.text())
        // Přepínač `Nálezy pod řádky` je `@AppStorage`, takže se pro sondu nastavuje **ve vlastní
        // doméně** (#411): do `UserDefaults.standard` se z testů nesahá.
        let defaults = try ScratchDefaults("diffMargin")
        // **Štěrbina je vstup sondy, ne rozměr okna náhodou**: podle ní se rozhoduje, jestli okraj
        // stojí jako kolona, nebo jako hrana (#505). 560 je pod prahem v obou pohledech.
        let cases: [(slug: String, inline: Bool, slot: Double, layout: DiffLayout)] = [
            ("okraj", false, 1_420, .unified),
            ("hrana", false, 560, .unified),
            ("hrana-vedle", false, 560, .split),
            ("bubliny", true, 1_420, .unified),
        ]
        for scenario in cases {
            defaults.store.set(scenario.inline, forKey: "showInlineFindingBubbles")
            let host = NSHostingView(rootView: DiffMarginProbe(
                diff: diff,
                findings: DiffMarginMaterial.findings(),
                store: defaults.store,
                layout: scenario.layout,
                slot: scenario.slot
            ))
            host.frame = NSRect(x: 0, y: 0, width: scenario.slot, height: 874)
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
            // **Čeká se `await`em, ne `RunLoop.current.run(until:)`** (#296, a tady to má druhý
            // důvod): točení runloopu **vyhladoví hlavní aktor**, takže se `DispatchQueue.main`
            // z `updateNSView` nedostane ke slovu a rámečky řádků dorazí teprve po skončení sondy
            // — okraj by se pak fotil s odhadem výšky místo se změřenou polohou. Měřeno: karty
            // stály u horní hrany, ačkoli blok už dávno hlásil.
            await waitUntil("diff se rozvrhne") {
                (Self.tallestScroller(in: host)?.documentView?.frame.height ?? 0) > 0
            }
            // **A počká se i na rámečky řádků**, ne jen na výšku obsahu: teprve z nich blok
            // ohlásí, kde jeho řádky leží (`DiffMarginAnchors`) — a bez toho hlášení stojí značky
            // i karty tam, kde je posadil odhad.
            await waitUntil("blok ohlásí rámečky řádků") {
                host.firstDescendant(ofType: DiffTextView.self)?.frame(ofLine: 0) != nil
            }
            // **Mezi koly se kreslí, ne jen čeká** (#505). Blok hlásí polohy svých řádků
            // z rozvržení textového view, tedy **až když se doopravdy kreslí** — a odmlka
            // v `Task`u žádné kreslení nevyvolá. Karty si to vynutí samy (měří si výšku, a tím
            // sáhnou do stavu), kdežto hrana nic neměří: bez `display()` sonda fotila stav, ve
            // kterém polohy ještě nikdo neposlal, a značky stály nastohované u horní hrany.
            // V okně ten stav nenastane — tam se kreslí pořád.
            for _ in 0..<16 {
                host.display()
                await settle()
            }

            let slug = scenario.slug
            let scroller = Self.tallestScroller(in: host)
            print(String(
                format: "SONDA %@: štěrbina %.0f, %@, okraj %@, kolona %.0f b",
                slug,
                scenario.slot,
                scenario.layout == .split ? "vedle sebe" : "pod sebou",
                String(describing: Policy.diffSideColumns(
                    layout: scenario.layout,
                    hasMargin: !scenario.inline,
                    available: scenario.slot
                ).margin),
                Policy.diffCodeColumnWidth(
                    available: scenario.slot,
                    columns: Policy.diffSideColumns(
                        layout: scenario.layout,
                        hasMargin: !scenario.inline,
                        available: scenario.slot
                    )
                ) ?? 0
            ))
            for offset in [0.0, 260.0, 620.0] {
                if let scroller {
                    scroller.contentView.scroll(to: NSPoint(x: 0, y: offset))
                    scroller.reflectScrolledClipView(scroller.contentView)
                }
                for _ in 0..<4 { await settle() }
                print(String(
                    format: "SONDA %@ posun %.0f: obsah %.0f pt, výřez na %.0f",
                    slug,
                    offset,
                    scroller?.documentView?.frame.height ?? 0,
                    scroller?.documentVisibleRect.origin.y ?? 0
                ))
                Self.write(
                    host,
                    to: URL(filePath: directory).appending(path: "okraj-\(slug)-\(Int(offset)).png")
                )
            }
        }
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
        // Selhání zápisu sondu nepokládá, ale mlčet se nesmí.
        do {
            try data.write(to: url)
            print("SONDA kresba → \(url.lastPathComponent)")
        } catch {
            print("SONDA kresba \(url.lastPathComponent) se neuložila: \(error.localizedDescription)")
        }
    }

    static func tallestScroller(in view: NSView) -> NSScrollView? {
        var best = view as? NSScrollView
        for child in view.subviews {
            guard let found = tallestScroller(in: child) else { continue }
            let height = found.documentView?.frame.height ?? 0
            if height > (best?.documentView?.frame.height ?? 0) { best = found }
        }
        return best
    }

    // MARK: - Scéna

    private struct Scene {
        let window: NSWindow
        let host: NSHostingView<BlockMarginProbe>
        let anchors: DiffMarginAnchors
        let viewport: DiffViewport
    }

    private func scene(markedLine: Int? = nil) throws -> Scene {
        let diff = DiffParser.parse(DiffMarginMaterial.text())
        let file = try #require(diff.files.first)
        let rows = DiffRow.blocked(DiffRow.rows(of: file))
        let block = try #require(rows.compactMap { row -> (String, DiffBlock)? in
            guard case .block(let id, let block) = row else { return nil }
            return (id, block)
        }.first)
        let anchors = DiffMarginAnchors()
        let viewport = DiffViewport()
        // Pás přes celý obsah, ať se blok nasadí — sonda o nasazování netvrdí nic (to je #469).
        viewport.band = -10_000...10_000
        let line = markedLine ?? Self.line
        let host = NSHostingView(rootView: BlockMarginProbe(
            blockID: block.0,
            block: block.1,
            marks: [line: DiffMarginMark(id: "probe|\(line)", severity: .blocking)],
            anchors: anchors,
            viewport: viewport,
            padding: Self.padding
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
        return Scene(window: window, host: host, anchors: anchors, viewport: viewport)
    }

    private func reported(
        _ scene: Scene,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> DiffMarginSpot {
        await waitUntil("blok ohlásí polohu řádku", sourceLocation: sourceLocation) {
            !scene.anchors.spots.isEmpty
        }
        return try #require(scene.anchors.spots.values.first, sourceLocation: sourceLocation)
    }

    /// Horní hrana řádku, změřená **na textovém view a převedená do hostovaného view** — tedy
    /// druhou cestou než tou, kterou jde hlášení.
    private static func rowTop(in scene: Scene) throws -> Double {
        let rect = try #require(rowFrame(in: scene))
        return rect.minY
    }

    private static func rowFrame(in scene: Scene) -> CGRect? {
        guard let text = scene.host.firstDescendant(ofType: DiffTextView.self),
              let index = text.lines.firstIndex(where: { $0.newNumber == Self.line }),
              let rect = text.frame(ofLine: index)
        else { return nil }
        let inHost = scene.host.convert(rect, from: text)
        // `NSHostingView` je převrácený (y dolů), takže horní hrana je `minY`. Kdyby nebyl,
        // přepočet by musel jít od spodní hrany — proto se to nepředpokládá, ale ptá.
        guard scene.host.isFlipped else {
            return CGRect(
                x: inHost.minX,
                y: scene.host.bounds.height - inHost.maxY,
                width: inHost.width,
                height: inHost.height
            )
        }
        return inHost
    }
}

/// Blok kódu s odsazením nad sebou, v pojmenovaném prostoru obsahu — tedy to, v čem blok stojí
/// v `DiffView`u. Odsazení je tam schválně: bez něj se zapomenutý počátek bloku neprojeví.
struct BlockMarginProbe: View {
    let blockID: String
    let block: DiffBlock
    let marks: [Int: DiffMarginMark]
    let anchors: DiffMarginAnchors
    let viewport: DiffViewport
    let padding: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: padding)
            DiffBlockRowView(
                block: block,
                blockID: blockID,
                marginMarks: marks,
                marginAnchors: anchors
            )
            Spacer(minLength: 0)
        }
        .coordinateSpace(.named(DiffView.contentSpace))
        .environment(viewport)
    }
}

/// Skutečný `DiffView` s nálezy — pro sondu, která kreslí okraj i bubliny.
struct DiffMarginProbe: View {
    let diff: Diff
    let findings: [FindingGroup]
    /// Doména, ze které si `@AppStorage` bere přepínač `Nálezy pod řádky`. Vlastní, ne procesní
    /// (#411).
    let store: UserDefaults
    var layout: DiffLayout = .unified
    /// Štěrbina, kterou diff dostane. **Bez ní se `Policy.diffSideColumns` rozhoduje jen podle
    /// pohledu** (#503, `nil` = nikdo nezměřil), takže by sonda složenou hranu (#505) nikdy
    /// neukázala — okraj by ve všech šířkách zůstal kolonou.
    var slot: Double?

    @State private var target: String?

    var body: some View {
        DiffView(
            diff: diff,
            subject: "probe/margin#1",
            scrollTarget: $target,
            expansion: DiffExpansionActions(
                state: { _ in FileExpansion() },
                reveal: { _, _ in },
                collapse: nil
            ),
            folding: DiffFoldingActions(
                isFolded: { _ in false },
                toggle: { _ in },
                foldAll: { _ in },
                unfoldAll: {}
            ),
            findings: findings,
            // Akce na kartě jsou to, kvůli čemu se na obrázek koukám: bez nich by sonda fotila
            // kartu ke čtení, kdežto v okně má karta řadu `Převzít · Neplatí · Nepatří sem`.
            findingActions: FindingActions(),
            draft: DraftActions(
                canCompose: true,
                target: { finding in
                    .line(
                        path: finding.file ?? "",
                        anchor: DraftAnchor(line: finding.line ?? 1, side: .right)
                    )
                }
            ),
            layout: .constant(layout)
        )
        .background(Palette.background)
        // Obojí naráz a touž hodnotou: `availableWidth` je štěrbina diffu, `sideColumnsWidth`
        // šířka, o kterou se dělí kolony (#506). Sonda hostí `DiffView` **bez** itineráře, takže
        // je to v ní totéž číslo — v okně se liší o šířku sloupce.
        .availableWidth(slot.map { CGFloat($0) })
        .sideColumnsWidth(slot.map { CGFloat($0) })
        // Přepínač `Nálezy pod řádky` je `@AppStorage`; sonda si ho podává vlastní doménou, ne
        // parametrem — je to tatáž cesta, jakou ho čte aplikace.
        .defaultAppStorage(store)
    }
}

/// Materiál sondy i tvrzení: jeden soubor, dva hunky, v nich přidané i odebrané řádky.
///
/// **První hunk je poskládaný tak, že staré a nové číslo se rozcházejí**: odebraných řádků je pět,
/// přidaný jeden, takže stará čísla `54`–`57` v nové verzi protějšek nemají. Na tom stojí tvrzení,
/// že se značka hledá podle **nové** strany — na hunku, který začíná na prvním řádku souboru, by
/// se to prokázat nedalo, protože tam obě čísla začínají stejně.
enum DiffMarginMaterial {
    /// Nové číslo řádku, na kterém v tvrzeních nález je — **přidaný** řádek, takže staré číslo
    /// nemá vůbec.
    static let line = 51
    /// Staré číslo řádku, které v nové verzi protějšek **nemá**. Značka na něm sednout nesmí.
    static let oldOnlyLine = 56

    static func text() -> String {
        var out = "diff --git a/src/Vault/Encryptor.php b/src/Vault/Encryptor.php\n"
        out += "index 1111111..2222222 100644\n"
        out += "--- a/src/Vault/Encryptor.php\n"
        out += "+++ b/src/Vault/Encryptor.php\n"
        out += "@@ -50,8 +50,4 @@ final class Encryptor\n"
        out += "     public function __construct(\n"
        out += "-        $this->legacy = true;\n"
        out += "-        $this->deprecated = true;\n"
        out += "-        $this->stale = true;\n"
        out += "-        $this->ancient = true;\n"
        out += "-        $this->obsolete = true;\n"
        out += "+        private readonly int $ttl = self::MAX_TTL,\n"
        out += "     ) {\n"
        out += "         $this->key = $key;\n"
        out += "@@ -80,42 +76,43 @@ final class Encryptor\n"
        for line in 0..<42 {
            out += "     $value = $this->compute(\(line));\n"
        }
        out += "+        return sodium_crypto_secretbox($plain, $this->nonce(), $key);\n"
        return out
    }

    /// Tři nálezy: dva na **sousedních** řádcích (tedy ty, které se v okraji odstrkují) a jeden
    /// hluboko v druhém hunku.
    static func findings() -> [FindingGroup] {
        Policy.groups(of: [
            finding(line: 51, category: "correctness", summary: """
            Horní mez TTL je pevná konstanta; u tenantů s vlastní politikou rotace ji nejde přebít.
            """),
            finding(line: 52, category: "robustness", summary: """
            Neinicializované `$ttl` projde konstruktorem — první čtení dostane nulu.
            """),
            finding(line: 100, category: "style", summary: """
            Proč `nonce()` místo pole zrovna tady, a ne v konstruktoru?
            """),
        ])
    }

    private static func finding(line: Int, category: String, summary: String) -> Finding {
        Finding(
            reported: ReportedFinding(
                file: "src/Vault/Encryptor.php",
                line: line,
                category: category,
                verdict: .confirmed,
                shortSummary: nil,
                summary: summary,
                failureScenario: nil
            ),
            reviewer: "security-review",
            headSha: "aaaa1111"
        )
    }
}
