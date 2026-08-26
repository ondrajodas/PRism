import SwiftUI

/// Textové pole, jak vypadá v tomhle okně — rámeček, nápověda na prvním znaku, strop výšky.
///
/// **Drží jen podobu, ne to, kam se text ukládá.** Ukládání je u každého composeru jiné:
/// rozdělané review posílá text dolů **po odmlce** (`DraftTextEditor`, protože ho čtou bubliny
/// v diffu), kdežto rozhovor v tabu `Zeptat se` až **při odeslání** (`AskComposer`, protože
/// odmlka mezi „co je vidět“ a „co store ví“ tam odeslala starší otázku, #452). Dvě kopie
/// rámečku by se rozešly, takže je tady jednou a rozhoduje se nad ním, ne v něm.
struct DraftTextField: View {
    @Binding var text: String
    var placeholder = ""
    var minHeight: Double = 60
    /// Strop výšky. `nil` = pole se roztáhne, kolik dostane.
    ///
    /// Potřebuje ho ten, kdo pole staví do **svislého rozvržení se zbývajícím místem** (#216):
    /// `TextEditor` je svisle nenasytný, takže si o to zbylé místo řekne stejným dílem jako
    /// osa konverzace vedle něj — a composer pak zabral půlku tabu. Uvnitř scrollu (bublina
    /// vlákna, panel review) žádné zbylé místo není, proto tam strop netřeba.
    var maxHeight: Double?

    var body: some View {
        TextEditor(text: $text)
            .font(.callout)
            .scrollContentBackground(.hidden)
            // `map` schválně: `Double?` se na `CGFloat?` implicitně nepřevede, i když
            // `Double` na `CGFloat` ano.
            .frame(minHeight: minHeight, maxHeight: maxHeight.map { CGFloat($0) })
            // **Nápověda visí na editoru, ne na orámované ploše.** Kdyby se zavěsila až za
            // `padding`, počítala by se od hrany rámečku, kdežto kurzor stojí na začátku
            // textu — a mezi tím je právě to odsazení. Blikající kurzor mimo text z toho byl
            // vidět na první pohled.
            .overlay(alignment: .topLeading) { prompt }
            .padding(6)
            .background(.quinary, in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 1)
            }
    }

    /// `TextEditor` nápovědu neumí, takže se kreslí přes něj — a musí začínat **na prvním
    /// znaku**, ne na hraně pole.
    ///
    /// Svisle to znamená zavěsit ji na editor, ne na orámovanou plochu (viz `body`).
    /// Vodorovně chybí ještě `lineFragmentPadding` textového pole, tedy 5 pt, kterými
    /// `NSTextView` odsazuje glyfy od svého okraje — bez nich kurzor blikal přes první
    /// písmeno nápovědy. Číslo je systémové, ne odhad: `NSTextContainer` ho má takhle
    /// v defaultu.
    @ViewBuilder private var prompt: some View {
        if text.isEmpty && !placeholder.isEmpty {
            Text(verbatim: placeholder)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.leading, 5)
                .allowsHitTesting(false)
        }
    }
}
