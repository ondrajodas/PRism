import AppKit
import Testing

@testable import PRism

/// Přepnutí vzhledu celé aplikace (#278).
///
/// Měří se to na **hodnotě, kterou by dostal `NSApp.appearance`**, ne na běžící aplikaci: živý
/// `NSApp` je v testech hostitel testů, takže vynucený režim by přetekl do render sond, které si
/// režim nastavují samy.
@Suite("Vzhled aplikace")
@MainActor
struct AppAppearanceTests {
    @Test("Vynucený režim dá aqua a darkAqua")
    func mapsForcedModesToSystemAppearances() {
        #expect(AppearanceMode.light.nsAppearance?.name == .aqua)
        #expect(AppearanceMode.dark.nsAppearance?.name == .darkAqua)
    }

    /// Nejcennější tvrzení v tomhle souboru je to, že se něco **nestalo**: `Podle systému` nesmí
    /// vzhled vynutit, jinak by aplikace zamrzla v tom režimu, ve kterém se zapnula, a přepnutí
    /// v macOS by se v ní přestalo projevovat.
    @Test("Podle systému nevynucuje nic")
    func theSystemModeForcesNothing() {
        #expect(AppearanceMode.system.nsAppearance == nil)
    }

    /// Obráceně k předchozímu: `nil` smí vyjít **jedině** u `.system`. Kdyby ho vrátil i vynucený
    /// režim, byla by volba k nerozeznání od „podle systému“ a tiše by nezabrala — přesně ten
    /// tichý `?? default`, kterému se tady vyhýbáme.
    @Test("Jen podle systému dá nil")
    func onlyTheSystemModeIsUnset() {
        let unset = AppearanceMode.allCases.filter { $0.nsAppearance == nil }

        #expect(unset == [.system])
    }

    /// `NSApp` je jediný cíl, který má aplikace nastavovat — vzhled se dává **aplikaci**, ne
    /// oknu, protože jen tak platí i na okno, které v době přepnutí není vpředu.
    @Test("Živý cíl je aplikace")
    func theLiveTargetIsTheApplication() {
        #expect(AppAppearance.application === NSApplication.shared)
    }

    @Test("Každý režim má vlastní jméno v okně")
    func namesEveryModeInTheWindow() {
        #expect(AppearanceMode.light.displayName == "Světlý")
        #expect(AppearanceMode.dark.displayName == "Tmavý")
        #expect(AppearanceMode.system.displayName == "Podle systému")
        // Dvě stejná jména by z přepínače udělala hádanku, a stane se to tichou opravou
        // překlepu — proto výčet, ne tři porovnání.
        #expect(Set(AppearanceMode.allCases.map(\.displayName)).count == AppearanceMode.allCases.count)
    }
}
