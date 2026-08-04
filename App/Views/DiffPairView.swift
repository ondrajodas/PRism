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
    var performDraftAction: (LineDraftAction) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            cell(left, side: .left)
            Rectangle().fill(.separator).frame(width: 1)
            cell(right, side: .right)
        }
        // Pozadí kreslí dvojice, ne buňky. Buňka se roztáhne jen na svůj obsah, takže
        // u kratší strany (a hlavně u té chybějící) by pod ní prosvítalo okno a chybějící
        // řádek by vypadal jako mezera. Rozdělení šířky je stejné jako výš — poloviny proto
        // sedí na sebe.
        .background {
            HStack(spacing: 0) {
                background(of: left)
                Color.clear.frame(width: 1)
                background(of: right)
            }
        }
    }

    @ViewBuilder private func cell(_ line: DiffLine?, side: DiffSide) -> some View {
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
                performDraftAction: performDraftAction
            )
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

    @ViewBuilder private func background(of line: DiffLine?) -> some View {
        if let line {
            DiffLineView.background(of: line.kind).frame(maxWidth: .infinity)
        } else {
            // Neutrální plocha, ne prázdno: „tady žádný řádek není“ se od „je tu prázdný
            // řádek“ jinak nepozná. `Color.primary` funguje v obou režimech — v tmavém je
            // bílá, ve světlém černá, takže odstín vyjde vždycky proti pozadí okna.
            Color.primary.opacity(0.05).frame(maxWidth: .infinity)
        }
    }
}
