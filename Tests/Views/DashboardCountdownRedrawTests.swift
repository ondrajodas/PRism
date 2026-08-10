import AppKit
import Observation
import SwiftUI
import Testing

@testable import PRism

/// Cena odpočtu (#237). Rozhodnutí z #181 stálo na tom, že odpočet znamená **přepočítávat
/// dashboard každou vteřinu** — a tenhle test je to místo, kde se ta věta ověřuje, ne opisuje.
///
/// Měří se to na sondě, ne na `DashboardView`: spočítat přepočty těla jde jedině tak, že si je
/// view samo počítá, a to do aplikace nepatří. Sonda drží **tvar**, o který jde — `Text` s datem
/// v těle hostovaného view.
///
/// Druhý test je **kontrola měřidla**: tentýž postup nad odpočtem, který se v těle přepočítává,
/// musí přepočty spočítat. Bez něj by zelený první test mohl znamenat jen to, že sonda vůbec
/// nežije.
@Suite("Cena odpočtu na dashboardu", .serialized)
@MainActor
struct DashboardCountdownRedrawTests {
    /// `Text(_:style: .relative)` je ten mechanismus, na kterém #237 stojí: vteřiny si překresluje
    /// sám, tělo view o nich neví.
    @Test("Odpočet si vteřiny odtiká sám, tělo view se kvůli nim nepřepočítává")
    func selfUpdatingCountdownDoesNotRecomputeTheBody() async throws {
        let counter = BodyCounter()

        try await host(SelfUpdatingProbe(counter: counter, deadline: .now.addingTimeInterval(600)))

        #expect(counter.count == 1)
    }

    /// Vložená regrese: hodiny ve stavu a odpočet spočítaný v těle, tedy přesně to, čeho se
    /// #181 bálo. Kdyby měřidlo přepočty nevidělo, byl by test výš zelený i nad tímhle.
    @Test("Kontrola měřidla: odpočet přepočítaný v těle přepočty stojí")
    func recomputingCountdownIsDetected() async throws {
        let counter = BodyCounter()
        let clock = ProbeClock()
        // `try?` je tady na místě: jediné, co spánek vyhodí, je zrušení z `defer` níž, a to
        // je normální konec sondy, ne selhání.
        let ticker = Task { @MainActor in
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(200))
                clock.now = .now
            }
        }
        defer { ticker.cancel() }

        try await host(
            RecomputingProbe(counter: counter, clock: clock, deadline: .now.addingTimeInterval(600))
        )

        #expect(counter.count > 1)
    }

    /// Sonda v okně, protože bez okna SwiftUI přepočty neplánuje. Okno je bez rámu a mimo
    /// obrazovku — nemá co ukázat a nemá komu skočit před oči.
    ///
    /// **Rozměr se okna netýká** (`sizingOptions = []` a pevný `frame`). Bez toho hostující view
    /// tlačí svou vnitřní velikost do mezí okna, a protože se text sondy s každou vteřinou mění,
    /// AppKit po několika kolech hodí `NSGenericException` („more Update Constraints in Window
    /// passes than there are views“) a **položí celý testovací běh**. Chytilo se to až tím, že
    /// jeden běh spadl a druhý ne.
    private func host(_ view: some View, for duration: Duration = .milliseconds(1500)) async throws {
        let frame = NSRect(x: -10_000, y: -10_000, width: 320, height: 44)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: view.frame(width: frame.width, height: frame.height))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        try await Task.sleep(for: duration)
    }
}

/// Kolikrát se přepočítalo tělo sondy.
@MainActor
private final class BodyCounter {
    var count = 0
}

/// Hodiny ve stavu — to, co odpočet spočítaný v těle potřebuje.
@MainActor
@Observable
private final class ProbeClock {
    var now = Date.now
}

private struct SelfUpdatingProbe: View {
    let counter: BodyCounter
    let deadline: Date

    var body: some View {
        counter.count += 1
        return Text(deadline, style: .relative)
    }
}

private struct RecomputingProbe: View {
    let counter: BodyCounter
    let clock: ProbeClock
    let deadline: Date

    var body: some View {
        counter.count += 1
        return Text(verbatim: "za \(Int(deadline.timeIntervalSince(clock.now))) s znovu")
    }
}
