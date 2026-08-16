import SwiftUI

/// Záložka „Repozitáře“ — režim a override skillů a kategorií pro jedno repo.
struct RepositorySettingsView: View {
    @Bindable var settings: SettingsModel
    let repositories: [RepoID]
    @State private var selection: RepoID?

    var body: some View {
        HStack(spacing: 0) {
            // Široký sloupec schválně: `keboola/sandboxes-notebook-utils` je běžné jméno
            // a uříznuté `…andboxes-notebook-utils` se od sousedního repa nepozná.
            list
                .frame(width: 290)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Bez výběru je pravá půlka prázdná hned po otevření záložky, což vypadá jako
        // chyba. První repo je odpověď na „ukaž mi něco“, ne rozhodnutí za uživatele.
        //
        // `id:` je podstatné: okno se dá otevřít dřív, než dorazí první polling. Bez něj
        // by seznam vlevo naskočil, ale vpravo by zůstalo „Vyber repozitář“, dokud si
        // uživatel neklikne.
        .task(id: repositories) { selection = selection ?? repositories.first }
    }

    @ViewBuilder private var list: some View {
        if repositories.isEmpty {
            EmptyStateView(
                nature: .calm,
                symbol: "folder",
                title: "Žádné repozitáře",
                message: "Objeví se tu, jakmile dorazí první PR."
            )
        } else {
            List(repositories, id: \.self, selection: $selection) { repo in
                row(repo)
            }
        }
    }

    private func row(_ repo: RepoID) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: repo.description)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)
            if settings.draft.resolved(for: repo).mode == .automatic {
                Text("auto")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.tint.opacity(0.18), in: .capsule)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let repo = selection, repositories.contains(repo) {
            RepositoryDetailView(settings: settings, repo: repo)
        } else {
            EmptyStateView(
                nature: .waiting,
                symbol: "sidebar.left",
                title: "Vyber repozitář",
                message: "Vlevo jsou repa z posledního seznamu PR i z konfigurace."
            )
        }
    }
}

/// Nastavení jednoho repa.
private struct RepositoryDetailView: View {
    @Bindable var settings: SettingsModel
    let repo: RepoID

    var body: some View {
        Form {
            Section {
                // `nil` je vlastní volba, ne prázdno: „ber globální“ se musí dát vybrat
                // zpátky, jinak by se repo po jednom kliknutí navždycky odpojilo od
                // globálního defaultu.
                Picker("Režim", selection: config.mode) {
                    Text("Podle globálního nastavení (\(modeName(settings.draft.global.mode)))")
                        .tag(ReviewMode?.none)
                    Text("Manuální").tag(ReviewMode?.some(.manual))
                    Text("Automatický").tag(ReviewMode?.some(.automatic))
                }
                .pickerStyle(.radioGroup)

                // Tříhodnotový jako režim, a ze stejného důvodu: „ber globální“ se musí dát
                // vybrat zpátky. `false` u repa navíc není totéž jako `nil` — po přepnutí
                // globálního defaultu na povoleno si ho repo podrží.
                Picker("Odesílání na GitHub", selection: config.allowsPublishing) {
                    Text("Podle globálního nastavení (\(publishingName(settings.draft.global.allowsPublishing)))")
                        .tag(Bool?.none)
                    Text("Povoleno").tag(Bool?.some(true))
                    Text("Zakázáno").tag(Bool?.some(false))
                }
                .pickerStyle(.radioGroup)

                // `nil` je i tady vlastní volba, ne prázdno — ze stejného důvodu jako
                // u režimu.
                Picker("Jazyk nálezů", selection: config.findingsLanguage) {
                    Text("Podle globálního nastavení (\(settings.draft.global.findingsLanguage.displayName.lowercased()))")
                        .tag(FindingsLanguage?.none)
                    ForEach(FindingsLanguage.allCases, id: \.self) { language in
                        Text(verbatim: language.displayName).tag(FindingsLanguage?.some(language))
                    }
                }
            } header: {
                Text(verbatim: repo.description)
                    .font(.headline)
            } footer: {
                Text("Manuální čeká na tlačítko. Automatický spustí review, jakmile se PR objeví v seznamu. Odesílání rozhoduje jen o tom, jestli se review dá odeslat; když je zakázané, tlačítko `Odeslat review…` zůstane zakázané a řekne proč. Potvrdit odeslání musí vždycky člověk. Jazyk se projeví na dalším běhu; už uložené nálezy zůstanou, jak jsou.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            override(
                title: "Skilly",
                items: config.skills,
                fallback: settings.draft.global.skills,
                itemLabel: "Skill",
                placeholder: "code-review:code-review",
                addLabel: "Přidat skill",
                emptyMeaning: "Prázdný seznam znamená, že se tady nereviewuje nic."
            )

            override(
                title: "Blokující kategorie",
                items: config.blockingCategories,
                fallback: settings.draft.global.blockingCategories,
                itemLabel: "Kategorie",
                placeholder: "correctness",
                addLabel: "Přidat kategorii",
                emptyMeaning: "Prázdný seznam znamená, že tady nic neblokuje."
            )

            timeoutOverride
        }
        .formStyle(.grouped)
    }

    /// Vlastní časový limit běhu (#320).
    ///
    /// Přepínač a číslo, ne tříhodnotový picker jako u režimu: hodnot je 56 a „ber globální“ je
    /// mezi nimi jen jedna z odpovědí. Zapnutí začíná od globální hodnoty ze stejného důvodu jako
    /// u sad — nejčastější důvod pro override je posunout ji, ne psát od nuly.
    private var timeoutOverride: some View {
        Section {
            Toggle("Vlastní limit", isOn: isOverridden)
            if config.reviewTimeoutMinutes.wrappedValue != nil {
                ReviewTimeoutField(label: "Časový limit běhu (min)", minutes: unwrappedTimeout)
            }
        } header: {
            Text("Časový limit běhu")
        } footer: {
            if config.reviewTimeoutMinutes.wrappedValue == nil {
                Text("Bere globální: \(settings.draft.global.reviewTimeoutMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Platí na jednu session — na každý skill zvlášť a stejně tak na kontrolu nálezů. Projeví se na dalším běhu; ten, který právě běží, doběhne s limitem, se kterým začal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isOverridden: Binding<Bool> {
        Binding(
            get: { config.reviewTimeoutMinutes.wrappedValue != nil },
            set: { on in
                config.reviewTimeoutMinutes.wrappedValue = on
                    ? settings.draft.global.reviewTimeoutMinutes
                    : nil
            }
        )
    }

    /// Odvozený `Binding` bez `nil`, se stejnou pojistkou jako u sad: doběhlá editace už
    /// zrušeného override ho nesmí vzkřísit.
    private var unwrappedTimeout: Binding<Int> {
        Binding(
            get: { config.reviewTimeoutMinutes.wrappedValue ?? settings.draft.global.reviewTimeoutMinutes },
            set: { newValue in
                guard config.reviewTimeoutMinutes.wrappedValue != nil else { return }
                config.reviewTimeoutMinutes.wrappedValue = newValue
            }
        )
    }

    /// Sekce s vlastní sadou, nebo jen výpis té globální.
    ///
    /// Vypnutý přepínač je `nil` („ber globální“), zapnutý prázdný seznam je vlastní
    /// odpověď („tady nic“) — a to jsou dvě různé věci, které se musí dát rozeznat i na
    /// obrazovce, nejen v souboru.
    @ViewBuilder private func override(
        title: LocalizedStringKey,
        items: Binding<[String]?>,
        fallback: [String],
        itemLabel: LocalizedStringKey,
        placeholder: String,
        addLabel: String,
        emptyMeaning: LocalizedStringKey
    ) -> some View {
        Section {
            Toggle("Vlastní sada", isOn: isOverridden(items, fallback: fallback))
            if items.wrappedValue != nil {
                StringListEditor(
                    items: unwrapped(items),
                    itemLabel: itemLabel,
                    placeholder: placeholder,
                    addLabel: addLabel
                )
            }
        } header: {
            Text(title)
        } footer: {
            if items.wrappedValue == nil {
                Text("Bere globální: \(describe(fallback))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if items.wrappedValue?.isEmpty == true {
                Text(emptyMeaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func describe(_ items: [String]) -> String {
        items.isEmpty ? "nic" : items.joined(separator: ", ")
    }

    private func publishingName(_ allowed: Bool) -> String {
        allowed ? "povoleno" : "zakázáno"
    }

    private func modeName(_ mode: ReviewMode) -> String {
        switch mode {
        case .manual: "manuální"
        case .automatic: "automatický"
        }
    }

    /// Odvozený `Binding` bez `nil`.
    ///
    /// **Nesmí to být `Binding(items)`**: ten force-unwrapuje při každém čtení a editor
    /// nad ním jeden cyklus přežije i vypnutí přepínače — takže `nil` spadne rovnou
    /// v `BindingOperations.ForceUnwrapping`. Ověřeno pádem aplikace při vypnutí vlastní
    /// sady skillů. Zápis se stejnou pojistkou zahazuje: doběhlá editace už zrušeného
    /// override by ho jinak vzkřísila.
    private func unwrapped(_ items: Binding<[String]?>) -> Binding<[String]> {
        Binding(
            get: { items.wrappedValue ?? [] },
            set: { newValue in
                guard items.wrappedValue != nil else { return }
                items.wrappedValue = newValue
            }
        )
    }

    /// Zapnutí začíná od globální sady — nejčastější důvod pro override je jednu položku
    /// ubrat, ne psát seznam od nuly.
    private func isOverridden(_ items: Binding<[String]?>, fallback: [String]) -> Binding<Bool> {
        Binding(
            get: { items.wrappedValue != nil },
            set: { items.wrappedValue = $0 ? fallback : nil }
        )
    }

    /// Repo bez záznamu v konfiguraci se chová jako `RepositoryConfig()`, takže se dá
    /// editovat rovnou. Prázdný záznam za sebou nenechává — o to se stará
    /// `Configuration.setRepository(_:for:)`.
    private var config: Binding<RepositoryConfig> {
        Binding(
            get: { settings.draft.repositories[repo] ?? RepositoryConfig() },
            set: { settings.draft.setRepository($0, for: repo) }
        )
    }
}
