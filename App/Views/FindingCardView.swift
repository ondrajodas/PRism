import SwiftUI

/// Jeden nález v panelu jako karta (#175).
///
/// Tabulka měla při šířkách z #60 problém, který se nedal vyřešit sloupci: kategorie, místo
/// i shrnutí se perou o místo, a odmítnutí (#113) muselo skončit jako odznak u kategorie,
/// protože nový sloupec neměl kam. Karta má místa dost a **závažnost nese proužek na hraně**,
/// takže se pozná dřív než z textu — tatáž úvaha jako u řádku fronty (#172).
struct FindingCardView: View {
    let row: FindingRow
    /// Stojí na téhle kartě kurzor procházení (#187)? Rámeček je jediné, co v panelu říká
    /// „tady jsem“ — v diffu to řekne skok, ale ten je jinde na obrazovce.
    var isCurrent = false
    var findingActions: FindingActions?
    let jump: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            // Přeškrtnuté jen **shrnutí**, ne celá karta (#150): celořádkové „nepočítá se“ nosí
            // `DismissedRowStyle`, tedy rozhodnutí člověka, a tvrzení modelu ho nesmí napodobit.
            Text(verbatim: row.summary)
                .strikethrough(row.severityBadge.strikesFindingText, color: .secondary)
                .font(.callout)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            recheck
            footer
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: .rect(cornerRadius: 8))
        .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 3) }
        .clipShape(.rect(cornerRadius: 8))
        // Rámeček **kolem** karty, ne změna pozadí: pozadí už nese odmítnutí (ztlumením)
        // a dvě věci na jednom kanálu se pletou.
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.tint, lineWidth: isCurrent ? 2 : 0)
        }
        // Celá karta je tlačítko, ne jen místo v patičce: klik do řádku tabulky skákal taky
        // odkudkoli a je to ten pohyb, který se dělá nejčastěji.
        .contentShape(.rect)
        .onTapGesture(perform: jump)
        .modifier(DismissedRowStyle(row: row, actions: findingActions))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        // `onTapGesture` **není** akce, kterou VoiceOver umí spustit: prvek by se četl jako
        // tlačítko, ale „activate“ by neudělalo nic. Skok se proto přidává i jako akce.
        .accessibilityAction(.default, jump)
        .accessibilityHint("Skočí na místo v diffu")
    }

    private var header: some View {
        HStack(spacing: 6) {
            severity
            Text(verbatim: row.category)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(verbatim: "·")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(verbatim: row.reviewer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if isCurrent {
                Text("tady jsi")
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }
        }
    }

    /// Odznak závažnosti: `blokuje`, důvod odmítnutí, nebo `vyřešeno` z kontroly (#150).
    ///
    /// Co v něm stojí, rozhoduje `Policy` — tady se to jen kreslí. `vyřešeno` je **před**
    /// `blokuje`, protože odpovídá na otázku „musím se na to ještě koukat“; `blokuje` zůstává
    /// hned za ním, aby se karta nečetla jako hotová věc, která pořád drží merge.
    @ViewBuilder private var severity: some View {
        switch row.severityBadge {
        case .dismissed(let reason):
            pill(reason.label, tint: .secondary).help(row.categoryHelp)
        case .resolved(let status, let blocking):
            pill(FindingSeverityBadge.resolvedLabel, tint: FindingSeverityBadge.resolvedTint)
                .help(status.help)
            if blocking { blockingWarning }
        case .blocking:
            blockingWarning
        case .none:
            EmptyView()
        }
    }

    /// **Nezalomí se a neustoupí** (`fixedSize`, `layoutPriority`): ve 300 bodech panelu se vedle
    /// `vyřešeno` zalomilo na `blo-kuje` a odznak vyšel jako `vyřeše…` (offscreen render). Odznak
    /// je jedno slovo, které buď je čitelné, nebo neříká nic, takže v úzkém panelu ustupují texty
    /// vedle něj — kategorie a reviewer. Tatáž úvaha jako u odznaků v bublině.
    private var blockingWarning: some View {
        Label("blokuje", systemImage: "exclamationmark.triangle.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.red)
            .fixedSize()
            .layoutPriority(2)
            .help("Blokující nález — kvůli němu se PR nemerguje")
    }

    private func pill(_ text: String, tint: Color) -> some View {
        Text(verbatim: text)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.15), in: .capsule)
            .foregroundStyle(tint)
            .fixedSize()
            .layoutPriority(2)
    }

    /// Co o nálezu řekla kontrola z minula (#150) — **vlastní řádek pod textem**, ne odznak
    /// v hlavičce.
    ///
    /// Do hlavičky se to nevešlo, a je to změřené, ne odhadnuté: panel je 300 bodů, takže se
    /// v ní vedle `blokuje`, kategorie a revieweera odznak zkrátil na `kontrola…` a `blokuje` se
    /// zalomilo na dva řádky (offscreen render). Pod textem je místa dost a je to **tatáž sazba
    /// jako v bublině u kódu**: odznak a za ním věta.
    ///
    /// Odmítnutý nález odznak nedostane — o něm už rozhodl člověk a druhý stav vedle sebe se plete.
    @ViewBuilder private var recheck: some View {
        if row.dismissal == nil, let status = row.recheck {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: status.verdict.label)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(status.verdict.tint.opacity(0.15), in: .capsule)
                    .foregroundStyle(status.verdict.tint)
                if let note = status.note {
                    // Jeden řádek: karta je náhled, ne celý nález. Celá věta je v bublině u kódu
                    // a v nápovědě, takže se tady nic neztrácí.
                    Text(verbatim: note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .help(status.help)
        }
    }

    /// Místo se ořezává **zepředu**, ať zůstane vidět jméno souboru a číslo řádku — z dlouhé
    /// cesty je zajímavý konec. Stejné pravidlo jako ve sloupci `Místo`, který karta nahradila.
    private var footer: some View {
        Text(verbatim: row.location)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.head)
            .help(row.locationHelp)
    }

    /// Barva hrany. Blokující červená, platný nález oranžový, odmítnutý tlumený — a je to
    /// **tatáž škála jako v řádku fronty** (#172), aby seznam a panel neříkaly o téže věci
    /// každý něco jiného.
    private var accent: Color {
        if row.dismissal != nil { return .secondary }
        return row.isBlocking ? .red : .orange
    }
}

#Preview {
    let rows = FindingRow.rows(of: [
        Finding(
            reported: ReportedFinding(
                file: "src/Vault/SecretClient.php",
                line: 81,
                category: "correctness",
                verdict: .confirmed,
                shortSummary: nil,
                summary: "`?? ''` schová chybějící secret jako prázdnou hodnotu",
                failureScenario: nil
            ),
            reviewer: "php-review",
            headSha: "aaaa1111"
        ),
        Finding(
            reported: ReportedFinding(
                file: nil,
                line: nil,
                category: "test-coverage",
                verdict: .plausible,
                shortSummary: nil,
                summary: "Nová výjimka SecretNotFound nemá test",
                failureScenario: nil
            ),
            reviewer: "php-review",
            headSha: "aaaa1111"
        ),
    ])

    return VStack(spacing: 8) {
        ForEach(rows) { row in
            FindingCardView(row: row, isCurrent: row.id == 0, jump: {})
        }
    }
    .padding()
    .frame(width: 460)
}
