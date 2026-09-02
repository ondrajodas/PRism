import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// **Co okraj stojí na ostrých datech** (#503) — a jestli laguje přepnutí na tab `Změněné soubory`.
///
/// `DiffMarginWheelProbe` měří **jeden soubor o dvou tisících řádcích**, tedy scénu, kterou si
/// sonda vyrobila. Tahle sonda odpovídá na jinou otázku: **jak se to chová nad diffy, které
/// doopravdy přijdou** — jiné rozložení souborů, jiná délka hunků, stovky souborů místo jednoho.
/// Materiál jsou proto **skutečné diffy** ze složky, kterou sonda dostane v `PRISM_SHARP_DIFFS`;
/// bez ní se nespustí a řekne to. Obvykle je to výstup `gh pr diff`, ale u PR nad **300 soubory**
/// ho `gh` odmítne (`HTTP 406`, tedy tudy ho nedostane ani aplikace) a diff se skládá z `pulls/
/// {n}/files` — postup i cena jsou v [`docs/testovani.md`](../../docs/testovani.md).
///
/// Proti wheel sondě se liší ve třech věcech, a každá z nich je důvod, proč to není parametr té
/// první:
///
/// - **Měří se dvě gesta, ne jedno.** Vedle projíždění i **přepnutí tabu** `Přehled` ↔ `Soubory`,
///   protože to je to gesto, na kterém byl lag nahlášený — a je to jiná cena než projíždění:
///   přepnutím se obsah tabu **zahodí a postaví znovu**, takže se platí **první rozvržení**
///   (tatáž úvaha jako u `Driver.tab` v `DetailRelayoutMeasurement`).
/// - **Scéna je celé okno nad skutečným `AppStore`em**, ne `DiffView` samotný. Kdyby okraj špinil
///   tělo detailu (zápisem, který čte někdo nad diffem), v hostovaném `DiffView`u by se to
///   neprojevilo vůbec — a přesně tuhle třídu chyby sonda hledá.
/// - **Střídá se A/B/A/B po celých případech** (#274), a k tomu se měří **základ bez nálezů**:
///   bez něj se rozdíl nedá přiřadit, protože scéna s bublinami má **jiný obsah** (bubliny
///   rozrážejí bloky). Tatáž lekce jako u wheel sondy — první podoba té měřila jen okraj proti
///   bublinám a vyšlo z ní „+17 %“, což byl ze dvou třetin rozdíl scén.
///
/// **Naměřilo by to rozdíl, kdyby zhoršení bylo?** (#478) Sonda na to odpovídá **sama a v čísle**:
/// varianta `okraj, čtyřnásobek karet` kreslí tentýž okraj se **čtyřikrát** tolika kartami. Když
/// vyjde jako `okraj`, měřidlo druhou vrstvu nad blokem **nevidí** a čísla z celé tabulky netvrdí
/// nic. (Ablace pásu by byla přímější, ale `Policy.isBlockMounted` je čistá funkce bez přepínače
/// a hák do `App/` kvůli měření tam nemá co dělat — sonda proto zvětšuje hustotu **daty**.)
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, materiál v `TEST_RUNNER_PRISM_SHARP_DIFFS`.
@MainActor
@Suite(
    "Okraj na ostrých datech (#503)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil),
    .serialized
)
struct DiffMarginSharpProbe {
    /// Kolik přepnutí tabu v sérii. Jedno je pod rozlišením měřidla; deset je řádově to, co
    /// člověk udělá, když mezi diffem a přehledem přeskakuje při čtení.
    ///
    /// **Dá se stáhnout `PRISM_SHARP_SWITCHES`**, a je to potřeba u krajního případu: nad diffem
    /// o třech tisících souborech stojí jedno přepnutí sekundy, takže deset v sérii × dvě série
    /// × pět variant je čtvrt hodiny jen na jeden vzorek. Cena za to je hrubší rozlišení — proto
    /// se s tabulkou vypisuje i to, kolika přepnutími se to změřilo.
    private static var switches: Int {
        ProcessInfo.processInfo.environment["PRISM_SHARP_SWITCHES"].flatMap(Int.init) ?? 10
    }
    /// Kroků kolečka v gestu a bodů na krok — **tatáž hodnota jako u `DiffMarginWheelProbe`**,
    /// aby se čísla dala srovnat napříč sondami.
    private static let wheelSteps = 150
    private static let wheelStep = 40.0

    private static let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013)

    @Test("Přepnutí tabu a projíždění nad skutečnými diffy")
    func sharpCost() async throws {
        let material = try Self.material()
        for sample in material {
            var costs: [Key: [Double]] = [:]
            var facts: [Key: String] = [:]
            // **Kolik karet ta scéna doopravdy má, se musí říct číslem.** Bez toho by se nedalo
            // odlišit „okraj stojí málo“ od „okraj v té scéně vůbec nebyl“ — a to druhé je snadné
            // omylem změřit: `Policy.marginCards` kartu vydá jedině pro řádek, který se **kreslí**
            // (soubor rozbalený, nález na existujícím řádku). Rozeseté nálezy sedí na skutečných
            // přidaných řádcích právě proto.
            print("SONDA materiál \(sample.name): \(sample.files) souborů, \(sample.rows) řádků diffu,"
                + " nálezů \(sample.findings.count) → karet v okraji \(Self.cards(in: sample, sample.findings))"
                + ", hustě \(sample.denseFindings.count) → \(Self.cards(in: sample, sample.denseFindings))"
                + ", skutečných \(sample.realFindings.count) → \(Self.cards(in: sample, sample.realFindings))")
            // A/B/A/B: dvě série, uvnitř střídavě po variantách. Drift sezení je větší než hledaný
            // rozdíl (#274), takže série po variantě by měřila, jak se stroj během měření zahřál.
            for _ in 0..<2 {
                for variant in Variant.allCases where sample.has(variant) {
                    // **Každé gesto ve vlastní scéně, a je to opravená chyba, ne opatrnost.**
                    // Do první podoby sondy se obojí měřilo nad jednou scénou a projíždění po
                    // přepínání tabů **nikdy nikam nedojelo** (`dojelo na 0` u všech variant,
                    // 0,03 s CPU) — tedy tatáž hodnota pro funguje i nefunguje (#478). Přepnutím
                    // se obsah tabu zahodí a postaví znovu, takže v hierarchii chvíli visí
                    // **starý** scroller s vysokým dokumentem; `tallestScroller` sáhne na něj,
                    // šťouchnutí i gesto na něm projdou, ale rozvržení mu počátek při každém kole
                    // srovná na nulu. Ve vlastní scéně ta dvojznačnost není.
                    for gesture in Self.gestures {
                        let key = Key(sample: sample.name, gesture: gesture, variant: variant)
                        let scene = try await Self.scene(sample: sample, variant: variant)
                        defer { scene.window.orderOut(nil) }
                        guard let mounted = await Self.ready(scene) else {
                            // **Rozdělaná scéna se neměří.** Číslo z ní vypadá v tabulce jako
                            // číslo, a přitom měří první rozvržení místo gesta (#478).
                            print("SONDA \(sample.name) / \(variant.rawValue) / \(gesture.rawValue):"
                                + " scéna se neusadila, měření vynecháno")
                            continue
                        }
                        switch gesture {
                        case .tab:
                            let cost = Self.measureTabSwitch(scene)
                            costs[key, default: []].append(cost)
                            facts[key] = "usazeno na \(mounted) blocích, "
                                + "\(Self.mounts(in: scene.window.contentView ?? NSView())) nasazení bloku"
                            print(String(
                                format: "MĚŘENÍ %@ / %@ / přepnutí: %.2f s CPU (%.0f ms na jedno) — %@",
                                sample.name, variant.rawValue, cost,
                                cost / Double(Self.switches) * 1000, facts[key] ?? ""
                            ))
                        case .wheel:
                            let (cost, landed, content) = Self.measureWheel(scene)
                            // **Gesto, které nikam nedojelo, se nezapíše.** Je to ta past z #478:
                            // nula se v tabulce nedá odlišit od „nic to nestojí“.
                            guard landed > 0 else {
                                print("SONDA \(sample.name) / \(variant.rawValue): gesto nikam"
                                    + " nedojelo (obsah \(Int(content))), měření vynecháno"
                                    + " — \(Self.screenState())")
                                continue
                            }
                            costs[key, default: []].append(cost)
                            facts[key] = String(
                                format: "dojelo na %.0f z obsahu %.0f, usazeno na %d blocích",
                                landed, content, mounted
                            )
                            print(String(
                                format: "MĚŘENÍ %@ / %@ / projíždění: %.2f s CPU — %@",
                                sample.name, variant.rawValue, cost, facts[key] ?? ""
                            ))
                        }
                    }
                }
            }
            Self.report(sample: sample.name, costs: costs, facts: facts)
        }
    }

    // MARK: - Výpis

    private static func report(sample: String, costs: [Key: [Double]], facts: [Key: String]) {
        print("SOUHRN \(sample) — přepnutí měřeno po \(switches) v sérii,"
            + " projíždění gestem \(wheelSteps) × \(Int(wheelStep)) pt")
        for gesture in Gesture.allCases {
            for variant in Variant.allCases {
                let key = Key(sample: sample, gesture: gesture, variant: variant)
                let values = costs[key] ?? []
                guard !values.isEmpty else { continue }
                let average = values.reduce(0, +) / Double(values.count)
                let unit = gesture == .tab
                    ? String(format: " (%.0f ms na přepnutí)", average / Double(switches) * 1000)
                    : ""
                print("SOUHRN \(sample) | \(gesture.rawValue) | \(variant.rawValue) | "
                    + values.map { String(format: "%.2f", $0) }.joined(separator: " / ")
                    + String(format: " s CPU, průměr %.2f", average) + unit
                    + " — \(facts[key] ?? "")")
            }
        }
    }

    private struct Key: Hashable {
        let sample: String
        let gesture: Gesture
        let variant: Variant
    }

    /// Co se měří. **Dvě gesta, ne jedno**: přepnutí platí za první rozvržení, projíždění za
    /// druhou vrstvu nad blokem — a lag byl nahlášený u toho prvního.
    enum Gesture: String, CaseIterable {
        case tab = "přepnutí na Změněné soubory"
        case wheel = "projíždění kolečkem"
    }

    /// Která gesta se v tomhle běhu měří — `PRISM_SHARP_GESTURE` (`tab`, `wheel`, jinak obojí).
    ///
    /// Existuje proto, že **projíždění je vázané na odemčenou obrazovku a přepínání ne**: gesto
    /// kolečkem se nad zamčeným sezením nedoručí (shield okno je nad naším), kdežto přepnutí tabu
    /// pohání zápis do store a obrazovku nepotřebuje. Bez toho rozdělení by se půlka, která jde
    /// změřit vždycky, platila čekáním na tu druhou.
    private static var gestures: [Gesture] {
        switch ProcessInfo.processInfo.environment["PRISM_SHARP_GESTURE"] {
        case "tab": [.tab]
        case "wheel": [.wheel]
        default: Gesture.allCases
        }
    }

    /// Jak je na tom obrazovka. **Patří to k vynechanému měření, ne do komentáře**: „gesto nikam
    /// nedojelo“ bez příčiny se nedá odlišit od rozbitého okraje (#478), a příčina je tady
    /// zvenčí — nad zamčeným sezením leží shield okno nad tím naším a událost kolečka se
    /// nedoručí (v logu je to vidět jako `elementWindow(3) is lower than shield(2001)`).
    private static func screenState() -> String {
        guard let session = CGSessionCopyCurrentDictionary() as NSDictionary? else {
            return "stav sezení se nedal přečíst"
        }
        // **Tři odpovědi, ne dvě.** Chybějící klíč znamená „nevím“, a `?? false` by z něj udělalo
        // „obrazovka je odemčená, příčina je jinde“ — tedy věta, která tvrdí víc, než co data
        // unesou, a poslala by hledání příčiny do kódu okraje.
        guard let locked = (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue else {
            return "jestli je obrazovka zamčená, se z sezení nedalo zjistit"
        }
        return locked
            ? "obrazovka je ZAMČENÁ, takže se gesto doručit nemohlo"
            : "obrazovka je odemčená, příčina je jinde"
    }

    /// Jak se nálezy kreslí. Pořadí je pořadí měření.
    enum Variant: String, CaseIterable {
        /// Diff bez nálezů: základ, proti kterému se čte, co si která vrstva bere.
        case clean = "bez nálezů"
        /// Karty v okraji (#503).
        case margin = "okraj"
        /// Bubliny pod řádky, tedy stav do #503.
        case bubbles = "bubliny"
        /// **Kalibrace měřidla, ne varianta k výběru** (#478): tentýž okraj, ale se **čtyřikrát**
        /// tolika kartami. Ptá se, jestli měřidlo druhou vrstvu nad blokem **vidí** — když tahle
        /// vyjde jako `okraj`, čísla z celé tabulky netvrdí nic, protože měřidlo nemá rozlišení.
        ///
        /// **Ablace pásu by byla lepší, ale nejde ze sondy** (`Policy.isBlockMounted` je čistá
        /// funkce bez přepínače a hák do `App/` kvůli měření tam nemá co dělat), takže se hustota
        /// karet zvětšuje daty — tedy tím koncem, na který sonda dosáhne.
        case dense = "okraj, čtyřnásobek karet"
        /// Okraj s **nálezy ze skutečně proběhlého review** — jen u vzorku, který k diffu má
        /// sidecar `<jméno>.findings.json` z `ReportFindings`.
        ///
        /// Existuje proto, že rozeseté karty jsou **horní odhad**, ne obraz: skutečné review nad
        /// `PRism#499` (45 souborů, +4670) nahlásilo **dva** nálezy, ne jedenáct. Bez téhle
        /// varianty by z tabulky nešlo poznat, že se běžná scéna liší od té měřené o řád.
        case real = "okraj, skutečné nálezy z review"
    }

    // MARK: - Gesta

    private static func measureTabSwitch(_ scene: Scene) -> Double {
        let started = mainThreadCPUSeconds()
        for _ in 0..<switches {
            scene.store.setDetailTab(.overview, for: pr)
            _ = spinMainRunLoop(seconds: 0.016)
            scene.store.setDetailTab(.filesChanged, for: pr)
            _ = spinMainRunLoop(seconds: 0.016)
        }
        return mainThreadCPUSeconds() - started
    }

    /// - Returns: cena gesta, kam posuvník dojel, a výška dokumentu.
    private static func measureWheel(_ scene: Scene) -> (cost: Double, landed: Double, content: Double) {
        guard let scroller = tallestScroller(in: scene.window.contentView ?? NSView()) else {
            // **Chybějící scroller se hlásí**, ne obchází: nula z gesta, které nemělo kam jít,
            // vypadá v tabulce jako „nic to nestojí“ (#478).
            print("SONDA projíždění: v okně není scroller — gesto se nevypálilo")
            return (0, 0, 0)
        }
        let started = mainThreadCPUSeconds()
        let landed = WheelGesture.scroll(
            over: scroller,
            in: scene.window,
            steps: wheelSteps,
            step: wheelStep
        )
        let cost = mainThreadCPUSeconds() - started
        return (cost, landed, Double(scroller.documentView?.frame.height ?? 0))
    }

    /// Kolikrát se nasadily bloky, které v okně **visí teď** (#469 proti #472).
    ///
    /// **Není to počet nasazení za celé měření, a nesmí se tak čtít**: počitadlo si nese každá
    /// instance sama, takže co se během přepínání vyrobilo a zahodilo, se v součtu neobjeví.
    /// Nula proto znamená „dnešní bloky jsou čerstvé“, ne „nic se nenasazovalo“. Jako fakt vedle
    /// čísla to stačí — je to kontrola, že se diff doopravdy staví, ne měřená hodnota.
    private static func mounts(in view: NSView) -> Int {
        let own = (view as? DiffPairBlockContainer)?.mounts ?? (view as? DiffTextView)?.mounts ?? 0
        return view.subviews.reduce(own) { $0 + mounts(in: $1) }
    }

    // MARK: - Scéna

    private struct Scene {
        let window: NSWindow
        let store: AppStore
        /// **Drží se kvůli životnosti, ne kvůli čtení** — a je to ten případ, na který se
        /// v tomhle repu ptá pravidlo „stav, který nikdo nečte“. Obojí uklízí po sobě až
        /// v `deinit`u (doména v `~/Library/Preferences`, složka na disku), takže bez odkazu
        /// v scéně by zmizely uprostřed měření: `@AppStorage` by čekal přepínač v doméně, která
        /// už neexistuje, a store by psal draft do smazané cache.
        let defaults: ScratchDefaults
        let directory: TemporaryDirectory
    }

    private static func scene(sample: Sample, variant: Variant) async throws -> Scene {
        let defaults = try ScratchDefaults("diffMarginSharp")
        defaults.store.set(variant == .bubbles, forKey: "showInlineFindingBubbles")

        let directory = try TemporaryDirectory()
        let gateway = FakeGitHubGateway(
            always: .success([summary]),
            detail: .success(detail),
            diffs: [.success(sample.text)],
            conversations: [.success(ConversationFixture.conversation(comments: 40))]
        )
        let store = AppStore(
            gateway: gateway,
            // `stopAfter: 1`: `ContentView` si v `.task` pouští polling a fake hodiny nespí, takže
            // by se smyčka točila naplno a měřilo by se ona (tatáž past jako u #472).
            time: FakeTimeSource(stopAfter: 1),
            drafts: ReviewDraftStore(layout: CacheLayout(root: directory.url))
        )
        await store.refresh()
        await store.loadDetail(for: summary)
        await store.loadDiff(for: summary)
        await store.loadConversation(for: summary)
        let reported = sample.reported(for: variant)
        if !reported.isEmpty {
            store.reviewRecords[pr] = ReviewRecord(
                pullRequest: summary.id,
                headSha: "aaaa1111",
                runs: [makeStoredRun(findings: reported, headSha: "aaaa1111")]
            )
        }
        store.openTab(pr)
        store.setDetailTab(.filesChanged, for: pr)

        let clock = RelayoutClock()
        let host = NSHostingView(
            rootView: WindowRelayoutHost(store: store, summary: summary, scene: .window, clock: clock)
                .background(Palette.background)
                // Přepínač `Nálezy pod řádky` je `@AppStorage`; sonda si ho podává **vlastní
                // doménou** (#411), ne procesní — je to tatáž cesta, jakou ho čte aplikace.
                .defaultAppStorage(defaults.store)
        )
        host.sizingOptions = [.minSize]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1512, height: 874),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.setContentSize(NSSize(width: 1512, height: 874))
        // **Okno musí být na obrazovce**, ne mimo ni: událost kolečka nese
        // `mouseEventWindowUnderMousePointer`, a nad oknem odloženým na −10 000 se gesto nedoručí
        // — změřeno u #503, posuvník zůstal na nule u obou variant, tedy tatáž hodnota pro
        // funguje i nefunguje (#478).
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        window.level = .floating
        window.orderFrontRegardlessUnanimated()
        return Scene(window: window, store: store, defaults: defaults, directory: directory)
    }

    /// Nechá scénu **usadit**, ne jen rozvrhnout — podmínka měření, ne opatrnost (#503).
    ///
    /// Na první rozvržení se nasadí **všechny** bloky a hned nato se odpojí (#469), takže gesto
    /// vypálené do rozdělané scény jde přes desítky `NSTextView` místo přes pět. Změřeno **při
    /// stavbě téhle sondy**, nad `PRism#499`: nerozvržená scéna dala **22,8 s** CPU proti **1,7 s**
    /// u téže varianty, tedy třináctinásobek — a protože se to stane kterékoli variantě, vyjde
    /// z toho pořadí podle toho, která se chytila nerozvrženě.
    ///
    /// Proti wheel sondě (#503) se to muselo předělat ve dvou věcech, a obě z toho měření vylezly:
    ///
    /// - **Šťouchnutí posuvníkem se opakuje, nedělá se jednou.** Pás zapisuje
    ///   `onScrollGeometryChange`, a ten nad nehybným výřezem nemusí přijít vůbec; jedno
    ///   šťouchnutí **před** čekáním tedy nestačí, protože v tu chvíli nemusí být scéna ještě
    ///   rozvržená. Nad `PRism#499` z toho zůstalo **168 nasazených bloků** i po dvou minutách
    ///   čekání.
    /// - **Strop na počet bloků nemůže být konstanta.** Wheel sonda měří **jeden** soubor
    ///   o dvou tisících řádcích, takže jí čtrnáct stačí; do pásu nad diffem o pětačtyřiceti
    ///   souborech padne jinak velký počet a nad třemi tisíci ještě jinak. Usazení se proto pozná
    ///   **propadem proti vrcholu** (na čtvrtinu a míň), ne absolutní hodnotou.
    ///
    /// - Returns: kolik bloků zůstalo nasazených, nebo `nil`, když se scéna neusadila. **`nil` se
    ///   nesmí měřit**: číslo z rozdělané scény vypadá v tabulce jako číslo (#478).
    private static func ready(_ scene: Scene) async -> Int? {
        guard let root = scene.window.contentView else { return nil }
        guard await waitUntil("diff se rozvrhne", {
            (tallestScroller(in: root)?.documentView?.frame.height ?? 0) > root.bounds.height
        }) else { return nil }

        var peak = 0
        var quiet = 0
        var previous = -1
        var rounds = 0
        let settled = await waitUntil("bloky mimo pás se odpojí a usadí") {
            let now = blocks(in: root)
            peak = max(peak, now)
            quiet = now == previous ? quiet + 1 : 0
            previous = now
            rounds += 1
            // Šťouchnutí každých ~800 kol (`waitUntil` se ptá po milisekundě), dokud se pás
            // nezapíše. Levné, a jediné, co scénu z „nasazeno všechno“ dostane.
            if rounds.isMultiple(of: 800) { nudge(root) }
            return quiet >= 8 && now <= max(peak / 4, minimumSettledBlocks)
        }
        guard settled else { return nil }
        // A ještě odmlka navíc: usazená AppKitová hierarchie neznamená, že se dopočítaly polohy
        // karet — ty jdou přes `DispatchQueue.main` z `updateNSView`.
        for _ in 0..<4 { await settle() }
        return blocks(in: root)
    }

    /// Kolik bloků smí zůstat, aniž by se to považovalo za rozdělanou scénu, i kdyby vrchol byl
    /// nízký. Dva, protože pás drží nejmíň blok pod výřezem a jeho soused.
    private static let minimumSettledBlocks = 2

    /// Šťouchnutí posuvníkem o bod a zpátky — tím se pás jednou zapíše.
    private static func nudge(_ root: NSView) {
        guard let scroller = tallestScroller(in: root) else { return }
        scroller.contentView.scroll(to: NSPoint(x: 0, y: 1))
        scroller.reflectScrolledClipView(scroller.contentView)
        scroller.contentView.scroll(to: .zero)
        scroller.reflectScrolledClipView(scroller.contentView)
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

    /// Jeden měřený diff. **Skutečný výstup `gh pr diff`**, ne vyrobená scéna.
    struct Sample {
        let name: String
        let text: String
        let files: Int
        let rows: Int
        /// Nálezy **na řádcích, které v tom diffu doopravdy jsou** — jinak by karta v okraji
        /// nevznikla (`Policy.marginCards` chce řádek, který se kreslí) a měřily by se dvě scény
        /// bez karet.
        let findings: [ReportedFinding]
        /// Čtyřnásobek téhož, na kalibraci měřidla (#478).
        let denseFindings: [ReportedFinding]
        /// Nálezy ze **skutečně proběhlého** review, když k diffu je sidecar. Prázdné = varianta
        /// `real` se u tohohle vzorku neměří.
        let realFindings: [ReportedFinding]

        func has(_ variant: Variant) -> Bool {
            variant != .real || !realFindings.isEmpty
        }

        func reported(for variant: Variant) -> [ReportedFinding] {
            switch variant {
            case .clean: []
            case .margin, .bubbles: findings
            case .dense: denseFindings
            case .real: realFindings
            }
        }
    }

    /// Kolik nálezů se do diffu rozseje. **Jedenáct, a je to horní odhad, ne obraz** — okraj
    /// s jednou kartou o ceně neřekne nic, takže se měří scéna hustší, než jaká obvykle přijde.
    ///
    /// **Skutečné review nad `PRism#499` nahlásilo dva nálezy**, ne jedenáct (45 souborů, +4670,
    /// `code-review:code-review`, 84 tahů, 21,97 USD). Jedenáct je tedy pětinásobek běžné
    /// hustoty; kolik stojí ta skutečná, měří varianta `real` ze sidecaru.
    private static let findingCount = 11

    private static func material() throws -> [Sample] {
        guard let root = ProcessInfo.processInfo.environment["PRISM_SHARP_DIFFS"] else {
            // **Chybějící materiál se hlásí**, ne obchází: sonda, která tiše nic nezměřila,
            // vypadá jako sonda, která prošla.
            Issue.record("PRISM_SHARP_DIFFS nenastavené — sonda nemá co měřit")
            return []
        }
        let directory = URL(filePath: root)
        let names = try FileManager.default
            .contentsOfDirectory(atPath: root)
            .filter { $0.hasSuffix(".diff") }
            .sorted()
        return try names.compactMap { name in
            let text = try String(contentsOf: directory.appending(path: name), encoding: .utf8)
            guard !text.isEmpty else {
                print("SONDA materiál \(name): prázdný soubor, přeskočeno")
                return nil
            }
            let diff = DiffParser.parse(text)
            let spots = addedSpots(in: diff)
            let stem = name.replacingOccurrences(of: ".diff", with: "")
            return Sample(
                name: stem,
                text: text,
                files: diff.files.count,
                rows: TextLines.all(text).count,
                findings: findings(over: spots, count: findingCount),
                denseFindings: findings(over: spots, count: findingCount * 4),
                realFindings: realFindings(named: stem, in: directory)
            )
        }
    }

    /// Nálezy rozeseté po **skutečných** přidaných řádcích diffu, dva z nich na **sousedních** —
    /// tedy i s odstrkováním, na které se okraj ptá.
    ///
    /// Souhrny mají délku, jakou mívají skutečné: karta se podle nich sází, takže krátké „nález“
    /// by měřilo užší kartu, než jaká v okně stojí.
    /// Nálezy ze **skutečného** `ReportFindings` — sidecar `<jméno>.findings.json` vedle diffu,
    /// obsah je pole tak, jak ho reviewer poslal.
    ///
    /// **Chybějící sidecar není chyba** (většina vzorků ho nemá a varianta se pak neměří), ale
    /// **rozbitý je**: `try?` by z nečitelného souboru udělal „review nic nenašlo“, tedy tvrzení,
    /// které data neunesou.
    private static func realFindings(named stem: String, in directory: URL) -> [ReportedFinding] {
        let url = directory.appending(path: "\(stem).findings.json")
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([ReportedFinding].self, from: data)
            print("SONDA \(stem): \(items.count) skutečných nálezů ze sidecaru")
            return items
        } catch {
            Issue.record("Sidecar \(url.lastPathComponent) se nedal přečíst: \(error)")
            return []
        }
    }

    /// Kolik karet z těch nálezů v okraji doopravdy vznikne — **`Policy` na to odpoví bez okna**,
    /// takže se to dá tvrdit vedle čísla, ne odhadovat z výšky dokumentu.
    ///
    /// Soubory jsou brané jako **rozbalené a bez odkrytého kontextu**, tedy tak, jak je scéna má
    /// hned po načtení diffu: nic se nerozklikávalo.
    private static func cards(in sample: Sample, _ reported: [ReportedFinding]) -> Int {
        let diff = DiffParser.parse(sample.text)
        let sources = diff.files.map {
            DiffMarginSource(file: $0, revealed: RevealedLines(), isFolded: false)
        }
        return Policy.marginCards(of: Policy.groups(of: findings(from: reported)), in: sources).count
    }

    /// Nálezy tak, jak je vidí store — reviewer a `headSha` jsou tytéž, jaké scéna zapisuje.
    private static func findings(from reported: [ReportedFinding]) -> [Finding] {
        reported.map { Finding(reported: $0, reviewer: "code-review", headSha: "aaaa1111") }
    }

    private static func addedSpots(in diff: Diff) -> [(file: String, line: Int)] {
        var spots: [(file: String, line: Int)] = []
        for file in diff.files {
            guard let path = file.newPath else { continue }
            for hunk in file.hunks {
                for line in hunk.lines where line.kind == .added {
                    guard let number = line.newNumber else { continue }
                    spots.append((path, number))
                }
            }
        }
        return spots
    }

    private static func findings(
        over spots: [(file: String, line: Int)],
        count: Int
    ) -> [ReportedFinding] {
        guard !spots.isEmpty else { return [] }
        // Rozestup po celém diffu, ne prvních jedenáct řádků: karty mají být rozeseté tak, jak je
        // reviewer nahlásí — po celé délce, ne v jednom hunku.
        let step = max(spots.count / count, 1)
        var reported: [ReportedFinding] = []
        for index in 0..<min(count, spots.count) {
            let spot = spots[index * step]
            reported.append(makeReported(
                file: spot.file,
                line: spot.line,
                category: index.isMultiple(of: 3) ? "correctness" : "style",
                summary: "Návratová hodnota se zahazuje, takže selhání zápisu vypadá v UI jako "
                    + "„nic tu nebylo“ — patří to do stavu, ne do `try?`."
            ))
            // Druhá karta na **sousedním** řádku: odstrkování je ta část okraje, která počítá
            // z rámečků řádků, a bez ní by se měřil okraj bez `L` spojnice.
            if index == 1,
               let next = spots.first(where: { $0.file == spot.file && $0.line == spot.line + 1 }) {
                reported.append(makeReported(
                    file: next.file,
                    line: next.line,
                    category: "style",
                    summary: "Tentýž vzor o řádek níž — karta se má odstrčit a spojnice zalomit."
                ))
            }
        }
        return reported
    }

    private static let summary = PullRequestSummary(
        id: pr,
        title: "Route autolink requests through api.Client",
        author: "williammartin",
        url: URL(string: "https://github.com/cli/cli/pull/14013")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .open
    )

    private static let detail = PullRequest(
        id: summary.id,
        title: summary.title,
        author: summary.author,
        headSha: "aaaa1111",
        baseSha: "bbbb2222",
        url: summary.url,
        updatedAt: summary.updatedAt,
        state: .open,
        body: "Popis pull requestu, nad kterým se měří okraj na ostrých datech."
    )
}
