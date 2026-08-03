import SwiftUI

/// Číslo v nastavení: **šipky i přepsání**.
///
/// Samotný `Stepper` nutí doklikat se z 60 na 600 po jedné, samotné textové pole zase nutí
/// psát i tam, kde se mění o krok. Obojí vedle sebe je to, co dělá macOS všude jinde.
///
/// Popisky u pole i šipek zůstávají **vyplněné** a schovávají se `.labelsHidden()`: skryje
/// jen zobrazení, pro VoiceOver je to pořád jediný popis ovládacího prvku.
struct SettingsNumberField: View {
    let label: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                // `grouping(.never)`: v editovatelném poli je „10 240“ na obtíž.
                TextField(label, value: bounded, format: .number.grouping(.never))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                Stepper(label, value: bounded, in: range, step: step)
                    .labelsHidden()
            }
        }
    }

    /// Hodnota oříznutá na povolený rozsah.
    ///
    /// `Stepper` sám za hranici nepustí, ale **textové pole ano** — a přepsaný rozpočet na
    /// `-5` nebo interval na nulu by se propsal do konfigurace a odtud do chování aplikace.
    private var bounded: Binding<Int> {
        Binding(
            get: { min(max(value, range.lowerBound), range.upperBound) },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }
        )
    }
}
