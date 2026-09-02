import SwiftUI

/// Sekce `Organizace k prohledávání` na stránce `Zdroje PR` (#532).
///
/// **Chipy podle zákresu** (`docs/navrh.html`, `.chipline` + `.tagchip` + `.tagchip.plus`), sazba
/// v `TagChipStyle` jeden ku jedné. První podoba měla řádky s poli, aby se sekce shodovala
/// s `Moje loginy` o řádek výš — to je **zamítnuté rozhodnutím uživatele**: kreslí se to, co je
/// v návrhu, a sjednocení `Moje loginy` je jiné issue.
///
/// Tři věci, které chipline proti zákresu potřebovala navíc, protože statická kresba je nemá:
///
/// - **křížek v chipu** na odebrání (`TagChipStyle.removeGlyphSize`) — jinak se organizace nedá
///   dostat pryč jinak než ručním zásahem do `config.json`;
/// - **pole místo přidávacího chipu**, když se na něj klikne. Jméno organizace je volný text (na
///   rozdíl od labelu, který se vybírá z uzavřené množiny, #392), takže nabídka nemá odkud vzniknout;
/// - **věta o selhání pod chipline**, uvozená jménem organizace. Organizace, na kterou účet nevidí,
///   se od organizace bez repozitářů jinak nepozná — obojí je prázdný seznam.
struct OrganizationListEditor: View {
    @Binding var organizations: [String]
    let catalog: RepositoryCatalog
    /// Kdy se má dotáhnout, co v cache chybí nebo je starší než den. Volá to **potvrzení
    /// napsaného jména**, ne úhoz — dotažení je nad velkou organizací věc desítek sekund.
    let refreshStale: () -> Void
    let refreshAll: () -> Void
    let now: Date

    /// Píše se právě nová organizace? `nil` = ne, kreslí se přidávací chip.
    @State private var typed: String?
    @FocusState private var isTyping: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row
            failures
        }
    }

    /// `.set-row` ze zákresu: chipy vlevo, `.val` (souhrn a `Obnovit`) vpravo přes
    /// `margin-left: auto` — **dokud se to na jeden řádek vejde**.
    ///
    /// **`ViewThatFits`, ne `layoutPriority`, a je to ze dvou renderů**: SwiftUI nemá `flex-shrink`,
    /// takže `FlowRow` s `maxWidth: .infinity` si v `HStack`u řekne o celou šířku — a souhrn se pak
    /// nakreslí **přes první chip** (změřeno na scéně `organizace-chyba`, kde souhrn nese i klauzuli
    /// `1 organizace nenačtena`: v renderu stálo `kebo412 rep`). `layoutPriority(1)` na souhrnu to
    /// **nespravilo**, protože ideální šířka nekonečného rámce zůstane nekonečná. `ViewThatFits`
    /// proti tomu **rozhodne z rozměru**, ne z vyjednávání: co se vejde, je řádek ze zákresu; co ne,
    /// jsou dva řádky pod sebou.
    private var row: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                chipline
                // **Na řádku se souhrn nesmí smrsknout**, jinak by se `ViewThatFits` rozhodl, že
                // se vejde, a přitom by byl ukousnutý. V zákresu má `.val` vlastní šířku
                // (`margin-left: auto`), tedy totéž.
                catalogStatus(isRigid: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                chipline
                // Pod chipy se naopak **ořezat smí**: je to poslední možnost, takže přetečení
                // z hodně dlouhého souhrnu (`nejméně …` a k tomu tři nenačtené organizace) nemá
                // kam ustoupit.
                catalogStatus(isRigid: false)
            }
        }
    }

    /// `.chipline` ze zákresu: `flex-wrap` s mezerou 5.
    ///
    /// **Nezalamuje to `HStack`** — ten by místo zalomení popisky zkrátil. Bere se `FlowRow`
    /// (#333), tedy `Layout`, který **polohy počítá, nevyjednává**: každý chip dostane svou
    /// ideální velikost a řady se z nich složí. Mezera je `gap: 5px` ze zákresu v obou osách,
    /// protože chipline žádnou sazbu textu pod sebou nemá.
    private var chipline: some View {
        FlowRow(spacing: TagChipStyle.spacing, lineSpacing: TagChipStyle.spacing) {
            ForEach(Policy.searchOrganizations(organizations), id: \.self) { organization in
                TagChipView(
                    title: organization,
                    removeLabel: "Odebrat organizaci \(organization)"
                ) {
                    remove(organization)
                }
            }
            if typed == nil {
                Button {
                    typed = ""
                    isTyping = true
                } label: {
                    AddTagChipLabel(title: "+ organizace")
                }
                .buttonStyle(.plain)
                .help("Přidat organizaci, ve které se mají hledat repozitáře")
            } else {
                field
            }
        }
    }

    /// Pole, které z přidávacího chipu vyroste po kliknutí.
    ///
    /// **Potvrzuje se Enterem, ruší odkliknutím** nebo `⏎` na prázdném poli. Dotažení
    /// visí na tom potvrzení, ne na textu: `keboola` po písmenech je sedm hodnot, takže fetch na
    /// změnu by z jednoho dopsaného jména udělal sedm dotazů po desítkách sekund.
    @ViewBuilder private var field: some View {
        TextField(
            "Organizace",
            text: Binding { typed ?? "" } set: { typed = $0 },
            prompt: Text(verbatim: "keboola")
        )
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .font(Font(TagChipStyle.font()))
        .focused($isTyping)
        // Šířka je pevná schválně: pole v zalamované řadě chipů, které si říká o celý řádek, by
        // chipy před sebou vytlačilo na řádek nahoru a při každém úhozu s nimi hýbalo.
        .frame(width: 150)
        .onSubmit { commit() }
        // **`onExitCommand` tady vědomě není** a `⎋` zůstává zkratkou okna (#151). Ta znalost je
        // v repu změřená u `hiddenShortcuts`: `onExitCommand` se váže na **fokus**, kdežto zkratka
        // na tlačítku se registruje na **celé okno** — a která z nich vyhraje, se v harnessu
        // ověřit nedá (#184). Nechat obojí by znamenalo klávesu, o které se neví, kam padne;
        // takhle `⎋` dělá jednu věc, jak #151 chce, a rozepsané jméno se zahodí se zavřením okna,
        // tedy se stejným výsledkem, jaký by mělo zrušení.
        //
        // Zrušit se dá i bez zavírání okna: odkliknutím (zahodí to `onChange` níž) nebo Enterem
        // na prázdném poli.
        .onChange(of: isTyping) { _, hasFocus in
            // Odklik pole zahodí — rozepsané jméno, které by v chipline zůstalo stát, vypadá jako
            // chip, který se nepřidal.
            if !hasFocus { typed = nil }
        }
    }

    /// Věty o organizacích, které se nepodařilo dotáhnout — jedna na organizaci, uvozená jejím
    /// jménem, aby se poznalo, o který chip jde.
    @ViewBuilder private var failures: some View {
        let failing = Policy.searchOrganizations(organizations)
            .compactMap { organization -> (String, String)? in
                catalog.failure(for: organization).map { (organization, $0) }
            }
        if !failing.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(failing, id: \.0) { organization, failure in
                    Label {
                        Text(verbatim: "\(organization): \(failure)")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.find)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Souhrn nad celým katalogem a tlačítko `Obnovit` — `.val` na pravé straně řádku s chipy.
    ///
    /// **Vejde se to na jeden řádek, a je to změřené, ne odhadnuté**: v nejužší podobě okna
    /// (509 bodů obsahové části při `minWidth` 720) zbývá chipům po souhrnu a tlačítku ~250 bodů,
    /// tedy dvě organizace a přidávací chip. Třetí se zalomí — a to je v pořádku, protože
    /// `.chipline` se v zákresu zalamuje taky (`flex-wrap: wrap`).
    ///
    /// **Kreslí se, jen když nějaká organizace je.** Prázdná sekce nemá co obnovovat a tlačítko,
    /// které nikdy nic neudělá, je horší než žádné.
    @ViewBuilder private func catalogStatus(isRigid: Bool) -> some View {
        let status = Policy.repositoryCatalogStatus(
            // Ne `organizations` rovnou: `Policy.searchOrganizations` ověřuje jména a zahazuje
            // duplicity, takže souhrn nevznikne z rozepsaného jména ani z téže organizace dvakrát.
            organizations: Policy.searchOrganizations(organizations),
            snapshots: catalog.snapshots,
            refreshing: catalog.refreshing
        )
        if let summary = Policy.repositoryCatalogSummary(status, now: now) {
            // `gap: 8px` z `.set-row .val`.
            HStack(spacing: 8) {
                // `.set-row .val .mono` ze zákresu: mono 11,5 a `--ink-2`.
                Text(verbatim: summary)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Obnovit", action: refreshAll)
                    .controlSize(.small)
                    // Druhý klik uprostřed dotažení by ten první nezrychlil — je to tatáž úvaha
                    // jako u `Policy.refreshControl` v hlavičce okna.
                    .disabled(catalog.isRefreshing)
            }
            .fixedSize(horizontal: isRigid, vertical: false)
        }
    }

    /// Přidá napsané jméno a nechá dotáhnout, co je potřeba.
    ///
    /// **Neplatné jméno se nepřidá a pole zůstane stát** — `Policy.organizationName(from:)` je
    /// tatáž funkce, která rozhoduje o cestě do cache, takže co neprojde tam, nemá vzniknout ani
    /// jako chip. Prázdné pole je odchod, ne chyba.
    private func commit() {
        guard let name = Policy.organizationName(from: typed ?? "") else {
            // Prázdné pole zavře, rozepsané nesmysl nechá k opravě — jinak by se napsané jméno
            // ztratilo pod rukou a nebylo by z čeho poznat, co na něm bylo špatně.
            if (typed ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { typed = nil }
            return
        }
        typed = nil
        // Duplicitu zahodí `Policy.searchOrganizations` až při kreslení, ale zapsat ji do
        // konfigurace nemá důvod — soubor se edituje ručně a dvakrát tatáž organizace v něm mate.
        guard !Policy.searchOrganizations(organizations).contains(name) else { return }
        organizations.append(name)
        refreshStale()
    }

    private func remove(_ organization: String) {
        organizations.removeAll { Policy.organizationName(from: $0) == organization }
    }
}
