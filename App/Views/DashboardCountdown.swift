import SwiftUI

/// Odpočet do příštího tiku v hlavičce dashboardu — `za 43s znovu` (#260).
///
/// **Mezera mezi číslem a jednotkou tam není, a je to vědomá odchylka od české typografie** (ta ji
/// mezi číslem a jednotkou chce). Je to výslovné přání uživatele nad jeho osobním nástrojem, takže
/// tady rozhoduje, jak to má vypadat, ne norma — a taky vědomá odchylka od mockupu, který má
/// `za 43 s znovu`. Ať to stojí zapsané, aby to příště nikdo „neopravil“ zpátky.
///
/// **Formát je proto náš, ne systémový** (mění část #237). Do #260 kreslil odpočet
/// `Text(_:style: .relative)`, jehož řetězec skládá systém — a v české locale je v něm mezera,
/// kterou z něj nejde vyndat: `43 s`, `12 min, 29 s`. Změřeno na všech čtyřech šířkách
/// `Duration.UnitsFormatStyle` i na `DateComponentsFormatter`u; mezeru má každá z nich.
///
/// Vlastní formát znamená vlastní takt, a ten dává `TimelineView`. Rozhodnutí z #237 („za odpočet
/// se neplatí přepočtem dashboardu“) tím **drží**: `TimelineView` přepočítává jen svůj obsah, tedy
/// tenhle jeden krátký `Text`, ne tabulku, sparkline a frontu nad ním. Ověřeno sondou
/// v `DashboardCountdownRedrawTests`, která přepočty těla počítá.
///
/// **Ne `RunUsageText`**, přestože i tam se formátuje čas: `duration(_:)` je změřené trvání
/// doběhlého běhu (`2 m 5 s`, systémový formát včetně mezery) a `elapsed(_:)` jsou stopky, které
/// jdou nahoru (`1:12`). Odpočet je třetí věc — jde dolů, končí v nule a mezeru mít nesmí — takže
/// by se do jednoho z nich vešel jen tak, že by se ten typ rozdvojil.
struct DashboardCountdown: View {
    /// Kdy se polling zeptá znovu (`PollState.nextPoll`). Že je v budoucnosti, rozhoduje
    /// `DashboardTick` — uplynulý termín je `ptám se…`, ne odpočet.
    let deadline: Date

    var body: some View {
        TimelineView(Self.schedule(until: deadline)) { context in
            Text(verbatim: Self.label(until: deadline, at: context.date))
        }
    }

    /// Takt odpočtu — po vteřině, ukotvený **v termínu**, ne v `.now`.
    ///
    /// Ukotvení rozhoduje o tom, kde padnou hranice tiků: od termínu vyjdou přesně na celých
    /// vteřinách zbývajícího času (změřeno na `entries` — od `now` vrací termín − 43,0 s,
    /// − 42,0 s, …), kdežto od `.now` by byly posunuté o zlomek vteřiny a s nimi i každá
    /// zobrazená hodnota. Vlastní funkce proto, že si to takhle může přečíst test — jinak by
    /// rozvrh byl schovaný v těle, kde se dá ověřit jedině okem.
    nonisolated static func schedule(until deadline: Date) -> PeriodicTimelineSchedule {
        PeriodicTimelineSchedule(from: deadline, by: 1)
    }

    /// Celá věta odpočtu — `za 43s znovu`.
    ///
    /// Slova jsou tady schválně **s číslem v jedné funkci**: do #260 se text skládal ze tří
    /// `Text`ů (`… · za ` + odpočet + ` znovu`) a mezera, o kterou v tom issue jde, tak ležela
    /// mezi dvěma z nich. Co je vidět v jednom řetězci, se dá otestovat výčtem.
    ///
    /// `at` je „teď“ zvenčí, aby se text dal vyčerpat testem — tatáž úvaha jako u popisku pruhu
    /// běhu (`ReviewRunbarView.label`).
    nonisolated static func label(until deadline: Date, at now: Date) -> String {
        "za \(amount(deadline.timeIntervalSince(now))) znovu"
    }

    /// Kolik zbývá: `43s`, `1min`, `12min 29s`, `1h 5min`.
    ///
    /// **Dvě jednotky nejvýš a nulová spodní se vynechává** — tolik informace nesl i systémový
    /// formát (`12 min, 29 s`), takže se odstraněním mezery nemá co ztratit. Minuty unese backoff
    /// při rate limitu (roste do 15 minut), hodiny strop intervalu v nastavení (3600 s).
    ///
    /// **Zaokrouhluje se, nekrátí:** rozvrh tiká přesně na celých vteřinách odpočtu, ale časovač
    /// se probouzí vždycky o kousek **později**, takže `Int(0,998)` by z poslední vteřiny udělalo
    /// `0s` a jedna hodnota by se přeskočila.
    ///
    /// **Záporný čas je nula, ne `-3s`** ani odpočet obrácený nahoru. `DashboardTick` uplynulý
    /// termín do odpočtu nepustí, ale tělo view se mezi tiky nepřepočítává — po probuzení stroje
    /// tedy termín uplyne pod rukama a `0s` je to poslední, co se smí ukázat, než se stav překlopí
    /// na `ptám se…` (tatáž úvaha jako u #237, kde `za 0 s` na obrazovce taky byla).
    ///
    /// Strop je tam kvůli `Int(_:)`, které na přetečení **spadne**: interval má v nastavení strop
    /// hodinu, takže se k němu normální provoz nedostane, ale okno se nemá položit ani kvůli
    /// hodnotě z ručně upraveného `config.json`.
    private nonisolated static func amount(_ remaining: TimeInterval) -> String {
        let total = Int(min(max(remaining, 0), longestCountdown).rounded())
        guard total >= 60 else { return "\(total)s" }
        guard total >= 3600 else {
            let seconds = total % 60
            return seconds == 0 ? "\(total / 60)min" : "\(total / 60)min \(seconds)s"
        }
        let minutes = (total % 3600) / 60
        return minutes == 0 ? "\(total / 3600)h" : "\(total / 3600)h \(minutes)min"
    }

    /// Nejdelší odpočet, který se ještě vypíše (`za 99h znovu`). Přes tuhle hodnotu už jde jen
    /// nesmyslná konfigurace, a u té je useknutý údaj lepší než pád.
    private static let longestCountdown: TimeInterval = 99 * 3600 + 59 * 60 + 59
}

#Preview {
    VStack(alignment: .trailing, spacing: 6) {
        DashboardCountdown(deadline: .now.addingTimeInterval(43))
        DashboardCountdown(deadline: .now.addingTimeInterval(750))
        DashboardCountdown(deadline: .now.addingTimeInterval(3600))
    }
    .font(.system(size: 11, design: .monospaced))
    .padding()
}
