import AppKit
import Foundation
import Testing

@testable import PRism

/// Vystředění pomocného okna v hlavním okně (#164).
///
/// Testuje se **geometrie**, ne `NSWindow`: `centered(_:in:on:)` je čistá funkce, protože si
/// obrazovky bere parametrem (`ScreenBounds`) — a zrovna zarovnávání zpátky na viditelnou plochu
/// se jinak otestovat nedá, `NSScreen` se vyrobit nedá. Do #164 to byla `private` funkce ve
/// `SettingsView` a držel ji jen komentář.
@Suite("Vystředění okna")
struct WindowCenteringTests {
    /// Jedna obrazovka 1920×1080 s menu barem, tedy `visible` o 40 bodů nižší.
    private let screen = ScreenBounds(
        frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
        visible: NSRect(x: 0, y: 0, width: 1920, height: 1040)
    )

    private func window(width: Double = 900, height: Double = 620) -> NSRect {
        NSRect(x: 0, y: 0, width: width, height: height)
    }

    @Test("Okno se vystředí v hostiteli, ne na obrazovce")
    func centersInTheHost() {
        // Hlavní okno v levé horní části, tedy nikde blízko středu obrazovky.
        let host = NSRect(x: 100, y: 400, width: 1100, height: 600)

        let result = WindowCentering.centered(window(), in: host, on: [screen])

        #expect(result.midX == host.midX)
        #expect(result.midY == host.midY)
        // Velikost se nemění — středění okno nezvětšuje ani nezmenšuje.
        #expect(result.size == window().size)
    }

    /// Bez hlavního okna (zavřené, skryté) se **nedělá nic** a rozhoduje systém. Ne dohad na
    /// střed obrazovky, ne pád: chování systému je správný fallback.
    @Test("Bez hostitele zůstane rámec, jak byl")
    func leavesTheFrameAloneWithoutAHost() {
        let original = NSRect(x: 17, y: 23, width: 900, height: 620)

        #expect(WindowCentering.centered(original, in: nil, on: [screen]) == original)
    }

    // MARK: - Zarovnání zpátky na plochu

    /// Hlavní okno může být zpola mimo viditelnou plochu a okno vystředěné v něm by skončilo
    /// za hranou, kde po něm není ani křížek.
    @Test("Hostitel u pravého kraje nevystrčí okno z obrazovky")
    func keepsTheWindowOnScreenNearTheRightEdge() {
        let host = NSRect(x: 1700, y: 500, width: 1100, height: 600)

        let result = WindowCentering.centered(window(), in: host, on: [screen])

        #expect(result.maxX <= screen.visible.maxX)
        #expect(result.minX >= screen.visible.minX)
        // A neposunulo se to jinam, než bylo potřeba: drží se u kraje.
        #expect(result.maxX == screen.visible.maxX)
    }

    @Test("Hostitel u levého a dolního kraje taky")
    func keepsTheWindowOnScreenNearTheOtherEdges() {
        let host = NSRect(x: -400, y: -300, width: 1100, height: 600)

        let result = WindowCentering.centered(window(), in: host, on: [screen])

        #expect(result.minX == screen.visible.minX)
        #expect(result.minY == screen.visible.minY)
    }

    /// Menu bar: `visible` je nižší než `frame`, takže vystředěné okno u horního kraje se musí
    /// srazit pod něj. Kdyby se ořezávalo podle `frame`, zalezla by hlavička okna za menu bar.
    @Test("Okno u horního kraje zůstane pod menu barem")
    func staysBelowTheMenuBar() {
        let host = NSRect(x: 500, y: 900, width: 1100, height: 600)

        let result = WindowCentering.centered(window(), in: host, on: [screen])

        #expect(result.maxY <= screen.visible.maxY)
    }

    /// **To hlavní tvrzení téhle sady.** Pořadí ořezu je `max(min(…))`: u okna širšího než
    /// obrazovka vyjde `maxX - width` menší než `minX`, takže opačné pořadí by rámec poslalo
    /// **za levý okraj**. Takhle skončí zarovnaný k němu a je vidět jeho levá část i s hlavičkou.
    @Test("Okno širší než obrazovka zůstane zarovnané k levému okraji")
    func alignsAnOversizedWindowToTheLeftEdge() {
        let host = NSRect(x: 200, y: 200, width: 1100, height: 600)

        let result = WindowCentering.centered(window(width: 2400), in: host, on: [screen])

        #expect(result.minX == screen.visible.minX)
        #expect(result.minX >= 0)
    }

    /// Totéž na výšku — vyšší okno než obrazovka se nesmí utopit pod dolní hranou.
    @Test("Okno vyšší než obrazovka zůstane zarovnané ke spodnímu okraji")
    func alignsATallWindowToTheBottomEdge() {
        let host = NSRect(x: 200, y: 200, width: 1100, height: 600)

        let result = WindowCentering.centered(window(height: 1600), in: host, on: [screen])

        #expect(result.minY == screen.visible.minY)
    }

    // MARK: - Dvě obrazovky

    /// Obrazovka se vybírá podle **plochy průniku** s hlavním oknem, ne podle první v seznamu:
    /// okno na druhém monitoru se má vystředit tam, a ořezat podle jeho plochy.
    @Test("Rozhoduje obrazovka, na které hostitel převážně leží")
    func picksTheScreenWithMostOfTheHost() {
        let second = ScreenBounds(
            frame: NSRect(x: 1920, y: 0, width: 1920, height: 1080),
            visible: NSRect(x: 1920, y: 0, width: 1920, height: 1040)
        )
        // Hlavní okno je celé na druhém monitoru, u jeho pravého kraje.
        let host = NSRect(x: 3600, y: 400, width: 1100, height: 600)

        let result = WindowCentering.centered(window(), in: host, on: [screen, second])

        // Ořezalo se podle druhé obrazovky, ne podle první — na první by `maxX` bylo 1920.
        #expect(result.maxX == second.visible.maxX)
        #expect(result.minX > screen.visible.maxX)
    }

    /// Hostitel **přesahující mezi monitory** patří tomu, na kterém ho je víc — a okno se
    /// **nerozpůlí přes hranu**: ořez ho posune celé na tu obrazovku. Změřeno tímhle testem
    /// (první verze čekala přesný střed hostitele a spadla), a je to tak správně: okno
    /// rozseknuté mezerou mezi dvěma monitory se čte hůř než okno posunuté o kus vedle.
    @Test("Hostitel přes dva monitory nerozpůlí okno přes hranu")
    func keepsTheWindowWholeOnOneScreen() {
        let second = ScreenBounds(
            frame: NSRect(x: 1920, y: 0, width: 1920, height: 1080),
            visible: NSRect(x: 1920, y: 0, width: 1920, height: 1040)
        )
        // Tři čtvrtiny hlavního okna leží na druhém monitoru.
        let host = NSRect(x: 1620, y: 400, width: 1200, height: 600)

        let result = WindowCentering.centered(window(), in: host, on: [screen, second])

        // Celé na druhém monitoru, zarovnané k jeho levému okraji — tam, kde hostitele je víc.
        #expect(result.minX == second.visible.minX)
        #expect(result.maxX <= second.visible.maxX)
        // Svisle nic nepřekáží, takže se střed hostitele dodrží.
        #expect(result.midY == host.midY)
        // **Pořadí v seznamu nesmí rozhodovat** — s obráceným pořadím musí vyjít totéž.
        let reversed = WindowCentering.centered(window(), in: host, on: [second, screen])
        #expect(reversed == result)
    }

    /// Bez obrazovek se nemá podle čeho ořezávat — vystředěný rámec se vrátí, jak vyšel.
    /// Nestane se to, ale tichý pád nebo nula by byly horší než střed v hostiteli.
    @Test("Bez obrazovek zůstane vystředěný rámec")
    func survivesWithoutAnyScreens() {
        let host = NSRect(x: 100, y: 100, width: 1100, height: 600)

        let result = WindowCentering.centered(window(), in: host, on: [])

        #expect(result.midX == host.midX)
        #expect(result.midY == host.midY)
    }

    // MARK: - Plocha průniku

    /// `NSRect.intersection` u nepřekrývajících se rámců vrací `NSRect.null`, a to má
    /// **nekonečné** rozměry — bez ošetření by z „žádný průnik“ vyšla největší plocha a vybrala
    /// by se právě ta obrazovka, na které hostitel není.
    @Test("Prázdný průnik má nulovou plochu, ne nekonečnou")
    func treatsANullIntersectionAsZero() {
        let left = NSRect(x: 0, y: 0, width: 100, height: 100)
        let right = NSRect(x: 500, y: 500, width: 100, height: 100)

        #expect(left.intersection(right).area == 0)
        #expect(left.intersection(left).area == 10_000)
    }
}
