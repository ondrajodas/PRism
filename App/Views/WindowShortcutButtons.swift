import SwiftUI

/// Překlad katalogu zkratek (#441) do SwiftUI. Katalog sám žije v `Policy`, aby se dal projít
/// testem bez kreslení — tenhle soubor je ta druhá půlka: jediné místo v aplikaci, kde se
/// `keyboardShortcut` píše nad kombinací z katalogu.
extension WindowShortcut.Combination {
    var keyboardShortcut: KeyboardShortcut {
        // `.cancelAction` modifikátory nemá a mít nemůže — je to pojmenovaná role, ne klávesa
        // s maskou. Katalog to ví (`⎋` se zapisuje bez modifikátorů), takže se tu nic nezahazuje.
        guard case .cancelAction = key else {
            return KeyboardShortcut(key.equivalent, modifiers: modifiers.eventModifiers)
        }
        return .cancelAction
    }
}

extension WindowShortcut.Key {
    /// `.cancelAction` tu vrací `.escape` jen proto, aby byl `switch` úplný — **použije se
    /// nikdy**, protože `Combination.keyboardShortcut` ho odchytí o kus výš. Dva zápisy téže
    /// klávesy v jednom okně znamenají hádat, který AppKit spáruje dřív (#317).
    var equivalent: KeyEquivalent {
        switch self {
        case .character(let character): KeyEquivalent(character)
        case .tab: .tab
        case .backTab: .backTab
        case .return: .return
        case .cancelAction: .escape
        case .upArrow: .upArrow
        case .downArrow: .downArrow
        case .leftArrow: .leftArrow
        case .rightArrow: .rightArrow
        }
    }
}

extension ShortcutModifiers {
    /// Modifikátory stisknuté klávesy do jazyka katalogu (#152).
    ///
    /// **Tady, ne u volajícího**: tenhle soubor je jediné místo, které mluví oběma jazyky, a druhý
    /// překlad by se s tímhle rozešel. Potřebuje to pole hledání, které se rozhoduje, jestli si `↵`
    /// vezme, nebo ho propustí okenní zkratce (`Policy.searchStepKey`).
    init(_ modifiers: EventModifiers) {
        var result: ShortcutModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        self = result
    }

    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if contains(.control) { modifiers.insert(.control) }
        if contains(.option) { modifiers.insert(.option) }
        if contains(.shift) { modifiers.insert(.shift) }
        if contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
}

extension EnvironmentValues {
    /// Má fokus zásuvka s terminálem? (#459)
    ///
    /// **Prostředí, ne parametr**, a je to podmínka toho, aby pravidlo platilo celé: zkratky okna
    /// se registrují v `ContentView`, v detailu PR, v diffu i v přehledu, takže předávat příznak
    /// argumentem by znamenalo na jedno z těch míst zapomenout — a projevilo by se to `⌃W`
    /// uprostřed psaní. Nasazuje se **jednou, na kořen okna**.
    @Entry var terminalFocused = false
}

/// Schovaná tlačítka jedné zkratky z katalogu (#441).
///
/// Kombinací může být víc a **každá dostane vlastní tlačítko**: `keyboardShortcut` se dá na jedno
/// tlačítko pověsit jen jednou. Dvě tlačítka se stejnou akcí a jinou klávesou jsou v pořádku, dvě
/// se stejnou kombinací ne (#151, #184) — a že se to v katalogu nestalo, hlídá test.
///
/// Jak se tlačítka schovávají, ví `hiddenShortcuts` — tenhle typ se do něj vkládá, sám nic
/// neschovává.
struct WindowShortcutButtons: View {
    let action: WindowShortcut.Action
    /// Zakázané tlačítko klávesu **nebere a propadne dál** — vzorec, na kterém v tomhle okně stojí
    /// `⌘⏎`, `⌘2` i `⎋`.
    var isEnabled = true
    let run: () -> Void

    /// Dokud píše člověk do terminálu, patří klávesa jemu (#459).
    @Environment(\.terminalFocused) private var terminalFocused

    var body: some View {
        let shortcut = Policy.windowShortcut(action)
        // `id: \.self`, ne index: kombinace jsou `Hashable` a katalog je má vzájemně různé.
        ForEach(shortcut.combinations, id: \.self) { combination in
            Button(shortcut.title, action: run)
                // **`nil`, ne `disabled`**, a je to rozdíl v tvrzení: zakázané tlačítko říká
                // „akce teď není k dispozici“, kdežto tady ta akce k dispozici je — jen tu
                // klávesu okno nemá brát. Obojí propadne dál, takže se chová stejně; rozejít by
                // se to dalo teprve tehdy, kdyby zkratka někdy dostala i viditelné tlačítko.
                .keyboardShortcut(yields(combination) ? nil : combination.keyboardShortcut)
                .disabled(!isEnabled)
        }
    }

    private func yields(_ combination: WindowShortcut.Combination) -> Bool {
        terminalFocused && Policy.shortcutYieldsToTerminal(action, combination)
    }
}

extension View {
    /// Zkratka z katalogu na **viditelném** tlačítku.
    ///
    /// Bere jen tu primární kombinaci — víc jich na jedno tlačítko pověsit nejde. Akce, které mají
    /// alternativu (sekce railu, potvrzení odeslání, terminál), proto viditelné tlačítko se
    /// zkratkou nemají a jdou přes `WindowShortcutButtons`.
    ///
    /// **Ustupování terminálu (#459) platí i tady**, ačkoli dnešní dva volající jsou obojí na `⌘`,
    /// takže se jich netýká. Je to schválně: kdyby se pravidlo psalo jen do `WindowShortcutButtons`,
    /// porušila by ho první zkratka na `Control`u, která by dostala viditelné tlačítko — a poznalo
    /// by se to až tím, že `⌃W` zavře záložku uprostřed psaní.
    func windowShortcut(_ action: WindowShortcut.Action) -> some View {
        modifier(WindowShortcutModifier(action: action))
    }
}

/// Zkratka na viditelném tlačítku, která umí ustoupit terminálu.
///
/// Vlastní `ViewModifier`, protože `View` extension se na prostředí zeptat nemůže — a příznak
/// „terminál má fokus“ jde právě prostředím (viz `EnvironmentValues.terminalFocused`).
private struct WindowShortcutModifier: ViewModifier {
    let action: WindowShortcut.Action
    @Environment(\.terminalFocused) private var terminalFocused

    func body(content: Content) -> some View {
        let combination = Policy.windowShortcut(action).primary
        let yields = terminalFocused && Policy.shortcutYieldsToTerminal(action, combination)
        return content.keyboardShortcut(yields ? nil : combination.keyboardShortcut)
    }
}
