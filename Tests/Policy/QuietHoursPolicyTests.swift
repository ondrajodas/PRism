import Foundation
import Testing

@testable import PRism

/// Tiché hodiny (#519) — rozhodnutí o tom, **kdy automat velké PR pustí**.
///
/// Vyčerpávajícím výčtem, jak se `Policy` testuje: velikost (pod prahem / na prahu / nad ním)
/// × okno (v tichých hodinách / mimo) × záložka (otevřeno / neotevřeno). K tomu **přechod přes
/// půlnoc** a **změna letního času** — obojí je vlastní případ, ne varianta: naivní
/// `hour >= 22 && hour < 6` je vždycky nepravda a naivní `+86 400` mine na přechodu celou hodinu.
///
/// Cenná polovina jsou tvrzení o tom, co se **nestane**: že se pod prahem neodkládá, že otevřený
/// PR se neodkládá vůbec, že otevřená záložka odložený běh sama **nespouští** a že nesmyslné okno
/// odklad **vypne** místo aby review zastavilo. Ani jedno není z obrazovky poznat — odložený běh
/// vypadá jako běh, na který ještě nedošlo.
@Suite("Policy — tiché hodiny (#519)")
struct QuietHoursPolicyTests {
    private let pr = PRIdentifier("cli/cli#1")!

    /// Kalendář s **pevnou zónou**: `Calendar.current` nese zónu stroje, takže by se test v jiné
    /// zóně rozešel s tím, co se počítá v okně (#367 — globální stav procesu).
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    /// Okamžik v místním čase pevné zóny. Skládá se z komponent, ne z `timeIntervalSince1970`:
    /// „22:00 na den, kdy se mění čas“ se přes vteřiny od roku 1970 napsat nedá.
    private func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private var rules: QuietHours {
        QuietHours(isEnabled: true, lineThreshold: 1500, startHour: 22, endHour: 6)
    }

    private func pullRequest(lines: Int?) -> PullRequest {
        PullRequest(
            id: pr,
            title: "velké PR",
            author: "autor",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/1")!,
            updatedAt: moment(2026, 9, 6, 12),
            state: .open,
            changedLines: lines
        )
    }

    private func decide(
        lines: Int?,
        at hour: Int,
        isOpen: Bool = false,
        rules: QuietHours? = nil
    ) -> QuietHoursDeferral? {
        Policy.deferToQuietHours(
            pr: pullRequest(lines: lines),
            isOpen: isOpen,
            now: moment(2026, 9, 6, hour),
            rules: rules ?? self.rules,
            calendar: calendar
        )
    }

    // MARK: - Výčet: velikost × okno × záložka

    @Test("Nad prahem, mimo tiché hodiny a bez otevřené záložky se odkládá")
    func defersALargePullRequestDuringTheDay() {
        let decision = decide(lines: 2790, at: 15)
        #expect(decision?.runAt == moment(2026, 9, 6, 22))
        // **Počet řádků i práh jdou z rozhodnutí**, aby si je záznam odkladu nemusel dobírat sám —
        // `?? 0` u počtu řádků by v okně stálo jako `0 řádků nad prahem 1 500`.
        #expect(decision?.changedLines == 2790)
        #expect(decision?.threshold == 1500)
    }

    /// Práh je **hranice velkého PR, ne jeho první hodnota** — `nad 1 500` znamená 1 501.
    @Test("Přesně na prahu se nic neodkládá", arguments: [1499, 1500])
    func doesNotDeferAtOrBelowTheThreshold(lines: Int) {
        #expect(decide(lines: lines, at: 15) == nil)
    }

    @Test("O řádek nad prahem se odkládá")
    func defersOneLineAboveTheThreshold() {
        #expect(decide(lines: 1501, at: 15) != nil)
    }

    /// V noci je **tohle** ta chvíle, na kterou se odkládá — druhý odklad by review nepustil nikdy.
    @Test("V tichých hodinách se neodkládá, ať je PR jakkoli velké", arguments: [23, 0, 5])
    func runsInsideTheWindow(hour: Int) {
        #expect(decide(lines: 100_000, at: hour) == nil)
    }

    /// **Rozhoduje se to při odkládání, ne při vyzvedávání**: PR, který mám na obrazovce, se
    /// neodloží vůbec. Odklad, který už padl, otevření záložky **nespustí** — viz
    /// `anOpenTabDoesNotRelease` níž.
    @Test("Otevřený PR se neodkládá")
    func anOpenTabPreventsTheDeferral() {
        #expect(decide(lines: 2790, at: 15, isOpen: true) == nil)
    }

    /// Bezpečná strana je „pusť to“: odložit review kvůli tomu, co nevíme, je tichá ztráta času.
    /// Tatáž strana jako u neznámých cest v routingu (#518).
    @Test("Neznámý počet řádků se za velký nepočítá")
    func unknownSizeDoesNotDefer() {
        #expect(decide(lines: nil, at: 15) == nil)
    }

    @Test("Vypnuté pravidlo neodkládá nic")
    func disabledRulesDoNotDefer() {
        var off = rules
        off.isEnabled = false
        #expect(decide(lines: 100_000, at: 15, rules: off) == nil)
    }

    // MARK: - Nesmyslné nastavení

    /// **Vypne odklad, nezastaví review.** Ručně editovaný `config.json` umí mít hodinu 25;
    /// brát to vážně by znamenalo PR odložený na okamžik, který nikdy nenastane.
    @Test(
        "Nesmyslné okno odklad vypne",
        arguments: [
            QuietHours(isEnabled: true, lineThreshold: 1500, startHour: 25, endHour: 6),
            QuietHours(isEnabled: true, lineThreshold: 1500, startHour: 22, endHour: -1),
            // Prázdné okno, ne „ticho pořád“: `22`–`22` znamená nedopsaný konec, a odklad, který
            // by z toho udělal ticho po celý den, by review zastavil úplně.
            QuietHours(isEnabled: true, lineThreshold: 1500, startHour: 22, endHour: 22),
            QuietHours(isEnabled: true, lineThreshold: 0, startHour: 22, endHour: 6),
        ]
    )
    func brokenRulesDisableTheDeferral(broken: QuietHours) {
        #expect(Policy.quietHoursAreUsable(broken) == false)
        #expect(decide(lines: 100_000, at: 15, rules: broken) == nil)
        #expect(Policy.quietHours(contain: moment(2026, 9, 6, 23), rules: broken, calendar: calendar) == false)
    }

    // MARK: - Přechod přes půlnoc

    /// Naivní `hour >= 22 && hour < 6` je **vždycky** nepravda, takže by se v noci nepustilo nic
    /// a odložené běhy by se hromadily do rána, které nikdy nepřijde.
    @Test(
        "Okno 22–6 přechází přes půlnoc",
        arguments: [
            (21, false), (22, true), (23, true), (0, true), (3, true), (5, true), (6, false), (12, false),
        ]
    )
    func theWindowCrossesMidnight(hour: Int, isQuiet: Bool) {
        #expect(Policy.quietHours(contain: moment(2026, 9, 6, hour), rules: rules, calendar: calendar) == isQuiet)
    }

    /// Okno **uvnitř jednoho dne** je ta druhá větev a musí platit taky — jinak by se pravidlo
    /// spravilo jen pro noční okno a `9`–`17` by bylo ticho pořád.
    @Test(
        "Okno 9–17 zůstává uvnitř dne",
        arguments: [(8, false), (9, true), (16, true), (17, false), (23, false)]
    )
    func aDaytimeWindowStaysInsideTheDay(hour: Int, isQuiet: Bool) {
        let day = QuietHours(isEnabled: true, lineThreshold: 1500, startHour: 9, endHour: 17)
        #expect(Policy.quietHours(contain: moment(2026, 9, 6, hour), rules: day, calendar: calendar) == isQuiet)
    }

    /// Odloženo pár minut před oknem — příští začátek je **dnes**, ne zítra.
    @Test("Těsně před oknem se odkládá na dnešní večer")
    func defersToTonightJustBeforeTheWindow() {
        let now = moment(2026, 9, 6, 21, 59)
        #expect(Policy.nextQuietHours(after: now, rules: rules, calendar: calendar) == moment(2026, 9, 6, 22))
    }

    /// A ráno těsně po okně na ten **následující** večer, ne na ten, který právě skončil.
    @Test("Ráno po okně se odkládá na příští večer")
    func defersToTheNextEveningInTheMorning() {
        let now = moment(2026, 9, 6, 6, 1)
        #expect(Policy.nextQuietHours(after: now, rules: rules, calendar: calendar) == moment(2026, 9, 6, 22))
    }

    // MARK: - Letní čas

    /// **Den má 25 hodin**, takže naivní `+86 400` mine začátek okna o hodinu. Tvrdí se obojí:
    /// místní okamžik (22:00) i **skutečný** odstup (24,5 h, ne 23,5 h) — bez toho druhého by test
    /// prošel i implementaci, která pracuje s pevnou délkou dne.
    @Test("Podzimní změna času: den má 25 hodin")
    func handlesTheLongDay() {
        let now = moment(2026, 10, 24, 22, 30)
        let next = Policy.nextQuietHours(after: now, rules: rules, calendar: calendar)
        #expect(next == moment(2026, 10, 25, 22))
        #expect(next?.timeIntervalSince(now) == 24.5 * 3600)
    }

    /// **Hodina, která ten den neexistuje.** Na jarním posunu se 2:00–3:00 přeskočí, takže okno
    /// začínající ve dvě nemá kdy začít — správná odpověď je nejbližší další čas, ne `nil`
    /// (to by v kódu znamenalo „nikdy“ a běh by v cache uvízl).
    @Test("Jarní změna času: začátek okna, který ten den neexistuje")
    func handlesTheMissingHour() {
        let two = QuietHours(isEnabled: true, lineThreshold: 1500, startHour: 2, endHour: 6)
        let now = moment(2026, 3, 29, 1, 30)
        let next = Policy.nextQuietHours(after: now, rules: two, calendar: calendar)
        #expect(next == moment(2026, 3, 29, 3))
    }

    // MARK: - Vyzvednutí

    private func deferral(runAt: Date, lines: Int = 2790, threshold: Int = 1500) -> DeferredRun {
        DeferredRun(
            pullRequest: pr,
            headSha: "aaaa1111",
            changedLines: lines,
            threshold: threshold,
            deferredAt: moment(2026, 9, 6, 15),
            runAt: runAt
        )
    }

    private func summary(_ id: PRIdentifier) -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: "velké PR",
            author: "autor",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: moment(2026, 9, 6, 12),
            state: .open
        )
    }

    @Test("Před časem se odložený běh nepustí")
    func doesNotReleaseEarly() {
        let released = Policy.deferralsToRelease(
            in: [summary(pr)],
            deferred: { _ in self.deferral(runAt: self.moment(2026, 9, 6, 22)) },
            now: moment(2026, 9, 6, 21, 59)
        )
        #expect(released.isEmpty)
    }

    @Test("V okamžiku, na který se odložilo, se pustí")
    func releasesOnTime() {
        let released = Policy.deferralsToRelease(
            in: [summary(pr)],
            deferred: { _ in self.deferral(runAt: self.moment(2026, 9, 6, 22)) },
            now: moment(2026, 9, 6, 22)
        )
        #expect(released == [pr])
    }

    /// Aplikace, která přes noc neběžela, najde `runAt` v minulosti — a slib se plní tím, že se
    /// běh pustí, ne tím, že se posune o den.
    @Test("Zmeškaná noc se vyzvedne ráno")
    func releasesAMissedNight() {
        let released = Policy.deferralsToRelease(
            in: [summary(pr)],
            deferred: { _ in self.deferral(runAt: self.moment(2026, 9, 6, 22)) },
            now: moment(2026, 9, 7, 8)
        )
        #expect(released == [pr])
    }

    /// **Otevřená záložka běh nespouští, a je to vědomá odchylka od věty v zadání issue.** Dráha
    /// `odloženo na noc` se kreslí jedině v otevřené záložce, takže by se pod pravidlem „otevření
    /// pouští“ nedala vidět vůbec. Otevřený PR se **neodkládá** (`deferToQuietHours` výš); cesta
    /// ven z už padlého odkladu je `Pustit teď`.
    @Test("Otevřená záložka odložený běh sama nespustí")
    func anOpenTabDoesNotRelease() {
        let released = Policy.deferralsToRelease(
            in: [summary(pr)],
            deferred: { _ in self.deferral(runAt: self.moment(2026, 9, 6, 22)) },
            now: moment(2026, 9, 6, 15)
        )
        #expect(released.isEmpty)
    }

    /// **Bere seznam z tiku, ne obsah cache.** Odklad umí ležet i po PR, které se mezitím zavřelo,
    /// a pustit review na zavřený PR je session za odpověď, kterou nikdo nepřečte.
    @Test("Odklad po PR, které ze seznamu vypadlo, nevystřelí")
    func anOrphanedDeferralNeverFires() {
        let released = Policy.deferralsToRelease(
            in: [],
            deferred: { _ in self.deferral(runAt: self.moment(2026, 9, 6, 22)) },
            now: moment(2026, 9, 7, 8)
        )
        #expect(released.isEmpty)
    }

    // MARK: - Věty

    /// Píše se **práh, podle kterého se rozhodlo**, ne ten dnešní: jinak by věta po změně
    /// nastavení tvrdila něco jiného, než co se stalo.
    @Test("Věta v hlavičce nese počet řádků i práh z okamžiku rozhodnutí")
    func theNoteCarriesTheThresholdItDecidedWith() {
        let run = deferral(runAt: moment(2026, 9, 6, 22), lines: 2790, threshold: 1500)
        let note = Policy.deferralNote(run)
        #expect(note.hasPrefix(Plural.czech(2790, one: "řádek", few: "řádky", many: "řádků")))
        #expect(note.hasSuffix("· nikdo na PR nečeká"))
        // **Tohle je ta regrese**: kdyby se práh bral z nastavení, byly by obě věty stejné —
        // dva odklady rozhodnuté podle jiného prahu musí mluvit každý o svém.
        let stricter = deferral(runAt: moment(2026, 9, 6, 22), lines: 2790, threshold: 2000)
        #expect(Policy.deferralNote(stricter) != note)
        // Počet je **množství**, takže se skupinuje podle locale — porovnává se proto proti téže
        // cestě, ne proti literálu s mezerou, kterou by jiná locale napsala jinak.
        #expect(note.contains(1500.formatted(.number.grouping(.automatic))))
    }

    @Test("Dnešní večer se píše bez dne, zítřejší ráno se dnem")
    func theRunLabelSaysTheDayOnlyWhenItMatters() {
        let tonight = deferral(runAt: moment(2026, 9, 6, 22))
        #expect(Policy.deferralRunLabel(tonight, now: moment(2026, 9, 6, 15), calendar: calendar)
            .contains("zítra") == false)

        let tomorrow = deferral(runAt: moment(2026, 9, 7, 6))
        #expect(Policy.deferralRunLabel(tomorrow, now: moment(2026, 9, 6, 23), calendar: calendar)
            .contains("zítra"))
    }

    /// Čas, který už byl, by v dráze vypadal jako zaseknutý odklad.
    @Test("Zmeškaný slib se přizná")
    func aMissedPromiseSaysSo() {
        let missed = deferral(runAt: moment(2026, 9, 6, 22))
        #expect(Policy.deferralRunLabel(missed, now: moment(2026, 9, 7, 8), calendar: calendar) == "poběží hned")
    }
}
