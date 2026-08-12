import Foundation

extension String {
    /// Text na jeden řádek — řádkové zlomy se nahradí mezerou.
    ///
    /// Potřebuje to každé místo, kde se **cizí** text (komentář, nález, cesta k souboru) vkládá
    /// do řádku, který si zalomení nesmí nechat vnutit: hlavička bubliny, přehled draftu,
    /// syntetická hlavička diffu (`Policy.snippet(of:)`) a od #200 tělo notifikace, kde je na
    /// třetím řádku jméno PR — jeden `\n` navíc v nálezu by ho odsunul mimo banner.
    ///
    /// Bydlí to tady, protože kopií bylo pět a rozejít se umí i jednořádkové pravidlo: stačí,
    /// aby jedna z nich řešila `\r\n` a ostatní ne. Tatáž úvaha jako u `Plural`.
    ///
    /// **`isNewline` tady zůstává schválně**, ne omylem, i když dělení řádků jinak drží `TextLines`
    /// (#295). Tohle není otázka „kde končí řádek v bajtech, které mi někdo poslal“, ale „co mi
    /// zalomí popisek“ — a `U+2028` popisek zalomí, takže se srazit musí. Zdůvodnění je celé
    /// v `Character.isLineTerminator`.
    var singleLine: String {
        split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
