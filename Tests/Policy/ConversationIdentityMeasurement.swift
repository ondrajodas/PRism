import Foundation
import Testing

@testable import PRism

/// Měření, ne test (#361): **kolik stojí přečtení identity řádků osy** — tedy to, co líný seznam
/// dělá při každém přerovnání obsahu.
///
/// Existuje proto, že ve vzorku ze ztuhlého okna je `key path getter for ConversationNode.id`
/// s kopiemi payloadu (`initializeWithCopy for ConversationNode`, `outlined init with copy of
/// ConversationEntry`) ~5 % vzorků hlavního vlákna. Kolo tím vysvětlené **není** (5 % z 99 %),
/// ale je to nejlevnější věc, která se v té cestě dá ubrat — a bez čísla by se nedalo poznat,
/// jestli se ubralo něco, nebo se to jen přepsalo jinak.
///
/// Časy se **netvrdí** `#expect`em: na jiném stroji vyjdou jinak. **Pouští se ručně**:
/// `TEST_RUNNER_PRISM_MEASURE=1`.
@Suite(
    "Měření identity osy (#361)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct ConversationIdentityMeasurement {
    /// Dvě věci, každá na jiné frekvenci:
    ///
    /// - **Průchod tělem**: složení osy plus pole tuplů proti složení řádků. Tady se čeká, že
    ///   to bude nastejno — vyměňuje se jedna kopie osy za jinou.
    /// - **Přerovnání obsahu**: přečtení identity každého prvku. Přes tuple a keypath se
    ///   payload enumu **kopíruje**, u uloženého `String`u je to čtení pole. Tohle je ta
    ///   frekvence, která v profilu hoří.
    @Test("Kolik stojí identita řádků osy")
    func identityCost() {
        let entries = Self.entries(count: 300)
        let nodes = Policy.conversation(of: entries)
        let rows = Policy.conversationRows(of: entries, since: nil)
        print("SONDA \(nodes.count) uzlů, \(rows.count) řádků")

        // **Obě strany musí obsahovat `Policy.conversation`**, protože osa se v těle skládá tak
        // i tak; bez ní by z toho vyšlo, že řádky jsou pětkrát dražší, a to by byl artefakt
        // měřidla, ne cena změny.
        measure("průchod tělem: conversation + Array(enumerated())") {
            Array(Policy.conversation(of: entries).enumerated()).count
        }
        measure("průchod tělem: conversationRows") {
            Policy.conversationRows(of: entries, since: nil).count
        }

        let keyPath = \(offset: Int, element: ConversationNode).element.id
        let pairs = Array(nodes.enumerated())
        measure("přerovnání: identita přes tuple a keypath") {
            pairs.reduce(0) { $0 + $1[keyPath: keyPath].utf8.count }
        }
        measure("přerovnání: identita z uloženého pole") {
            rows.reduce(0) { $0 + $1.id.utf8.count }
        }
    }

    /// Hodinky bez přípravy uvnitř (#274) a s **vráceným výsledkem**, aby ho optimalizátor
    /// nezahodil — bez toho se dá naměřit nula nad prací, která se vůbec nestala.
    private func measure(_ label: String, iterations: Int = 200, _ body: () -> Int) {
        let clock = ContinuousClock()
        var sink = body()
        let elapsed = clock.measure {
            for _ in 0..<iterations { sink &+= body() }
        }
        print("MĚŘENÍ \(label): \((elapsed / iterations).milliseconds) na volání (kontrolní součet \(sink))")
    }

    /// Materiál: komentáře a vlákna po deseti odpovědích. Vlákna jsou tam schválně — payload
    /// `ConversationEntry` nese pole komentářů, takže právě na nich se kopie prodraží.
    private static func entries(count: Int) -> [ConversationEntry] {
        (0..<count).map { index in
            index % 3 == 0
                ? .thread(thread(index))
                : .comment(comment(index))
        }
    }

    private static func comment(_ index: Int) -> ThreadComment {
        ThreadComment(
            id: "\(index)",
            author: "octocat",
            body: "Komentář \(index) s pár slovy, aby to nebyl prázdný řetězec.",
            createdAt: Date(timeIntervalSince1970: 1_753_000_000 + Double(index)),
            url: URL(string: "https://github.com/cli/cli/pull/13084#issuecomment-\(index)")!
        )
    }

    private static func thread(_ index: Int) -> ReviewThread {
        ReviewThread(
            id: "t\(index)",
            path: "src/Module\(index).swift",
            line: index,
            originalLine: index,
            side: .right,
            isResolved: false,
            isOutdated: false,
            diffHunk: "@@ -1,3 +1,3 @@\n-old\n+new\n",
            comments: ConversationPage(
                items: (0..<10).map { comment(index * 100 + $0) },
                total: 10,
                hasNextPage: false
            )
        )
    }
}
