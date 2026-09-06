import SwiftUI

/// Co řádek umí s odložením (#512) — **nabídka a akce v jedné hodnotě**.
///
/// Vzniklo z proklikání: nabídka byla navěšená jedině ve `PullRequestListView`, jenže `PullRequestRow`
/// se kreslí na **třech** místech (fronta, sekce `Rozdělaná`, deska), takže na dvou z nich
/// `Odložit` nebylo — a přitom na desce stojí věta `· 2 odložené`. Dva parametry, které se musí
/// předat oba a na každém místě zvlášť, jsou zrovna ten tvar, na který se zapomíná; jedna hodnota
/// z jednoho místa (`AppStore.snoozeAction(for:)`) se zapomenout dá taky, ale **je to vidět**
/// a hlídá to stráž nad zdrojáky (`PullRequestRowSnoozeWiringTests`).
///
/// **Rozhodnutí „smí se odložit“ zůstává v `Policy.canSnooze`**, ne tady: tahle hodnota ho jen
/// **nese** — u vlastního PR přijde prázdná nabídka, takže se `Odložit` nenakreslí vůbec.
struct SnoozeAction {
    /// Co nabídnout. Prázdné = řádek `Odložit` nemá (vlastní PR).
    let offers: [SnoozeOffer]
    let snooze: (SnoozeCondition) -> Void

    /// Má se `Odložit` kreslit? **Prázdná nabídka znamená nic, ne zašedlé tlačítko** — tatáž
    /// úvaha, kvůli které se v #333 přestala kreslit zakázaná `Prompt →`.
    var isAvailable: Bool { !offers.isEmpty }
}

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
    let action: SnoozeAction

    var body: some View {
        Menu {
            SnoozeMenuItems(offers: action.offers, snooze: action.snooze)
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
