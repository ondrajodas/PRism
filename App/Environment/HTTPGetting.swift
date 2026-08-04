import Foundation

/// Jediný způsob, jak aplikace sáhne na HTTP sama za sebe.
///
/// Do #31 šel **všechen** kontakt s vnějším světem přes podprocesy (`gh`, `git`, `claude`).
/// Status page provozovatelů se ale přes `gh` stáhnout nedá — je to cizí veřejný endpoint,
/// takže tady začíná `URLSession`. Za protokolem proto, že žádný test nesmí chodit na síť.
///
/// Podmíněný dotaz (`If-None-Match`) je součást protokolu, ne detail implementace: bez něj
/// by každá kontrola tahala celé tělo, kdežto s ním je druhý dotaz `304` bez těla.
protocol HTTPGetting: Sendable {
    /// GET na `url`. Když je `etag` z minula, server smí odpovědět `304` bez těla.
    func get(_ url: URL, ifNoneMatch etag: String?) async throws -> HTTPResponse
}

/// Co přišlo. **Stavový kód je data, ne chyba** — stejná úvaha jako u `ProcessResult`:
/// zařadit `500` umí až ten, kdo ví, na co se ptal.
struct HTTPResponse: Sendable, Equatable {
    let statusCode: Int
    /// `ETag` odpovědi, ať se dá příště poslat podmíněný dotaz. `nil` = server ho nedal.
    let etag: String?
    let body: Data

    init(statusCode: Int, etag: String? = nil, body: Data = Data()) {
        self.statusCode = statusCode
        self.etag = etag
        self.body = body
    }
}

/// Proč se nepovedlo dosáhnout na server.
///
/// Jen doprava — odpověď se stavovým kódem chybou není. Zrušení se sem nedostane vůbec:
/// překládá se na `CancellationError`, jako u podprocesů.
enum HTTPError: Error, Equatable, Sendable {
    /// Síť, DNS, TLS — na server jsme se nedostali.
    case transport(String)
    /// Server neodpověděl v limitu.
    case timedOut

    var detail: String {
        switch self {
        case .transport(let detail): detail
        case .timedOut: "Server neodpověděl v limitu."
        }
    }
}
