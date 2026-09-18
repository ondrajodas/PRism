import SwiftUI

/// Anotace ve stavovém řádku (#525) — `Anotace · 4 věty · proti 4f2ac91`.
///
/// **Odpovídá na jinou otázku než věty v diffu.** Ty říkají, *proč* je tam ten který hunk; tenhle
/// údaj říká, že je diff popsaný a **proti které hlavě** — tedy že to, co v něm stojí, platí pro
/// dnešní commit. Bez něj se „popis tu není“ nedá odlišit od „popis propadl pushem“, protože
/// zastaralé anotace se nekreslí vůbec (tvrdá podmínka č. 5).
///
/// **Vlastní view, ne řádek ve `StatusBarView`** — tatáž úvaha jako u `ItineraryStatusView`:
/// sledují se jen ty vlastnosti store, které tenhle `Text` čte, takže se překresluje on a ne pruh
/// s frontou, útratou a puntíky.
///
/// Kreslí se jedině nad otevřeným pull requestem — na domácí záložce není o čím diffu mluvit.
struct AnnotationStatusView: View {
    let store: AppStore

    var body: some View {
        if case .pullRequest(let id) = store.activeTab {
            content(for: id)
        }
    }

    /// **Bere tentýž getter jako diff** (`AppStore.annotations(for:)`), ne mapu napřímo: rozhodnutí
    /// „záznam z jiné hlavy se nepočítá“ má být jedno, jinak by pruh mluvil o větách, které v diffu
    /// nikdo nevidí.
    @ViewBuilder private func content(for id: PRIdentifier) -> some View {
        if let text = Policy.annotationStatus(of: store.annotations(for: id)) {
            Text(verbatim: text)
                .font(.caption)
                .foregroundStyle(Palette.ink2)
                .monospacedDigit()
                .help(Policy.annotationStatusHelp)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Anotace hunků")
                .accessibilityValue(text)
        }
    }
}
