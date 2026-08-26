import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Měření, ne test (#452): **co stojí první rozvržení rozhovoru v pevném `VStack`u**.
///
/// Existuje proto, že rozhodnutí „líný seznam, nebo ne“ se v tomhle repu **neopisuje z jedné nebo
/// druhé strany** — osa konverzace šla u #361 na pevný stack a diff zůstal líný, takže samotné
/// „jinde je to takhle“ neříká nic. Cena pevného stacku je **první rozvržení**: vyrobí se všechny
/// bubliny, ne jen viditelné, a roste to lineárně s jejich počtem. Otázka je, jestli se rozhovor
/// vejde pod strop, který #361 naměřilo u osy (44 uzlů 55 ms, 300 uzlů 410 ms, 400 uzlů 610 ms
/// v Debugu — viz `ConversationAxisShapeProbe`).
///
/// **Rozhovor je shora omezený jinak než osa**, a v tom je celá odpověď: osa má strop
/// z dotazu (`first: 100` na čtyři seznamy, tedy čtyři stovky uzlů), kdežto tady je každá zpráva
/// **zaplacená session** — dvacet otázek nad jedním PR je hodně a stovka je krajnost, ke které se
/// v praxi nikdo nedostane.
///
/// Časy se **netvrdí** `#expect`em: na jiném stroji vyjdou jinak. **Pouští se ručně**:
/// `TEST_RUNNER_PRISM_MEASURE=1`.
@MainActor
@Suite(
    "Měření rozhovoru (#452)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct AskLogMeasurement {
    @Test("Kolik stojí první rozvržení rozhovoru")
    func firstLayoutCost() {
        for count in [10, 20, 50, 100, 300] {
            let messages = Self.messages(count: count)
            let clock = ContinuousClock()
            // **Příprava mimo hodinky** (#274): materiál se skládá dopředu, uvnitř se měří jen
            // rozvržení.
            let hosting = NSHostingView(
                rootView: AskView(content: .thread(messages: messages, isAnswering: false))
                    .frame(width: 1047, height: 700)
            )
            hosting.frame = NSRect(x: 0, y: 0, width: 1047, height: 700)
            let elapsed = clock.measure { hosting.layoutSubtreeIfNeeded() }
            print("MĚŘENÍ první rozvržení \(count) bublin: \(elapsed.milliseconds)")
        }
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
