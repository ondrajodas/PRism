import Foundation
import Testing

@testable import PRism

@Suite("StatusPage — čtení stavu komponent")
struct StatusPageTests {
    @Test("Skutečná stránka GitHubu dá všechny sledované komponenty")
    func githubComponents() throws {
        let page = try StatusPage(
            json: Fixture.data("statuspage/github-components.json"),
            watching: MonitoredService.github.watchedComponents
        )

        // Jména jsou jediné, čím se komponenta pozná — když se rozejdou se stránkou,
        // hlídá se prázdno. Proto se to testuje proti skutečné odpovědi.
        #expect(page.watched.map(\.name) == ["API Requests", "Pull Requests", "Git Operations"])
        #expect(page.missing.isEmpty)
        #expect(page.incidents.isEmpty)
    }

    @Test("Skutečná stránka Claude dá všechny sledované komponenty")
    func claudeComponents() throws {
        let page = try StatusPage(
            json: Fixture.data("statuspage/claude-components.json"),
            watching: MonitoredService.claude.watchedComponents
        )

        #expect(page.watched.map(\.name) == ["Claude Code", "Claude API (api.anthropic.com)"])
        #expect(page.missing.isEmpty)
        #expect(page.incidents.isEmpty)
    }

    @Test("Vykrojí se jen sledované komponenty — na cizím výpadku nezáleží")
    func onlyWatchedComponents() throws {
        let page = try StatusPage(
            json: Fixture.data("statuspage/github-incident.json"),
            watching: MonitoredService.github.watchedComponents
        )

        // Ve fixture je `major_outage` i v `Actions`; ta se do stránky nesmí dostat vůbec.
        #expect(page.watched.count == 3)
        #expect(page.incidents.map(\.name) == ["API Requests", "Pull Requests"])
        #expect(page.incidents.map(\.label) == ["velký výpadek", "zhoršený výkon"])
    }

    @Test("Pořadí je naše, ne to ze stránky")
    func orderFollowsWatchedList() throws {
        let page = try StatusPage(
            json: Fixture.data("statuspage/github-components.json"),
            watching: ["Pull Requests", "API Requests"]
        )

        // Ve fixture jde `API Requests` první. Kdyby se pořadí bralo odtud, přerovnávalo by
        // se to podle cizího `position`.
        #expect(page.watched.map(\.name) == ["Pull Requests", "API Requests"])
    }

    @Test("Komponenta, kterou stránka nezná, se počítá")
    func missingComponentIsCounted() throws {
        let page = try StatusPage(
            json: Fixture.data("statuspage/github-components.json"),
            watching: ["API Requests", "Přejmenovaná komponenta"]
        )

        #expect(page.watched.map(\.name) == ["API Requests"])
        #expect(page.missing == ["Přejmenovaná komponenta"])
    }

    @Test("Rozbitý JSON je typovaná chyba, ne pád")
    func malformedJSON() {
        #expect(throws: StatusPageError.self) {
            try StatusPage(json: Data("{ tohle není JSON".utf8), watching: ["API Requests"])
        }
    }

    @Test("Chybějící pole komponenty je taky chyba")
    func missingFields() {
        let json = Data(#"{"components": [{"name": "API Requests"}]}"#.utf8)

        #expect(throws: StatusPageError.self) {
            try StatusPage(json: json, watching: ["API Requests"])
        }
    }

    @Test("Stránka bez komponent není chyba, jen prázdno")
    func emptyComponents() throws {
        let page = try StatusPage(json: Data(#"{"components": []}"#.utf8), watching: ["API Requests"])

        #expect(page.watched.isEmpty)
        #expect(page.missing == ["API Requests"])
    }

    @Test("Známé stavy mají český popis, neznámý se ukáže, jak přišel")
    func statusLabels() {
        let labels = [
            "operational": "v pořádku",
            "degraded_performance": "zhoršený výkon",
            "partial_outage": "částečný výpadek",
            "major_outage": "velký výpadek",
            "under_maintenance": "údržba",
            "something_new": "something_new",
        ]

        for (status, label) in labels {
            let component = StatusPageComponent(name: "X", status: status)
            #expect(component.label == label)
            #expect(component.isOperational == (status == "operational"))
        }
    }

    @Test("Sledované adresy míří na komponenty, ne na celostránkový indikátor")
    func componentEndpoints() {
        #expect(
            MonitoredService.github.componentsURL.absoluteString
                == "https://www.githubstatus.com/api/v2/components.json"
        )
        // `status.anthropic.com` jen přesměrovává; spoléhat na redirect znamená mít
        // v aplikaci závislost na tom, že ho někdo udržuje.
        #expect(
            MonitoredService.claude.componentsURL.absoluteString
                == "https://status.claude.com/api/v2/components.json"
        )
    }
}
