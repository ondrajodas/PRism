import AppKit
import Testing

@testable import PRism

/// Hladina pomocného okna (#243) — nastavení a novinky zůstávají před hlavním oknem, dokud jsou
/// otevřené.
///
/// Na rozdíl od středění (`WindowCenteringTests`) se tady testuje `NSWindow`, protože obě hodnoty,
/// na kterých to stojí, jsou jeho vlastnosti a nedají se z ničeho spočítat. Okno se v testu jen
/// vyrobí — nikdo ho neukazuje, takže na obrazovce se nic nestane.
///
/// **Nejcennější je tvrzení o `hidesOnDeactivate`.** Samo `.floating` je totiž ta naivní oprava,
/// která rozbije druhou polovinu zadání: okno by plavalo i nad cizími aplikacemi. Zelený test na
/// hladinu by přitom o tom mlčel, takže se ověřují obě hodnoty zvlášť a jedna bez druhé je chyba.
@Suite("Hladina pomocného okna")
@MainActor
struct AuxiliaryWindowLevelTests {
    private func window() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
    }

    @Test("Okno jde nad ostatní okna aplikace")
    func liftsTheWindowAboveTheOthers() {
        let window = window()
        #expect(window.level == .normal)

        AuxiliaryWindowLevel.apply(to: window)

        #expect(window.level == .floating)
    }

    /// Druhá polovina zadání: nad **cizí** aplikací okno stát nesmí. Drží to skrytí při odchodu
    /// aplikace do pozadí, ne hladina — takže bez tohoto tvrzení by `.floating` samo prošlo.
    @Test("Nad cizí aplikací nezůstane — okno se s ní skryje")
    func hidesWhenTheAppGoesToTheBackground() {
        let window = window()
        #expect(window.hidesOnDeactivate == false)

        AuxiliaryWindowLevel.apply(to: window)

        #expect(window.hidesOnDeactivate)
    }

    /// Hladina a středění (#164) jsou dvě různé věci udělané témuž oknu a nemají si do sebe
    /// mluvit: hladina oknem nehýbe, takže vystředěné okno zůstane, kde bylo.
    @Test("Hladina oknem nehýbe")
    func leavesTheFrameAlone() {
        let window = window()
        let before = window.frame

        AuxiliaryWindowLevel.apply(to: window)

        #expect(window.frame == before)
    }
}
