import SwiftUI

/// Odznak se stavem review v řádku seznamu.
///
/// Text i barvu drží `ReviewStateAppearance` — od #172 je potřebuje i proužek na hraně řádku
/// a dvě kopie téhož `switch`e by se rozešly.
///
/// **Sazba je `designPill`** (#404, zbytek třídy z #348): návrh kreslí tenhle odznak jako
/// `.pill.crit`/`run`/`ok`/`stale`/`idle`, tedy mono 10,5 s odsazením 7 a 2. Do #404 tady stálo
/// `.caption` (systémových 10) s odsazením 6 a 2, takže odznak stavu vypadal jako jiný druh prvku
/// než pilulka `N k předání`, která v tomtéž řádku stojí **na jeho místě** (#334).
///
/// **Barva se tím nemění.** Škálu drží `ReviewStateAppearance` a její hranice mezi systémovými
/// a paletovými barvami je rozhodnutá u #309 měřením; #404 je o sazbě.
struct ReviewStateBadge: View {
    let state: ReviewState
    /// Kolik nálezů blokuje. Mění text i barvu: „3 nálezy“ oranžově je práce,
    /// „3 nálezy · 1 blokuje“ červeně je zastavený merge.
    var blocking = 0

    var body: some View {
        Text(verbatim: ReviewStateAppearance.label(of: state, blocking: blocking))
            .designPill(tint: color, background: color.opacity(0.15))
            // `white-space: nowrap` z návrhu — a v tomhle řádku je to podmínka, ne ozdoba: mono je
            // u nejdelšího stavu o 48 bodů širší (`timeout · 2 · 1 blokuje`, 116 → 164 bodu).
            //
            // **`lineLimit` a `fixedSize` řeší dvě různé věci a obojí je potřeba** (změřeno,
            // ne odvozeno): `lineLimit(1)` brání zalomení, ale místo něj **zkracuje**, takže sám
            // o sobě by z odznaku udělal `3 nález…`. Neustoupit vůbec umí až `fixedSize` — a pak
            // ustupuje titulek PR, který `lineLimit(1)` má odjakživa. Odznak je stav, který buď je
            // čitelný, nebo neříká nic; tatáž úvaha jako u odznaků v bublině a v kartě nálezu.
            .lineLimit(1)
            .fixedSize()
            // `monospacedDigit()` je pryč: mono řez má stejně široké číslice sám (naměřeno
            // `TextWidth.pill("111") == TextWidth.pill("999")`), takže by to bylo druhé tvrzení
            // o tomtéž — a nasazené **za** `designPill` by ho stejně nepřebilo, protože bližší
            // `font` z modifikátoru vyhrává.
    }

    private var color: Color {
        ReviewStateAppearance.color(of: state, blocking: blocking)
    }
}

#Preview {
    VStack(alignment: .leading) {
        ReviewStateBadge(state: .notStarted)
        ReviewStateBadge(state: .running(finished: 2, total: 3))
        ReviewStateBadge(state: .clean)
        ReviewStateBadge(state: .completed(findings: 9))
        ReviewStateBadge(state: .completed(findings: 3), blocking: 1)
        ReviewStateBadge(state: .dismissed(findings: 3))
        ReviewStateBadge(state: .timedOut(findings: 2), blocking: 1)
        ReviewStateBadge(state: .failed(detail: "boom"))
        ReviewStateBadge(state: .inconclusive(reason: .unreadCode))
        ReviewStateBadge(state: .inconclusive(reason: .noReport))
        ReviewStateBadge(state: .inconclusive(reason: .droppedFindings))
        ReviewStateBadge(state: .stale)
    }
    .padding()
}
