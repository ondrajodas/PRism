import SwiftUI

/// Záložka „Repozitáře“ — režim a override skillů a kategorií pro jedno repo.
struct RepositorySettingsView: View {
    @Bindable var settings: SettingsModel
    let repositories: [RepoID]
    /// Co repozitář o mergi říká (#556). `nil` = ještě se to nezjistilo, takže se nepovolená
    /// metoda **nezašedne** a nabídnou se všechny tři — „nevím“ se chová jako „ano“.
    ///
    /// **Uzávěr, ne `AppStore`.** Stránka `Repozitáře` dostává i seznam rep zvlášť, ze stejného
    /// důvodu: views se musí dát složit bez storu (offscreen render, náhled).
    var mergeSettings: (RepoID) -> RepositoryMergeSettings? = { _ in nil }
    /// Dotáhne příznaky pro vybrané repo. **Na výběr repa, ne na tik** — je to výslovné gesto
    /// člověka a jedno volání za repo, které se drží v cache (0,62 s).
    var loadMergeSettings: (RepoID) async -> Void = { _ in }
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
        // **Až po výběru, a jen pro to jedno repo** (#556): výpis rep má desítky řádků a dotáhnout
        // příznaky pro všechna by bylo desítky volání za obrazovku, na které je vidět jedno.
        // Volání samo má stráž na cache, takže překliknutí sem a zpátky nestojí nic.
        .task(id: selection) {
            guard let repo = selection else { return }
            await loadMergeSettings(repo)
        }
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
            RepositoryDetailView(settings: settings, repo: repo, merge: mergeSettings(repo))
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
    /// Co tenhle repozitář o mergi říká (#556). `nil` = nevím.
    let merge: RepositoryMergeSettings?

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

                mergeMethodPicker

                // Tříhodnotový jako odesílání (#517), a ze stejného důvodu: `false` u repa není
                // totéž jako `nil` — repo, u kterého chci po pushi vždycky celé review, si to
                // podrží i po přepnutí globálního defaultu.
                Picker("Po pushi jen přírůstek", selection: config.incrementalAfterPush) {
                    Text("Podle globálního nastavení (\(incrementName(settings.draft.global.incrementalAfterPush)))")
                        .tag(Bool?.none)
                    Text("Jen přírůstek").tag(Bool?.some(true))
                    Text("Vždycky celý diff").tag(Bool?.some(false))
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
                Text("Manuální čeká na tlačítko. Automatický spustí review, jakmile se PR objeví v seznamu. Odesílání rozhoduje jen o tom, jestli se review dá odeslat; když je zakázané, tlačítko `Odeslat review…` zůstane zakázané a řekne proč. Potvrdit odeslání musí vždycky člověk. Metoda merge je výchozí hodnota pro potvrzení, ve kterém se dá přebít pro jeden merge; přeškrtnutá metoda je ta, kterou tenhle repozitář nepovoluje — přečteno z GitHubu. Jazyk se projeví na dalším běhu; už uložené nálezy zůstanou, jak jsou. Přírůstek platí až od druhého kola — v prvním se čte celý diff tak jako tak, a stejně tak u revieweera, který nad předchozí hlavou nedoběhl.")
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

            routing

            timeoutOverride
        }
        .formStyle(.grouped)
    }

    /// Výchozí metoda merge pro tohle repo (#556).
    ///
    /// **Čtyřhodnotový, ne tříhodnotový**: `Podle globálního (squash)` plus tři metody. „Ber
    /// globální“ se musí dát vybrat zpátky **i s tou hodnotou**, jinak není poznat, co se stane —
    /// tatáž úmluva jako u režimu a odesílání.
    ///
    /// **Nepovolená metoda se nedá vybrat, ale z nabídky nezmizí.** Zmizet nesmí, jinak se nedá
    /// poznat rozdíl mezi „repo to nepustí“ a „tuhle metodu GitHub nemá“; kreslí se proto
    /// přeškrtnutá a se slovem `nejde`. Uložit se tím do souboru nedá hodnota, se kterou by merge
    /// skončil chybou z API.
    ///
    /// **Vybraná hodnota, kterou repo přestalo povolovat, se nepřepisuje.** Když se povolení na
    /// GitHubu změní až potom, uložená hodnota v souboru zůstane — přepsat ji za člověka by
    /// znamenalo tiše změnit metodu nevratné akce. Pozná se to **v potvrzení**, které se v tom
    /// stavu otevře bez vybrané metody a řekne, co repo povoluje.
    private var mergeMethodPicker: some View {
        Picker("Metoda merge", selection: selectableMergeMethod) {
            Text("Podle globálního nastavení (\(settings.draft.global.mergeMethod.displayName))")
                .tag(MergeMethod?.none)
            ForEach(Policy.mergeMethodOptions(in: merge)) { option in
                // **`.tag` má i nevybratelná položka, a je to podmínka, ne nedůslednost.** Bez
                // něj by se hodnota, kterou repo přestalo povolovat, v nabídce nezobrazila jako
                // vybraná — a picker by tvrdil „ber globální“ nad souborem, ve kterém stojí
                // `rebase`. Zašedlá vybraná položka je pravda; tichý návrat na globální by nebyl.
                if option.isSelectable {
                    Text(verbatim: option.method.displayName).tag(MergeMethod?.some(option.method))
                } else {
                    // **Přeškrtnutí je z návrhu**, ne ozdoba: zašedlá položka sama vypadá jako
                    // „zatím nedostupné“, kdežto tady jde o „tohle repo to nepustí“. Věta za
                    // pomlčkou to říká slovy, protože ze škrtu neplyne **proč** — a škrt patří
                    // jedině na jméno metody, ne na tu větu (jinak by přeškrtnutý byl i důvod).
                    (
                        Text(verbatim: option.method.displayName).strikethrough()
                            + Text(verbatim: " — nejde, repozitář ji nepovoluje")
                    )
                    .tag(MergeMethod?.some(option.method))
                    .disabled(true)
                }
            }
        }
        .pickerStyle(.radioGroup)
    }

    /// Binding, který **nepovolenou metodu neuloží** — a je to stráž nad daty, ne nad kresbou.
    ///
    /// `.disabled(true)` na položce `Pickeru` je věc **vzhledu a myši**; jestli ji zavře i průchod
    /// klávesnicí, není nikde zaručené, a „nastavení nemá jak uložit hodnotu, se kterou by merge
    /// spadl“ je tvrzení o **souboru**, ne o tom, co se dá kliknout. Zápis se proto zahazuje tady,
    /// na jednom místě a podle **téže** funkce, ze které se kreslí nabídka.
    ///
    /// **Čtení se nefiltruje.** Hodnota, kterou repo přestalo povolovat (nebo která je v souboru
    /// napsaná ručně), se ukazuje **tak, jak je** — přepsat ji za člověka by znamenalo tiše změnit
    /// metodu nevratné akce. Pozná se to v potvrzení.
    private var selectableMergeMethod: Binding<MergeMethod?> {
        Binding(
            get: { config.mergeMethod.wrappedValue },
            set: { chosen in
                guard let chosen else {
                    // `nil` je „ber globální“, tedy vlastní volba — ta se nefiltruje.
                    config.mergeMethod.wrappedValue = nil
                    return
                }
                guard Policy.isMergeMethodSelectable(chosen, in: merge) else { return }
                config.mergeMethod.wrappedValue = chosen
            }
        )
    }

    /// Routing reviewerů (#518) — na kterých cestách se který reviewer pouští.
    ///
    /// **Bez přepínače „vlastní sada“**, na rozdíl od skillů a kategorií: routing globální úroveň
    /// nemá (proč, je u `RepositoryConfig.reviewerPaths`), takže není co dědit — prázdná tabulka
    /// **je** ten výchozí stav a znamená „pouštěj všechny“. Přepínač by nabízel volbu mezi dvěma
    /// stavy, které se nijak neliší.
    private var routing: some View {
        Section {
            ReviewerRoutingEditor(
                reviewerPaths: unwrappedRouting,
                // **Sražená sada, ne to, co je zapsané u repa**: nabídka má vypsat reviewery,
                // kteří se tady doopravdy pouštějí — u repa bez override jsou to ti globální.
                skills: settings.draft.resolved(for: repo).skills
            )
        } header: {
            Text("Routing reviewerů")
        } footer: {
            Text("Reviewer s pravidlem se pustí jen tehdy, když aspoň jeden změněný soubor sedí na aspoň jeden jeho vzor; reviewer bez pravidla se pouští vždycky. Vzor bez lomítka platí na jméno souboru kdekoli v repu (`composer.lock`, `*.env*`), vzor s lomítkem se čte od korene repa (`src/Auth/**`); `**` přeskočí i podsložky, `*` zůstane v jedné. Přeskočený reviewer je vidět v tabu Průběh i s důvodem a dá se pustit ručně — pravidlo tím zůstane, jak je.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Mapa bez `nil`: prázdná tabulka a chybějící klíč znamenají totéž, takže se `nil` **zapisuje
    /// zpátky** místo prázdné mapy — jinak by v `config.json` po každém proklikání zůstal prázdný
    /// objekt a `setRepository(_:for:)` by záznam nesmazal.
    private var unwrappedRouting: Binding<[String: [String]]> {
        Binding(
            get: { config.reviewerPaths.wrappedValue ?? [:] },
            set: { config.reviewerPaths.wrappedValue = $0.isEmpty ? nil : $0 }
        )
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
                Text(verbatim: inheritedTimeout)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Platí na jednu session — na každý skill zvlášť a stejně tak na kontrolu nálezů. Projeví se na dalším běhu; ten, který právě běží, doběhne s limitem, se kterým začal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Co repo bez vlastního limitu doopravdy dostane.
    ///
    /// **Sražená hodnota, ne ta ze souboru.** Globální číslo může být mimo meze (napsané ručně) —
    /// a napsat sem „Bere globální: 240 min“ nad během, který poběží 60, je přesně ten text, který
    /// tvrdí víc, než data unesou. Sráží to `Policy`, tedy totéž místo, kterým hodnota projde na
    /// cestě do běhu; a když se srazilo, je to tady vidět i s tím, co v souboru stojí.
    private var inheritedTimeout: String {
        let global = settings.draft.global.reviewTimeoutMinutes
        guard Policy.reviewTimeoutProblem(in: global) != nil else {
            return "Bere globální: \(inheritedMinutes) min"
        }
        return "Bere globální: \(inheritedMinutes) min — globálně je nastaveno \(global) min,"
            + " což je mimo rozsah \(ReviewTimeout.allowedMinutes.lowerBound)"
            + "–\(ReviewTimeout.allowedMinutes.upperBound) min."
    }

    /// Zapnutí začíná od **sražené** globální hodnoty, ne od té ze souboru — jinak by override
    /// zapnutý nad globálním nesmyslem ten nesmysl zkopíroval a hned si na sebe stěžoval.
    private var isOverridden: Binding<Bool> {
        Binding(
            get: { config.reviewTimeoutMinutes.wrappedValue != nil },
            set: { on in
                config.reviewTimeoutMinutes.wrappedValue = on ? inheritedMinutes : nil
            }
        )
    }

    /// Odvozený `Binding` bez `nil`, se stejnou pojistkou jako u sad: doběhlá editace už
    /// zrušeného override ho nesmí vzkřísit.
    private var unwrappedTimeout: Binding<Int> {
        Binding(
            get: { config.reviewTimeoutMinutes.wrappedValue ?? inheritedMinutes },
            set: { newValue in
                guard config.reviewTimeoutMinutes.wrappedValue != nil else { return }
                config.reviewTimeoutMinutes.wrappedValue = newValue
            }
        )
    }

    /// Kolik minut repo bez override doopravdy dostane. Jedno místo pro popisek i pro seed
    /// zapnutého přepínače.
    private var inheritedMinutes: Int {
        Policy.reviewTimeoutMinutes(from: settings.draft.global.reviewTimeoutMinutes)
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

    private func incrementName(_ enabled: Bool) -> String {
        enabled ? "jen přírůstek" : "vždycky celý diff"
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
