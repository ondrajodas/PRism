import SwiftUI

/// Věta *proč* pod souřadnicí hunku (#525, `.hunk-why` v zákresu sekce 59).
///
/// **Proporcionálním písmem a o odsazení dál**, ne mono jako souřadnice nad ní: jsou to dvě různá
/// tvrzení — `@@ -78,9 +78,21 @@` je strojový údaj, tohle věta pro člověka —, a v jednom řezu by
/// se četla jako jedno. Podklad nemá schválně: druhý barevný pruh hned pod hlavičkou hunku by
/// z diffu udělal pruhovanou tabulku.
///
/// **Vlastní řádek mezi bloky, ne vložka do `NSTextView`** (#469): na geometrii bloku kódu se tím
/// nesahá vůbec — je to `DiffRow.annotation`, tedy tentýž druh řádku jako hlavička hunku.
///
/// **Zdroj je za odrážkou a tišší** (`--ink-3`). Je to doklad, ne věta; anotace bez zdroje je pořád
/// věta, kterou stojí za to mít, takže se kvůli němu **nezahazuje** (`HunkAnnotation.source`
/// je volitelné).
struct DiffAnnotationRowView: View {
    let annotation: HunkAnnotation

    var body: some View {
        // Jeden `Text`, ne `HStack` dvou: věta se zdrojem se má lámat **jako jeden odstavec**,
        // jinak by zdroj skočil na vlastní řádek i tam, kde by se na ten předchozí ještě vešel.
        (Text(verbatim: annotation.why).foregroundStyle(Palette.ink2) + source)
            .font(.system(size: 11.5))
            .lineSpacing(2)
            // **Bez `.textSelection(.enabled)`**, přesně jako bublina nálezu a vlákna o kus vedle:
            // selekce v řádku nad diffem je podle `CLAUDE.md` druhý zdroj nevykreslených řádků.
            // Zkopírovat se ta věta nepotřebuje — vznikla z tohohle PR a nikam se neposílá.
            .padding(.leading, 22)
            .padding(.trailing, 14)
            .padding(.top, 3)
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Proč je tahle změna v PR")
            .accessibilityValue(Policy.annotationSpeech(of: annotation))
    }

    /// `· z commitu perf: cache secrets`. Prázdné, když zdroj není.
    private var source: Text {
        guard let text = annotation.source, !text.isEmpty else { return Text(verbatim: "") }
        return Text(verbatim: " · \(text)").foregroundStyle(Palette.ink3)
    }
}
