import Foundation

/// Co stojí v pravém horním koutu dashboardu: kdy se to naposledy načetlo a kolik zbývá do
/// příštího tiku (#237).
///
/// **Příští tik je odpočet, ne hodina na hodinách.** Interval pollingu je minuta a při rate
/// limitu roste backoff až na patnáct, takže otázka, kvůli které se na ten údaj kouká, zní „jak
/// dlouho ještě“ — a `další tik 15:21` si na ni musí člověk odpovědět odečítáním. Do #237 tu
/// stál absolutní čas, viz záznam rozhodnutí ve specifikaci.
///
/// Vlastní typ proto, že se z hodnot skládá **view**, ne `String`: odpočet musí být samostatné
/// view (`DashboardCountdown`), které si vteřiny odtiká samo. Rozhodnutí, **co** se v tom koutu
/// píše, se pak dá vyčerpat výčtem bez kreslení.
enum DashboardTick: Equatable {
    /// Ještě se nenačetlo nic a nikdo se zrovna neptá.
    case never
    /// Načetlo se, ale příští tik naplánovaný není. V běhu je to jen chvilka po prvním
    /// úspěšném dotazu, než smyčka usne; u ručního obnovení mimo smyčku to platí trvale.
    case idle(last: Date)
    /// Odpočet k příštímu tiku. Nese **datum**, ne spočítané vteřiny — ta hodnota se ve view
    /// odtikává sama a přepočítat ji tady by znamenalo přepočítávat dashboard každou vteřinu.
    case countdown(last: Date, deadline: Date)
    /// Zrovna se ptáme. `last` je `nil`, dokud se to poprvé nepovedlo.
    case polling(last: Date?)

    /// - Parameters:
    ///   - isRefreshing: Přebíjí odpočet. Po dobu dotazu je `nextPoll` v minulosti, protože ho
    ///     smyčka zapisuje až po něm.
    ///   - now: Čas přepočtu view. Odpočet **v minulosti se neukáže** ani zápornou hodnotou, ani
    ///     zamrzlou nulou: uplynulý termín znamená, že se ptáme (typicky po probuzení stroje, kde
    ///     smyčka nabíhá se zpožděním). Do #260 by se navíc `Text(_:style:)` nad ním obrátil
    ///     a začal počítat nahoru; vlastní formát ho srazí na `0s`, tedy na tvrzení o tiku, na
    ///     který se nečeká — proto se tahle větev nesmí spolehnout na formát a musí rozhodnout sama.
    init(lastSuccess: Date?, nextPoll: Date?, isRefreshing: Bool, now: Date) {
        guard !isRefreshing else {
            self = .polling(last: lastSuccess)
            return
        }
        guard let last = lastSuccess else {
            self = .never
            return
        }
        guard let deadline = nextPoll else {
            self = .idle(last: last)
            return
        }
        self = deadline > now ? .countdown(last: last, deadline: deadline) : .polling(last: last)
    }
}
