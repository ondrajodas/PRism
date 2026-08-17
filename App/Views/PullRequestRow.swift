import SwiftUI

/// Jeden řádek seznamu PR (#172).
///
/// **Titulek je nahoře, souřadnice pod ním.** Do #172 to bylo obráceně — repo první, titulek
/// druhý — a seznam se tím čte místo skenuje: „odkud to je“ je otázka, na kterou dojde řada
/// až po „co to je“.
///
/// Stav review nese **hrana řádku**, ne jen odznak. Barva na kraji se přečte periferně, takže
/// se fronta dá přejet očima; odznak vedle ní říká totéž slovy, protože samotná barva nestačí.
struct PullRequestRow: View {
    let pullRequest: PullRequestSummary
    let reviewState: ReviewState
    /// Leží na tomhle PR rozdělané review? Ukazuje se ikonou, ne slovem: „draft“ je vedle
    /// v řádku obsazený **rozpracovaným pull requestem**, což je něco jiného.
    var hasDraft = false
    /// Odvozená čísla k výsledku — kolik blokuje a jak se nálezy rozdělily mezi reviewery.
    /// Prázdné u PR, na kterém nic neběželo.
    var row: QueueRow = .empty
    /// Čí PR to je (#331). U vlastního má řádek vpravo `Prompt →`, protože sestavit z nálezů
    /// a konverzace zadání pro agenta je jediné, co s ním okno umí udělat — verdikt na vlastní PR
    /// GitHub odmítá.
    var ownership: PullRequestOwnership = .theirs

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            headline
            meta
        }
        .padding(.vertical, 4)
        .padding(.leading, 9)
        // Proužek přes celou výšku řádku. `overlay`, ne sloupec v `HStacku`: jinak by se
        // musela výška dopočítávat ručně a u dvouřádkového titulku by proužek nedosáhl.
        .overlay(alignment: .leading) {
            Capsule()
                .fill(ReviewStateAppearance.color(of: reviewState, blocking: row.blocking))
                .frame(width: 3)
        }
    }

    private var headline: some View {
        HStack(spacing: 6) {
            Image(systemName: PullRequestStateAppearance.symbol)
                .font(.caption)
                .foregroundStyle(PullRequestStateAppearance.color(of: pullRequest.state))
                .help(pullRequest.state.czechLabel)
                .accessibilityLabel(pullRequest.state.czechLabel)
            Text(pullRequest.title)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: 8)
            if !row.spectrum.isEmpty {
                SpectrumBar(shares: row.spectrum)
            }
            ReviewStateBadge(state: reviewState, blocking: row.blocking)
            if showsPromptAction {
                promptButton
            }
        }
    }

    /// Má řádek vpravo `Prompt →`? **Pojmenované, ne `if` uvnitř `body`** — je to jediné, čím se
    /// vlastní řádek od cizího liší, a uvnitř `body` se to tvrdit nedá; tatáž úvaha jako
    /// u `FindingBadgeAppearance`. Ven z aplikace se tím nic neotevírá, je to jeden modul.
    var showsPromptAction: Bool { ownership == .mine }

    /// `Prompt →` u vlastního PR (#331) — plné akcentové tlačítko z návrhu (`.mini.pri`).
    ///
    /// **Zakázané, dokud prompt není z čeho složit** (#333). Nakreslené je proto, že to je jediná
    /// akce, kterou vlastní PR má, a řádek bez ní by se od cizího nelišil ničím; zakázané proto, že
    /// tlačítko, po kterém se nic nestane, je lež o tom, co okno umí — tatáž zásada jako u popisek
    /// zkratek. Nápověda říká, co bude, aby se z toho stavu nedalo usoudit, že je něco rozbité.
    ///
    /// **Odznak stavu review vedle něj zůstává**, ačkoli návrh na tom místě kreslí pilulku
    /// `6 k předání`. Ta věta se dá napsat, teprve až předání existuje (#333) a nese razítko
    /// (#334); do té doby by šlo o počet, který nikdo nepředal. Odznak zatím říká to, co se ví —
    /// že reviewer běžel a s jakým výsledkem —, a to je zrovna materiál, který prompt ponese.
    ///
    /// **Ztlumení kreslí řádek, ne styl.** `MiniButtonStyle` se na `isEnabled` neptá, takže zakázané
    /// malé tlačítko vypadá v celém okně jako klikatelné — a plné akcentové, po kterém se nic
    /// nestane, je zrovna ta lež, kvůli které je tady `disabled`. Opravit to v samotném stylu by
    /// přebarvilo i akce u nálezu a u vlákna, tedy věci mimo tohle issue; jak se ta oprava udělá, je
    /// otázka na návrh (mockup zakázané tlačítko nekreslí).
    private var promptButton: some View {
        Button("Prompt →") {}
            .buttonStyle(.miniPrimary)
            .disabled(true)
            .opacity(0.55)
            .help("Zadání pro agenta se bude skládat z nálezů a konverzace — okno to zatím neumí")
            .accessibilityLabel("Sestavit prompt pro agenta")
    }

    private var meta: some View {
        HStack(spacing: 4) {
            // `verbatim`, jinak `Text` interpoluje číslo přes locale a z PR #21663 udělá
            // „#21 663“ — číslo PR není množství.
            Text(verbatim: "\(pullRequest.repo) #\(pullRequest.number)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            // Draft je **slovo**, ne jen odstín ikony. Tvar ikony je u otevřeného
            // a rozpracovaného PR tentýž, takže by rozdíl nesla pouze barva — a ta sama
            // nestačí. V prvním řádku pro něj místo není, tady zbývá.
            if pullRequest.state == .draft {
                Text(verbatim: "·")
                Text("draft")
            }
            Text(verbatim: "·")
            Text(verbatim: pullRequest.author)
            Text(verbatim: "·")
            Text(pullRequest.updatedAt, format: .relative(presentation: .named))
            Spacer(minLength: 8)
            if hasDraft {
                // **Mint, ne akcent** (#309), a to ze dvou důvodů naráz. Je to **totéž sdělení**
                // jako `2 review` v souhrnu fronty, a jedna věc nesmí mít v okně dvě barvy.
                // A v tomhle řádku akcent už něco znamená: `ReviewStateBadge` jím kreslí `běží`,
                // takže akcentové pero vedle něj tvrdilo „něco se tu děje“ místo „něco tu leží“.
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(Palette.mint)
                    .help("Leží tu rozdělané review, které jsi ještě neodeslal")
                    .accessibilityLabel("Rozdělané review")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

}

#Preview {
    List {
        PullRequestRow(
            pullRequest: PullRequestSummary(
                id: PRIdentifier(repo: RepoID(owner: "keboola", name: "vault"), number: 85),
                title: "chore: modernize dependencies (Symfony 8-ready, PHPUnit 11)",
                author: "odinuv",
                url: URL(string: "https://github.com/keboola/vault/pull/85")!,
                updatedAt: Date().addingTimeInterval(-3600),
                state: .open
            ),
            reviewState: .completed(findings: 3),
            row: QueueRow(
                blocking: 1,
                spectrum: [
                    ReviewerShare(reviewer: "php-review", outcome: .blocking, weight: 2),
                    ReviewerShare(reviewer: "security-review", outcome: .findings, weight: 1),
                    ReviewerShare(reviewer: "docs", outcome: .clean, weight: 1),
                ]
            )
        )
        PullRequestRow(
            pullRequest: PullRequestSummary(
                id: PRIdentifier(repo: RepoID(owner: "ondrajodas", name: "PRism"), number: 171),
                title: "feat: události na časové ose konverzace",
                author: "ondrajodas",
                url: URL(string: "https://github.com/ondrajodas/PRism/pull/171")!,
                updatedAt: Date().addingTimeInterval(-300),
                state: .draft
            ),
            reviewState: .notStarted,
            hasDraft: true
        )
    }
    .frame(width: 420)
}
