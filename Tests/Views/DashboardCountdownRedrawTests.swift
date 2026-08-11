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
/// musí přepočty spočítat **a musí u nich vidět měnící se kresbu**. Bez něj by zelený první test
/// mohl znamenat jen to, že sonda vůbec nežije.
///
/// **Na kresbu se čeká, neměří se v pevném okamžiku** (#269, mění #260). Do #269 sonda vzala dva
/// snímky 1,5 s od sebe a tvrdila, že se liší — a padala, protože se lišit **nemohly**: první
/// změna kresby přijde teprve na **druhém** tiku rozvrhu, tedy až za 2 s. Podrobnosti u
/// `redraws(of:count:within:)`.
@Suite("Cena odpočtu na dashboardu", .serialized)
@MainActor
struct DashboardCountdownRedrawTests {
    /// Strop čekání na dvě změny kresby. Rozvrh je ukotvený v termínu, ten je celý počet vteřin
    /// daleko, takže tiky padnou na celé vteřiny od nasazení sondy a změny na 2,0 s a 3,0 s
    /// (změřeno). Strop je o vteřinu dál, aby vytížený stroj sondu nebarvil na červeno — a přitom
    /// pořád tvrdí **vteřinový** takt: rozvrh po dvou vteřinách by změny posunul na 4,0 s a 6,0 s,
    /// tedy za strop (změřeno vloženou regresí).
    private static let ceiling: TimeInterval = 4

    /// `TimelineView` uvnitř `DashboardCountdown`u přepočítává jen svůj obsah — jeden krátký
    /// `Text`. Tělo nad ním (v aplikaci celý dashboard: karty, sparkline, fronta) o vteřinách neví.
    ///
    /// **Obě poloviny v jednom tvrzení**, protože jedna bez druhé se dá splnit omylem: zamrzlý
    /// odpočet tělo taky nepřepočítává, a odpočet, který si bere hodiny ze stavu, se překresluje
    /// celý. Že se text opravdu přetiká, se pozná z **bitmapy hostovaného view** — accessibility
    /// tree se v takovém okně nenaplní (změřeno: `accessibilityChildren` vrací prázdno), takže se
    /// text z něj přečíst nedá.
    ///
    /// Změny se čekají **dvě**, ne jedna: jedna dokazuje, že se odpočet překreslil, dvě že se
    /// **přetiká**, tedy že takt pokračuje. Termín je 600 s daleko, aby se sonda držela minutové
    /// větve formátu (`za 9min 59s znovu`) — vteřinu z ní ubere každý tik, takže se kresba mění
    /// stejně jako v poslední minutě před dotazem.
    @Test("Odpočet si vteřiny odtiká sám, tělo view se kvůli nim nepřepočítává")
    func tickingCountdownDoesNotRecomputeTheBody() async throws {
        let counter = BodyCounter()

        let changes = try await redraws(
            of: CountdownProbe(counter: counter, deadline: .now.addingTimeInterval(600)),
            count: 2,
            within: Self.ceiling
        )

        #expect(
            changes.count == 2,
            "Odpočet se za \(Self.ceiling) s přetikal \(changes.count)× místo dvakrát \(Self.stamps(changes))."
        )
        #expect(counter.count == 1, "Tělo sondy se přepočítalo \(counter.count)× místo jednou.")
    }

    /// Vložená regrese: hodiny ve stavu a odpočet spočítaný v těle, tedy přesně to, čeho se
    /// #181 bálo. Kdyby měřidlo přepočty nevidělo, byl by test výš zelený i nad tímhle.
    ///
    /// Od #269 kontroluje **obě měřidla**: přepočty těla i porovnání bitmap. Rozbité porovnání
    /// (prázdná kresba, `cacheDisplay`, který přestane kreslit) by test výš obarvilo na červeno
    /// tvrzením „odpočet se nepřetikal“ — tedy hlášením o aplikaci nad chybou v sondě, což je
    /// zdržení, kvůli kterému #269 vzniklo.
    ///
    /// Odpočet v těle je tady na **desetiny**, ne na celé vteřiny: hodiny se posouvají po 200 ms,
    /// takže s celými vteřinami by se text za 1,5 s změnil nejvýš jednou a dvě změny kresby by se
    /// nemohly stihnout. Sonda modeluje **odpočet spočítaný v těle**, ne formát z aplikace, takže
    /// jemnější dělení nic neubírá.
    @Test("Kontrola měřidla: odpočet přepočítaný v těle přepočty stojí a kresbu mění")
    func recomputingCountdownIsDetected() async throws {
        let counter = BodyCounter()
        let clock = ProbeClock()
        // `try?` je tady na místě: jediné, co spánek vyhodí, je zrušení z `defer` níž, a to
        // je normální konec sondy, ne selhání.
        let ticker = Task { @MainActor in
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(200))
                clock.now = .now
            }
        }
        defer { ticker.cancel() }

        let changes = try await redraws(
            of: RecomputingProbe(counter: counter, clock: clock, deadline: .now.addingTimeInterval(600)),
            count: 2,
            within: 1.5
        )

        #expect(
            counter.count > 1,
            "Tělo se přepočítalo \(counter.count)×, tedy jen při nasazení — měřidlo přepočtů nežije."
        )
        #expect(
            changes.count == 2,
            "Měřidlo kresby vidělo \(changes.count) změn místo dvou \(Self.stamps(changes))."
        )
    }

    /// Kdy se kresba hostovaného view změnila, počítáno od nasazení do okna — dokud jich není
    /// `count`, nebo dokud neuplyne `within` vteřin.
    ///
    /// **Čeká se, protože pevný okamžik tady nejde spočítat** (#269). `TimelineView` vykreslí
    /// hned při nasazení hodnotu **prvního** tiku rozvrhu, který je v budoucnosti, a další
    /// překreslení naplánuje až na tik po něm — první změna kresby tedy přijde za **1 až 2
    /// periody** podle toho, jak daleko od nasazení leží mřížka tiků. Změřeno: s termínem 600,0 s
    /// daleko (mřížka na celých vteřinách od nasazení) se kresba změní ve 2,01 s, 3,00 s, 4,00 s
    /// a dál po vteřině; s termínem 600,4 s daleko v 1,41 s a 2,40 s. Do #269 sonda porovnávala
    /// snímky **1,5 s** od sebe, takže s celým počtem vteřin se lišit nemohly — a zeleně vycházela
    /// jedině tehdy, když spánek přetáhl o půl vteřiny. Test na hodinách takhle nesmí stát: buď se
    /// čeká na jev, nebo se fáze mřížky spočítá, a čekání je to, co přežije jiný stroj.
    ///
    /// Hodiny jsou schválně `Date`, ne `ContinuousClock`: rozvrh `TimelineView`u tiká podle
    /// nástěnných hodin, takže se sonda musí koukat na tytéž.
    ///
    /// Opakované snímkování samo přepočty **nestojí** ani takt neposouvá — změřeno: tělo se přes
    /// šest vteřin snímkování po 100 ms přepočítalo jednou a tiky chodily po 1,00 s.
    ///
    /// Strop platí **s přesností na jeden krok** snímkování: poslední snímek se bere za podmínkou,
    /// takže může padnout až 100 ms za stropem. Tvrzení nad tím se proto opírá o **počet** změn, ne
    /// o samotný čas té poslední.
    private func redraws(
        of view: some View,
        count: Int,
        within limit: TimeInterval,
        step: Duration = .milliseconds(100)
    ) async throws -> [TimeInterval] {
        let window = window(hosting: view)
        defer { window.orderOut(nil) }
        let hosting = try #require(window.contentView)

        let start = Date.now
        var last = try bitmap(of: hosting)
        var changes: [TimeInterval] = []
        while changes.count < count, Date.now.timeIntervalSince(start) < limit {
            try await Task.sleep(for: step)
            let frame = try bitmap(of: hosting)
            guard frame != last else { continue }
            last = frame
            changes.append(Date.now.timeIntervalSince(start))
        }
        return changes
    }

    /// Sonda v okně, protože bez okna SwiftUI přepočty neplánuje. Okno je bez rámu a mimo
    /// obrazovku — nemá co ukázat a nemá komu skočit před oči.
    ///
    /// **Rozměr se okna netýká** (`sizingOptions = []` a pevný `frame`). Bez toho hostující view
    /// tlačí svou vnitřní velikost do mezí okna, a protože se text sondy s každou vteřinou mění,
    /// AppKit po několika kolech hodí `NSGenericException` („more Update Constraints in Window
    /// passes than there are views“) a **položí celý testovací běh**. Chytilo se to až tím, že
    /// jeden běh spadl a druhý ne.
    private func window(hosting view: some View) -> NSWindow {
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
        return window
    }

    /// Co je ve view vidět, jako bitmapa. `cacheDisplay` kreslí i do okna mimo obrazovku — tatáž
    /// cesta, jakou se kontroluje blok kódu v diffu (viz `docs/testovani.md`). Že v ní je opravdu
    /// text a ne prázdná plocha, je změřené u #269: 1904 z 56320 pixelů se liší od pozadí a věta
    /// `za 9min 59s znovu` se z uloženého PNG dá přečíst okem.
    private func bitmap(of view: NSView) throws -> Data {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    /// Časy změn do hlášky o selhání — bez nich se z červeného testu nepozná, jestli takt chybí,
    /// nebo jen přišel pozdě.
    private static func stamps(_ changes: [TimeInterval]) -> String {
        guard !changes.isEmpty else { return "(kresba se nezměnila ani jednou)" }
        return "(změny po \(changes.map { String(format: "%.2f", $0) }.joined(separator: " s, ")) s)"
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
        return Text(
            verbatim: String(format: "za %.1fs znovu", max(deadline.timeIntervalSince(clock.now), 0))
        )
    }
}
