import SwiftUI

/// Věta nad seznamem, který se nepovedlo načíst **znovu** — takže to, co je pod ní, je poslední
/// známý stav, ne dnešní (#215 pro kontroly, #316 pro commity).
///
/// **Jedno místo pro obojí.** Do #316 to byla dvojice skoro shodných funkcí v `PullRequestDetailView`;
/// dvě kopie téže věty znamenají, že se příští úprava (barva, umístění tlačítka, formulace) udělá
/// jen v jedné — a v okně pak stojí dvě „skoro stejné“ hlášky o téže situaci.
///
/// Dvě věci, na kterých stojí:
///
/// - **Sedí nad `ScrollView`em**, ne v něm: věta o tom, že obsah pod ní může být zastaralý, nesmí
///   odscrollovat pryč od obsahu, o kterém mluví. Zajišťuje to volající tím, kam ji dá.
/// - **Okrová, ne červená.** Je to cizí fakt, který se nepovedlo **zjistit** — tedy „nevím“, ne
///   „je to rozbité“.
struct StaleNoticeView: View {
    /// Celá věta, i s textem od `gh`. Ten **zůstává, jak přišel**: je to jediné, z čeho se pozná,
    /// co dělat dál.
    let text: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(text, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Palette.stale)
                .fixedSize(horizontal: false, vertical: true)
            // Tlačítko **hned za větou**, ne u pravé hrany: u širokého okna by mezi nimi zbylo
            // půl obrazovky a přestalo by být vidět, k čemu ta akce je.
            Button("Zkusit znovu", action: retry)
                .font(.caption)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}
