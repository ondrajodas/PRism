import SwiftUI

/// Souhrn fronty ve stavovém řádku (#155): kolik PR čeká, kolik má blokující nález a kolik
/// rozdělané review.
///
/// Odpovídá na otázku „musím se na to podívat hned?“, kterou dosud v okně nemělo kde zodpovědět:
/// odznak v řádku mluví za **jeden** PR, tohle za frontu. Filtr reviewerů (#117) seznam zužuje —
/// tenhle souhrn ho **sčítá**, protože je to tvrzení o obsahu, ne o pohledu.
struct QueueSummaryView: View {
    let summary: QueueSummary

    /// **Jeden chip, ne tři** (#179, podle návrhu). Souhrn je jedna odpověď na jednu otázku
    /// („musím se na to podívat hned?“), takže má být i jeden útvar; tři kapsle vedle sebe
    /// vypadaly jako tři nezávislé ukazatele od tří různých věcí. Části odděluje `·`, jak to
    /// pruh dělá i jinde.
    var body: some View {
        HStack(spacing: 5) {
            item(
                symbol: "tray.full",
                count: summary.pullRequests,
                // „PR“ se neskloňuje, takže je to jedno slovo pro všechny počty.
                label: "PR",
                tint: .secondary,
                // Sloveso patří **do tvarů**, ne za ně: „2 pull requesty čeká“ je špatně česky.
                // Nález Copilota na #168; tentýž vzor se našel ještě na dvou starších místech.
                help: Plural.czech(
                    summary.pullRequests,
                    one: "pull request čeká na review",
                    few: "pull requesty čekají na review",
                    many: "pull requestů čeká na review"
                )
            )
            // **Jen když je co hlásit.** Nula blokujících vedle nuly rozdělaných review je řádek
            // plný nul, ve kterém se to jedno číslo, na kterém záleží, ztratí.
            if summary.blocking > 0 {
                separator
                item(
                    symbol: "exclamationmark.triangle.fill",
                    count: summary.blocking,
                    label: Plural.word(summary.blocking, one: "blokující", few: "blokující", many: "blokujících"),
                    tint: .red,
                    help: "\(Plural.czech(summary.blocking, one: "pull request má", few: "pull requesty mají", many: "pull requestů má")) blokující nález"
                )
            }
            if summary.drafts > 0 {
                separator
                item(
                    symbol: "square.and.pencil",
                    count: summary.drafts,
                    // „review“ se neskloňuje; co je na něm rozdělané, řekne ikona pera a nápověda.
                    label: "review",
                    // **Mint, ne akcent** (#309). Souhrn je počet, na který se neklikne — a ve
                    // stejném pruhu, o pár desítek bodů vedle, sedí `Připravit` z
                    // `WorkingCopyStatusView` jako akcentový odkaz, na který se klikat má.
                    // Do #309 měly obě věci tutéž barvu (a tahle ještě k tomu systémovou modrou),
                    // takže pruh nabízel klik na číslo.
                    tint: Palette.mint,
                    help: "\(Plural.czech(summary.drafts, one: "pull request má", few: "pull requesty mají", many: "pull requestů má")) rozdělané review"
                )
            }
        }
        .statusChip()
    }

    private var separator: some View {
        Text(verbatim: "·")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    /// Ikona, číslo a **slovo, které říká, čeho** — samotná ikona s číslem se nedá přečíst
    /// (vyžádané při zkoušení #155: „nevím, co co znamená“). Konvence toho pruhu je ikona plus text,
    /// jako u puntíků služeb.
    ///
    /// Nápověda po hoveru zůstává a říká celou větu, protože v pruhu je místo jen na jedno slovo.
    private func item(symbol: String, count: Int, label: String, tint: Color, help: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(tint)
            // `verbatim`, ne interpolace do `Text` — ta jde přes locale a z 1234 udělá „1 234“.
            // Počet PR není množství k formátování, je to počet položek v seznamu.
            Text(verbatim: "\(count) \(label)")
                .font(.caption)
                .foregroundStyle(count > 0 ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                .monospacedDigit()
        }
        .help(help)
    }
}
