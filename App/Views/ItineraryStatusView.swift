import SwiftUI

/// Průběh review ve stavovém řádku (#507, `.sitem plain`) — `Krok 4 z 9 · 12 min`.
///
/// **Odpovídá na jinou otázku než sloupec vedle diffu.** Itinerář říká, *co* zbývá; tenhle údaj
/// je tu proto, aby šlo rozhodnout, jestli review dodělat teď, nebo zítra — tedy kolik z toho je
/// za mnou a jak dlouho už to trvá. Proto stojí v pruhu, kde jsou stavy prostředí, a ne
/// v hlavičce PR.
///
/// **Minuty jsou uplynulé, ne zbývající**, a je to vědomý rozdíl proti hlavičce sloupce
/// (`Itinerář · 4 z 11 · 10 min` je odhad, co zbývá). Aby se ty dva údaje nepletly, začíná pruh
/// slovem `Krok` a celá věta stojí v nápovědě.
///
/// Tichá, bez kapsle (`plain`), jako stav pracovní kopie vedle: je to běžný stav, ne upozornění.
/// Kreslí se jen nad otevřeným pull requestem — na domácí záložce není o čí dráze mluvit.
struct ItineraryStatusView: View {
    let store: AppStore

    var body: some View {
        if case .pullRequest(let id) = store.activeTab {
            content(for: id)
        }
    }

    /// **Počítadlo se skládá tou samou cestou jako v hlavičce sloupce** (`AppStore` →
    /// `Policy.itinerary`), ne z druhé kopie: dvě odpovědi na jednu otázku by se rozešly při
    /// první úpravě zastávek. Že se skládá i tady, je **vlastní view a ne řádek ve
    /// `StatusBarView`** — sledují se vlastnosti store, které čte, takže se překresluje tenhle
    /// jeden `Text`, ne celý pruh s frontou, útratou a puntíky.
    @ViewBuilder private func content(for id: PRIdentifier) -> some View {
        let progress = store.itineraryProgress(for: id)
        if let openedAt = store.tabOpenedAt(id) {
            // **Vlastní takt, ne přepočet okna** (tatáž úvaha jako `DashboardCountdown`, #260):
            // `TimelineView` překreslí jeden `Text`, ne stavový řádek s frontou a puntíky. Rozvrh
            // je ukotvený **v otevření záložky**, takže minuta přeskočí přesně na celé minutě
            // otevřeného tabu, ne o zlomek vteřiny vedle.
            TimelineView(Self.schedule(from: openedAt)) { context in
                label(progress, openedAt: openedAt, at: context.date)
            }
        } else {
            // Bez času otevření se minuty nepíšou a není co odtikávat — statický text.
            label(progress, openedAt: nil, at: store.time.now)
        }
    }

    @ViewBuilder private func label(
        _ progress: ItineraryProgress,
        openedAt: Date?,
        at now: Date
    ) -> some View {
        if let text = Policy.itineraryStatus(progress: progress, openedAt: openedAt, now: now) {
            Text(verbatim: text)
                .font(.caption)
                .foregroundStyle(Palette.ink2)
                .monospacedDigit()
                .help(Self.help)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Průběh review")
                .accessibilityValue(text)
        }
    }

    /// Takt po minutě, ukotvený v otevření záložky — vlastní funkce, aby si ji mohl přečíst test
    /// (tatáž úvaha jako u `DashboardCountdown.schedule`).
    nonisolated static func schedule(from openedAt: Date) -> PeriodicTimelineSchedule {
        PeriodicTimelineSchedule(from: openedAt, by: 60)
    }

    /// **Že se čas neodečítá, musí být v nápovědě**: bez toho vypadá `40 min` nad záložkou
    /// otevřenou přes oběd jako tvrzení o odvedené práci.
    static let help = """
        Kolik zastávek itineráře je hotových a jak dlouho je záložka otevřená.
        Čas běží od otevření a nečinnost se z něj neodečítá — je to orientace, ne měření práce.
        """
}
