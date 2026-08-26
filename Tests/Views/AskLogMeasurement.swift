import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Měření, ne test (#452): **co stojí první rozvržení rozhovoru** — a obě strany rozhodnutí
/// „líný seznam, nebo ne“.
///
/// Existuje proto, že rozhodnutí se v tomhle repu **neopisuje z jedné nebo druhé strany** — osa
/// konverzace šla u #361 na pevný stack a diff zůstal líný, takže samotné „jinde je to takhle“
/// neříká nic. Cena pevného stacku je **první rozvržení**: vyrobí se všechny bubliny, ne jen
/// viditelné, a roste to lineárně s jejich počtem. Otázka je, jestli se rozhovor vejde pod strop,
/// který #361 naměřilo u osy (44 uzlů 55 ms, 300 uzlů 413 ms — viz `ConversationAxisShapeProbe`).
///
/// **Rozhovor je shora omezený jinak než osa**, a v tom je celá odpověď: osa má strop z dotazu
/// (`first: 100` na čtyři seznamy, tedy čtyři stovky uzlů), kdežto tady je každá zpráva
/// **zaplacená session** — dvacet otázek nad jedním PR je hodně a stovka je krajnost, ke které se
/// v praxi nikdo nedostane.
///
/// ## Měří se v okně, a je to oprava (#458)
///
/// První podoba tohohle měření hostovala `AskView` v `NSHostingView` **bez `NSWindow`u** — past,
/// kterou má tenhle repos popsanou u `AskTabRenderProbe` a `DetailTabRenderProbe`: **`ScrollView`
/// bez okna obsah nerozvrhne**. Nález Copilota na #458, a **mechanismus se potvrdil**: bez okna
/// vyjde `obsah 0 pt`, takže scroller o výšce dokumentu neví nic.
///
/// **Závěr „měření podhodnocuje cenu“ se ale nepotvrdil, a je to změřené, ne odhadnuté.** Bez okna
/// je pevný stack **dražší**, ne levnější (300 bublin: 283 / 301 / 308 ms bez okna proti
/// 242 / 238 / 257 ms v okně), a **počet vyrobených prvků je totožný** (907). Neúplné je tedy to,
/// co scroller ví o svém dokumentu, ne to, kolik práce si stack vyžádal — a `VStack` proto
/// z opraveného měření vychází stejně jako z původního.
///
/// Vedle času se od té doby vypisuje **výška obsahu a počet prvků** — bez nich by číslo netvrdilo
/// nic a přesně tuhle chybu by nešlo poznat. Okno se zakládá stejně jako
/// v `ConversationAxisShapeProbe`, se kterým se ta čísla porovnávají; série se **střídají**
/// A/B/A/B (#274), protože drift sezení je větší než hledaný rozdíl.
///
/// ## Co z toho vyšlo (Debug, okno 1047×700, 2026-08-26)
///
/// | Bublin | `VStack` | `LazyVStack` | Obsah | Prvků (`VStack` / `LazyVStack`) |
/// |---|---|---|---|---|
/// | 10 | **14 / 15 / 10 ms** | 5,1 / 4,7 / 4,6 | 868 pt | 37 / 33 |
/// | 20 | **18 / 18 / 19** | 4,6 / 4,6 / 4,4 | 1 718 pt | 67 / 33 |
/// | 50 | **44 / 50 / 42** | 4,7 / 4,7 / 4,6 | 4 268 pt | 157 / 33 |
/// | 100 | **87 / 89 / 84** | 4,7 / 4,5 / 4,3 | 8 518 pt | 307 / 33 |
/// | 300 | **242 / 238 / 257** | 4,6 / 5,0 / 6,2 | 25 518 pt | 907 / 33 |
///
/// Čte se z toho jedno: **líný seznam je levnější, a přesto se nebere.** Cena pevného stacku je
/// při reálném počtu otázek **pod dvacet milisekund jednou při otevření tabu** a i v krajnosti
/// zůstává pod tím, co #361 naměřilo u osy (413 ms na 300 uzlů) a **s čím se u ní pevný stack
/// přijal**. Za to se nekreslí kolo `updateItemPhases` → `propagate_dirty`, kvůli kterému #361
/// líný seznam z osy vyhodilo.
///
/// Časy se **netvrdí** `#expect`em: na jiném stroji vyjdou jinak. **Pouští se ručně**, a proměnná
/// musí mít prefix `TEST_RUNNER_` — jen ty `xcodebuild` do testovacího procesu pustí; bez něj se
/// suita **tiše přeskočí** a nezměří se nic:
///
/// ```bash
/// TEST_RUNNER_PRISM_MEASURE=1 \
///     xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex test \
///     -only-testing:PRismTests/AskLogMeasurement
/// ```
@MainActor
@Suite(
    "Měření rozhovoru (#452)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct AskLogMeasurement {
    /// Kolik bublin se poměřuje. Horní hranice je **krajnost**, ne očekávaný stav: tři sta otázek
    /// nad jedním PR je tři sta zaplacených session.
    static let sizes = [10, 20, 50, 100, 300]

    @Test("Kolik stojí první rozvržení rozhovoru")
    func firstLayoutCost() {
        for count in Self.sizes {
            var times: [AskLogShape: [Double]] = [:]
            var facts: [AskLogShape: String] = [:]
            for _ in 0..<3 {
                for shape in AskLogShape.allCases {
                    let (elapsed, fact) = measureFirstLayout(shape: shape, count: count)
                    times[shape, default: []].append(elapsed)
                    facts[shape] = fact
                }
            }
            for shape in AskLogShape.allCases {
                let values = times[shape] ?? []
                print("MĚŘENÍ první rozvržení \(count) bublin, \(shape.rawValue): "
                    + values.map { String(format: "%.1f", $0) }.joined(separator: " / ")
                    + " ms — \(facts[shape] ?? "")")
            }
        }
    }

    // MARK: - Okno a materiál

    /// Jedno postavení okna a jeho první rozvržení. Vrací čas v milisekundách a to, co v okně
    /// doopravdy vzniklo.
    ///
    /// **`ContinuousClock`, ne `Date`**: `Date` jde za systémovým časem, takže posun hodin (NTP,
    /// uspání stroje) by měřenou latenci posunul nebo poslal do minusu.
    private func measureFirstLayout(shape: AskLogShape, count: Int) -> (Double, String) {
        let messages = Self.messages(count: count)
        let host = NSHostingView(rootView: ShapedAskLog(messages: messages, shape: shape))
        host.frame = NSRect(x: 0, y: 0, width: 1_047, height: 700)
        // **Okno musí být**, i když se nic nekreslí: `ScrollView` bez `NSWindow`u obsah
        // nerozvrhne, takže by se měřilo prázdno (#458).
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        let duration = ContinuousClock().measure { host.layoutSubtreeIfNeeded() }
        let elapsed = Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1e15
        let content = Self.tallestScroller(in: host)?.documentView?.frame.height ?? 0
        let fact = "obsah \(Int(content)) pt, \(Self.descendants(of: host)) prvků"
        window.orderOut(nil)
        return (elapsed, fact)
    }

    private static func descendants(of view: NSView) -> Int {
        view.subviews.reduce(1) { $0 + descendants(of: $1) }
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

    /// Materiál: střídavě otázka a odpověď, odpověď s markdownem a s dokladem — tedy to, co se
    /// doopravdy kreslí. Kratší text by měřil prázdné bubliny.
    private static func messages(count: Int) -> [AskMessage] {
        (0..<count).map { index in
            index.isMultiple(of: 2)
                ? AskMessage(
                    speaker: .mine,
                    text: "Proč se ten mutex bere kolem celého `fetch`, a ne jen kolem zápisu \(index)?",
                    at: Date(timeIntervalSince1970: Double(index))
                )
                : AskMessage(
                    speaker: .claude,
                    text: """
                        Protože `fetch` po minulé změně **sám plní cache**, ne jen čte — zámek \
                        kolem zápisu by dvě souběžná volání pustil oběma dovnitř.

                        Stojí to na `a1f77c2`. V tomhle PR je to src/SecretClient.php:\(index).
                        """,
                    at: Date(timeIntervalSince1970: Double(index)),
                    readFiles: ["SecretClient.php", "CacheWarmer.php"],
                    usage: RunUsage(cost: 0.04, duration: .seconds(12), turns: 4)
                )
        }
    }
}

/// Které podoby rozhovoru se poměřují. **Jen dvě** — cokoli mezi tím (líný seznam až nad N
/// bublinami) má vazbu z #361 pořád, jen v méně případech.
enum AskLogShape: String, CaseIterable {
    /// `VStack` — podoba, kterou má aplikace.
    case eager = "VStack"
    /// `LazyVStack` — podoba, kterou #361 z osy konverzace vyhodilo.
    case lazyStack = "LazyVStack"
}

/// Rozhovor v obou podobách. **Skutečné `AskBubbleView`** nad skutečnými `AskMessage` — bez
/// markdownu, dokladu a útraty by cena pevného stacku vyšla nižší, než jaká v aplikaci je.
///
/// Je to úmyslně jen ta část `AskView`, o kterou v rozhodnutí jde (osa bublin ve `ScrollView`u);
/// lišta `ví o tomhle PR:` ani composer se s počtem bublin nemění, takže by do obou stran přičetly
/// tutéž konstantu.
private struct ShapedAskLog: View {
    let messages: [AskMessage]
    let shape: AskLogShape

    var body: some View {
        ScrollView {
            switch shape {
            case .eager:
                VStack(alignment: .leading, spacing: 14) { bubbles }
                    .padding(16)
                    .filling(alignment: .leading)
            case .lazyStack:
                LazyVStack(alignment: .leading, spacing: 14) { bubbles }
                    .padding(16)
                    .filling(alignment: .leading)
            }
        }
    }

    @ViewBuilder private var bubbles: some View {
        ForEach(messages) { message in
            AskBubbleView(message: message).id(message.id)
        }
    }
}
