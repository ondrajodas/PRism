import Foundation

/// Pull request napříč repozitáři — `owner/repo#číslo`.
///
/// Klíč všeho, co se k PR váže: PR ze dvou zdrojů se podle něj deduplikuje, review stavy
/// i uložené nálezy se podle něj hledají. Stejně jako `RepoID` se kóduje na jediný řetězec.
struct PRIdentifier: Hashable, Sendable, LosslessStringConvertible, Comparable {
    let repo: RepoID
    let number: Int

    /// Pořadí je `(owner, repo, číslo)` a **číslo se srovnává číselně**.
    ///
    /// Řadit podle `description` je past, do které tenhle repozitář spadl třikrát: řetězcově
    /// vyjde `#10` před `#2`. Determinismus by to sice zachovalo, ale výpis, ve kterém jde
    /// desítka před dvojkou, vypadá rozbitě — a je to jediná věc, kterou od pořadí PR
    /// v seznamu chceme. Proto je to **jedno místo** a všechna řazení jdou přes něj.
    static func < (left: PRIdentifier, right: PRIdentifier) -> Bool {
        (left.repo.owner, left.repo.name, left.number)
            < (right.repo.owner, right.repo.name, right.number)
    }

    init(repo: RepoID, number: Int) {
        self.repo = repo
        self.number = number
    }

    /// Parsuje `owner/repo#číslo`. Číslo musí být kladné celé — GitHub jiné nedává
    /// a nula by tiše vyrobila klíč k neexistujícímu PR.
    init?(_ description: String) {
        let parts = description.split(separator: "#", omittingEmptySubsequences: false)
        guard parts.count == 2, let repoPart = parts.first, let numberPart = parts.last else {
            return nil
        }
        guard let repo = RepoID(String(repoPart)),
              let number = Int(numberPart), number > 0
        else { return nil }

        self.init(repo: repo, number: number)
    }

    var description: String { "\(repo)#\(number)" }
}

extension PRIdentifier: Codable {
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = PRIdentifier(raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Očekáván tvar owner/repo#číslo, přišlo „\(raw)“"
            )
        }
        self = parsed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Aby `[PRIdentifier: ReviewState]` v JSONu vyšlo jako objekt.
extension PRIdentifier: CodingKeyRepresentable {
    var codingKey: any CodingKey { description.codingKey }

    init?<Key: CodingKey>(codingKey: Key) {
        self.init(codingKey.stringValue)
    }
}
