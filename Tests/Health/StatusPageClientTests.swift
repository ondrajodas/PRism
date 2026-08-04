import Foundation
import Testing

@testable import PRism

@Suite("StatusPageClient — podmíněné čtení status page")
struct StatusPageClientTests {
    @Test("Prošlá odpověď dá stav sledovaných komponent")
    func fetchesOperationalPage() async throws {
        let http = FakeHTTPGetter(responses: [
            HTTPResponse(statusCode: 200, etag: "W/\"a\"", body: try Fixture.data("statuspage/github-components.json"))
        ])
        let client = StatusPageClient(http: http)

        let result = try await client.read(.github)

        guard case .fetched(let page) = result else {
            Issue.record("Čekal jsem stránku, přišlo \(result)")
            return
        }
        #expect(page.incidents.isEmpty)
        #expect(page.watched.count == 3)
        #expect(http.requests == [.init(url: MonitoredService.github.componentsURL, ifNoneMatch: nil)])
    }

    @Test("Incident na sledované komponentě projde až do stránky")
    func fetchesIncident() async throws {
        let http = FakeHTTPGetter(responses: [
            HTTPResponse(statusCode: 200, body: try Fixture.data("statuspage/github-incident.json"))
        ])

        let result = try await StatusPageClient(http: http).read(.github)

        guard case .fetched(let page) = result else {
            Issue.record("Čekal jsem stránku, přišlo \(result)")
            return
        }
        #expect(page.incidents.map(\.name) == ["API Requests", "Pull Requests"])
    }

    @Test("Druhý dotaz posílá ETag a 304 znamená „platí, co jsi měl“")
    func conditionalGet() async throws {
        let http = FakeHTTPGetter(responses: [
            HTTPResponse(statusCode: 200, etag: "W/\"a\"", body: try Fixture.data("statuspage/github-components.json")),
            HTTPResponse(statusCode: 304),
        ])
        let client = StatusPageClient(http: http)

        _ = try await client.read(.github)
        let second = try await client.read(.github)

        // Bez ETagu by každá kontrola tahala celé tělo; s ním je druhý dotaz bez těla.
        #expect(http.requests.map(\.ifNoneMatch) == [nil, "W/\"a\""])
        #expect(second == .unchanged)
    }

    @Test("ETag se drží po službách, ne dohromady")
    func etagsAreNotShared() async throws {
        let http = FakeHTTPGetter(responses: [
            HTTPResponse(statusCode: 200, etag: "W/\"gh\"", body: try Fixture.data("statuspage/github-components.json")),
            HTTPResponse(statusCode: 200, etag: "W/\"cl\"", body: try Fixture.data("statuspage/claude-components.json")),
            HTTPResponse(statusCode: 304),
        ])
        let client = StatusPageClient(http: http)

        _ = try await client.read(.github)
        _ = try await client.read(.claude)
        _ = try await client.read(.github)

        // Poslat GitHubu ETag stránky Claude by znamenalo `200` navždycky, nebo `304` na
        // stránku, kterou jsme nikdy nečetli.
        #expect(http.requests.map(\.ifNoneMatch) == [nil, nil, "W/\"gh\""])
    }

    @Test("ETag se ukládá teprve po úspěšném dekódování")
    func etagIsNotStoredForMalformedBody() async throws {
        let http = FakeHTTPGetter(responses: [
            HTTPResponse(statusCode: 200, etag: "W/\"rozbité\"", body: Data("nonsense".utf8)),
            HTTPResponse(statusCode: 200, etag: "W/\"a\"", body: try Fixture.data("statuspage/github-components.json")),
        ])
        let client = StatusPageClient(http: http)

        await #expect(throws: StatusPageError.self) { try await client.read(.github) }
        _ = try await client.read(.github)

        // Kdyby se ETag zapsal hned, přišel by příště `304` — „platí, co jsi měl“ na
        // stránku, které jsme nerozuměli. Puntík by zůstal nezjištěný navždycky.
        #expect(http.requests.map(\.ifNoneMatch) == [nil, nil])
    }

    @Test("Chybný JSON je typovaná chyba")
    func malformedBody() async throws {
        let http = FakeHTTPGetter(responses: [HTTPResponse(statusCode: 200, body: Data("{".utf8))])

        await #expect(throws: StatusPageError.self) {
            try await StatusPageClient(http: http).read(.claude)
        }
    }

    @Test("Jiný stavový kód než 200 a 304 je chyba se svým číslem")
    func badStatusCode() async throws {
        let http = FakeHTTPGetter(responses: [HTTPResponse(statusCode: 503)])

        await #expect(throws: StatusPageError.badStatus(503)) {
            try await StatusPageClient(http: http).read(.github)
        }
    }

    @Test("Nedosažitelný server je vlastní chyba, ne rozbitá odpověď")
    func transportFailure() async throws {
        let http = FakeHTTPGetter(failing: .transport("Nejsi připojen k internetu."))

        await #expect(throws: StatusPageError.unreachable("Nejsi připojen k internetu.")) {
            try await StatusPageClient(http: http).read(.github)
        }
    }

    @Test("Timeout dorazí jako nedosažitelnost, i s vysvětlením")
    func timeout() async throws {
        let http = FakeHTTPGetter(failing: .timedOut)

        await #expect(throws: StatusPageError.unreachable(HTTPError.timedOut.detail)) {
            try await StatusPageClient(http: http).read(.claude)
        }
    }

    @Test("Každá chyba má věty pro nápovědu")
    func errorsExplainThemselves() {
        let errors: [StatusPageError] = [.unreachable("detail"), .badStatus(500), .malformed("detail")]

        for error in errors {
            #expect(!error.userDescription.isEmpty)
        }
    }
}
