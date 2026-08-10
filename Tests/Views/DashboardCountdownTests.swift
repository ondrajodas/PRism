import SwiftUI
import Testing

@testable import PRism

/// Text odpočtu v hlavičce dashboardu (#260) — čistá funkce nad termínem a hodinami, takže se dá
/// vyčerpat výčtem bez kreslení.
///
/// **Nejcennější tvrzení je to o mezeře**: `za 43s znovu`, ne `za 43 s znovu`. Systémový formát,
/// který tam do #260 byl (`Text(_:style: .relative)`), mezeru v české locale má a nejde z něj
/// vyndat — proto se tady kontroluje celá věta, ne jen číslo.
@Suite("Text odpočtu příštího tiku")
struct DashboardCountdownTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func label(_ remaining: TimeInterval) -> String {
        DashboardCountdown.label(until: now.addingTimeInterval(remaining), at: now)
    }

    // MARK: - Vteřiny

    @Test("Vteřiny se lepí na číslo bez mezery")
    func secondsSitOnTheNumber() {
        #expect(label(43) == "za 43s znovu")
    }

    @Test("Jedna vteřina se od ostatních formátem neliší")
    func oneSecondLooksLikeTheRest() {
        #expect(label(1) == "za 1s znovu")
    }

    @Test("Poslední vteřina pod minutou je pořád ve vteřinách")
    func justUnderAMinuteStaysInSeconds() {
        #expect(label(59) == "za 59s znovu")
    }

    /// Časovač se probouzí vždycky o kousek **později**, než na kdy je rozvrh naplánovaný, takže
    /// zbývající čas vyjde `0,998` tam, kde má stát `1s`. Krácení na celé by z toho udělalo `0s`
    /// a jedna hodnota by se v odpočtu přeskočila.
    @Test("Zaokrouhluje se, nekrátí — pozdě probuzený časovač vteřinu nepřeskočí")
    func lateTimerDoesNotSkipASecond() {
        #expect(label(0.998) == "za 1s znovu")
        #expect(label(42.6) == "za 43s znovu")
    }

    // MARK: - Minuty a hodiny

    /// Nulová spodní jednotka se vynechává, stejně jako ji vynechával systémový formát
    /// (`1 min`, ne `1 min, 0 s`).
    @Test("Celá minuta je jen minuta")
    func wholeMinuteDropsTheSeconds() {
        #expect(label(60) == "za 1min znovu")
    }

    @Test("Nad minutu se píšou dvě jednotky, každá u svého čísla")
    func aboveAMinuteTwoUnits() {
        #expect(label(90) == "za 1min 30s znovu")
        #expect(label(750) == "za 12min 30s znovu")
    }

    /// Backoff po rate limitu roste do 15 minut, takže tohle je hodnota, kterou formát musí unést
    /// v provozu — ne teoretický okraj.
    @Test("Minutový backoff unese i těsně pod stropem")
    func rateLimitBackoffFits() {
        #expect(label(899) == "za 14min 59s znovu")
        #expect(label(900) == "za 15min znovu")
    }

    /// Interval pollingu se v nastavení dá vytáhnout na 3600 s, takže hodina není teorie.
    @Test("Strop intervalu v nastavení vyjde v hodinách")
    func settingsCeilingUsesHours() {
        #expect(label(3600) == "za 1h znovu")
        #expect(label(3599) == "za 59min 59s znovu")
        #expect(label(3661) == "za 1h 1min znovu")
    }

    // MARK: - Nula a to, co je za ní

    /// `DashboardTick` uplynulý termín do odpočtu nepustí, ale tělo view se mezi tiky
    /// nepřepočítává — po probuzení stroje tedy termín uplyne pod rukama. `-3s` ani odpočet
    /// obrácený nahoru se na tom místě ukázat nesmí.
    @Test("Uplynulý termín je nula, ne záporné číslo")
    func pastDeadlineClampsToZero() {
        #expect(label(0) == "za 0s znovu")
        #expect(label(-3) == "za 0s znovu")
        #expect(label(-28_800) == "za 0s znovu")
    }

    /// Druhý konec téhož: `Int(_:)` na přetečení **spadne**, takže nesmyslná hodnota z ručně
    /// upraveného `config.json` nesmí položit okno. Useknutý údaj je lepší než pád.
    @Test("Nesmyslně dlouhý termín se usekne, ne aby spadl")
    func absurdDeadlineIsCapped() {
        #expect(label(.greatestFiniteMagnitude) == "za 99h 59min znovu")
    }

    // MARK: - Mezera, kvůli které to vzniklo

    /// **Tvrzení o tom, co se nestane**, a přes celý rozsah, ve kterém se odpočet umí pohybovat:
    /// za číslem nikdy nestojí mezera. Jednotlivé případy výš by přehlédly hodnotu, u které by se
    /// mezera vrátila jen v jedné větvi formátu.
    @Test("Za číslem nikdy nestojí mezera, ať je odpočet jakkoli dlouhý")
    func noValuePutsASpaceAfterTheNumber() {
        for seconds in stride(from: -5, through: 7200, by: 7) {
            let text = label(TimeInterval(seconds))
            #expect(
                text.range(of: #"\d\s"#, options: .regularExpression) == nil,
                "\(seconds) s dalo „\(text)“"
            )
        }
    }

    // MARK: - Rozvrh tiků

    /// Rozvrh je ukotvený **v termínu**, ne v `.now`, a je to ten důvod, proč hranice tiků padnou
    /// přesně na celé vteřiny zbývajícího času. Ukotvení v `.now` by je posunulo o zlomek vteřiny
    /// (`43,4 s`, `42,4 s`, …) a s ním i každou zobrazenou hodnotu — proto se rozvrh čte
    /// z komponenty, ne skládá v testu.
    ///
    /// Termín je půl vteřiny „mimo“ (`43,4`) schválně: nad celým číslem by test prošel i s ukotvením
    /// v `.now`.
    @Test("Tiky padnou na celé vteřiny odpočtu")
    func ticksLandOnWholeSeconds() {
        let deadline = now.addingTimeInterval(43.4)
        let entries = DashboardCountdown.schedule(until: deadline).entries(from: now, mode: .normal)

        let remaining = entries.prefix(3).map { (deadline.timeIntervalSince($0) * 1_000).rounded() / 1_000 }

        #expect(remaining == [43, 42, 41])
    }

    /// A totéž zobrazené: každá vteřina se v odpočtu ukáže právě jednou.
    @Test("Sousední tiky ukážou sousední vteřiny")
    func consecutiveTicksShowConsecutiveSeconds() {
        let deadline = now.addingTimeInterval(43.4)
        let entries = DashboardCountdown.schedule(until: deadline).entries(from: now, mode: .normal)

        let shown = entries.prefix(3).map { DashboardCountdown.label(until: deadline, at: $0) }

        #expect(shown == ["za 43s znovu", "za 42s znovu", "za 41s znovu"])
    }
}
