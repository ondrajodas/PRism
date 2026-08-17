import Foundation

/// Podproces, o kterém aplikace ví, že ho spustila — zapsaný na disk, aby se po zabité
/// aplikaci dal dohledat a zabít (#351).
///
/// Drží **dvě** identity, a to je celý ten záznam:
///
/// - `owner` je instance aplikace, která běh spustila. Bez ní by se nedalo poznat, jestli je
///   zapsaná session sirotek, nebo jestli se o ni pořád stará někdo živý — a úklid při startu
///   by zabíjel session běžící aplikaci pod rukama. Naráží na to i `xcodebuild test`: testovací
///   host je tentýž bundle, takže sahá do **téže cache** jako aplikace v `/Applications`.
/// - `process` je sám podproces (`claude -p`).
///
/// Zapsané PID je jediné, podle čeho se session pozná. **Nikdy se nehledá v `ps` podle jména
/// nebo promptu**: na stroji běží `claude` i mimo aplikaci (uživatelovy vlastní session,
/// paralelní agenti) a zabít cizí je horší než nechat běžet sirotka.
struct RunningSession: Codable, Equatable, Sendable {
    let owner: ProcessIdentity
    let process: ProcessIdentity
}
