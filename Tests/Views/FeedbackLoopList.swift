import SwiftUI

/// **Kontrola měřidla k #361**: seznam, který se chvíli neusazuje.
///
/// Sonda `IdleDiffSpinProbe` tvrdí, že po projetí konverzace v okně nezůstane kolo rozvržení
/// (0,00 % CPU). Taková nula je ale k nerozeznání od sondy, která smyčku **nevidí** — a přesně
/// to se u #375 stalo měřidlu na pružnou výšku. Tenhle seznam je proto ten druhý konec: každý
/// řádek si přečte svou výšku a zapíše ji do stavu tak, že ji tím změní, takže si rozvržení
/// říká o další kolo. Je to tatáž třída chyb, jakou #361 hledá v aplikaci (zpětná vazba
/// z rozvržení do stavu, #358), jen napsaná schválně.
///
/// **Zpětná vazba je záměrně ohraničená rozpočtem kol** a je to poučení z první verze: bez
/// rozpočtu se okno sondy nedalo zavřít ani ukončit a musela ho zabít ruka u stroje, na kterém
/// se zrovna pracovalo. Ohraničená smyčka doběhne sama do sekundy — a měřidlu to stačí, protože
/// se čte **první úsek proti pozdějšímu**: dokud se krmí, hoří, a jak přestane, spadne na nulu.
/// Co tím tedy **není** ověřené: že sonda uvidí kolo, které nikdy nedoběhne.
///
/// **Není to test aplikace** — v `App/` nic takového není a být nemá. Je to kontrolní scéna,
/// bez které by číslo z té sondy neneslo informaci.
struct FeedbackLoopList: View {
    /// Kolikrát se řádek smí nakrmit vlastní výškou. Rozpočet je **pojistka proti zaseknutému
    /// oknu**, ne parametr scénáře — ale musí být dost velký na to, aby kolo přežilo první
    /// měřený úsek: se 120 koly bylo z něj 4,24 % za dvě sekundy, tedy poznat, ale málo;
    /// s 1200 je to zřetelné a doběhne to i tak samo.
    var budget = 1200

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<40, id: \.self) { index in
                    FeedbackLoopRow(index: index, budget: budget)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FeedbackLoopRow: View {
    let index: Int
    let budget: Int
    /// Odsazení, které se dopočítává z **vlastní** výšky řádku. Kdyby se zapisovala hodnota,
    /// která se ustálí, kolo by se zavřelo jednou a zmizelo.
    @State private var padding: Double = 0
    @State private var rounds = 0

    var body: some View {
        Text(verbatim: "Řádek \(index)")
            .padding(.bottom, padding)
            .onGeometryChange(for: Double.self) { proxy in
                proxy.size.height
            } action: { height in
                guard rounds < budget else { return }
                rounds += 1
                padding = height.truncatingRemainder(dividingBy: 7) + 1
            }
    }
}
