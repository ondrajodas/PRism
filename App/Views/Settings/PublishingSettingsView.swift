import SwiftUI

/// Stránka `Odesílání` (#177), od #556 se dvěma sekcemi.
///
/// Vlastní stránka, i když to začalo jedním přepínačem: je to jediné místo, kde se rozhoduje,
/// jestli z aplikace **může něco odejít** (tvrdá podmínka č. 1). Vysvětlivka je proto dlouhá
/// schválně — text je tu důležitější než přepínač.
///
/// **Výchozí metoda merge leží pod branou, ne vedle ní** (#556). Brána rozhoduje, jestli se dá
/// mergnout **vůbec**, tahle sekce jenom **čím**; obráceně by to vypadalo, že se metodou odesílání
/// zapíná. Vlastní stránka by k tomu znamenala jeden knoflík na stránku, a merge je z toho, co
/// z aplikace odchází, ta nejnevratnější část — tedy věc, která na téhle stránce patří nejvíc.
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

            mergeMethod
        }
        .formStyle(.grouped)
    }

    /// Výchozí metoda merge vlastního PR (#556).
    ///
    /// **Radiogroup jako režim a odesílání**, ne rozbalovací nabídka: jsou to tři hodnoty a všechny
    /// tři mají být vidět naráz — u nevratné akce se nemá hledat v seznamu, co je vybráno.
    ///
    /// **Metoda, kterou konkrétní repozitář nepovoluje, tady vybrat jde.** Globální hodnota platí
    /// pro všechna repa a o kterémkoli z nich se odsud nedá nic tvrdit — zašednout tu, kterou
    /// nepovoluje repo, na které se člověk zrovna kouká, by znamenalo vlastnost jednoho repa
    /// vydávat za pravidlo pro všechna. Že ji tenhle konkrétní repozitář nepustí, se pozná
    /// v potvrzení, tedy dřív, než se cokoli mergne.
    private var mergeMethod: some View {
        Section {
            Picker("Výchozí metoda", selection: $settings.draft.global.mergeMethod) {
                ForEach(MergeMethod.allCases, id: \.self) { method in
                    Text(verbatim: method.displayName).tag(method)
                }
            }
            .pickerStyle(.radioGroup)
        } header: {
            Text("Merge vlastního PR")
        } footer: {
            Text("Platí pro repa, která si neřeknou o jinou. Squash je výchozí, protože tak se aplikace chovala předtím, než tahle volba vznikla. Potvrzení metodu vypisuje a dovolí ji přebít pro jeden merge; do nastavení se tím nezapisuje. Metodu, kterou repozitář nepovoluje, tady vybrat jde — globální hodnota platí pro všechna repa. Že ji to konkrétní repo nepustí, se pozná v potvrzení, ne z chyby po něm.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
