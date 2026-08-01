import Foundation

/// Repozitář na GitHubu — `owner/repo`.
///
/// Kóduje se na **jediný řetězec**, ne na objekt se dvěma poli. Díky tomu je čitelný
/// v JSONu na disku, dá se použít jako klíč slovníku (viz `CodingKeyRepresentable` níž)
/// a existuje jen jeden kanonický textový zápis — ten samý, který se ukazuje v UI.
struct RepoID: Hashable, Sendable, LosslessStringConvertible {
    let owner: String
    let name: String

    /// Invariant drží typ, ne volající. Parsování z řetězce neplatné jméno odmítne, ale
    /// tenhle init by ho pustil dál — a z obou vede stejná cesta do cache aplikace, na
    /// které se maže. `precondition` proto, že jde o chybu v kódu, ne o data z GitHubu:
    /// ten `.` ani `..` jako jméno repa nevydá.
    init(owner: String, name: String) {
        precondition(
            Self.isValidComponent(owner[...]) && Self.isValidComponent(name[...]),
            "Neplatné jméno repozitáře: \(owner)/\(name)"
        )
        self.owner = owner
        self.name = name
    }

    /// Parsuje `owner/repo`. `nil` u čehokoli jiného — dělené jméno bez jedné z půlek
    /// nebo s bílým znakem uvnitř by se dostalo až do cesty na disku a do `gh` volání.
    init?(_ description: String) {
        let parts = description.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let owner = parts.first, let name = parts.last else { return nil }
        guard Self.isValidComponent(owner), Self.isValidComponent(name) else { return nil }

        self.init(owner: String(owner), name: String(name))
    }

    var description: String { "\(owner)/\(name)" }

    /// `.` a `..` jsou odmítnuté schválně: z identifikátoru se skládá cesta do cache
    /// aplikace a na té cestě se maže. Jméno jako `../..` by mazání pustilo ven z cache.
    /// GitHub takové repo nevydá, ale kontrola je jeden řádek a chyba by byla drahá.
    private static func isValidComponent(_ component: Substring) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && !component.contains("#")
            && !component.contains("/")
            && component.allSatisfy { !$0.isWhitespace }
    }
}

extension RepoID: Codable {
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = RepoID(raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Očekáván tvar owner/repo, přišlo „\(raw)“"
            )
        }
        self = parsed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Aby `[RepoID: RepoConfig]` v JSONu vyšlo jako objekt, ne jako střídavé pole klíčů
/// a hodnot, kterým `JSONEncoder` řeší neřetězcové klíče.
extension RepoID: CodingKeyRepresentable {
    var codingKey: any CodingKey { description.codingKey }

    init?<Key: CodingKey>(codingKey: Key) {
        self.init(codingKey.stringValue)
    }
}
