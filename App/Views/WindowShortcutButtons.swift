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
        }
    }
}

extension ShortcutModifiers {
    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if contains(.control) { modifiers.insert(.control) }
        if contains(.option) { modifiers.insert(.option) }
        if contains(.shift) { modifiers.insert(.shift) }
        if contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
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

    var body: some View {
        let shortcut = Policy.windowShortcut(action)
        // `id: \.self`, ne index: kombinace jsou `Hashable` a katalog je má vzájemně různé.
        ForEach(shortcut.combinations, id: \.self) { combination in
            Button(shortcut.title, action: run)
                .keyboardShortcut(combination.keyboardShortcut)
                .disabled(!isEnabled)
        }
    }
}

extension View {
    /// Zkratka z katalogu na **viditelném** tlačítku.
    ///
    /// Bere jen tu primární kombinaci — víc jich na jedno tlačítko pověsit nejde. Akce, které mají
    /// alternativu (sekce railu, potvrzení odeslání), proto viditelné tlačítko se zkratkou nemají
    /// a jdou přes `WindowShortcutButtons`.
    func windowShortcut(_ action: WindowShortcut.Action) -> some View {
        keyboardShortcut(Policy.windowShortcut(action).primary.keyboardShortcut)
    }
}
