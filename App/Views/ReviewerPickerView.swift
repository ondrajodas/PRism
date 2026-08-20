import SwiftUI

/// Nabídka lidí, od kterých jde vyžádat review (#392).
///
/// **Jedno pojmenované kliknutí, ne `+` vedle avatara.** Reviewer request pošle člověku upozornění
/// a odebráním se **nedá vzít zpět**, takže na tlačítku musí být napsané, co se stane a komu —
/// potvrzení je v textu tlačítka, ne v druhém okně. Sheet by z toho udělal klikačku a nic by
/// nepřidal: payload je jedno jméno, které je na tlačítku vidět celé.
///
/// Množina je **uzavřená** (`assignableUsers`), takže z nabídky nejde vyžádat někdo, komu to GitHub
/// odmítne.
struct ReviewerPickerView: View {
    let candidates: [String]
    /// Dorazila už nabídka? `false` = ještě se načítá, takže se o repu nesmí nic tvrdit.
    var isLoaded = false
    /// Proč je nabídka prázdná. `nil` = načetla se, takže prázdno znamená „všichni už jsou
    /// vyžádaní“ — a to je jiná věta než porucha.
    var failure: String?
    let request: @MainActor (String) -> Void
    let load: @MainActor () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Kdo na repozitář smí")
                .font(.system(size: 10, design: .monospaced))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Palette.ink3)
                .padding(.horizontal, 11)
                .padding(.top, 9)
                .padding(.bottom, 6)
            if candidates.isEmpty {
                // Tatáž úvaha jako u labelů: „všichni už jsou vyžádaní“ je odpověď, porucha je
                // porucha, a slít se to nesmí.
                Text(emptyReason)
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .padding(.horizontal, 11)
                    .padding(.bottom, 10)
                    .frame(maxWidth: 240, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(candidates, id: \.self) { login in
                            row(login)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.bottom, 7)
                }
                .frame(maxWidth: 320)
                .frame(height: min(Double(candidates.count) * 26 + 7, 320))
            }
        }
        .task { await load() }
    }

    /// Tři různé věty, tři různé stavy — viz `LabelPickerView`.
    private var emptyReason: String {
        if let failure {
            "Seznam lidí se nepodařilo načíst. \(failure) Zavři nabídku a otevři ji znovu."
        } else if isLoaded {
            "Vyžádat už není od koho — všichni ze seznamu na PR čekají."
        } else {
            "Načítám lidi, kteří na repozitář smí…"
        }
    }

    private func row(_ login: String) -> some View {
        Button {
            request(login)
        } label: {
            HStack(spacing: 7) {
                ReviewerAvatarView(login: login, answer: .waiting)
                // **Celá věta, ne jen login.** Z „Vyžádat review od odinuv“ je vidět, co klik udělá;
                // samotné jméno v seznamu by se dalo přečíst i jako „tenhle už review dělá“.
                Text("Vyžádat review od \(login)")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
