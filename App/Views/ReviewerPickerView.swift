import SwiftUI

/// Nabídka lidí **a týmů**, od kterých jde vyžádat review (#392).
///
/// **Sloveso je v nadpisu, ne v každé položce** — přepsané po proklikání. Do té doby stálo na
/// každém řádku `Vyžádat review od …`, takže čtrnáct řádků opakovalo totéž a předpona ořezala to
/// jediné, čím se od sebe liší: jméno. Nadpis `Vyžádat review od` a pod ním samá jména se čte jako
/// jedna věta a zůstane z ní to podstatné. Pojmenované kliknutí se tím **neztrácí** — jen se říká
/// jednou.
///
/// Request pošle upozornění a odebráním se **nedá vzít zpět**, takže je z nadpisu vidět, co klik
/// udělá, dřív než se klikne. U týmu je to o to důležitější: upozornění odejde všem jeho členům,
/// a proto u něj stojí `tým`.
///
/// Množina je **uzavřená** (`assignableUsers` a `orgs/{org}/teams`), takže z nabídky nejde vyžádat
/// někdo, komu to GitHub odmítne.
struct ReviewerPickerView: View {
    let candidates: [ReviewerCandidate]
    /// Dorazila už nabídka? `false` = ještě se načítá, takže se o repu nesmí nic tvrdit.
    var isLoaded = false
    /// Proč je nabídka prázdná. `nil` = načetla se, takže prázdno znamená „všichni už jsou
    /// vyžádaní“ — a to je jiná věta než porucha.
    var failure: String?
    let request: @MainActor (ReviewerCandidate) -> Void
    let load: @MainActor () async -> Void

    @State private var query = ""
    /// Který řádek je vybraný klávesnicí. Ořezává se při každém překreslení podle počtu řádků —
    /// filtr se mění pod rukama, takže index z předchozího dotazu může být za koncem.
    @State private var selected = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PickerHeading(title: "Vyžádat review od")
            // **Hledání jedině nad seznamem, který má co filtrovat.** Nad prázdnem by to bylo pole,
            // ve kterém se nedá nic najít, a nad třemi jmény šum.
            if candidates.count > Self.searchFrom {
                PickerSearchField(
                    query: $query,
                    count: filtered.count,
                    move: { step in
                        selected = Policy.pickerSelection(
                            from: selected,
                            step: step,
                            count: filtered.count
                        ) ?? 0
                    },
                    confirm: confirmSelection
                )
            }
            if filtered.isEmpty {
                Text(verbatim: emptyReason)
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .padding(.horizontal, 11)
                    .padding(.bottom, 10)
                    .frame(maxWidth: 240, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(filtered, id: \.self) { candidate in
                            row(candidate)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.bottom, 7)
                }
                .frame(maxWidth: 320)
                .frame(height: min(Double(filtered.count) * 26 + 7, 320))
            }
        }
        .task { await load() }
    }

    /// Od kolika položek má hledání smysl. Tři jména se přečtou rychleji, než se do pole klikne.
    private static let searchFrom = 6

    /// Nabídka po filtru — rozhoduje `Policy`, ne tohle view.
    ///
    /// **Filtruje se podle toho, co je v řádku vidět**: u člověka login, u týmu slug. Kdyby filtr
    /// sedl na něco, co v řádku není, vypadal by výsledek jako chyba.
    private var filtered: [ReviewerCandidate] {
        Policy.filteredPicker(candidates, query: query) { $0.name }
    }

    /// Vybraný řádek, ořezaný na to, co po filtru zbylo.
    private var selectedIndex: Int? {
        Policy.pickerSelection(from: selected, step: 0, count: filtered.count)
    }

    private func confirmSelection() {
        guard let selectedIndex else { return }
        request(filtered[selectedIndex])
    }

    /// Tři různé věty, tři různé stavy — a od hledání čtvrtá: **filtr, který nic nenašel**, není
    /// prázdná nabídka. Prázdná plocha by u nabídky vypadala jako spadlé načítání, což je stav,
    /// který tu existuje taky.
    private var emptyReason: String {
        if !query.isEmpty {
            "Nikdo takový tu není."
        } else if let failure {
            // **„Lidí a týmů“**, ne jen lidí: nabídka nese obojí a věta, která jmenuje jen půlku,
            // si odporuje s nadpisem i s hláškou o načítání (nález Copilota).
            "Seznam lidí a týmů se nepodařilo načíst. \(failure) Zavři nabídku a otevři ji znovu."
        } else if isLoaded {
            "Vyžádat už není od koho — všichni ze seznamu na PR čekají."
        } else {
            "Načítám lidi a týmy, které na repozitář smí…"
        }
    }

    private func row(_ candidate: ReviewerCandidate) -> some View {
        let isSelected = selectedIndex.map { filtered[$0] == candidate } ?? false
        return Button {
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
                Text(verbatim: candidate.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                // **`tým` zůstává u položky**, i když sloveso z ní odešlo: druh není opakování,
                // je to ta informace, kvůli které se u týmu rozmýšlí (upozornění odejde všem).
                if case .team = candidate {
                    Text("tým")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.ink3)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 5).fill(Palette.accentWeak)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilityLabel(of: candidate))
    }

    /// Pro čtečku zůstává celá věta: nadpis se k položce nepřečte, takže by z „ajda-swimlane“
    /// nebylo poznat, co se stane.
    private static func accessibilityLabel(of candidate: ReviewerCandidate) -> String {
        switch candidate {
        case .person(let login): "vyžádat review od \(login)"
        case .team(let slug): "vyžádat review od týmu \(slug)"
        }
    }
}
