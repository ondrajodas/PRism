import Foundation

/// Vstup kontroly nálezů (#150): co se hlásilo minule a na kterém commitu.
///
/// **Bez materiálu se kontrola nespouští.** Chybějící vstup by skončil session, která hádá —
/// tlačítko se proto nenabízí, dokud se nálezy z předchozího commitu nemají kde vzít
/// (`AppStore.recheckMaterial(for:)`).
///
/// Nálezy se předávají **v pořadí**, ve kterém se na ně prompt ptá: index je `id` v otázce
/// i v odpovědi. Párování zpátky na nález pak nestojí na tom, že model přepíše text nálezu
/// doslova — a klíč z něj skládá `Policy.key(of:)`, tedy to jediné místo, kde se skládá.
struct RecheckMaterial: Sendable, Equatable {
    /// Commit, na kterém nálezy vznikly. V promptu je z něj `git diff <headSha>...HEAD`, tedy
    /// přesně to, co se od minula změnilo.
    let headSha: String
    /// Nálezy, na které se ptáme. Nikdy prázdné — kontrola bez nálezů nemá co zjišťovat.
    let findings: [Finding]
    /// Moje odeslané komentáře, na které se ptáme taky (#522). **Smí být prázdné**, a je to
    /// běžný stav: konverzace se nenačetla, žádné vlastní vlákno na PR nemám, nebo mi do všech
    /// někdo odpověděl — a na zodpovězené se model neptá (`Policy.unansweredComments(in:)`).
    ///
    /// Je to **rozšíření vstupu téže kontroly**, ne druhý běh: tentýž prompt, tatáž session,
    /// tentýž tvar odpovědi. Sada nástrojů se tím nemění ani o položku (tvrdá podmínka č. 2) —
    /// je to materiál v promptu, jako nálezy samotné.
    let comments: [SentComment]

    init(headSha: String, findings: [Finding], comments: [SentComment] = []) {
        self.headSha = headSha
        self.findings = findings
        self.comments = comments
    }

    /// Kde v poli odpovědí začínají komentáře.
    ///
    /// **Jedno pole indexů pro nálezy i komentáře**, protože odpověď má jeden tvar: `parse` čte
    /// jedno pole (první `[` po posledním `]`) a dvě by se do něj nevešla. Posun se proto počítá
    /// **tady a nikde jinde** — druhé místo by znamenalo verdikt přiřazený cizí větě.
    var commentIDOffset: Int { findings.count }

    /// Na kolik položek se prompt ptá — strop, proti kterému `parse` zahazuje vymyšlená `id`.
    var questionCount: Int { findings.count + comments.count }
}
