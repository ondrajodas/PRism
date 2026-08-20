import SwiftUI

/// Nadpis nabídky — **místo, kde se sloveso říká jednou** (#392).
///
/// Do proklikání ho nesla každá položka (`Vyžádat review od …`), což u čtrnácti řádků opakovalo
/// totéž a ořezalo jméno, kvůli kterému se do nabídky kouká. Nadpis je proti tomu jedna řádka
/// a čte se s položkou jako věta.
struct PickerHeading: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: 10, design: .monospaced))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(Palette.ink3)
            .padding(.horizontal, 11)
            .padding(.top, 9)
            .padding(.bottom, 6)
    }
}
