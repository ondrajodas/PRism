import Foundation
import Testing

@testable import PRism

@Suite("Policy — dostupnost služeb")
struct ServiceHealthTests {
    private let checked = Date(timeIntervalSince1970: 1_000_000)

    @Test("Dokud nic neproběhlo, je stav nezjištěný")
    func unknownWithoutSignals() {
        let report = Policy.health(of: .github, from: HealthSignals())

        #expect(report.state == .unknown)
        #expect(report.reason.contains("Zatím neproběhlo žádné volání"))
        #expect(report.call == nil)
        #expect(report.checkedAt == nil)
    }

    @Test("Prošlé volání a čistá status page dají zelenou")
    func operationalFromRealCall() {
        let report = Policy.health(
            of: .github,
            from: HealthSignals(
                lastCall: ServiceCall(since: checked),
                page: .watching(["API Requests": "operational"]),
                pageCheckedAt: checked
            )
        )

        #expect(report.state == .operational)
        #expect(report.reason.contains("Poslední volání prošlo"))
    }

    @Test("Čistá status page dá zelenou i před prvním voláním, ale řekne to")
    func aCleanPageIsGreenBeforeTheFirstCall() {
        let report = Policy.health(
            of: .claude,
            from: HealthSignals(page: .watching(["Claude Code": "operational"]), pageCheckedAt: checked)
        )

        // Šedá znamená „nevíme nic“, a tady víme, co o sobě říká provozovatel. Claude by
        // jinak zůstal šedý, dokud neproběhne první review — tedy většinu času.
        #expect(report.state == .operational)
        // Na čem zelená stojí, musí říct věta: status page nemluví o rate limitu ani
        // o chybějícím scope, takže „vyzkoušeno“ z ní neplyne.
        #expect(report.reason.contains("Vlastní volání ještě neproběhlo"))
    }

    @Test("Stará status page po selhané kontrole zelenou nedá")
    func aStalePageIsNotGreen() {
        let report = Policy.health(
            of: .claude,
            from: HealthSignals(
                page: .watching(["Claude Code": "operational"]),
                pageCheckedAt: checked,
                pageFailure: "Stránka se stavem služby odpověděla 503."
            )
        )

        #expect(report.state == .unknown)
    }

    @Test("Incident na sledované komponentě svítí žlutě, i když volání procházejí")
    func incidentWhileCallsPass() {
        let report = Policy.health(
            of: .github,
            from: HealthSignals(
                lastCall: ServiceCall(since: checked),
                page: .watching(["API Requests": "major_outage", "Pull Requests": "operational"]),
                pageCheckedAt: checked
            )
        )

        #expect(report.state == .incident)
        #expect(report.reason.contains("API Requests — velký výpadek"))
        #expect(!report.reason.contains("Pull Requests"))
        #expect(report.reason.contains("Volání zatím procházejí"))
    }

    @Test("Incident mimo sledované komponenty puntík nerozsvítí")
    func incidentOutsideWatchedComponents() throws {
        // Skutečný tvar stránky GitHubu s výpadkem v `Actions` — komponenta, kterou tahle
        // aplikace nepoužívá. Kdyby se sledoval celostránkový indikátor, svítilo by to.
        let page = try StatusPage(
            json: Fixture.data("statuspage/github-incident.json"),
            watching: ["Git Operations"]
        )
        let report = Policy.health(
            of: .github,
            from: HealthSignals(lastCall: ServiceCall(since: checked), page: page, pageCheckedAt: checked)
        )

        #expect(report.state == .operational)
    }

    @Test("Neznámý stav komponenty se nespolkne jako „v pořádku“")
    func unknownComponentStatusCountsAsIncident() {
        let report = Policy.health(
            of: .claude,
            from: HealthSignals(
                lastCall: ServiceCall(since: checked),
                page: .watching(["Claude Code": "something_new"]),
                pageCheckedAt: checked
            )
        )

        #expect(report.state == .incident)
        // Neznámé hodnotě se nevymýšlí popis — ukáže se, jak přišla.
        #expect(report.reason.contains("Claude Code — something_new"))
    }

    @Test("Incident se ukáže i před prvním voláním")
    func incidentBeforeFirstCall() {
        let report = Policy.health(
            of: .claude,
            from: HealthSignals(page: .watching(["Claude Code": "partial_outage"]), pageCheckedAt: checked)
        )

        #expect(report.state == .incident)
        #expect(!report.reason.contains("Volání zatím procházejí"))
    }

    @Test("Selhané volání svítí červeně a řekne, co selhalo")
    func failingCall() {
        let report = Policy.health(
            of: .github,
            from: HealthSignals(
                lastCall: ServiceCall(since: checked, failure: "gh není přihlášený — spusť gh auth login."),
                page: .watching(["API Requests": "operational"]),
                pageCheckedAt: checked
            )
        )

        #expect(report.state == .failing)
        #expect(report.reason.contains("gh auth login"))
        // To hlavní, kvůli čemu řádek existuje: oni, nebo já?
        #expect(report.reason.contains("problém nehlásí"))
    }

    @Test("Selhané volání nad incidentem řekne, že problém je na jejich straně")
    func failingCallDuringIncident() {
        let report = Policy.health(
            of: .github,
            from: HealthSignals(
                lastCall: ServiceCall(since: checked, failure: "GitHub není dostupný."),
                page: .watching(["API Requests": "major_outage"]),
                pageCheckedAt: checked
            )
        )

        // Selhané volání přebíjí incident: „nefunguje mi to“ je silnější tvrzení než
        // „oni něco hlásí“ — incident se přidá jako vysvětlení.
        #expect(report.state == .failing)
        #expect(report.reason.contains("GitHub hlásí problém: API Requests"))
    }

    @Test("Neznámý stav služby se nevydává za „oni nic nehlásí“")
    func withoutAPageNothingIsClaimedAboutThem() {
        let failing = Policy.health(
            of: .github,
            from: HealthSignals(lastCall: ServiceCall(since: checked, failure: "GitHub není dostupný."))
        )
        let passing = Policy.health(of: .github, from: HealthSignals(lastCall: ServiceCall(since: checked)))

        // Věta, která má rozhodnout „oni, nebo já?“, by jinak poslala hledat chybu u sebe
        // i ve chvíli, kdy o výpadku prostě nevíme.
        #expect(!failing.reason.contains("problém nehlásí"))
        #expect(!passing.reason.contains("problém nehlásí"))
        #expect(failing.reason.contains("ještě nezjišťoval"))
    }

    @Test("Selhaná kontrola „oni nic nehlásí“ taky nedovolí, ale známý incident ukáže")
    func staleStateIsNotUsedForReassurance() {
        let base = HealthSignals(
            lastCall: ServiceCall(since: checked, failure: "GitHub není dostupný."),
            pageCheckedAt: checked,
            pageFailure: "Stránka se stavem služby odpověděla 503."
        )
        var withOldPage = base
        withOldPage.page = .watching(["API Requests": "operational"])
        var withOldIncident = base
        withOldIncident.page = .watching(["API Requests": "major_outage"])

        // Nesymetrické schválně: zamlčet známý problém je dražší než ukázat ho o deset
        // minut starší, ale ujistit „u nich je čisto“ podle starých dat ne.
        #expect(!Policy.health(of: .github, from: withOldPage).reason.contains("problém nehlásí"))
        #expect(Policy.health(of: .github, from: withOldIncident).reason.contains("hlásí problém"))
    }

    @Test("Bez sítě je vlastní důvod, ne výpadek služby")
    func offlineIsNotAnOutage() {
        let signals = HealthSignals(
            lastCall: ServiceCall(since: checked, failure: "GitHub není dostupný."),
            page: .watching(["API Requests": "operational"]),
            pageCheckedAt: checked,
            isOnline: false
        )
        let report = Policy.health(of: .github, from: signals)

        #expect(report.state == .offline)
        #expect(report.reason.contains("bez sítě"))
        // A nesmí to vypadat jako výpadek GitHubu — to je jiná odpověď a vede jinam.
        #expect(!report.reason.contains("hlásí problém"))
    }

    @Test("Bez sítě přebíjí i prošlé volání z doby, kdy síť byla")
    func offlineOverridesStaleSuccess() {
        let report = Policy.health(
            of: .claude,
            from: HealthSignals(lastCall: ServiceCall(since: checked), isOnline: false)
        )

        #expect(report.state == .offline)
    }

    @Test("Nezjištěný stav sítě puntík nemění")
    func unknownReachabilityChangesNothing() {
        let report = Policy.health(
            of: .claude,
            from: HealthSignals(lastCall: ServiceCall(since: checked), isOnline: nil)
        )

        #expect(report.state == .operational)
    }

    @Test("Selhaná kontrola status page nic nezablokuje, ale je o ní vidět")
    func pageFailureDoesNotBlock() {
        let report = Policy.health(
            of: .github,
            from: HealthSignals(
                lastCall: ServiceCall(since: checked),
                pageCheckedAt: checked,
                pageFailure: "Na stránku se stavem služby nešlo dosáhnout. offline"
            )
        )

        // Volání procházejí, takže zelená je pravdivější než šedá — mlčet o tom ale nejde:
        // bez té věty se „o incidentech nevíme“ nepozná od „žádný incident není“.
        #expect(report.state == .operational)
        #expect(report.reason.contains("nešlo dosáhnout"))
    }

    @Test("Komponenta, kterou status page nezná, se hlásí")
    func missingComponentIsReported() {
        let report = Policy.health(
            of: .github,
            from: HealthSignals(
                lastCall: ServiceCall(since: checked),
                page: .watching(["Git Operations": "operational"], missing: ["API Requests"]),
                pageCheckedAt: checked
            )
        )

        // Přejmenovaná komponenta by jinak znamenala kontrolu, která tiše nehlídá nic —
        // a ta vypadá stejně jako „všechno v pořádku“.
        #expect(report.state == .operational)
        #expect(report.reason.contains("nezná komponentu API Requests"))
    }

    @Test("Nezjišťovaný stav služby se přizná")
    func neverCheckedIsMentioned() {
        let report = Policy.health(of: .github, from: HealthSignals(lastCall: ServiceCall(since: checked)))

        #expect(report.state == .operational)
        #expect(report.reason.contains("ještě nezjišťoval"))
        #expect(report.reason.contains("Poslední volání prošlo."))
    }

    @Test("Každý stav má neprázdný důvod i popis", arguments: ServiceHealth.allCases)
    func everyStateExplainsItself(state: ServiceHealth) {
        // Puntík, který po hoveru nic neřekne, je dekorace. Stavy se skládají tak, aby
        // z každého vypadl právě ten testovaný.
        let report = Policy.health(of: .github, from: Self.signals(for: state))

        #expect(report.state == state)
        #expect(!report.reason.isEmpty)
        #expect(!state.label.isEmpty)
    }

    @Test("Report nese službu i časy pro nápovědu")
    func reportCarriesTimes() {
        let called = checked.addingTimeInterval(-60)
        let report = Policy.health(
            of: .claude,
            from: HealthSignals(lastCall: ServiceCall(since: called), pageCheckedAt: checked)
        )

        #expect(report.id == .claude)
        #expect(report.call?.since == called)
        #expect(report.checkedAt == checked)
    }

    private static func signals(for state: ServiceHealth) -> HealthSignals {
        let now = Date(timeIntervalSince1970: 1_000_000)
        return switch state {
        case .unknown:
            HealthSignals()
        case .operational:
            HealthSignals(lastCall: ServiceCall(since: now), page: .watching([:]), pageCheckedAt: now)
        case .incident:
            HealthSignals(page: .watching(["API Requests": "major_outage"]), pageCheckedAt: now)
        case .failing:
            HealthSignals(lastCall: ServiceCall(since: now, failure: "gh nedoběhl v limitu."))
        case .offline:
            HealthSignals(isOnline: false)
        }
    }
}
