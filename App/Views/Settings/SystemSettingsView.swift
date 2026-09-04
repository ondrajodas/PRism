import SwiftUI

/// Stránka `Systém` (#529, návrh sekce 49) — co aplikace hlídá, má být vidět i se zavřeným oknem.
///
/// **Vlastní stránka ve skupině `Prostředí`, ne řádek v `Běhu`.** Obojí, co je na ní, sahá **mimo
/// okno**: odznak na dlaždici v Docku a přihlašovací položka v systému. `Běh` je proti tomu hrst
/// čísel o tom, jak se aplikace chová dovnitř (interval, rozpočet cache, souběh) — a dělení stránek
/// je podle otázky, na kterou odpovídají, ne podle typu ovládacího prvku.
///
/// **Dvě různé cesty k hodnotě, a je to vidět.** Volba odznaku je preference, takže jde do
/// `config.json` odloženě jako zbytek formuláře (`SettingsModel`). Přihlašovací položka je stav
/// systému, takže se **čte zpátky** a zapisuje hned — kdo si ji vypne v Nastavení systému, má to
/// vidět tady.
struct SystemSettingsView: View {
    @Bindable var settings: SettingsModel
    let store: AppStore

    /// Jak moc se zašedne řádek, se kterým nejde cvaknout. **Číslo je ze zákresu** (sekce 49,
    /// `opacity: 0.55` na `.set-row`) a je tu proto, že samotné `.disabled(_:)` **vidět není** —
    /// změřeno: dvě bitmapy téhož řádku, jedna zakázaná a jedna ne, se v hostovaném okně liší jen
    /// odstínem přepínače a popiska zůstává plná. Zašedlý řádek, který vypadá jako povolený, je
    /// horší než chybějící: člověk klikne a nic se nestane.
    ///
    /// Vzor je `FindingTableRowView.dismissedOpacity` a `ReviewerChipsView` — tlumený řádek se
    /// v tomhle okně kreslí opacitou, ne vlastní barvou.
    private static let disabledOpacity: Double = 0.55

    var body: some View {
        Form {
            dockBadge
            launch
        }
        .formStyle(.grouped)
        // Při **každém** zobrazení stránky, ne jednou při startu: vypnout položku jde i v Nastavení
        // systému, takže snímek ze startu by do večera zestaral. Je to čtení jedné hodnoty ze
        // systému, nic se tím nezapisuje.
        .task { store.refreshLoginItem() }
    }

    private var dockBadge: some View {
        Section {
            Picker("Co se počítá", selection: $settings.draft.global.dockBadge) {
                ForEach(DockBadgeMode.allCases) { mode in
                    Text(verbatim: mode.title).tag(mode)
                }
            }
            // Segmentovaný, ne `radioGroup` jako pohled na diff: jsou to tři krátká slova na jedné
            // ose od „nejvíc“ k „nic“, takže je vidět celá škála naráz — tak je to i v návrhu.
            .pickerStyle(.segmented)
        } header: {
            Text("Odznak v Docku")
        } footer: {
            // Musí být napsané, že **nula se nekreslí**: jinak prázdná dlaždice vypadá jako
            // rozbitý odznak, kdežto je to dobrá zpráva.
            Text(
                "`čekající` je počet cizích PR ve frontě, tedy totéž číslo, co má odznak fronty v railu — včetně toho, že se schová, co schoval filtr. `blokující` počítá z těch samých PR jen ta, na kterých leží platný blokující nález, takže nikdy nevyjde větší. Vypnuto znamená prázdný odznak, ne nulu — a nula se nekreslí ani u zapnutého: prázdná fronta je dobrá zpráva, ne položka k vyřízení. Totéž prázdno je na dlaždici, dokud nedorazí první seznam; rozliší to stavový řádek v okně. Vlastní PR se do odznaku nepočítají, ty mají v railu svůj."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Přihlašovací položka. **Věta pod přepínačem je vždycky**, ne jen v poruše: u zašedlého říká
    /// proč, u zapnutelného kam se to zapisuje. Rozhoduje o ní `Policy.loginItem`.
    private var launch: some View {
        Section {
            Toggle("Spustit po přihlášení", isOn: isOn)
                .disabled(!row.isEnabled)
                .opacity(row.isEnabled ? 1 : Self.disabledOpacity)
            // Odskok je **další krok**, ne dekorace: zákaz v Nastavení systému aplikace nezvrátí,
            // takže `register()` znovu by nepomohl. Vzor z #414.
            if row.offersSystemSettings {
                Button("Otevřít Nastavení systému") { SystemSettings.openLoginItems() }
                    .controlSize(.small)
            }
        } header: {
            Text("Spuštění")
        } footer: {
            Text(verbatim: row.note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var row: Policy.LoginItemRow { store.loginItem }

    /// Poloha jde **ze systému** (přes `Policy.loginItem`), zápis do systému. Není to `@State`:
    /// druhá kopie by po ručním vypnutí v Nastavení systému ukazovala opak toho, co platí.
    private var isOn: Binding<Bool> {
        Binding(
            get: { row.isOn },
            set: { store.setLoginItem($0) }
        )
    }
}
