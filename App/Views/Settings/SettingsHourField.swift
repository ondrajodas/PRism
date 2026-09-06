import SwiftUI

/// Hodina v nastavení (#519) — `0`–`23` a k tomu vidět, co to znamená.
///
/// **Vlastní pole, ne `SettingsNumberField` s rozsahem `0...23`.** Číslo samo o sobě neřekne, jestli
/// je `6` ráno nebo večer, a okno tichých hodin se přes tenhle rozdíl láme (`22`–`6` je noc,
/// `6`–`22` den). Za polem proto stojí **odvozený** čas — `22:00` —, ne napsaný vedle: dvě hodnoty
/// psané zvlášť se rozejdou první změnou kroku.
///
/// Rozsah hlídá `SettingsNumberField` (ořezává i to, co se do pole napíše), takže se sem hodnota
/// mimo `0…23` nedostane. Že by ji tam napsal ručně editovaný `config.json`, řeší
/// `Policy.quietHoursAreUsable` — odklad se tím **vypne**, review nezastaví.
struct SettingsHourField: View {
    let label: LocalizedStringKey
    @Binding var hour: Int

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                SettingsNumberField(label: label, value: $hour, range: 0...23)
                    .labelsHidden()
                Text(verbatim: Self.clock(hour))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// `22` → `22:00`. **Bez `DateFormatteru`**: je to popisek k číslu, ne okamžik — formátovat
    /// hodinu přes kalendář by na ni napasovalo dnešní datum a v zemích s dvanáctihodinovým
    /// zápisem by z `22` vyšlo `10 PM` vedle českého okna.
    static func clock(_ hour: Int) -> String {
        "\(hour):00"
    }
}
