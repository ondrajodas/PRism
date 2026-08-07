import SwiftUI

/// Kopírování kódu z diffu (#157) — co nabídne kontextové menu řádku a hlavičky hunku.
///
/// Jeden parametr místo dvou closures, které patří k sobě — stejný vzor jako `DraftActions`
/// a `RangeDragActions`.
///
/// **Skládá se až při otevření menu.** Obě closures se volají z `contextMenu`, tedy jednou za
/// pravé kliknutí; text rozsahu se hledá přes všechny hunky souboru, takže při vykreslení každého
/// řádku by to byla práce navíc u operace, kterou nikdo nevyvolal.
struct DiffCopyActions {
    /// Co se dá zkopírovat z tohohle řádku. Prázdné = menu se nekreslí.
    var targets: (DiffLine) -> [DiffCopyTarget] = { _ in [] }
    /// Co se dá zkopírovat z hunku jako celku.
    var hunkTargets: (DiffHunk) -> [DiffCopyTarget] = { _ in [] }
    /// Hunk, ve kterém řádek leží, jako text k vybírání (#157). `nil` = není z čeho ho složit,
    /// položka se pak v menu nekreslí.
    var selectableText: (DiffLine) -> CodeText? = { _ in nil }
    /// Totéž z hlavičky hunku.
    var selectableHunkText: (DiffHunk) -> CodeText? = { _ in nil }
    /// Otevře sheet s tím textem. Sheet drží `DiffView`, protože je nad celým diffem.
    var showText: (CodeText) -> Void = { _ in }
}

extension View {
    /// Kontextové menu s kopírováním. Prázdný seznam menu **nepřidá**: prázdné menu, které se po
    /// pravém kliknutí otevře a nic nenabídne, vypadá jako rozbitá aplikace.
    ///
    /// Patří **na buňku, ne na seznam** — pravé kliknutí se vztahuje k tomu, na co se kliklo.
    @ViewBuilder func copyMenu(_ targets: [DiffCopyTarget], selectText: (() -> Void)? = nil) -> some View {
        if targets.isEmpty && selectText == nil {
            self
        } else {
            contextMenu {
                ForEach(targets) { target in
                    Button(target.title, systemImage: "doc.on.doc") {
                        Clipboard.copy(target.text)
                    }
                }
                if let selectText {
                    Divider()
                    // Tři tečky, protože se otevře okno — konvence systému. Vybírání přes řádky
                    // v diffu nejde (každý řádek je vlastní `Text`), takže tohle je jediná cesta,
                    // jak si vzít vlastní výřez z víc řádků.
                    Button("Vybrat text z hunku…", systemImage: "text.cursor", action: selectText)
                }
            }
        }
    }
}
