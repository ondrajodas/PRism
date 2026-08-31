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
    /// Kam se zapisuje otevřená nabídka emotikonů (#483). `nil` = **pole emotikony nenašeptává**.
    ///
    /// **Třem polím ano, čtvrtému ne.** Box podává ten, ze koho text odchází na GitHub (composer
    /// komentáře pod PR, odpověď do vlákna, tělo review v panelu); prompt v tabu `Zeptat se` ho
    /// nemá, protože to není text pro GitHub, ale zadání pro session — a je to jediné pole v okně,
    /// které si už bere `Return` (`Policy.claimsReturnShortcut`, #452). Přidat do něj druhého
    /// zájemce o tutéž klávesu je přesně ten postup, po kterém #184 popsalo, čím končí.
    ///
    /// **Nabídku kreslí ten, kdo box drží**, ne tohle pole — `overlay` by ji nechal uříznout
    /// o `ScrollView` panelu i o `clipShape` bubliny (viz `EmojiSuggestionBox`).
    ///
    /// Pole s boxem si bere **kurzor**, tedy `TextEditor(text:selection:)`. Bez boxu ne, a je to
    /// schválně: každý pohyb kurzoru je zápis do stavu, a v poli, které nabídku nemá, by to byla
    /// práce, kterou nikdo nepřečte.
    var suggestions: EmojiSuggestionBox?

    @State private var selection: TextSelection?

    var body: some View {
        if let suggestions {
            framed(TextEditor(text: $text, selection: $selection))
                .modifier(
                    EmojiSuggesting(text: $text, selection: $selection, suggestions: suggestions)
                )
        } else {
            framed(TextEditor(text: $text))
        }
    }

    /// Rámeček, nápověda a strop výšky — **jedny pro obě podoby pole**. Dvě kopie by se rozešly
    /// a jediné, co by z toho bylo vidět, je jinak vysoké pole v jednom ze čtyř composerů.
    private func framed(_ editor: some View) -> some View {
        editor
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
