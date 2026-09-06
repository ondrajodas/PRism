import Foundation

extension Policy {
    // MARK: - Okno

    /// Dá se podle těchhle pravidel vůbec odkládat? (#519)
    ///
    /// **Nesmyslné nastavení automat nezastaví, jen odklad vypne.** Ručně editovaný `config.json`
    /// umí mít hodinu 25 nebo práh −1; brát to vážně by znamenalo počítat `nextDate` nad
    /// komponentami, které žádný okamžik nesplňuje — tedy PR odložený na `nil`, což je v kódu
    /// „nikdy“. Bezpečná strana je stejná jako všude jinde v automatu: **pusť to**.
    ///
    /// **Stejný začátek jako konec je prázdné okno, ne celý den.** Obě čtení jdou obhájit, ale
    /// tohle je to, které se dá poznat: `22`–`22` znamená, že si někdo nedopsal konec, a odklad,
    /// který by z toho udělal „ticho pořád“, by review zastavil úplně a vypadalo by to jako
    /// porucha automatu.
    static func quietHoursAreUsable(_ rules: QuietHours) -> Bool {
        guard rules.isEnabled, rules.lineThreshold > 0 else { return false }
        guard (0..<24).contains(rules.startHour), (0..<24).contains(rules.endHour) else { return false }
        return rules.startHour != rules.endHour
    }

    /// Je tenhle okamžik v tichých hodinách? (#519)
    ///
    /// **Okno umí přejít přes půlnoc, a je to ten běžný případ.** `22:00–6:00` napsané naivně jako
    /// `hour >= 22 && hour < 6` je **vždycky** nepravda, takže by se nikdy nic nepustilo a odložené
    /// běhy by se hromadily do rána, které nikdy nepřijde. Rozhodují proto dvě větve podle toho,
    /// jestli je konec za začátkem, nebo před ním.
    ///
    /// **Hodina se bere z kalendáře, ne z `timeIntervalSince1970`.** Den má na přechodu letního
    /// času 23 nebo 25 hodin a půlnoc není každých 86 400 s; počítat okno modulem by na tom dni
    /// posunulo hranici o hodinu.
    ///
    /// - Parameter calendar: parametr, ne `Calendar.current` uvnitř — `current` nese časové pásmo
    ///   stroje, takže by se test v jiné zóně rozešel s tím, co se počítá v okně. Tentýž kořen jako
    ///   globální stav procesu v `Tests/` (#367), a tatáž volba jako u `Policy.snoozeMorning`.
    static func quietHours(contain moment: Date, rules: QuietHours, calendar: Calendar = .current) -> Bool {
        guard quietHoursAreUsable(rules) else { return false }
        let hour = calendar.component(.hour, from: moment)
        guard rules.startHour > rules.endHour else {
            return hour >= rules.startHour && hour < rules.endHour
        }
        return hour >= rules.startHour || hour < rules.endHour
    }

    /// Nejbližší začátek tichých hodin po tomhle okamžiku (#519). `nil` = neodkládá se.
    ///
    /// **`Calendar.nextDate`, ne „dnešek plus 86 400“.** Na přechodu letního času má den 23 nebo 25
    /// hodin, takže přičtený interval mine celou hodinu — a když hodina, na kterou se míří, ten den
    /// **vůbec neexistuje** (jarní posun přeskočí 2:00–3:00), musí být odpovědí ta nejbližší další,
    /// ne `nil`. Obojí vyřídí `matchingPolicy: .nextTime`.
    ///
    /// **Ostře po** `moment`: kdyby vrátil týž okamžik, byl by odložený běh naplánovaný na chvíli,
    /// ve které se právě rozhodlo, že se nemá pustit.
    static func nextQuietHours(
        after moment: Date,
        rules: QuietHours,
        calendar: Calendar = .current
    ) -> Date? {
        guard quietHoursAreUsable(rules) else { return nil }
        return calendar.nextDate(
            after: moment,
            matching: DateComponents(hour: rules.startHour, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
    }

    // MARK: - Rozhodnutí

    /// Má automat tenhle běh odložit do tichých hodin? (#519)
    ///
    /// Vrací **rozhodnutí, ne jen okamžik** (`QuietHoursDeferral`); `nil` znamená „pusť to teď“.
    /// Počet řádků a práh jdou s ním schválně: jsou to hodnoty, kterými se to rozhodlo, a volající
    /// je tak nemá kde dosadit jinak. Je to čistá funkce nad předaným `now` — hodiny se uvnitř
    /// nečtou, jinak by se ta pravidla nedala projít výčtem a sada by byla zelená jen odpoledne.
    ///
    /// Čtyři důvody, po kterých se **neodkládá**, a každý z nich je vlastní věta:
    ///
    /// 1. **Pravidla nedávají smysl nebo jsou vypnutá** (`quietHoursAreUsable`).
    /// 2. **Na PR se někdo dívá.** Otevřená záložka znamená, že člověk čeká — a čekat vedle
    ///    otevřeného diffu do desíti večer je zrovna to, kvůli čemu tohle pravidlo **není** pro
    ///    ruční spouštění. Platí to ale na **rozhodnutí, ne na vyzvednutí**: odklad, který už
    ///    padl, otevření záložky nespustí (viz `deferralsToRelease`).
    /// 3. **PR není velký.** Ostře nad prahem, takže PR přesně na prahu se pouští hned.
    ///    **Neznámý počet řádků se nepočítá za velký**: `nil` znamená, že hlavička o velikosti
    ///    nic neřekla (starší uložená data), a odložit review kvůli tomu, co nevíme, je tichá
    ///    ztráta času — tatáž bezpečná strana jako u `Policy.reviewersToRun` s neznámými cestami.
    /// 4. **Už je noc.** V tichých hodinách je tohle **ta** chvíle, na kterou se odkládá.
    ///
    /// **O rozpočtu tahle funkce nerozhoduje.** Denní limit i strop útraty platí i v noci a sahá si
    /// o ně `AppStore.canSpendSession` až v okamžiku, kdy se session opravdu utrácí — odklad není
    /// cesta, jak limit obejít, jen jak ho utratit jindy.
    ///
    /// - Parameters:
    ///   - pr: dotažený detail. **Velikost se bere z něj**, ne z diffu: u velkého PR se diff nemusí
    ///     ani stáhnout (#542), takže by se práh nedal změřit zrovna u toho, kvůli komu existuje.
    ///   - isOpen: je PR otevřený v záložce? Parametr, ne dotaz do storu — je to fakt o okně,
    ///     kdežto tady se rozhoduje nad daty.
    static func deferToQuietHours(
        pr: PullRequest,
        isOpen: Bool,
        now: Date,
        rules: QuietHours,
        calendar: Calendar = .current
    ) -> QuietHoursDeferral? {
        guard quietHoursAreUsable(rules), !isOpen else { return nil }
        guard let lines = pr.changedLines, lines > rules.lineThreshold else { return nil }
        guard !quietHours(contain: now, rules: rules, calendar: calendar) else { return nil }
        guard let runAt = nextQuietHours(after: now, rules: rules, calendar: calendar) else { return nil }
        return QuietHoursDeferral(runAt: runAt, changedLines: lines, threshold: rules.lineThreshold)
    }

    /// Odložené běhy, které se **v tomhle tiku** mají pustit (#519).
    ///
    /// **Rozhoduje jedině čas, ne otevřená záložka** — a je to vědomá odchylka od věty v zadání
    /// issue („otevření PR ruší odklad“). Otevřený PR se **neodkládá** (`deferToQuietHours`
    /// s `isOpen`), ale odklad, který už padl, otevření **nespouští**, a rozhodl o tom zákres
    /// (sekce 46): dráha `odloženo na noc` se dá vidět jedině v otevřené záložce, takže by se
    /// pod pravidlem „otevření pouští“ nedala nakreslit vůbec — `poběží 23:00` ani `Pustit teď`
    /// by se na obrazovku nikdy nedostaly. Cesta ven je proto **jedno pojmenované tlačítko**,
    /// jako `Pustit přesto` u routingu (#518). Rozbor je v `docs/architektura.md`.
    ///
    /// **Bere seznam z tiku, ne uložené odklady**, jako `Policy.snoozeProbe` (#512): odklad umí
    /// v cache ležet i po PR, které se mezitím zavřelo nebo mergnulo, a pustit review na zavřený
    /// PR je session za odpověď, kterou nikdo nepřečte. Osiřelý zápis takhle nikdy nevystřelí
    /// a ze souboru ho vyhodí lhůta v `DeferredRunStore`.
    ///
    /// **Zmeškaná noc se pouští ráno, ne odkládá na další.** Aplikace, která přes noc neběžela,
    /// najde `runAt` v minulosti — a slib „poběží ve 23:00“ se plní tím, že se to pustí, ne tím,
    /// že se posune o den. Že se to pak nesmí odložit znovu, drží `AppStore.review` parametrem
    /// `honoringQuietHours`, ne tahle funkce.
    static func deferralsToRelease(
        in pullRequests: [PullRequestSummary],
        deferred: (PRIdentifier) -> DeferredRun?,
        now: Date
    ) -> [PRIdentifier] {
        pullRequests.compactMap { summary in
            guard let run = deferred(summary.id), now >= run.runAt else { return nil }
            return summary.id
        }
    }

    // MARK: - Věty

    /// Proč se odložilo — do hlavičky dráhy (#519). Věta z návrhu, sekce 46, doslova.
    ///
    /// **Píše se, podle čeho se rozhodlo**, ne co je v nastavení dneska: práh se bere z odkladu.
    /// Jinak by věta po změně nastavení tvrdila, že 2 790 řádků přesáhlo práh, který v tu chvíli
    /// neplatil.
    static func deferralNote(_ run: DeferredRun) -> String {
        let lines = Plural.czech(run.changedLines, one: "řádek", few: "řádky", many: "řádků")
        return "\(lines) nad prahem \(run.threshold.formatted()) · nikdo na PR nečeká"
    }

    /// `poběží 23:00`, u zítřka `poběží zítra 23:00` (#519) — pravá strana hlavičky dráhy.
    ///
    /// **Den se dopisuje jen tehdy, když to není dnes.** Odklad míří nejvýš o necelý den dopředu,
    /// takže `poběží dnes 23:00` by přidalo slovo, které nic nerozlišuje. Zítřek naopak vynechat
    /// nejde: `poběží 6:00` v pět odpoledne by lhalo o půl dne. Datum je třetí větev, ne mrtvý kód:
    /// odložení leží v cache a stroj umí být týden vypnutý — a `zítra` u tří dnů starého odkladu je
    /// zrovna ten text, co tvrdí víc, než data unesou.
    ///
    /// **Zmeškaný slib se pozná** (`poběží hned`): `runAt` v minulosti znamená, že aplikace přes
    /// noc neběžela a běh čeká na nejbližší tik. Napsat tam čas, který už byl, by vypadalo jako
    /// zaseknutý odklad.
    static func deferralRunLabel(_ run: DeferredRun, now: Date, calendar: Calendar = .current) -> String {
        guard run.runAt > now else { return "poběží hned" }
        let time = run.runAt.formatted(date: .omitted, time: .shortened)
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: run.runAt)
        ).day
        switch days {
        case 0: return "poběží \(time)"
        case 1: return "poběží zítra \(time)"
        default: return "poběží \(run.runAt.formatted(date: .abbreviated, time: .omitted)) \(time)"
        }
    }
}
