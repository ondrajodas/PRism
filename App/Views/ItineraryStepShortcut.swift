import SwiftUI

/// Mezerník jako další zastávka itineráře (#507).
///
/// **Vlastní view, ne `@ViewBuilder` v detailu — a je to výkonová podmínka**, tatáž jako
/// u `DiffReadShortcut` (#500): čte se tu poloha výřezu, tedy hodnota, která se mění při každém
/// otočení kolečka. Kdyby to čtení stálo v těle `PullRequestDetailView`, překládalo by se při
/// každém snímku celé tělo detailu i s diffem pod ním. Takhle se překresluje jedno průhledné
/// tlačítko.
///
/// Schovává ho `hiddenShortcuts` v detailu, jako ostatní zkratky okna — proto si tenhle typ
/// průhlednost nenasazuje sám.
struct ItineraryStepShortcut: View {
    /// Zastávky v pořadí čtení — `Policy.itinerary`, složené detailem.
    let stops: [ItineraryStop]
    /// Kde jsem v procházení dráhy. `nil` = ještě nikde, takže se jde na aktuální zastávku.
    let cursor: ItineraryStop.Kind?
    let pullRequest: PRIdentifier
    let tab: PullRequestTab
    /// Kde stojí výřez obsahu. Čte se **tady**, ne v detailu — viz výš.
    let content: ContentEndState
    let select: (ItineraryStop) -> Void

    /// Píše se někde v okně do pole? Do textu patří mezera, ne skok.
    @Environment(\.textFieldFocus) private var focus

    var body: some View {
        let step = Policy.itineraryStep(
            stops: stops,
            cursor: cursor,
            isEditing: focus?.isEditing ?? false,
            atEnd: content.isAtEnd(of: pullRequest, in: tab)
        )
        // **Zakázané tlačítko klávesu nebere a mezerník propadne scrollu** — vzorec, na kterém
        // v tomhle okně stojí `⌘⏎`, `⌘2` i `⎋`, a jediné, čím se dá holá klávesa vzít bezpečně.
        WindowShortcutButtons(action: .nextItineraryStop, isEnabled: step != nil) {
            if let step { select(step) }
        }
    }
}
