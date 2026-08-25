import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Tlačítko `⟳` v hlavičce okna, dokud se aplikace ptá (#442).
///
/// Testuje se **obojí naráz**, protože jedno bez druhého je horší než nic: točící se tlačítko,
/// které pustí druhý dotaz, i mrtvé tlačítko bez vysvětlení. Prstýnek se přitom nekontroluje jen
/// tím, že „tam něco je“ — ptá se na `SpinningRingView`, tedy na **ten** prstýnek z pruhu záložek,
/// a na to, že mu otáčení visí v CoreAnimation. Nový prstýnek nakreslený ve SwiftUI by ten test
/// neprošel, a to je celý smysl (#350: nekonečná animace ve SwiftUI stála 99 % CPU hlavního vlákna).
///
/// **Zákaz kliku se z hostovaného view přečíst nedá** a je to mez harnessu, ne opomenutí:
/// accessibility tree se v okně mimo obrazovku nenaplní (změřeno u `DashboardCountdownRedrawTests`
/// i u railu), takže na `AXEnabled` není kde se zeptat. Tvrdí se proto ze dvou stran, které
/// v harnessu k dispozici jsou: rozhodnutí samo (`RefreshControlTests`) a jeho **důsledek** na
/// vrstvě, kde by druhý klik doopravdy něco stál — `AppStoreRefreshTests`, kde se během běžícího
/// dotazu nesmí zeptat podruhé.
@MainActor
@Suite("Tlačítko obnovení v hlavičce (#442)")
struct RefreshButtonTests {
    /// Prstýnek je **tentýž kus kódu** jako u běžícího review, ne druhá kresba téhož: jeden tvar
    /// pro „pracuje se“ v celém okně, a hlavně jedno místo, kde se hlídá, že se točí v CoreAnimation.
    @Test("Po dobu dotazu je v tlačítku prstýnek a točí se v CoreAnimation")
    func drawsTheSharedRingWhileRefreshing() throws {
        let hosting = host(isRefreshing: true)

        let ring = try #require(Self.ring(in: hosting))
        #expect(ring.isSpinningInCoreAnimation)
    }

    /// Druhá půlka téhož: po dotazu se prstýnek **musí** ztratit. Bez tohohle tvrzení by prošla
    /// i verze, která ho jednou nakreslí a nechá tam navždycky — tedy okno, které tvrdí, že se
    /// pořád ptá.
    @Test("V klidu v tlačítku žádný prstýnek není")
    func drawsNoRingWhenIdle() {
        #expect(Self.ring(in: host(isRefreshing: false)) == nil)
    }

    /// **Hlavička nesmí poskočit tím, že se aplikace ptá.** Prstýnek má jiný tvar i jinou vnitřní
    /// velikost než šipka, takže bez pevného rámce by se šířka pruhu tlačítek měnila při každém
    /// tiku pollingu — a to je pohyb, který v okně nikdo nechtěl. Číslo je `.tbtn` z návrhu
    /// (27 × 25) a bere se 1 : 1 jako body.
    @Test("Rozměr tlačítka se mezi stavy nehne — 27 × 25 jako v návrhu")
    func keepsItsSizeInBothStates() {
        let idle = host(isRefreshing: false).fittingSize
        let busy = host(isRefreshing: true).fittingSize

        #expect(idle == busy)
        #expect(abs(idle.width - HeaderButtonMetrics.width) < 0.5)
        #expect(abs(idle.height - HeaderButtonMetrics.height) < 0.5)
        #expect(HeaderButtonMetrics.width == 27)
        #expect(HeaderButtonMetrics.height == 25)
    }

    /// Prstýnek se bere ve výchozí velikosti, protože **`.spin` z návrhu je s ním shodný** —
    /// 11 bodů, 2 body obtažení. Kdyby si tlačítko sáhlo na vlastní rozměr, byl by to druhý
    /// prstýnek v jiné velikosti, tedy přesně to, čemu se sdílením `SpinningRing` vyhýbáme.
    @Test("Prstýnek má rozměry z návrhu, protože se bere výchozí")
    func theRingKeepsTheMockupMetrics() {
        let ring = SpinningRing()

        #expect(ring.size == 11)
        #expect(ring.lineWidth == 2)
    }

    private func host(isRefreshing: Bool) -> NSHostingView<RefreshButton> {
        let hosting = NSHostingView(rootView: RefreshButton(isRefreshing: isRefreshing) {})
        hosting.frame = NSRect(x: 0, y: 0, width: 60, height: 40)
        // Otáčení se nasazuje až v `layout()`, takže bez vynuceného rozvržení by test tvrdil,
        // že animace není, nad kódem, který ji přidá.
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private static func ring(in view: NSView) -> SpinningRingView? {
        if let ring = view as? SpinningRingView { return ring }
        for child in view.subviews {
            if let ring = ring(in: child) { return ring }
        }
        return nil
    }
}
