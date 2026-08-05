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
    /// ⇧ klik: roztáhne naposledy přidaný komentář na rozsah po tenhle řádek (#110). Když není
    /// co roztahovat, založí obyčejný komentář — o tom rozhoduje store, ne view.
    var extendComment: (_ path: String, _ anchor: DraftAnchor) -> Void = { _, _ in }
    /// Tažení přes řádky (#110): hlásí se průběžně, komentář vzniká až v `endRangeDrag`.
    /// `to == nil` = pod myší není řádek; rozsah se pak drží, ne aby se srazil (řeší store).
    var dragRange: (_ path: String, _ from: DraftAnchor, _ to: DraftAnchor?) -> Void = { _, _, _ in }
    var endRangeDrag: () -> Void = {}
    /// Rozsah, který se právě táhne — kvůli zvýraznění řádků. `nil` = netáhne se.
    var draggedRange: (path: String, anchor: DraftAnchor)?
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
    /// Otevře potvrzení odeslání. **Sama nic neodesílá** — dvě kliknutí, dvě různá tlačítka.
    var send: () -> Void = {}
    /// Proč odeslat nejde. `nil` = jde. Je to stav, ne akce, ale patří k `send` stejně jako
    /// `canCompose` k psaní: zakázané tlačítko bez důvodu vypadá jako rozbitá aplikace.
    var sendBlock: DraftSendBlock?
    /// Dá se zastaralý draft přenést na nový commit (#69)? Rozhoduje o tom, jestli je tlačítko
    /// odeslání zakázané, nebo se jen jmenuje `Zkontrolovat a odeslat…` — kontrola i přenesení
    /// se dějí v tom okně, které otevře `send`.
    var canTransfer = false

    /// Akce svázané s jedním souborem diffu — cestu si doplní samy.
    ///
    /// Volající uvnitř diffu tak nemá jak poslat komentář na jiný soubor, než u kterého
    /// zrovna je. Kotvy se předávají jako hotová mapa, protože počítat je pro každý řádek
    /// zvlášť je kvadratické (viz `Policy.commentAnchors(in:)`).
    func bound(to file: FileDiff, anchors: [DiffLine: LineAnchors]) -> FileDraftActions {
        FileDraftActions(
            canCompose: canCompose,
            anchors: { anchors[$0] ?? LineAnchors() },
            comment: { addComment(file.displayPath, $0) },
            extend: { extendComment(file.displayPath, $0) },
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
    /// Kotvy komentáře na řádku po stranách — prázdné u řádku, který komentář neunese.
    var anchors: (DiffLine) -> LineAnchors = { _ in LineAnchors() }
    var comment: (DraftAnchor) -> Void = { _ in }
    /// ⇧ klik na tlačítko u řádku — roztažení rozsahu (#110).
    var extend: (DraftAnchor) -> Void = { _ in }
    var note: (Int?) -> Void = { _ in }
    var adopt: (Finding) -> Void = { _ in }
    var isAdopted: (Finding) -> Bool = { _ in false }
    var target: (Finding) -> DraftTarget = { _ in .body(path: nil, line: nil) }
    var updateComment: (_ id: UUID, _ body: String) -> Void = { _, _ in }
    var removeComment: (UUID) -> Void = { _ in }

    /// Co jde na řádku udělat. `nil` = nic — meta řádek ani hlavička hunku obsah souboru
    /// nejsou, takže se k nim nedá vztáhnout ani poznámka.
    ///
    /// `side` říká, **na kterou stranu diffu se ptáme**. Ve split pohledu se ptá buňka za sebe,
    /// aby komentář vznikl tam, kam se kliklo — kontextový řádek unese obě strany (změřeno #98).
    /// V pohledu pod sebou je `nil` a platí kanonická strana.
    func action(for line: DiffLine, on side: DiffSide? = nil) -> LineDraftAction? {
        guard canCompose else { return nil }
        let anchors = anchors(line)
        let anchor: DraftAnchor? = if let side { anchors.anchor(on: side) } else { anchors.preferred }
        if let anchor { return .comment(anchor) }
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
