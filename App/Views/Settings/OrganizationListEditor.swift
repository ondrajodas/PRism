import SwiftUI

/// Sekce `Organizace k prohledávání` na stránce `Zdroje PR` (#532).
///
/// **Řádky s polem, ne chipy** — a je to vědomá odchylka od zákresu. Mockup kreslí chipy
/// (`.tagchip`) i o řádek výš u `Moje loginy`, kde je aplikace od #389 sází jako obyčejný seznam
/// polí (`StringListEditor`), protože okno nastavení je nativní `Form`. Druhá vizuální podoba pro
/// tutéž věc na téže stránce by znamenala, že se dva sousední řádky ovládají jinak.
///
/// Co proti `StringListEditor`u přibylo, a proč vlastní typ: **pod řádkem je věta, když se výpis
/// nepodařilo dotáhnout**, a **pod seznamem souhrn s tlačítkem `Obnovit`**. Ta věta je jediné, co je
/// na řádku: organizace, na kterou účet nevidí, se od organizace bez repozitářů jinak nepozná
/// (obojí je prázdný seznam), kdežto počty a stáří říká souhrn. **Řádek stav nemá schválně** — z
/// renderu vyšlo, že `zatím nenačteno` na řádku nad souhrnem `Zatím nenačteno` je tatáž věta dvakrát
/// pod sebou.
struct OrganizationListEditor: View {
    @Binding var organizations: [String]
    let catalog: RepositoryCatalog
    /// Kdy se má dotáhnout, co v cache chybí nebo je starší než den. Volá to dopsání řádku,
    /// **ne úhoz** — dotažení je nad velkou organizací věc desítek sekund.
    let refreshStale: () -> Void
    let refreshAll: () -> Void
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(organizations.indices, id: \.self) { index in
                row(at: index)
            }
            Button("Přidat organizaci", systemImage: "plus.circle") { organizations.append("") }
                .controlSize(.small)
            catalogStatus
        }
    }

    private func row(at index: Int) -> some View {
        let organization = index < organizations.count ? organizations[index] : ""
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                // Nápověda patří do `prompt:` — první argument by se ve `Form`u vykreslil jako
                // popisek vlevo od pole. Tatáž past jako u `StringListEditor`.
                TextField("Organizace", text: binding(at: index), prompt: Text(verbatim: "keboola"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    // **Dotahuje se až po dopsání**, ne při psaní. Fetch navěšený na změnu textu
                    // by na `keboola` znamenal sedm dotazů po desítkách sekund, jeden na písmeno.
                    .onSubmit(refreshStale)
                Button {
                    // Tatáž ochrana jako v `binding(at:)` a ze stejného důvodu: identita řádku je
                    // index, takže mezi dvěma kliknutími může být pole už kratší.
                    guard index < organizations.count else { return }
                    organizations.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Odebrat")
            }
            if let failure = catalog.failure(for: organization) {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Palette.find)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Souhrn nad celým katalogem a tlačítko `Obnovit` — pravá strana řádku ze zákresu.
    ///
    /// **Kreslí se, jen když nějaká organizace je.** Prázdná sekce nemá co obnovovat a tlačítko,
    /// které nikdy nic neudělá, je horší než žádné.
    @ViewBuilder private var catalogStatus: some View {
        let status = Policy.repositoryCatalogStatus(
            // Ne `organizations` rovnou: `Policy.searchOrganizations` ověřuje jména a zahazuje
            // duplicity, takže souhrn nevznikne z rozepsaného řádku ani z téže organizace dvakrát.
            organizations: Policy.searchOrganizations(organizations),
            snapshots: catalog.snapshots,
            refreshing: catalog.refreshing
        )
        if let summary = Policy.repositoryCatalogSummary(status, now: now) {
            HStack(spacing: 8) {
                Text(verbatim: summary)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button("Obnovit", action: refreshAll)
                    .controlSize(.small)
                    // Druhý klik uprostřed dotažení by ten první nezrychlil — je to tatáž úvaha
                    // jako u `Policy.refreshControl` v hlavičce okna.
                    .disabled(catalog.isRefreshing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Index je identita řádku, takže mezi odebráním a překreslením existuje okamžik, kdy
    /// `ForEach` sahá na řádek, který v poli už není. Tatáž ochrana jako v `StringListEditor`u.
    private func binding(at index: Int) -> Binding<String> {
        Binding(
            get: { index < organizations.count ? organizations[index] : "" },
            set: { newValue in
                guard index < organizations.count else { return }
                organizations[index] = newValue
            }
        )
    }
}
