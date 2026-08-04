import Foundation

/// Čtení stavu služby z její status page.
///
/// Za protokolem proto, že **žádný test nesmí chodit na síť** — a taky proto, že je to
/// jediná věc v aplikaci, která by na ni šla bez `gh`.
protocol StatusPageReading: Sendable {
    func read(_ service: MonitoredService) async throws -> StatusPageResult
}

/// Status page přes HTTP, s podmíněným dotazem.
///
/// Aktor kvůli `ETagům`: drží se mezi dotazy a dvě služby se kontrolují za sebou v jednom
/// kole, takže si to zápis musí serializovat samo.
actor StatusPageClient: StatusPageReading {
    private let http: any HTTPGetting
    private var etags: [MonitoredService: String] = [:]

    init(http: any HTTPGetting = URLSessionHTTP()) {
        self.http = http
    }

    func read(_ service: MonitoredService) async throws -> StatusPageResult {
        let response: HTTPResponse
        do {
            response = try await http.get(service.componentsURL, ifNoneMatch: etags[service])
        } catch let error as HTTPError {
            throw StatusPageError.unreachable(error.detail)
        }

        switch response.statusCode {
        case 200:
            let page = try StatusPage(json: response.body, watching: service.watchedComponents)
            // `ETag` se ukládá **teprve po úspěšném dekódování**. Kdyby se zapsal hned,
            // odpověď, které nerozumíme, by nám příště přišla jako `304` — a puntík by
            // zůstal nezjištěný navždycky, protože „platí, co jsi měl“ by odkazovalo na
            // stránku, kterou jsme nikdy nepřečetli.
            etags[service] = response.etag
            return .fetched(page)
        case 304:
            return .unchanged
        default:
            throw StatusPageError.badStatus(response.statusCode)
        }
    }
}
