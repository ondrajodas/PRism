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

    init(headSha: String, findings: [Finding]) {
        self.headSha = headSha
        self.findings = findings
    }
}
