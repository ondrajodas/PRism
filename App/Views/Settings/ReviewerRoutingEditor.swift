import SwiftUI

/// Tabulka `Routing reviewerů` per repo (#518) — řádek reviewer → vzory cest.
///
/// **Ukazují se jen reviewery, kteří pravidlo mají**, jako u `LanguageSkillsEditor`: prázdný
/// seznam vzorů pod každým skillem ze sady by z formuláře udělal tabulku, ve které není vidět to
/// jediné, co je nastavené — a přidat řádek je jedno kliknutí v nabídce.
///
/// **Nabídka vypisuje sadu toho repa**, ne globální: routing rozhoduje o tom, co se na tomhle repu
/// pouští, takže skill, který tady v sadě není, by dostal pravidlo, které nikdy nikoho neovlivní.
/// Pravidlo po skillu, který ze sady vypadl, se ale **nemaže** — je to zápis v konfiguraci a smaže
/// ho člověk (řádek zůstává vidět i s odznakem `mimo sadu`), stejně jako dráha po odebraném
/// revieweerovi v tabu `Průběh` nezmizí.
struct ReviewerRoutingEditor: View {
    @Binding var reviewerPaths: [String: [String]]
    /// Sada skillů, která na tomhle repu doopravdy platí (`ResolvedConfig.skills`). Předává se
    /// zvenčí, protože editor sám konfiguraci nevidí.
    let skills: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(configured, id: \.self) { skill in
                section(for: skill)
            }
            // Prázdná sada skillů (`tady nereviewuj nic`) znamená, že tabulka nemá **co**
            // vypisovat ani co nabídnout — a prázdná krabice bez věty vypadá jako porucha.
            if configured.isEmpty, unconfigured.isEmpty {
                Text("Sada skillů je prázdná, takže není co routovat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            addButton
        }
    }

    /// Nejdřív v pořadí sady, pak abecedně to, co v sadě není — `Dictionary` pořadí nemá, takže by
    /// řádky mezi překreslením poskakovaly. Je to tatáž úvaha jako u pořadí drah
    /// (`Policy.lanes`).
    private var configured: [String] {
        let inSet = skills.filter { reviewerPaths[$0] != nil }
        let rest = reviewerPaths.keys.filter { !skills.contains($0) }.sorted()
        return inSet + rest
    }

    private var unconfigured: [String] {
        skills.filter { reviewerPaths[$0] == nil }
    }

    private func section(for skill: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: skill)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.head)
                // Pravidlo po skillu, který v sadě není, se **nesmí tvářit jako aktivní** — tatáž
                // úvaha jako u odznaku `mimo sadu` na dráze: nemaže se, ale musí být poznat, že
                // dnes o ničem nerozhoduje.
                if !skills.contains(skill) {
                    Text("mimo sadu")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                        .help("Tenhle skill není v sadě pro tohle repo, takže pravidlo dnes nikoho neovlivní.")
                }
                Spacer()
                Button {
                    reviewerPaths[skill] = nil
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Zrušit pravidlo — reviewer se pak pouští na každém PR")
            }
            StringListEditor(
                items: paths(for: skill),
                itemLabel: "Cesta",
                placeholder: "src/Auth/**",
                addLabel: "Přidat vzor"
            )
        }
    }

    @ViewBuilder private var addButton: some View {
        if unconfigured.isEmpty {
            EmptyView()
        } else {
            // Nový řádek začíná **prázdný**, ne s vymyšleným vzorem: co se má hlídat, ví jedině
            // člověk, a předvyplněný `src/**` by pravidlo udělal bezzubým. Prázdné pravidlo se
            // proto pouští vždycky (viz `ReviewerRouting`) — mezistav mezi kliknutím a dopsáním
            // vzoru nesmí revieweera vypnout.
            Menu("Přidat reviewera") {
                ForEach(unconfigured, id: \.self) { skill in
                    Button(skill) { reviewerPaths[skill] = [""] }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .controlSize(.small)
        }
    }

    /// Stejná pojistka jako u ostatních editorů: záznam může zmizet dřív, než se seznam
    /// překreslí, a zápis do smazaného klíče by ho vzkřísil.
    private func paths(for skill: String) -> Binding<[String]> {
        Binding(
            get: { reviewerPaths[skill] ?? [] },
            set: { newValue in
                guard reviewerPaths[skill] != nil else { return }
                reviewerPaths[skill] = newValue
            }
        )
    }
}
