import SwiftUI

/// Dvojice řádků v pohledu **vedle sebe**: vlevo starý obsah se starým číslem, vpravo nový
/// s novým. Chybějící protistrana je prázdná buňka s neutrálním pozadím, ne mezera.
///
/// Buňky kreslí `DiffLineView` se `side` — obarvení, znak změny i tlačítko na komentář jsou
/// tedy na jednom místě pro oba pohledy.
struct DiffPairView: View {
    let left: DiffLine?
    let right: DiffLine?
    /// Jazyk souboru kvůli obarvení. `nil` = jednobarevný řádek.
    var language: Language?
    /// Akce rozdělaného review svázané s tímhle souborem.
    var draft = FileDraftActions()
    /// Druhý parametr je „⇧ bylo držené“ — roztažení rozsahu místo nového komentáře (#110).
    var performDraftAction: (LineDraftAction, Bool) -> Void = { _, _ in }
    /// Leží ta která strana uvnitř rozsahu mého komentáře? Pozadí rozsahu kreslí dvojice ze
    /// stejného důvodu jako pozadí druhu řádku — buňka se roztáhne jen na svůj obsah.
    var leftInRange = false
    var rightInRange = false
    /// Totéž pro rozsah, který se právě táhne — svítí výrazněji.
    var leftInDrag = false
    var rightInDrag = false
    /// Konec taženého rozsahu; tlačítko se při tažení ukazuje jen tam.
    var dragEnd: DraftAnchor.Endpoint?
    /// Tažení přes řádky (#110). Identita se doplňuje stranou, aby se rámečky obou buněk
    /// nepřebily — ve split pohledu se právě z rámečku pozná, na které straně se táhne.
    var rangeDrag = RangeDragActions()
    var dragID: String?
    /// Kopírování kódu do schránky (#157). Menu patří **na buňku**, ne na dvojici: pravé kliknutí
    /// do levé poloviny se vztahuje k odebranému řádku, ne k tomu vedle.
    var copy = DiffCopyActions()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            cell(left, side: .left, inDrag: leftInDrag)
            Rectangle().fill(.separator).frame(width: 1)
            cell(right, side: .right, inDrag: rightInDrag)
        }
        // Pozadí kreslí dvojice, ne buňky. Buňka se roztáhne jen na svůj obsah, takže
        // u kratší strany (a hlavně u té chybějící) by pod ní prosvítalo okno a chybějící
        // řádek by vypadal jako mezera. Rozdělení šířky je stejné jako výš — poloviny proto
        // sedí na sebe.
        .background {
            HStack(spacing: 0) {
                background(of: left, tint: DiffLineView.tint(dragged: leftInDrag, saved: leftInRange))
                Color.clear.frame(width: 1)
                background(of: right, tint: DiffLineView.tint(dragged: rightInDrag, saved: rightInRange))
            }
        }
    }

    @ViewBuilder private func cell(_ line: DiffLine?, side: DiffSide, inDrag: Bool) -> some View {
        if let line {
            DiffLineView(
                line: line,
                side: side,
                language: language,
                // **Buňka se ptá za svou stranu**, takže komentář vznikne tam, kam se kliklo.
                // Kontextový řádek unese obě strany — změřeno u #98 na živém API, viz
                // `LineAnchors`. Do té doby se ptalo bez strany a klik do levé poloviny
                // zakládal komentář vpravo („okno se otevře jinde, než kam jsem klikl“);
                // předtím se zase tlačítko vlevo vůbec nenabízelo, což bylo horší.
                draftAction: draft.action(for: line, on: side),
                performDraftAction: performDraftAction,
                dragEnd: dragEnd,
                rangeDrag: rangeDrag,
                dragID: dragID.map { "\($0)|\(side.rawValue)" }
            )
            .copyMenu(copy.targets(line), selectText: copy.selectableText(line).map { text in
                { copy.showText(text) }
            })
            // **Jen šířka, výška ne.** `maxHeight: .infinity` tady bylo a položilo to aplikaci:
            // main thread se zasekl na 99 % v `StackLayout.explicitAlignment` a
            // `ViewResponder.hitTest`, tedy v přepočtu layoutu při každém pohybu myši nad
            // diffem (změřeno `sample`m u #98). Pružná výška v líném seznamu, který výšku
            // nenavrhuje, je pro layout engine práce bez konce. Cena: citlivá na myš je jen
            // výška textu, takže u dvojice, které se jedna strana zalomila, se pod kratším
            // textem tlačítko na komentář nenabídne.
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            // Šířku si vzít musí, jinak by proti sobě stály jinak široké poloviny a čísla
            // by se rozešla s obsahem.
            Color.clear.frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func background(of line: DiffLine?, tint: Color) -> some View {
        if let line {
            DiffLineView.background(of: line.kind)
                // Pruh rozsahu jde **přes** barvu druhu řádku, ať zůstane vidět, co je přidané
                // a co odebrané. Od #277 `overlay`, ne `background`: barva druhu řádku je
                // vyčíslená, tedy neprůhledná, takže pruh pod ní zmizel — viz `DiffLineView`.
                .overlay(tint)
                .frame(maxWidth: .infinity)
        } else {
            // Díra, ne prázdno: „tady žádný řádek není“ se od „je tu prázdný řádek“ jinak
            // nepozná. Od #277 z palety a se šrafou, protože samotná plocha na to v tmavém
            // režimu nestačí (ΔE 3,3) — podrobnosti u `Palette.diffMissing`.
            Palette.diffMissing
                .overlay {
                    DiffMissingHatch()
                        .stroke(Palette.diffMissingStripe, lineWidth: DiffMissingHatch.lineWidth)
                        // Pruhy jsou o výšku rámečku posunuté doleva (sklon 45°), takže bez
                        // ořezu přetečou do řádku vedle. V bloku kódu to dělá `setClip`.
                        .clipped()
                }
                .frame(maxWidth: .infinity)
        }
    }
}
