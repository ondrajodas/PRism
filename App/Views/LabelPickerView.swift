import SwiftUI

/// Nabídka labelů, které **zná repozitář** (#392).
///
/// **Uzavřená množina, žádný volný text**, a to je celý smysl téhle obrazovky: z volného textu se
/// dá omylem vyrobit nový label, a ten už z repozitáře sám nezmizí. Hledací řádek na tom nic nemění
/// — **filtruje, nezakládá**: co se v nabídce nenajde, se nedá vybrat.
///
/// **Popover, ne `Menu`**, a je to rozhodnutí ze tří důvodů. Nabídka se musí **dotáhnout při
/// otevření** (labely repozitáře jsou volání `gh`, které se nemá platit při každém výběru řádku)
/// a `Menu` k tomu na macOS spolehlivý okamžik nedává; u labelu se kreslí **puntík s barvou
/// z repozitáře**, což v systémovém menu není kam dát; a od hledání je v ní **pole a obsluha
/// šipek**, kterou by `Menu` neuneslo vůbec.
///
/// Sloveso je v **nadpisu**, ne v položkách — položka je chip s barvou a jménem, tedy to, čím se
/// řádky od sebe liší. Odškrtnutí říká, které labely na PR leží.
struct LabelPickerView: View {
    let known: [PullRequestLabel]
    let selected: [PullRequestLabel]
    /// Dorazila už nabídka? `false` = ještě se načítá, takže se o repu nesmí nic tvrdit.
    var isLoaded = false
    /// Proč je nabídka prázdná. `nil` = načetla se — takže prázdno znamená „repo žádné labely
    /// nezná“, a to je jiná věta než porucha.
    var failure: String?
    let toggle: @MainActor (PullRequestLabel) -> Void
    let load: @MainActor () async -> Void

    @State private var query = ""
    @State private var selection = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // **Sloveso, ne kategorie.** `Labely repozitáře` bylo věcně správně, ale neříkalo, co
            // klik udělá — a klik je tady přepínač, takže se stejným řádkem label i sundá.
            PickerHeading(title: "Přepnout label")
            if known.count > Self.searchFrom {
                PickerSearchField(
                    query: $query,
                    count: filtered.count,
                    move: { step in
                        selection = Policy.pickerSelection(
                            from: selection,
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
                        ForEach(filtered, id: \.name) { label in
                            row(label)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.bottom, 7)
                }
                // Strop výšky, ne pružná: nabídka na repu se stovkou labelů by jinak přerostla
                // obrazovku. Šířka je z nejdelšího jména, takže se popover nekreslí na půl okna.
                .frame(maxWidth: 320)
                .frame(height: min(Double(filtered.count) * 24 + 7, 320))
            }
        }
        .task { await load() }
    }

    /// Od kolika labelů má hledání smysl — u pěti se přečtou rychleji, než se do pole klikne.
    private static let searchFrom = 6

    /// **Filtruje se podle jména, tedy podle toho, co je v řádku vidět.** Rozhoduje `Policy`.
    private var filtered: [PullRequestLabel] {
        Policy.filteredPicker(known, query: query, text: \.name)
    }

    private var selectedIndex: Int? {
        Policy.pickerSelection(from: selection, step: 0, count: filtered.count)
    }

    private func confirmSelection() {
        guard let selectedIndex else { return }
        toggle(filtered[selectedIndex])
    }

    /// Čtyři stavy, čtyři věty — a **filtr, který nic nenašel, není prázdná nabídka**. Prázdná
    /// plocha by vypadala jako spadlé načítání, což je stav, který tu existuje taky.
    private var emptyReason: String {
        if !query.isEmpty {
            "Žádný takový label tu není."
        } else if let failure {
            "Labely repozitáře se nepodařilo načíst. \(failure) Zavři nabídku a otevři ji znovu."
        } else if isLoaded {
            "Repozitář žádné labely nezná."
        } else {
            "Načítám labely repozitáře…"
        }
    }

    private func row(_ label: PullRequestLabel) -> some View {
        let isOn = selected.contains { $0.name == label.name }
        let isSelected = selectedIndex.map { filtered[$0].name == label.name } ?? false
        return Button {
            toggle(label)
        } label: {
            HStack(spacing: 7) {
                // Odškrtnutí místo zaškrtávátka: klik je **přepínač**, takže se stejným tlačítkem
                // label sundá. Bez značky by se nepoznalo, který na PR už je.
                //
                // **Neviditelná se dělá `opacity`, ne prázdným jménem symbolu.**
                // `Image(systemName: "")` vykreslí placeholder chybějícího symbolu a loguje —
                // a šířku sloupce drží `frame` tak jako tak (nález Copilota).
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .opacity(isOn ? 1 : 0)
                    .frame(width: 10)
                LabelChipView(label: label, maxWidth: nil)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 5).fill(Palette.accentWeak)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "sundat label \(label.name)" : "přidat label \(label.name)")
    }
}
