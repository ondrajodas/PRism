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
            Text(verbatim: row.summary)
                .font(.callout)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            if row.showsBlockingWarning {
                Label("blokuje", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
                    .help("Blokující nález — kvůli němu se PR nemerguje")
            }
            if let dismissal = row.dismissal {
                Text(verbatim: dismissal.reason.label)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.15), in: .capsule)
                    .foregroundStyle(.secondary)
                    .help(row.categoryHelp)
            }
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
