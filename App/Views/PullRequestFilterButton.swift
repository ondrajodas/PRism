import SwiftUI

/// Filtr seznamu PR v toolbaru (#117) — ikona s popoverem, ve kterém se odškrtávají repa a autoři.
///
/// **V toolbaru, ne jako `VStack` nad `Listem`.** Tím by `List` přestal být tím, co se odsazuje od
/// horní hrany, a řádky by zalezly pod lištu — tatáž past, kvůli které jde `PollStatusBanner` přes
/// `safeAreaInset` a hlášky pod seznamem mimo `NavigationSplitView`.
struct PullRequestFilterButton: View {
    let options: PullRequestFilterOptions
    let filter: PullRequestFilter
    /// Kolik PR je právě schovaných — píše se k ikoně, aby byl filtr vidět bez otevírání nabídky.
    let hidden: Int
    let apply: (PullRequestFilter) -> Void

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            // **Zapnutý filtr musí být vidět bez otevírání nabídky**: skrytý filtr je způsob, jak
            // přijít o review. Proto plná ikona s počtem schovaných, ne jen obrys.
            Label {
                if hidden > 0 {
                    Text(verbatim: String(hidden)).monospacedDigit()
                }
            } icon: {
                Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .foregroundStyle(filter.isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .help(help)
        // Popisek ručně: v toolbaru je vidět jen ikona a titulek `Label`u je prázdný, dokud filtr
        // nic neschovává — accessibility by z tlačítka udělala bezejmenné „tlačítko“ vedle
        // pojmenovaných (`Obnovit`, `Nastavení`). Zjištěno accessibility výpisem běžící aplikace.
        .accessibilityLabel("Filtr seznamu")
        .accessibilityValue(filter.isActive ? help : "vypnutý")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { popover }
    }

    private var help: String {
        guard filter.isActive else { return "Zúžit seznam na vybraná repa a autory" }
        return "Filtr je zapnutý a schovává \(Plural.czech(hidden, one: "pull request", few: "pull requesty", many: "pull requestů"))"
    }

    // MARK: - Popover

    private var popover: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if options.isEmpty {
                // **Věta musí sednout na oba stavy**, protože prázdná nabídka znamená obojí: seznam
                // ještě nedorazil, nebo dorazil prázdný. „Až dorazí seznam PR“ by u načteného
                // prázdného seznamu tvrdilo, že se ještě čeká — nález Copilota na #170.
                Text("Není z čeho vybírat — v seznamu nejsou žádné PR.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        axis("Repozitáře", values: options.repositories.map(\.description), selected: Set(filter.repositories.map(\.description))) { name, on in
                            toggleRepository(named: name, on: on)
                        }
                        if !options.authors.isEmpty {
                            axis("Autoři", values: options.authors, selected: filter.authors) { author, on in
                                toggleAuthor(author, on: on)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 280)
        // Výška podle obsahu, ale se stropem: u dvaceti rep by popover přerostl obrazovku.
        .frame(maxHeight: 420)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Filtr").font(.callout.weight(.semibold))
            Spacer(minLength: 0)
            // **Pojistka proti zapomenutému filtru.** Zakázané tlačítko, ne schované: mizející
            // tlačítko vypadá jako jiná nabídka, kdežto zakázané řekne, že filtr prostě není.
            Button("Vymazat filtr") { apply(PullRequestFilter()) }
                .disabled(!filter.isActive)
                .font(.callout)
        }
        .padding(12)
    }

    /// Jedna osa filtru jako seznam přepínačů.
    ///
    /// `Toggle` s vlastním bindingem, ne `Picker`: vybírá se **víc hodnot** („ukaž mi dvě repa, na
    /// kterých teď pracuju“ je běžnější než jedno) a `Picker` s `.multiple` na macOS není.
    /// `selected` je **`Set`**, ne pole: `contains` se volá pro každý řádek nabídky, takže nad polem
    /// je to lineární v počtu vybraných hodnot × počet řádků. Nález Copilota na #170; u pěti rep to
    /// nikdo nepozná, ale pole tady bylo jen proto, že se `RepoID`y mapovaly na jména.
    private func axis(
        _ title: String,
        values: [String],
        selected: Set<String>,
        toggle: @escaping (String, Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(values, id: \.self) { value in
                Toggle(isOn: Binding(
                    get: { selected.contains(value) },
                    set: { toggle(value, $0) }
                )) {
                    Text(verbatim: value)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    // MARK: - Změny

    /// Repo se hledá **podle jména z nabídky**, ne skládáním `RepoID` z textu: nabídka vznikla
    /// z `RepoID`ů, takže se to musí vrátit k témuž typu bez druhého parsování.
    private func toggleRepository(named name: String, on: Bool) {
        guard let repo = options.repositories.first(where: { $0.description == name }) else { return }
        var updated = filter
        if on { updated.repositories.insert(repo) } else { updated.repositories.remove(repo) }
        apply(updated)
    }

    private func toggleAuthor(_ author: String, on: Bool) {
        var updated = filter
        if on { updated.authors.insert(author) } else { updated.authors.remove(author) }
        apply(updated)
    }
}
