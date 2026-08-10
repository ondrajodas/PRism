import AppKit
import Testing

@testable import PRism

/// Hladina pomocného okna (#243) — nastavení a novinky zůstávají před hlavním oknem, dokud jsou
/// otevřené, a jedině dokud je aplikace vpředu.
///
/// Na rozdíl od středění (`WindowCenteringTests`) se tady testuje i `NSWindow`, protože hladina je
/// jeho vlastnost. Okno se v testu jen vyrobí — nikdo ho neukazuje, takže na obrazovce se nic
/// nestane.
///
/// **Nejcennější jsou dvě tvrzení o tom, co se stát nesmí.** Že hladina v neaktivní aplikaci padá
/// zpátky na `.normal` — jinak by okno plavalo i nad cizími aplikacemi, což je ta naivní oprava.
/// A že se okno **neskrývá** (`hidesOnDeactivate` zůstává `false`): skrytí je stav, který se s
/// SwiftUI umí rozejít a okno pak leží mimo obrazovku, ačkoli je pro scénu otevřené — změřeno na
/// běžící aplikaci, viz `docs/testovani.md`.
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

    @Test("Dokud je aplikace vpředu, okno jde nad ostatní okna aplikace")
    func liftsTheWindowWhileTheAppIsActive() {
        #expect(AuxiliaryWindowLevel.level(appIsActive: true) == .floating)

        let window = window()
        AuxiliaryWindowLevel.apply(to: window, appIsActive: true)

        #expect(window.level == .floating)
    }

    /// Druhá polovina zadání: nad **cizí** aplikací okno stát nesmí. Drží to pád hladiny zpátky,
    /// takže bez tohohle tvrzení by `.floating` nastavené jednou provždy prošlo.
    @Test("V neaktivní aplikaci hladina padá zpátky na normální")
    func dropsTheLevelWhenTheAppIsNotActive() {
        #expect(AuxiliaryWindowLevel.level(appIsActive: false) == .normal)

        let window = window()
        AuxiliaryWindowLevel.apply(to: window, appIsActive: true)
        AuxiliaryWindowLevel.apply(to: window, appIsActive: false)

        #expect(window.level == .normal)
    }

    /// Okno se **nikdy neschovává** — hladina je jediné, co se mění. Skryté okno se s SwiftUI umí
    /// rozejít a zůstat mimo obrazovku, ačkoli je scéna otevřená; `⌘,` s ním pak nepohne.
    @Test("Okno se neskrývá, když aplikace odejde do pozadí")
    func neverHidesTheWindow() {
        let window = window()
        #expect(window.hidesOnDeactivate == false)

        AuxiliaryWindowLevel.apply(to: window, appIsActive: true)
        AuxiliaryWindowLevel.apply(to: window, appIsActive: false)

        #expect(window.hidesOnDeactivate == false)
    }

    /// Hladina a středění (#164) jsou dvě různé věci udělané témuž oknu a nemají si do sebe
    /// mluvit: hladina oknem nehýbe, takže vystředěné okno zůstane, kde bylo.
    @Test("Hladina oknem nehýbe")
    func leavesTheFrameAlone() {
        let window = window()
        let before = window.frame

        AuxiliaryWindowLevel.apply(to: window, appIsActive: true)
        AuxiliaryWindowLevel.apply(to: window, appIsActive: false)

        #expect(window.frame == before)
    }
}
