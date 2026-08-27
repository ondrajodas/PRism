import Foundation

/// Dotaz, kterým se merguje vlastní PR (#465). Čisté funkce, žádné I/O.
///
/// **REST, ne GraphQL**, ze stejného důvodu jako u komentáře (#216) a labelů (#392): merge se
/// adresuje číslem PR a repem, tedy tím, co `PRIdentifier` má. GraphQL `mergePullRequest` by chtěl
/// node ID, které se dnes netahá nikde.
enum MergeRequest {
    /// Metoda merge. **Jedna, a jedno místo** — čte ji payload i potvrzení v okně, takže se kresba
    /// a to, co odejde, nemůžou rozejít.
    ///
    /// Squash proto, že tak se v tomhle repu merguje a titulek PR je z něj commit message. Volba
    /// mezi metodami tady **není**: byla by to třetí věc na potvrzení, kterou člověk projde
    /// jednou za rok, a přepnout ji jde na GitHubu.
    static let method = "squash"

    /// Tělo `PUT /pulls/{n}/merge`.
    ///
    /// **`commit_title` se posílá vždycky.** Bez něj si ho GitHub skládá podle nastavení
    /// repozitáře (`Default to pull request title for squash merges`), do kterého aplikace nevidí —
    /// a potvrzení by ukazovalo titulek, který nemusí vzniknout. Skládá ho `Policy.squashTitle`,
    /// takže je to tatáž hodnota, kterou má člověk před očima.
    ///
    /// **`commit_message` se naopak neposílá, a je to rozhodnutí.** Bez něj složí GitHub tělo
    /// squash commitu ze zpráv slévaných commitů (ověřeno na `PRism`, kde tak vypadá celá
    /// historie `main`u) — a právě v nich je v tomhle repu zdůvodnění změny. Poslat prázdné tělo by
    /// znamenalo, že se ta próza mergem zahodí; poslat vlastní by znamenalo skládat ji podruhé
    /// tady. Že tělo bude z commitů, říká potvrzení nahlas, aby výpis neslíbil míň, než co odejde.
    struct Payload: Encodable, Equatable {
        let commitTitle: String
        let mergeMethod: String
        /// Hlava, na kterou se merguje. **Podmínka, ne údaj**: GitHub na neshodu odpoví `409`
        /// a nemergne nic, takže je to jediná ochrana, která zabírá i na commit pushnutý mezi
        /// pre-flightem a voláním. U review taková možnost není — tam se `commit_id` bere jako
        /// údaj a zastaralé review projde (změřeno u #62).
        let sha: String

        enum CodingKeys: String, CodingKey {
            case commitTitle = "commit_title"
            case mergeMethod = "merge_method"
            case sha
        }

        init(_ plan: MergePlan) {
            commitTitle = plan.commitTitle
            mergeMethod = MergeRequest.method
            sha = plan.headSha
        }
    }

    /// Argumenty pro `gh api`.
    ///
    /// Payload jde **souborem**, jako sada labelů a nový label: titulek je text, který napsal
    /// člověk do titulku PR, takže projde JSONem s uvozovkami, zalomením i emoji stejně jako
    /// cokoli jiného — a kódování zůstává na jednom místě místo druhé cesty přes `-f`.
    static func arguments(for pr: PRIdentifier, payload file: URL) -> [String] {
        [
            "api", "repos/\(pr.repo)/pulls/\(pr.number)/merge",
            "-X", "PUT",
            "--input", file.path(percentEncoded: false),
        ]
    }

    static func encoded(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }
}

/// Odpověď `PUT /pulls/{n}/merge`.
///
/// `merged` je v ní schválně: při návratovém kódu nula je vždycky `true`, ale je to jediné pole,
/// kterým odpověď o výsledku **mluví sama** — a tvrdit „mergnuto“ z toho, že se nic nepokazilo, je
/// přesně ten druh textu v UI, který slibuje víc, než data unesou.
struct GhMergeResponse: Decodable {
    let sha: String?
    let merged: Bool?
    let message: String?

    /// `nil` = odpovědi nerozumíme, nebo GitHub říká, že se nemergovalo.
    ///
    /// **Chybějící `sha` se nedoplňuje prázdným řetězcem**, stejně jako chybějící autor
    /// u odeslaného review: mergnutý PR commit vždycky má, takže jeho absence znamená, že
    /// odpověď není tím, co čekáme.
    func merge() -> MergedPullRequest? {
        guard merged == true, let sha, !sha.isEmpty else { return nil }
        return MergedPullRequest(sha: sha)
    }
}
