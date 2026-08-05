import Foundation

/// Identita nálezu napříč běhy — to, podle čeho se pozná, že se **týž** nález vrátil.
///
/// Skládá ji `Policy.key(of:)` a **nikdo jiný**: kdyby se klíč skládal na dvou místech, po
/// druhém běhu by se označení přestalo párovat a **tiše zmizelo**. Proto tady žije jen tvar,
/// ne pravidlo.
///
/// Zpátky se neparsuje. Nese volný text od revieweera, takže rozdělení na části by bylo
/// hádání — a k ničemu: klíč slouží k vyhledání, ne k rekonstrukci nálezu. `init` proto
/// řetězec bere, jak je.
struct FindingKey: Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }
}

extension FindingKey: Codable {
    init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Aby `[FindingKey: FindingDismissal]` v JSONu vyšlo jako objekt, ne jako pole střídavých
/// klíčů a hodnot. Stejný důvod jako u `PRIdentifier`.
extension FindingKey: CodingKeyRepresentable {
    var codingKey: any CodingKey { rawValue.codingKey }

    init?<Key: CodingKey>(codingKey: Key) {
        self.init(codingKey.stringValue)
    }
}
