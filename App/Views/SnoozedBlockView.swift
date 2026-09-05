import SwiftUI

/// Blok `Odložené · 2` pod frontou (#512).
///
/// **Existuje proto, aby se odložení dalo poznat.** Fronta, ze které PR potichu zmizí, je horší
/// než fronta, ve které leží: práci, o které nikdo neví, nejde ani udělat, ani odmítnout. Blok je
/// proto to druhé oko odložení — schová se v seznamu, ukáže se tady.
///
/// **Tichý.** Ztlumené písmo, žádné odznaky stavu review, žádná mapa PR: je to seznam toho, co
/// jsem si odsunul, ne druhá fronta. Kdyby vypadal jako fronta, nemělo by odložení smysl.
///
/// **Kreslí se jedině, když je co ukázat** (`Policy.snoozedBlockTitle(count:)` vrací `nil` na
/// nule) — prázdný rámeček s nulou je pět šestin obrazovky za odpověď, o kterou se nikdo neptal
/// (tatáž úvaha jako u prázdných pruhů desky, #515).
struct SnoozedBlockView: View {
    /// Odložené PR, v pořadí seznamu.
    let pullRequests: [PullRequestSummary]
    /// `vrátí se zítra 9:00` u řádku — skládá `Policy.snoozeNote(_:now:)`. `nil` = nekreslí se nic
    /// (nemá nastat; znamenalo by to řádek v bloku bez odložení).
    let note: (PRIdentifier) -> String?
    /// Otevře PR. Odložený pull request se pořád dá přečíst — odložení je o frontě, ne o zámku.
    let open: (PRIdentifier) -> Void
    /// `Vrátit teď`.
    let wake: (PRIdentifier) -> Void

    /// Který řádek je pod kurzorem. `Vrátit teď` se kreslí jen u něj, ze stejného důvodu jako
    /// tlačítko `Odložit` v řádku fronty: blok má být tichý.
    @State private var hovered: PRIdentifier?

    var body: some View {
        if let title = Policy.snoozedBlockTitle(count: pullRequests.count) {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                header(title)
                // **Pevný `VStack`, ne `LazyVStack`** (#469): odložených je hrstka, a i kdyby
                // nebyla, neomezenost seznamu není důvod ten vzor snést.
                VStack(spacing: 0) {
                    ForEach(pullRequests, id: \.id) { row($0) }
                }
            }
            // `--panel-3` z mockupu (sekce 53), tedy `Palette.raised` — vyvýšená plocha, na které
            // v okně leží tiché chipy. Blok tím sedí **na** seznamu, ne v něm.
            .background(Palette.raised)
        }
    }

    private func header(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func row(_ pullRequest: PullRequestSummary) -> some View {
        Button { open(pullRequest.id) } label: {
            HStack(spacing: 8) {
                Text(pullRequest.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if hovered == pullRequest.id {
                    // **Tlačítko, ne odkaz s ikonou**: je to jediná akce bloku a musí být
                    // pojmenovaná. Vlastní `Button` uvnitř řádku — klik na něj nesmí PR otevřít.
                    Button("Vrátit teď") { wake(pullRequest.id) }
                        .buttonStyle(MiniButtonStyle(emphasis: .secondary))
                } else {
                    Text(verbatim: note(pullRequest.id) ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Zápis jen na změnu, jako v `PullRequestTabBar` a v patce pruhu desky: odchod z řádku
        // nesmí přepsat hover, který si mezitím vzal jiný.
        .onHover { hovered = $0 ? pullRequest.id : (hovered == pullRequest.id ? nil : hovered) }
    }
}
