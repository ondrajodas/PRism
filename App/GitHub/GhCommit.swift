import Foundation

/// Jedna položka `gh api repos/{o}/{r}/pulls/{n}/commits` (#316).
///
/// Vlastní typ, ne dekódování rovnou do `PullRequestCommit`: tvar odpovědi patří GitHubu, kdežto
/// model patří aplikaci — tatáž hranice jako u `GhCheck` a `GhSearchItem`.
///
/// **Skoro všechno je optional, a je to schválně.** Odpověď má přes šedesát polí a my z ní bereme
/// šest; kdyby jediné chybějící pole položilo dekódování, přišel by o seznam celý tab kvůli něčemu,
/// co se v něm nekreslí. Ověřeno na živých datech, že chybět umí `author` (u `keboola/job-queue-daemon#858`
/// je `null` u všech sedmi commitů) i `parents` u zkrácených odpovědí.
struct GhCommit: Decodable, Sendable {
    /// Vnořený git commit — jméno a datum autora sem GitHub dává i tehdy, když účet nezná.
    struct Detail: Decodable, Sendable {
        struct Signature: Decodable, Sendable {
            let name: String?
            let date: Date?
        }

        let message: String?
        let author: Signature?
    }

    struct Account: Decodable, Sendable {
        let login: String?
        let avatarURL: URL?

        private enum CodingKeys: String, CodingKey {
            case login
            // REST API píše `snake_case`, na rozdíl od `gh … --json`, které dává `camelCase`.
            // Převod klíčů se nezapíná na dekodéru: ten je společný pro obojí a přejmenoval by
            // i pole, která už `camelCase` jsou.
            case avatarURL = "avatar_url"
        }
    }

    struct Parent: Decodable, Sendable {
        let sha: String?
    }

    let sha: String
    let commit: Detail?
    let author: Account?
    let parents: [Parent]?

    /// Model pro seznam. `nil` = položka, ze které se nedá udělat řádek.
    ///
    /// Jediné, bez čeho to nejde, je **sha**: je to klíč řádku i to, čím se commit rozklikne.
    /// Chybějící jméno autora se nahradí, protože prázdné kolečko vedle zprávy je pořád seznam,
    /// kdežto vynechaný řádek je díra v postupu, o které se nikdo nedozví.
    var pullRequestCommit: PullRequestCommit? {
        guard !sha.isEmpty else { return nil }
        return PullRequestCommit(
            sha: sha,
            message: commit?.message ?? "",
            // Prázdné jméno by dalo prázdný monogram; `?` je vidět a nevypadá jako chyba kreslení.
            authorName: commit?.author?.name.flatMap { $0.isEmpty ? nil : $0 } ?? "?",
            authorLogin: author?.login,
            avatarURL: author?.avatarURL,
            committedAt: commit?.author?.date,
            // **Chybějící `parents` znamená „nevíme“, a to se počítá jako obyčejný commit.**
            // Opačná volba by z každé zkrácené odpovědi udělala sedm sloučení, tedy sedm pilulek,
            // které o commitech nic netvrdí.
            isMerge: (parents?.count ?? 0) > 1
        )
    }
}
