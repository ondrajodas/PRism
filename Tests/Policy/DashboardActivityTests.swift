import Foundation
import Testing

@testable import PRism

/// Blok `Dění` na dashboardu (#443) — strop, patka, počet v nadpisu, den u času a prázdno.
///
/// Čisté funkce, takže výčtem a bez mockování. Tři věci se tu dají pokazit **potichu**: patka, která
/// se rozejde s kresbou („+37“ nad šesti nakreslenými řádky vypadá platně), **den u času**, který
/// z včerejší události udělá dnešní ráno, a **prázdno, které tvrdí klid** nad ztracenou historií.
@Suite("Blok dění na dashboardu (#443)")
struct DashboardActivityTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "keboola", name: "vault"), number: 85)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(_ kind: ActivityEvent.Kind = .findings, at seconds: TimeInterval) -> ActivityEvent {
        ActivityEvent(
            id: "\(kind.rawValue)|\(pr)|\(seconds)",
            kind: kind,
            pullRequest: pr,
            at: Date(timeIntervalSince1970: seconds),
            headline: "cokoli",
            wasAnnounced: true
        )
    }

    /// `count` položek, každá o minutu starší — takže se dá poznat, jestli řez vzal ty nejnovější.
    private func events(_ count: Int) -> [ActivityEvent] {
        (0..<count).map { event(at: now.timeIntervalSince1970 - Double($0) * 60) }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }
}

// MARK: - Strop a patka

extension DashboardActivityTests {
    /// **Tentýž strop jako u front** (#371), a je to celý důvod, proč blok na dashboardu nemá
    /// vlastní číslo: dashboard je jedna obrazovka bez rolování.
    @Test("Nad stropem kreslí pět nejnovějších a zbytek shrne patka")
    func capsRowsAndSumsUpTheRest() {
        let block = Policy.dashboardActivity(events(42), since: nil, empty: nil)

        #expect(block.rows.count == Policy.dashboardRowLimit)
        // Nejnovější nahoře: první řádek je ten s časem `now`, pátý o čtyři minuty starší.
        #expect(block.rows.first?.at == now)
        #expect(block.rows.last?.at == now.addingTimeInterval(-4 * 60))
        #expect(block.footer?.title == "Zobrazit celé dění")
        #expect(block.footer?.rest == "+37")
        #expect(block.footer?.section == .activity)
    }

    /// Patka nad seznamem, který je celý vidět, je akce, po které se nic nezmění — tatáž úvaha jako
    /// u bloku fronty, a v mockupu je to vidět na prázdném bloku.
    @Test("Pod stropem patku nemá")
    func hasNoFooterBelowTheLimit() {
        #expect(Policy.dashboardActivity(events(3), since: nil, empty: nil).footer == nil)
    }

    /// **Ani při přesně pěti**: strop je „nejvýš pět“, ne „pět a pak patka“. Tady se to rozhoduje
    /// o jedničku, takže je to ten případ, na kterém se `>=` proti `>` pozná.
    @Test("Přesně pět řádků patku nedostane")
    func hasNoFooterAtExactlyTheLimit() {
        let block = Policy.dashboardActivity(events(Policy.dashboardRowLimit), since: nil, empty: nil)

        #expect(block.rows.count == Policy.dashboardRowLimit)
        #expect(block.footer == nil)
    }

    /// Vstup v opačném pořadí je ten případ, ve kterém by řez ukázal **pět jiných** položek a nikdo
    /// by si toho nevšiml: pět řádků vypadá platně, ať v nich stojí cokoli.
    @Test("Rozházené pořadí se srovná před řezem")
    func reordersBeforeCutting() {
        let block = Policy.dashboardActivity(Array(events(9).reversed()), since: nil, empty: nil)

        #expect(block.rows.first?.at == now)
        #expect(block.footer?.rest == "+4")
    }

    /// Duplicita v záznamu (dvě všimnutí téže věci) se nesmí projevit ani v řádcích, ani v počtu
    /// v patce — je to totéž slití, jaké dělá `Policy.activityLog` při zápisu.
    @Test("Duplicitní položka nezabere řádek ani se nepočítá do patky")
    func mergesDuplicates() {
        let block = Policy.dashboardActivity(events(6) + events(6), since: nil, empty: nil)

        #expect(block.rows.count == Policy.dashboardRowLimit)
        #expect(block.footer?.rest == "+1")
    }
}

// MARK: - Počet v nadpisu

extension DashboardActivityTests {
    /// Nadpis nese **nepřečtené z celého záznamu**, ne z nakreslených řádků: je to totéž číslo,
    /// jaké nese odznak sekce v railu, a dvě čísla o jedné věci vedle sebe by se lišila.
    @Test("Nadpis počítá nepřečtené z celého záznamu, ne z pěti řádků")
    func countsUnreadAcrossTheWholeLog() {
        let block = Policy.dashboardActivity(
            events(20),
            since: now.addingTimeInterval(-10 * 60 - 30),
            empty: nil
        )

        // Jedenáct položek je novějších než značka, i když se nakreslí pět.
        #expect(block.title == "Dění · 11 nových")
        #expect(block.rows.count == Policy.dashboardRowLimit)
    }

    /// **Bez značky je nové všechno** — tatáž volba jako u odznaku (`Policy.unreadActivity`):
    /// záznam vzniká teprve za běhu aplikace, takže „nikdy jsem tu nebyl“ znamená, že jsem opravdu
    /// nic z toho neviděl.
    @Test("Bez značky je nové všechno")
    func countsEverythingWithoutAMark() {
        #expect(Policy.dashboardActivity(events(3), since: nil, empty: nil).title == "Dění · 3 nové")
    }

    /// Nula se **nepíše**: „Dění · 0 nových“ je hlášení o ničem — tatáž úvaha jako u odznaku, který
    /// se nad nulou nekreslí.
    @Test("Přečtený záznam nadpis nerozšiřuje")
    func leavesTheTitleBareWhenEverythingIsRead() {
        let block = Policy.dashboardActivity(events(3), since: now.addingTimeInterval(60), empty: nil)

        #expect(block.title == "Dění")
    }

    /// Skloňování je totéž jako v nadpisu bloku dne v sekci (`Dnes · 4 nové`) — jeden počet, jedno
    /// znění; „1 nové“ je ta třída chyby, kterou Copilot v tomhle repu chytá opakovaně.
    @Test("Počet se skloňuje", arguments: [(1, "1 nová"), (2, "2 nové"), (5, "5 nových")])
    func inflectsTheCount(_ count: Int, _ expected: String) {
        let block = Policy.dashboardActivity(events(count), since: nil, empty: nil)

        #expect(block.title == "Dění · \(expected)")
    }
}

// MARK: - Den u času

extension DashboardActivityTests {
    /// **Kvůli tomuhle to rozhodnutí je v `Policy`.** V sekci nese den hlavička bloku, na dashboardu
    /// ho nemá kdo nést — takže by `v 7:58` u včerejší události tvrdilo, že to bylo dneska ráno.
    @Test("Řádek na dashboardu dopisuje den, řádek v sekci ne")
    func writesTheDayOnlyWhenTheRowCarriesIt() {
        let yesterday = now.addingTimeInterval(-86_400)

        let carried = Policy.activityTime(of: yesterday, now: now, at: .dashboard, calendar: calendar)
        let borne = Policy.activityTime(of: yesterday, now: now, at: .section, calendar: calendar)

        #expect(carried == .absolute(Policy.visitLabel(yesterday, now: now, calendar: calendar)))
        #expect(carried == .absolute("včera v \(yesterday.formatted(.dateTime.hour().minute()))"))
        #expect(borne == .absolute("v \(yesterday.formatted(.dateTime.hour().minute()))"))
    }

    /// Dnešní událost den nedostane ani na dashboardu: `dnes v 7:58` je slovo navíc v řádku, ve
    /// kterém se o místo perou čtyři další údaje.
    @Test("Dnešní čas den nedostane ani na dashboardu")
    func skipsTheDayForToday() {
        let morning = now.addingTimeInterval(-5 * 60 * 60)
        let clock = "v \(morning.formatted(.dateTime.hour().minute()))"

        #expect(Policy.activityTime(of: morning, now: now, at: .dashboard, calendar: calendar) == .absolute(clock))
        #expect(Policy.activityTime(of: morning, now: now, at: .section, calendar: calendar) == .absolute(clock))
    }

    /// Starší než včerejšek dostane datum, ne „předevčírem“ — tentýž formát jako popisek návštěvy.
    @Test("Starší než včerejšek dostane datum")
    func writesTheDateForOlderRows() {
        let older = now.addingTimeInterval(-3 * 86_400)
        let label = Policy.activityTime(of: older, now: now, at: .dashboard, calendar: calendar)

        #expect(label == .absolute(Policy.visitLabel(older, now: now, calendar: calendar)))
        guard case .absolute(let text) = label else { return }
        #expect(!text.hasPrefix("v ") && !text.hasPrefix("včera"))
        #expect(text.contains(":"))
    }

    /// Čerstvá událost zůstává relativní **na obou obrazovkách**: text si skládá view, protože se
    /// v okně přepočítává sám, a místo na to nesmí sáhnout.
    @Test("Do dvou hodin je čas relativní na obou místech")
    func staysRelativeInsideTheWindow() {
        let fresh = now.addingTimeInterval(-120)

        #expect(Policy.activityTime(of: fresh, now: now, at: .dashboard, calendar: calendar) == .relative)
        #expect(Policy.activityTime(of: fresh, now: now, at: .section, calendar: calendar) == .relative)
    }

    /// Hranice okna je tatáž jako v sekci (`showsRelativeTime`), takže se ty dvě obrazovky nemají
    /// čím rozejít v tom, odkdy se píše hodinami.
    @Test("Hranice relativního okna je jedna pro obě obrazovky")
    func sharesTheRelativeWindow() {
        for offset in [-60.0, -7100, -7300, -86_400] {
            let date = now.addingTimeInterval(offset)
            let isRelative = Policy.activityTime(of: date, now: now, at: .dashboard, calendar: calendar) == .relative

            #expect(isRelative == Policy.showsRelativeTime(of: date, now: now))
        }
    }
}

// MARK: - Prázdno

extension DashboardActivityTests {
    /// Prázdný blok je **jedna věta**, ne díra: prázdné místo pod hlavičkou vypadá jako chybějící
    /// údaj — tatáž úvaha jako u prázdné fronty vedle.
    @Test("Prázdný záznam dostane větu místo řádků")
    func explainsTheEmptyBlock() {
        let block = Policy.dashboardActivity([], since: nil, empty: .calm)

        #expect(block.rows.isEmpty)
        #expect(block.footer == nil)
        #expect(block.title == "Dění")
        #expect(block.emptyExplanation == "Od tvé poslední návštěvy se na pull requestech nic nestalo.")
    }

    /// **Čtyři prázdna, čtyři věty** — a je to to tvrzení, kvůli kterému se sem prázdný stav vůbec
    /// předává. Nad ztracenou historií a nad mlčící aplikací by klid tvrdil víc, než data unesou.
    @Test("Každé prázdno má vlastní větu", arguments: ActivityEmptyState.allCases)
    func tellsTheEmptyStatesApart(_ state: ActivityEmptyState) {
        let sentences = ActivityEmptyState.allCases.map {
            Policy.dashboardActivity([], since: nil, empty: $0).emptyExplanation
        }

        #expect(Set(sentences).count == ActivityEmptyState.allCases.count)
        #expect(Policy.dashboardActivity([], since: nil, empty: state).emptyExplanation?.isEmpty == false)
    }

    /// Ztracená historie se **nesmí slít s klidem**: soubor tam byl a nepřečetl se, takže „nic se
    /// nestalo“ by nad tím lhalo.
    @Test("Ztracený záznam nemluví o klidu")
    func doesNotCallLostHistoryCalm() {
        let lost = Policy.dashboardActivity([], since: nil, empty: .unreadable).emptyExplanation

        #expect(lost?.contains("ztracené") == true)
        #expect(lost?.contains("nic nestalo") == false)
    }

    /// Mlčící aplikace to musí přiznat — a **rozlišit oba důvody**, protože každý se spravuje jinde:
    /// zakázané oprávnění v Nastavení systému, vypnutý přepínač v nastavení aplikace.
    @Test("Zakázané a vypnuté hlášení se od sebe poznají")
    func tellsDeniedFromDisabled() {
        let denied = Policy.dashboardActivity([], since: nil, empty: .notificationsDenied).emptyExplanation
        let off = Policy.dashboardActivity([], since: nil, empty: .notificationsOff).emptyExplanation

        #expect(denied?.contains("Nastavení systému") == true)
        #expect(off?.contains("nastavení") == true)
        #expect(off?.contains("Nastavení systému") == false)
        // Obě říkají, že zápis běží dál — jinak by vypadaly jako „záznam nemáš“.
        #expect(denied?.contains("plní dál") == true && off?.contains("plní dál") == true)
    }

    /// Neprázdný záznam větu **nedostane**: prázdný stav a řádky se nesmí kreslit naráz.
    @Test("Řádky větu o prázdnu nevydají")
    func hasNoSentenceWithRows() {
        #expect(Policy.dashboardActivity(events(2), since: nil, empty: nil).emptyExplanation == nil)
    }
}

// MARK: - Blok je součástí jednoho snímku

extension DashboardActivityTests {
    /// **Jedno volání za překreslení** (#443): blok je v témže `Dashboard`, který si view bere
    /// jednou — ne vlastní getter, který by při každém průchodu tělem prošel záznam podruhé.
    @Test("Dashboard nese blok dění v témže snímku")
    func carriesTheBlockInTheSnapshot() {
        let dashboard = Policy.dashboard(
            pullRequests: [],
            records: [:],
            drafts: [:],
            activity: events(8),
            lastVisit: now.addingTimeInterval(-90),
            activityEmpty: nil
        )

        #expect(dashboard.activity.rows.count == Policy.dashboardRowLimit)
        #expect(dashboard.activity.footer?.rest == "+3")
        #expect(dashboard.activity.title == "Dění · 2 nové")
    }
}
