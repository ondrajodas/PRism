import Foundation

/// Co se dá dělat s rozdělaným review. Jeden parametr místo devíti closures, které patří
/// k sobě — stejný vzor jako `DiffExpansionActions`.
///
/// Výchozí hodnoty jsou prázdné, aby se `DiffView` a bubliny daly postavit i bez draftu
/// (náhledy, testy skládání řádků).
struct DraftActions {
    /// Dá se do draftu psát? `false`, dokud nevíme, proti kterému commitu — detail PR se
    /// zrovna načítá nebo se nepovedl. Akce se pak nenabízejí, protože draft bez commitu
    /// nejde ani označit za zastaralý, ani odeslat.
    var canCompose = false
    /// Založí prázdný řádkový komentář a nechá ho k dopsání.
    var addComment: (_ path: String, _ anchor: DraftAnchor) -> Void = { _, _ in }
    /// Poznámka do těla review s odkazem na kód — pro řádek, který komentář neunese.
    var addNote: (_ path: String, _ line: Int?) -> Void = { _, _ in }
    /// Převezme nález; kam půjde, rozhoduje store podle `Policy.draftTarget`.
    var adopt: (Finding) -> Void = { _ in }
    var isAdopted: (Finding) -> Bool = { _ in false }
    /// Kam by převzatý nález šel — bublina podle toho pojmenuje tlačítko a vysvětlí proč.
    var target: (Finding) -> DraftTarget = { _ in .body(path: nil, line: nil) }
    var updateComment: (_ id: UUID, _ body: String) -> Void = { _, _ in }
    var removeComment: (UUID) -> Void = { _ in }
    var setBody: (String) -> Void = { _ in }
    var setVerdict: (ReviewDraft.Verdict?) -> Void = { _ in }
    var discard: () -> Void = {}

    /// Akce svázané s jedním souborem diffu — cestu si doplní samy.
    ///
    /// Volající uvnitř diffu tak nemá jak poslat komentář na jiný soubor, než u kterého
    /// zrovna je. Kotvy se předávají jako hotová mapa, protože počítat je pro každý řádek
    /// zvlášť je kvadratické (viz `Policy.commentAnchors(in:)`).
    func bound(to file: FileDiff, anchors: [DiffLine: DraftAnchor]) -> FileDraftActions {
        FileDraftActions(
            canCompose: canCompose,
            anchor: { anchors[$0] },
            comment: { addComment(file.displayPath, $0) },
            note: { addNote(file.displayPath, $0) },
            adopt: adopt,
            isAdopted: isAdopted,
            target: target,
            updateComment: updateComment,
            removeComment: removeComment
        )
    }
}

/// Akce draftu uvnitř jednoho souboru diffu.
struct FileDraftActions {
    var canCompose = false
    /// Kotva komentáře na řádku — `nil` u řádku, který komentář neunese.
    var anchor: (DiffLine) -> DraftAnchor? = { _ in nil }
    var comment: (DraftAnchor) -> Void = { _ in }
    var note: (Int?) -> Void = { _ in }
    var adopt: (Finding) -> Void = { _ in }
    var isAdopted: (Finding) -> Bool = { _ in false }
    var target: (Finding) -> DraftTarget = { _ in .body(path: nil, line: nil) }
    var updateComment: (_ id: UUID, _ body: String) -> Void = { _, _ in }
    var removeComment: (UUID) -> Void = { _ in }

    /// Co jde na řádku udělat. `nil` = nic — meta řádek ani hlavička hunku obsah souboru
    /// nejsou, takže se k nim nedá vztáhnout ani poznámka.
    func action(for line: DiffLine) -> LineDraftAction? {
        guard canCompose else { return nil }
        if let anchor = anchor(line) { return .comment(anchor) }
        // Rozbalený kontext (#47) v diffu není, takže na něj GitHub řádkový komentář
        // nepustí — poznámka s odkazem na kód je jediné, co k němu jde napsat.
        return line.newNumber.map { .note(line: $0) }
    }
}

/// Co se dá udělat s jedním řádkem diffu.
enum LineDraftAction: Hashable {
    /// Řádkový komentář — řádek je uvnitř hunku.
    case comment(DraftAnchor)
    /// Položka do těla review s odkazem na kód.
    case note(line: Int)
}
