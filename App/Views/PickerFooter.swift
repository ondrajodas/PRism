import SwiftUI

/// Patka nabídky v panelu — `.pkr-foot` z návrhu, **jedno místo pro obě její náplně** (#434).
///
/// Návrh tou třídou kreslí dvě různé věci: nápovědu kláves pod seznamem (sekce 24) a potvrzení
/// nového labelu na druhé obrazovce (sekce 26). Plocha je u obou tatáž — horní linka `--line-soft`,
/// podklad `--panel-2`, odsazení `6 × 11` a mezera `12` —, takže je i tady jedna. Do #434 stála
/// jen v potvrzení a druhá kopie by se s ní rozešla potichu: jediné, co by z toho bylo vidět, je
/// jinak vysoká patka v jedné z nabídek.
struct PickerFooter<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        // **Přes celou nabídku, ne jen pod obsah**: podklad a horní linka jsou v návrhu hrana mezi
        // seznamem a patkou, takže musí jít od kraje ke kraji.
        //
        // Nabídka labelů má pevných 300 bodů, takže je to u ní bez následku. **U reviewerů, kteří
        // si šířku neurčují rámcem, se přirozená šířka posunula ze 145 na 195 bodů** (změřeno) —
        // patka je od #434 nejširší prvek nabídky. Není to regrese: `.pkr` má v návrhu 300, takže
        // užší nabídka je odchylka na druhou stranu a 195 je jí blíž. Hlídá se, že těch 300
        // nepřeteče (`PickerKeyHintsTests`).
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
    }
}

/// Nápověda kláves pod nabídkou (#434) — `↑↓ vybírá`, `↵ …`, `esc zavře`.
///
/// **Proč vůbec:** od #392 a #413 se v nabídce nasbíralo dost kláves (šipky, `↵`, `⌥↵`, `esc`), aby
/// se nedaly uhodnout. Návrh na to má patku v obou nabídkách a v aplikaci nebyla ani v jedné.
///
/// **Liší se jediné slovo** — co udělá `↵`. U labelů `přepne` (klik je přepínač, takže se stejným
/// řádkem label i sundá), u reviewerů `vyžádá`. Zbytek je u obou týž, a proto je tady, ne dvakrát.
///
/// **`⌥↵` v patce schválně není.** Zakládání nového labelu má zkratku napsanou **u akce samotné**
/// (`.nl-add .keys`) a návrh to tak kreslí i v tom stavu, kde ta akce je (sekce 26): patka i tam
/// nese tři položky. Klávesa u akce stojí přímo nad tím, co udělá; v patce by byla čtvrtá položka,
/// která ve třech ze čtyř stavů nabídky neplatí.
///
/// **Nad prázdným výsledkem se patka nekreslí** — rozhoduje `Policy.pickerShowsKeyHints(rowCount:)`,
/// důvod je u ní.
struct PickerKeyHints: View {
    /// Co udělá `↵` na vybraném řádku. Sloveso, protože se to čte jako věta: `↵ přepne`.
    let confirm: String

    var body: some View {
        PickerFooter {
            hint(keys: "↑↓", does: "vybírá")
            hint(keys: "↵", does: confirm)
            hint(keys: "esc", does: "zavře")
        }
        // **Patka je zkratka pro oko, ne popisek položky** (#392 dalo celou větu každému řádku
        // a to platí dál). Čtečce se proto čte jednou a slovy: `↑↓` samo o sobě je dvojice znaků,
        // ze kterých není poznat, že jde o šipky.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("šipky vybírají, enter \(confirm), escape zavře")
    }

    /// Jedna položka patky. **Klávesa i sloveso jedním textem a jedním písmem** — návrh v `.pkr-foot`
    /// žádné mono nemá a dva `Text`y by mezi sebou nesly mezeru, která se umí zalomit.
    private func hint(keys: String, does: String) -> some View {
        Text(verbatim: "\(keys) \(does)")
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.ink3)
            // Nezalamovat a neořezávat: že se to do 300 bodů vejde, je **změřené**
            // (`PickerKeyHintsTests`), takže ořez by tu chybu jen schoval.
            .fixedSize()
    }
}
