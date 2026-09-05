import SwiftUI

/// Nabídka `Odložit` nad řádkem fronty (#512).
///
/// **Jeden obsah, dvě cesty k němu**: pravé tlačítko na řádku (`.contextMenu`) a tlačítko, které
/// se v řádku objeví pod kurzorem. Kdyby si každá skládala položky po svém, byly by to dvě
/// nabídky, které se rozejdou první změnou.
///
/// **`Vlastní datum…` tu není.** Hotové volby pokrývají to, co člověk zadá v devíti případech
/// z deseti; kalendář v kontextové nabídce znamená druhý překryv nad prvním a je to vlastní
/// obrazovka. Je to **zapsaná mezera proti zadání issue**, ne opomenutí — `na týden` je nejdelší
/// nabídnutý odklad a delší se dá složit dvojím odložením.
struct SnoozeMenuItems: View {
    /// Co nabídnout. Skládá `Policy.snoozeOffers(now:)` — kresba o čase ani o klávesách
    /// nerozhoduje.
    let offers: [SnoozeOffer]
    let snooze: (SnoozeCondition) -> Void

    var body: some View {
        ForEach(offers) { offer in
            Button(offer.title) { snooze(offer.condition) }
                // **Klávesa platí uvnitř otevřené nabídky**, ne v okně: `⌥1` zaregistrované
                // oknem by přebilo psaní v každém textovém poli. Do katalogu `WindowShortcut`
                // proto nepatří (viz `SnoozeOffer.key`), a rozhodnutá je přesto v `Policy`.
                .keyboardShortcut(KeyEquivalent(offer.key), modifiers: .option)
        }
    }
}

/// Tlačítko `Odložit` v řádku fronty — nabídka pod kurzorem (#512).
///
/// **Kreslí se jen pod kurzorem**, aby řádek ve fronte deseti PR nenesl deset tlačítek: odložení
/// je věc, kterou dělám jednou za čas, kdežto řádek čtu pořád. `.onHover`, ne
/// `onContinuousHover` — je to `Bool` na vstup i na výstup, takže bezpodmínečný zápis z každého
/// snímku (#358) tady vzniknout nemůže.
struct SnoozeRowButton: View {
    let offers: [SnoozeOffer]
    let snooze: (SnoozeCondition) -> Void

    var body: some View {
        Menu {
            SnoozeMenuItems(offers: offers, snooze: snooze)
        } label: {
            Image(systemName: "alarm")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Palette.ink3)
        .help("Odložit — zmizí z fronty, dokud se nesplní podmínka")
        .accessibilityLabel("Odložit")
    }
}
