import SwiftUI

/// Nabídka lidí **a týmů**, od kterých jde vyžádat review (#392).
///
/// **Jedno pojmenované kliknutí, ne `+` vedle avatara.** Reviewer request pošle člověku upozornění
/// a odebráním se **nedá vzít zpět**, takže na tlačítku musí být napsané, co se stane a komu —
/// potvrzení je v textu tlačítka, ne v druhém okně. Sheet by z toho udělal klikačku a nic by
/// nepřidal: payload je jedno jméno, které je na tlačítku vidět celé.
///
/// Množina je **uzavřená** (`assignableUsers`), takže z nabídky nejde vyžádat někdo, komu to GitHub
/// odmítne.
struct ReviewerPickerView: View {
    let candidates: [ReviewerCandidate]
    /// Dorazila už nabídka? `false` = ještě se načítá, takže se o repu nesmí nic tvrdit.
    var isLoaded = false
    /// Proč je nabídka prázdná. `nil` = načetla se, takže prázdno znamená „všichni už jsou
    /// vyžádaní“ — a to je jiná věta než porucha.
    var failure: String?
    let request: @MainActor (ReviewerCandidate) -> Void
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
                        ForEach(candidates, id: \.self) { candidate in
                            row(candidate)
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

    /// Co je na tlačítku — **druh i jméno**.
    private static func title(of candidate: ReviewerCandidate) -> String {
        switch candidate {
        case .person(let login): "Vyžádat review od \(login)"
        case .team(let slug): "Vyžádat review od týmu \(slug)"
        }
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

    private func row(_ candidate: ReviewerCandidate) -> some View {
        Button {
            request(candidate)
        } label: {
            HStack(spacing: 7) {
                // Tvar rozlišuje druh: kolečko s iniciálou je osoba, čtverec se skupinovou ikonou
                // tým — tatáž úmluva jako v panelu.
                switch candidate {
                case .person(let login):
                    ReviewerAvatarView(login: login, answer: .waiting)
                case .team:
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Palette.ink3)
                        .frame(width: 16, height: 16)
                        .background(Palette.raised, in: .rect(cornerRadius: 4))
                        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line) }
                }
                // **Celá věta, ne jen login.** Z „Vyžádat review od odinuv“ je vidět, co klik udělá;
                // samotné jméno v seznamu by se dalo přečíst i jako „tenhle už review dělá“. U týmu
                // je v ní slovo `týmu`, protože upozornění odejde **všem jeho členům** — a to je
                // rozdíl, který má být vidět dřív, než se klikne.
                Text(Self.title(of: candidate))
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
