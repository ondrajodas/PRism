import SwiftUI

/// Nabídka labelů, které **zná repozitář** (#392).
///
/// **Uzavřená množina, žádný volný text**, a to je celý smysl téhle obrazovky: z volného textu se
/// dá omylem vyrobit nový label, a ten už z repozitáře sám nezmizí. V nabídce proto není pole
/// k psaní — jen seznam toho, co v repu je, s odškrtnutím u těch, které na PR leží.
///
/// **Popover, ne `Menu`**, a je to rozhodnutí ze dvou důvodů. Nabídka se musí **dotáhnout při
/// otevření** (labely repozitáře jsou volání `gh`, které se nemá platit při každém výběru řádku)
/// a `Menu` k tomu na macOS spolehlivý okamžik nedává. A druhý: u labelu se kreslí **puntík
/// s barvou z repozitáře**, což v systémovém menu není kam dát.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Labely repozitáře")
                .font(.system(size: 10, design: .monospaced))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Palette.ink3)
                .padding(.horizontal, 11)
                .padding(.top, 9)
                .padding(.bottom, 6)
            if known.isEmpty {
                // **Dvě různé věty, protože jsou to dva různé stavy.** „Repo žádné labely nezná“ je
                // odpověď, kdežto porucha je porucha — a nabídka, která po výpadku sítě vypadá jako
                // repo bez labelů, posílá člověka hledat labely, které tam jsou. Nic se přitom nedá
                // pokazit: z prázdné nabídky nejde vyrobit label.
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
                        ForEach(known, id: \.name) { label in
                            row(label)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.bottom, 7)
                }
                // Strop výšky, ne pružná: nabídka na repu se stovkou labelů by jinak přerostla
                // obrazovku. Šířka je z nejdelšího jména, takže se popover nekreslí na půl okna.
                .frame(maxWidth: 320)
                .frame(height: min(Double(known.count) * 24 + 7, 320))
            }
        }
        .task { await load() }
    }

    /// Tři různé věty, protože jsou to tři různé stavy — a ten prostřední („ještě nevíme“) nesmí
    /// splynout ani s prázdnem, ani s poruchou.
    private var emptyReason: String {
        if let failure {
            "Labely repozitáře se nepodařilo načíst. \(failure) Zavři nabídku a otevři ji znovu."
        } else if isLoaded {
            "Repozitář žádné labely nezná."
        } else {
            "Načítám labely repozitáře…"
        }
    }

    private func row(_ label: PullRequestLabel) -> some View {
        let isOn = selected.contains { $0.name == label.name }
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
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "sundat label \(label.name)" : "přidat label \(label.name)")
    }
}
