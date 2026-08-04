import Foundation

/// Stav sledovaných komponent jedné služby, jak ho vrátila status page.
struct StatusPage: Sendable, Equatable {
    /// Sledované komponenty, které stránka zná. Pořadí je naše (podle `watchedComponents`),
    /// ne to ze stránky — jinak by se nápověda přerovnávala podle cizího `position`.
    let watched: [StatusPageComponent]

    /// Sledovaná jména, která stránka **nezná**.
    ///
    /// Musí být vidět: komponenta se dá přejmenovat a kontrola, která pak tiše nehlídá nic,
    /// je horší než žádná — vypadá totiž stejně jako „všechno v pořádku“. Tatáž úvaha jako
    /// u `Diff.unrecognizedLines` a `StreamSummary.droppedFindings`.
    let missing: [String]

    /// Komponenty, které nehlásí `operational`.
    var incidents: [StatusPageComponent] { watched.filter { !$0.isOperational } }
}

/// Jedna komponenta status page.
struct StatusPageComponent: Sendable, Equatable {
    let name: String

    /// Surový stav ze Statuspage (`operational`, `major_outage`, …).
    ///
    /// Držíme **řetězec, ne výčet**: seznam hodnot je jejich a může se rozšířit. Neznámou
    /// hodnotu se přitom nesmí spolknout jako „v pořádku“ — proto se za incident počítá
    /// cokoli, co není `operational`, a nápověda ukáže, jak to přišlo.
    let status: String

    var isOperational: Bool { status == Self.operational }

    /// Jak se stav řekne česky. Neznámý se ukáže, jak dorazil — vymýšlet mu popis by
    /// znamenalo tvrdit něco o hodnotě, kterou neznáme.
    var label: String {
        switch status {
        case Self.operational: "v pořádku"
        case "degraded_performance": "zhoršený výkon"
        case "partial_outage": "částečný výpadek"
        case "major_outage": "velký výpadek"
        case "under_maintenance": "údržba"
        default: status
        }
    }

    private static let operational = "operational"
}

extension StatusPage {
    /// Vykrojí ze stránky to, co sledujeme.
    ///
    /// Dekóduje se **typovaně** (`Codable`), na rozdíl od `stream-json` reviewera: tady jde
    /// o dokumentované veřejné API se dvěma poli, která potřebujeme, ne o vyvíjející se cizí
    /// proud eventů. Neznámá pole DTO ignoruje samo.
    init(json: Data, watching names: [String]) throws {
        let page: StatusPageDTO
        do {
            page = try JSONDecoder().decode(StatusPageDTO.self, from: json)
        } catch {
            throw StatusPageError.malformed(error.localizedDescription)
        }

        let byName = Dictionary(page.components.map { ($0.name, $0.status) }) { first, _ in first }
        watched = names.compactMap { name in
            byName[name].map { StatusPageComponent(name: name, status: $0) }
        }
        missing = names.filter { byName[$0] == nil }
    }
}

/// Tvar odpovědi `…/api/v2/components.json`.
private struct StatusPageDTO: Decodable {
    struct Component: Decodable {
        let name: String
        let status: String
    }

    let components: [Component]
}

/// Co ze čtení status page vyšlo.
///
/// `unchanged` je vlastní odpověď, ne prázdná stránka: `304` znamená „platí, co jsi měl“,
/// a kdo si to spletl s „nic tam není“, ten by po prvním nezměněném dotazu zhasl puntík.
enum StatusPageResult: Sendable, Equatable {
    case fetched(StatusPage)
    case unchanged
}

/// Proč se stav služby nepodařilo zjistit.
///
/// Žádná z těch chyb nesmí nic zablokovat — výsledkem je nápověda, která říká, že se to
/// nepovedlo, ne chyba, o kterou se zastaví review nebo polling.
enum StatusPageError: Error, Equatable, Sendable {
    /// Na status page jsme se nedostali.
    case unreachable(String)
    /// Odpověděla, ale ne `200` ani `304`.
    case badStatus(Int)
    /// Odpověděla něčím, čemu nerozumíme.
    case malformed(String)

    var userDescription: String {
        switch self {
        case .unreachable(let detail): "Na stránku se stavem služby nešlo dosáhnout. \(detail)"
        case .badStatus(let code): "Stránka se stavem služby odpověděla \(code)."
        case .malformed(let detail): "Odpovědi stránky se stavem služby nerozumím. \(detail)"
        }
    }
}
