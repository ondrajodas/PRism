import SwiftUI

/// Stránka `Vzhled` (#278) — tmavý, světlý, nebo podle systému.
///
/// Vlastní stránka, ne řádek na stránce `Diff`: přepínač platí pro **celé okno** — hlavičku,
/// rail, nastavení, novinky i sheety — takže na stránce pojmenované `Diff` by lhal. Je to tatáž
/// úvaha, kvůli které je vlastní stránkou `Odesílání` (#177): rozhoduje otázka, na kterou se
/// odpovídá, ne počet ovládacích prvků.
struct AppearanceSettingsView: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Vzhled okna", selection: $settings.draft.global.appearance) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(verbatim: mode.displayName).tag(mode)
                    }
                }
                // Radio group, ne segmentovaný přepínač: tentýž druh volby — globální předvolba
                // pohledu — nese tímtéž prvkem stránka `Diff`, a dva různé prvky na dvou
                // stránkách vedle sebe vypadají jako dvě různá rozhodnutí.
                //
                // **Šířka to nerozhodla.** Segmentovaný přepínač si řekne o 330 bodů proti 110
                // u radio groupu (změřeno `AppearanceRenderProbe`; ta stovka je za svislý sloupec,
                // který formulář v řádku rozloží vodorovně) — ale do řádku se vejdou oba, i na
                // nejužší stránce nastavení. Jak která varianta vypadá, se dá vyrendrovat tou samou
                // sondou: stačí prohodit tenhle řádek.
                .pickerStyle(.radioGroup)
            } header: {
                Text("Vzhled")
            } footer: {
                // Musí být napsané, že se to týká **všech** oken a že to platí hned — jinak to
                // vypadá jako volba, po které se má aplikace restartovat.
                Text("Platí pro všechna okna aplikace a uplatní se hned, bez restartu. `Podle systému` je výchozí a řídí se nastavením macOS. Barvy jsou v obou režimech tytéž, jaké má vizuální návrh — přepínač volí režim, ne paletu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Uloží se **hned**, bez těch 600 ms, po kterých se ukládá samo. Zpoždění je tam kvůli
        // psaní do textových polí; tady je klik hotová volba a čekání na přebarvení okna vypadá,
        // jako by přepínač nefungoval. Jde to pořád tou jedinou cestou (`AppStore.apply`), takže
        // vzhled si nikdo nenastavuje sám.
        //
        // **Změna zvenčí tím zápis nevyvolá**: po `sync(with:)` je rozepsaná konfigurace rovná té
        // usazené a `flush()` se z ní hned vrátí. Ručně editovaný soubor si tedy tahle stránka
        // nepřepíše sama sebou.
        .onChange(of: settings.draft.global.appearance) {
            Task { await settings.flush() }
        }
    }
}
