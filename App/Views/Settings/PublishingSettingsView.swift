import SwiftUI

/// Stránka `Odesílání` (#177).
///
/// Vlastní stránka, i když je to jeden přepínač: je to jediné místo, kde se rozhoduje, jestli
/// z aplikace **může něco odejít** (tvrdá podmínka č. 1). Vysvětlivka je proto dlouhá schválně —
/// text je tu důležitější než přepínač.
struct PublishingSettingsView: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Povolit odesílání", isOn: $settings.draft.global.allowsPublishing)
            } header: {
                // **Ne „Odesílání review“**: od #73 tenhle přepínač povoluje i odpovědi do
                // vláken a jejich vyřešení, takže názvem jen o review by tvrdil méně, než co
                // doopravdy řídí.
                Text("Odesílání na GitHub")
            } footer: {
                // Text nesmí být čitelný jako „zapnout automatické odesílání“. Přepínač
                // rozhoduje **jen** o tom, jestli se dá odeslat; odesílá pořád člověk.
                //
                // A nesmí slibovat, že se tlačítko schová — nechá se **zakázané a s důvodem**,
                // protože mizející tlačítko vypadá jako rozbitá aplikace.
                Text("Platí pro review i pro odpovědi do vláken. Když je vypnuté, tlačítka zůstanou zakázaná a řeknou proč. Samo se neodešle nikdy nic — review odchází jedině tak, že ho člověk potvrdí, a jedině proti commitu, který má před sebou. Repo si to může přebít.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

}
