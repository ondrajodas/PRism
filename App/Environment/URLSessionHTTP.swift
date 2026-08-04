import Foundation

/// `HTTPGetting` nad `URLSession`.
///
/// Vlastní `ETag` místo `URLCache`: cache rozhoduje sama, kdy se zeptá znovu, kdežto tady
/// je smyslem ptát se v pevném intervalu a **poznat**, že se nic nezměnilo. Sezení je proto
/// bez cache (`ephemeral`) a podmíněný dotaz si skládá `StatusPageClient`.
struct URLSessionHTTP: HTTPGetting {
    private let session: URLSession

    init(timeout: Duration = .seconds(10)) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout.seconds
        // Sledování stavu služby nemá nic společného s cookies ani s přihlášením — a tohle
        // je jediné místo v aplikaci, které chodí na síť bez `gh`. Token by tady neměl co
        // dělat ani omylem (tvrdá podmínka č. 4).
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    func get(_ url: URL, ifNoneMatch etag: String?) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (body, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HTTPError.transport("Odpověď není HTTP.")
            }
            return HTTPResponse(
                statusCode: http.statusCode,
                etag: http.value(forHTTPHeaderField: "ETag"),
                body: body
            )
        } catch let error as URLError {
            throw Self.translate(error)
        }
    }

    /// `URLError` na naši chybu — a **zrušení na `CancellationError`**.
    ///
    /// `URLSession` hlásí zrušený task jako `URLError(.cancelled)`. Vydávat ho za výpadek
    /// sítě by znamenalo, že po zavření okna probleskne hláška o nedostupné službě; je to
    /// totéž pravidlo, jaké drží `ReviewRunner` i `GhReviewPublisher`.
    private static func translate(_ error: URLError) -> any Error {
        switch error.code {
        case .cancelled: CancellationError()
        case .timedOut: HTTPError.timedOut
        default: HTTPError.transport(error.localizedDescription)
        }
    }
}
