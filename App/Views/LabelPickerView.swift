import SwiftUI

/// Nabídka labelů, které **zná repozitář** (#392), a od #413 i **založení nového**.
///
/// **Uzavřený zůstává seznam, ne nabídka.** Řádky nesou dál jedině labely, které repozitář zná, a
/// hledací pole nad nimi **filtruje** — `↵` na vybraném řádku znamená pořád „přepni tenhle label“.
/// Založení je vlastní akce **pod děličem**, mimo dosah šipky dolů, s vlastní klávesou (`⌥↵`), a vede
/// na **druhou obrazovku téhož popoveru**. Kdyby sedělo v seznamu jako další řádek, byl by z něj
/// nejpravděpodobnější omyl v celé obrazovce: přidržená šipka dolů na konci filtrovaného seznamu.
///
/// **Popover, ne `Menu`**, a je to rozhodnutí ze tří důvodů. Nabídka se musí **dotáhnout při
/// otevření** (labely repozitáře jsou volání `gh`, které se nemá platit při každém výběru řádku)
/// a `Menu` k tomu na macOS spolehlivý okamžik nedává; u labelu se kreslí **puntík s barvou
/// z repozitáře**, což v systémovém menu není kam dát; a od hledání je v ní **pole a obsluha
/// šipek**, kterou by `Menu` neuneslo vůbec. Druhá obrazovka je čtvrtý důvod — v `Menu` by nebyla kde.
///
/// Sloveso je v **nadpisu**, ne v položkách — položka je chip s barvou a jménem, tedy to, čím se
/// řádky od sebe liší. Odškrtnutí říká, které labely na PR leží.
struct LabelPickerView: View {
    /// Kam nový label půjde. Kreslí se to v potvrzení — **„kam“ je jedna ze čtyř otázek**, na které
    /// ta obrazovka odpovídá, takže je to povinná hodnota, ne ozdoba.
    let repo: RepoID
    let known: [PullRequestLabel]
    let selected: [PullRequestLabel]
    /// Dorazila už nabídka? `false` = ještě se načítá, takže se o repu nesmí nic tvrdit — a nedá se
    /// ani zakládat, protože bez seznamu není proti čemu hledat duplikát.
    var isLoaded = false
    /// Proč je nabídka prázdná. `nil` = načetla se — takže prázdno znamená „repo žádné labely
    /// nezná“, a to je jiná věta než porucha.
    var failure: String?
    /// Smí se na tomhle PR zakládat? Rozhoduje o tom `Policy`, ne tohle view — a předává se, i když
    /// se dnes popover jinak než `.allowed` neotevře: kontrola, která spoléhá na to, že se sem
    /// nedostaneš, je kontrola, kterou příští obrazovka obejde.
    var editing: Policy.MetadataEditing = .allowed
    let toggle: @MainActor (PullRequestLabel) -> Void
    /// Založit nový label a hned ho přidat (#413). Výchozí prázdná akce znamená nabídku jen ke čtení.
    var create: @MainActor (PullRequestLabel) -> Void = { _ in }
    let load: @MainActor () async -> Void

    /// Dotaz v hledacím poli. **Není to binding** — je to jen počáteční hodnota, kterou si dál drží
    /// view; parametr existuje kvůli sondám, které nemají klávesnici a jinak by druhou obrazovku
    /// nedokázaly vyfotit. V aplikaci se nepředává.
    @State var query = ""
    /// Druhá obrazovka popoveru. `nil` = seznam. Tatáž úvaha o parametru jako u `query`.
    ///
    /// **Drží celý label, ne jen jméno**: je to tatáž hodnota, kterou nakreslí náhled a pošle
    /// publisher, takže se náhled a payload nemají jak rozejít.
    @State var confirming: PullRequestLabel?

    @State private var selection = 0

    /// Šířka `.pkr` z návrhu. **Pevná, ne `maxWidth`**: obě obrazovky mají být stejně široké, jinak
    /// popover při přepnutí poskočí — a rezervy v zákresu jsou naměřené právě na 300.
    private static let width = 300.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let confirming {
                confirmation(of: confirming)
            } else {
                list
            }
        }
        .frame(width: Self.width)
        // **Na `VStack`u, ne na obrazovce**: přepnutí mezi seznamem a potvrzením nemá načítat znovu.
        .task { await load() }
    }

    // MARK: - Seznam

    @ViewBuilder private var list: some View {
        // **Sloveso, ne kategorie.** `Labely repozitáře` bylo věcně správně, ale neříkalo, co
        // klik udělá — a klik je tady přepínač, takže se stejným řádkem label i sundá.
        PickerHeading(title: "Přepnout label")
        // **Pole je u labelů vždycky** (#413): jméno nového labelu se bere z dotazu, takže bez pole
        // není kam ho napsat — v repu se třemi labely by se nedalo založit nic. Rozhoduje `Policy`,
        // ne tohle view.
        if Policy.pickerShowsSearch(count: known.count, canCreate: true) {
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
                confirm: confirmSelection,
                // `⌥↵` se nabídne jedině tehdy, když je co založit — jinak se klávesa propustí dál.
                create: offer.map { label in { confirming = label } }
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
            // obrazovku.
            .frame(height: min(Double(filtered.count) * 24 + 7, 320))
        }
        if let offer { newLabelAction(offer) }
        // Patka **až za akcí k založení**, jak ji kreslí sekce 26 — je to spodní hrana nabídky,
        // takže pod ní nesmí být nic. `⌥↵` v ní schválně není, důvod je u `PickerKeyHints`.
        if Policy.pickerShowsKeyHints(rowCount: filtered.count) {
            PickerKeyHints(confirm: "přepne")
        }
    }

    /// Akce `Založit „…“` **pod děličem**.
    ///
    /// Přerušovaně obtažená jako `+ label` a `čeká` u reviewera: přerušované je to, co se ještě
    /// nestalo. Jméno se sází **doslova a v uvozovkách** a **zalomí se, neořeže** — je to jediné
    /// místo před potvrzením, kde je vidět celé, takže ořezat by znamenalo ořezat zrovna tu
    /// informaci, kvůli které ten krok existuje.
    private func newLabelAction(_ label: PullRequestLabel) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.lineSoft).frame(height: 1)
            Button {
                confirming = label
            } label: {
                // `align-items: center` z návrhu, ne baseline: u zalomeného jména mají `+` i `⌥↵`
                // zůstat u prostředka akce, protože patří celé akci, ne prvnímu řádku jména.
                HStack(alignment: .center, spacing: 7) {
                    Text(verbatim: "+")
                        .font(.system(size: 12))
                    // Jméno je **`--ink`**, zbytek `--ink-2` (`.nl-add b`): je to ta jediná hodnota
                    // na řádku, kterou má člověk zkontrolovat.
                    (
                        Text("Založit ")
                            + Text(verbatim: "„\(label.name)“").bold().foregroundColor(Palette.ink)
                    )
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 7)
                    Text(verbatim: "⌥↵")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.ink3)
                }
                .foregroundStyle(Palette.ink2)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 5)
            .padding(.vertical, 6)
            .accessibilityLabel("založit nový label \(label.name)")
        }
    }

    // MARK: - Potvrzení (druhá obrazovka)

    /// Druhý krok, a je to **druhá obrazovka téhož popoveru, ne sheet**.
    ///
    /// Přepnutí existujícího labelu zůstává jedno kliknutí (#392 mu potvrzovací okno nedalo
    /// schválně) — potvrzuje se to, co vratné **není**, a modální okno kvůli jednomu slovu by
    /// z panelu udělalo klikačku.
    ///
    /// Jsou na ní **čtyři věci a každá odpovídá na jednu otázku**: co se objeví (chip s puntíkem
    /// a jménem doslova), kam to jde (slug repozitáře), jaká bude barva (hex) a co po tom zůstane
    /// (výstraha). Slug je **pod chipem a v mono s pravým casingem**, ne v nadpisu: `PickerHeading` je
    /// `textCase(.uppercase)`, takže `ondrajodas/PRism` by se vysázelo `ONDRAJODAS/PRISM` — a velká
    /// písmena ve jméně repozitáře jsou data, ne dekorace.
    @ViewBuilder private func confirmation(of label: PullRequestLabel) -> some View {
        PickerHeading(title: "Nový label v repozitáři")
        VStack(alignment: .leading, spacing: 9) {
            LabelChipView(label: label, maxWidth: nil)
            Text(verbatim: repo.description)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.ink2)
            HStack(spacing: 0) {
                Text(verbatim: "#\(label.color.uppercased())")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.ink2)
                Text(" · z výchozí palety GitHubu, podle jména")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink3)
            }
            .fixedSize(horizontal: false, vertical: true)
            warning
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 11)
        // `leading`, ne pružná šířka na chipu: `LabelChipView` je `HStack`, který by se ve svislém
        // sloupci natáhl přes celý popover — a z náhledu by byla pilulka na celou řádku, tedy něco,
        // co v panelu nikdy nevypadá takhle.
        .frame(maxWidth: .infinity, alignment: .leading)
        footer(for: label)
    }

    /// Co po tom zůstane. **Výstraha, ne poznámka**: je to jediná věta na obrazovce, která mluví
    /// o tom, co aplikace vzít zpět neumí — `deleteLabel` v `ReviewPublishing` není a nebude.
    private var warning: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.stale)
            Text("Zůstane v repozitáři i po odebrání z PR. Smazat ho odsud nejde — jedině na GitHubu.")
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Palette.stale.opacity(0.11), in: .rect(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.stale.opacity(0.4)) }
    }

    /// Patka potvrzení: `Zpět`, počet volání a `Založit a přidat`.
    ///
    /// **Výchozí akci nemá schválně** (`⌘↵` ani `↵`): poslední klik před něčím nevratným je klik,
    /// tak jako u potvrzení odeslání review (#68).
    ///
    /// `dvě volání` není ozdoba — je to jediné místo, kde je vidět, že tvrdá podmínka č. 5 pro
    /// tuhle akci neplatí, a proto se pak dá pochopit i věta o tom, že se založilo a nepřidalo.
    private func footer(for label: PullRequestLabel) -> some View {
        // Plocha patky je `PickerFooter`, tedy **tatáž jako u nápovědy kláves** (#434): návrh na to
        // má jednu třídu (`.pkr-foot`) a dvě kopie odsazení by se rozešly potichu.
        PickerFooter {
            Button("Zpět") { confirming = nil }
                .buttonStyle(.mini)
            Spacer(minLength: 7)
            Text("dvě volání")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.ink3)
                .fixedSize()
            Button("Založit a přidat") {
                confirming = nil
                create(label)
            }
            .buttonStyle(.miniPrimary)
            // Pro čtečku obrazovky **celá věta**, jako u položek nabídky: je to poslední klik před
            // něčím nevratným, takže se nemá muset dohledávat z chipu nad tlačítkem.
            .accessibilityLabel("založit label \(label.name) v repozitáři \(repo.description) a přidat ho na PR")
        }
    }

    // MARK: - Data

    /// **Filtruje se podle jména, tedy podle toho, co je v řádku vidět.** Rozhoduje `Policy`.
    private var filtered: [PullRequestLabel] {
        Policy.filteredPicker(known, query: query, text: \.name)
    }

    /// Label, který se z dotazu založí — nebo `nil`, a pak se akce nekreslí vůbec. Pět důvodů, proč
    /// `nil`, je vyjmenovaných u `Policy.newLabelOffer`.
    private var offer: PullRequestLabel? {
        Policy.newLabelOffer(query: query, known: known, isLoaded: isLoaded, editing: editing)
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
