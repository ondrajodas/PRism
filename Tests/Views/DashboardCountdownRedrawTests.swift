import AppKit
import Observation
import SwiftUI
import Testing

@testable import PRism

/// Cena odpočtu (#237, po #260 nad vlastním formátem). Rozhodnutí z #181 stálo na tom, že odpočet
/// znamená **přepočítávat dashboard každou vteřinu** — a tenhle test je to místo, kde se ta věta
/// ověřuje, ne opisuje.
///
/// **Od #260 tiká odpočet vlastním `TimelineView`**, protože systémový `Text(_:style: .relative)`
/// psal mezeru mezi číslo a jednotku. Vlastní takt je zrovna ta věc, kterou #237 platit nechtěl,
/// takže se měří dál — jen nad `DashboardCountdown`em, tedy nad **skutečnou** komponentou
/// z aplikace, ne nad tvarem, který ji napodobuje. Do #260 tu sondou byl samotný
/// `Text(_:style: .relative)`; ta míra je zapsaná ve specifikaci.
///
/// Sonda je kolem komponenty, protože spočítat přepočty těla jde jedině tak, že si je view samo
/// počítá, a to do aplikace nepatří.
///
/// Druhý test je **kontrola měřidla**: tentýž postup nad odpočtem, který se v těle přepočítává,
/// musí přepočty spočítat. Bez něj by zelený první test mohl znamenat jen to, že sonda vůbec
/// nežije.
@Suite("Cena odpočtu na dashboardu", .serialized)
@MainActor
struct DashboardCountdownRedrawTests {
    /// `TimelineView` uvnitř `DashboardCountdown`u přepočítává jen svůj obsah — jeden krátký
    /// `Text`. Tělo nad ním (v aplikaci celý dashboard: karty, sparkline, fronta) o vteřinách neví.
    ///
    /// **Obě poloviny v jednom tvrzení**, protože jedna bez druhé se dá splnit omylem: zamrzlý
    /// odpočet tělo taky nepřepočítává, a odpočet, který si bere hodiny ze stavu, se překresluje
    /// celý. Že se text opravdu přetiká, se pozná z **bitmapy hostovaného view** — accessibility
    /// tree se v takovém okně nenaplní (změřeno: `accessibilityChildren` vrací prázdno), takže se
    /// text z něj přečíst nedá.
    @Test("Odpočet si vteřiny odtiká sám, tělo view se kvůli nim nepřepočítává")
    func tickingCountdownDoesNotRecomputeTheBody() async throws {
        let counter = BodyCounter()
        var frames: [Data] = []

        try await host(CountdownProbe(counter: counter, deadline: .now.addingTimeInterval(600))) {
            frames.append(try bitmap(of: $0))
        }

        #expect(counter.count == 1)
        #expect(frames.count == 2)
        #expect(frames.first != frames.last, "Odpočet se za 1,5 s nepřekreslil.")
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
    ///
    /// `sampling` dostane hostující view **na začátku a na konci** — mezi těmi dvěma snímky se má
    /// odpočet přetikat. **První se bere bez čekání**, protože `cacheDisplay` vykreslí view
    /// synchronně: změřeno na zamrzlém odpočtu, kde oba snímky vyšly bajt na bajt stejné, takže ani
    /// ten první prázdný nebyl. Prázdný by byl horší než žádný — snímky by se lišily i tehdy, když
    /// odpočet netiká, a test by prošel z nesprávného důvodu.
    private func host(
        _ view: some View,
        for duration: Duration = .milliseconds(1500),
        sampling: (NSView) throws -> Void = { _ in }
    ) async throws {
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

        try sampling(hosting)
        try await Task.sleep(for: duration)
        try sampling(hosting)
    }

    /// Co je ve view vidět, jako bitmapa. `cacheDisplay` kreslí i do okna mimo obrazovku — tatáž
    /// cesta, jakou se kontroluje blok kódu v diffu (viz `docs/testovani.md`).
    private func bitmap(of view: NSView) throws -> Data {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
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

/// Skutečná komponenta z aplikace v těle, které si počítá přepočty.
private struct CountdownProbe: View {
    let counter: BodyCounter
    let deadline: Date

    var body: some View {
        counter.count += 1
        return DashboardCountdown(deadline: deadline)
    }
}

private struct RecomputingProbe: View {
    let counter: BodyCounter
    let clock: ProbeClock
    let deadline: Date

    var body: some View {
        counter.count += 1
        return Text(verbatim: "za \(Int(deadline.timeIntervalSince(clock.now)))s znovu")
    }
}
