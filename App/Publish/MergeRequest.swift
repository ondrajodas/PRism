import Foundation

/// Dotaz, kterým se merguje vlastní PR (#465). Čisté funkce, žádné I/O.
///
/// **REST, ne GraphQL**, ze stejného důvodu jako u komentáře (#216) a labelů (#392): merge se
/// adresuje číslem PR a repem, tedy tím, co `PRIdentifier` má. GraphQL `mergePullRequest` by chtěl
/// node ID, které se dnes netahá nikde.
enum MergeRequest {
    /// Tělo `PUT /pulls/{n}/merge`.
    ///
    /// **Metoda přišla z konstanty do plánu, a je to zapsaná korekce** (#556). Do #556 tady stálo
    /// `static let method = "squash"` a u toho zdůvodnění:
    ///
    /// > Volba mezi metodami tady **není**: byla by to třetí věc na potvrzení, kterou člověk projde
    /// > jednou za rok, a přepnout ji jde na GitHubu.
    ///
    /// **Praxe to vyvrátila.** Odejít z okna kvůli jedné hodnotě je dražší než ta hodnota, a squash
    /// není to, co se hodí ve všech repech: firemní repo s prořezanou historií chce merge commit.
    /// Zdůvodnění se proto **přepsalo, ne smazalo** — smazat ho a napsat nové by vypadalo jako
    /// opomenutí, kdežto takhle je poznat, že tohle je korekce. A argument z #465 o „třetí věci na
    /// potvrzení“ padl i sám: mluvil o světě, ve kterém **žádná výchozí hodnota nebyla**, takže se
    /// každý merge musel rozhodovat. Teď je předvybráno z nastavení a přepnutí je odchylka.
    ///
    /// **Rozhodnutí „jedno místo pro kresbu i pro payload“ zůstává, jen se přesunulo.** Metodu i
    /// titulek nese `MergePlan`, sheet z něj vypisuje řádky a tenhle typ ho kóduje — takže se
    /// kresba a to, co odejde, nemají jak rozejít. Skládá to `Policy.mergeCommitTitle`, tedy
    /// tatáž funkce, jejíž výsledek má člověk před očima.
    ///
    /// **`commit_title` se posílá u dvou metod ze tří.** Bez něj si ho GitHub skládá podle
    /// nastavení repozitáře (`Default to pull request title for squash merges`), do kterého
    /// aplikace nevidí — a nad repem bez práva zápisu se to nastavení ani nedá přečíst —, takže by
    /// potvrzení ukazovalo titulek, který nemusí vzniknout. **U rebase se neposílá vůbec**: žádný
    /// commit tam nevzniká, takže by to bylo pole, které GitHub zahodí, a potvrzení by slibovalo
    /// titulek, který se nikde neobjeví.
    ///
    /// **`commit_message` se naopak neposílá u žádné metody, a je to rozhodnutí.** Bez něj složí
    /// GitHub tělo podle nastavení repozitáře (na `PRism` je to `COMMIT_MESSAGES`, tedy zprávy
    /// slévaných commitů — a právě v nich je v tomhle repu zdůvodnění změny). Poslat prázdné tělo
    /// by znamenalo, že se ta próza mergem zahodí; poslat vlastní by znamenalo skládat ji podruhé
    /// tady. Co v těle bude, říká potvrzení nahlas — a od #556 **z přečteného nastavení**, ne
    /// z domněnky (`Policy.mergeBodyNotice`).
    struct Payload: Encodable, Equatable {
        /// `nil` u rebase. **Synteticky generovaný `encode(to:)` optional vynechá**
        /// (`encodeIfPresent`), takže se u rebase neposílá klíč s prázdnou hodnotou, ale žádný
        /// klíč — a to je rozdíl: `""` by GitHub vzal jako titulek.
        let commitTitle: String?
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
            mergeMethod = plan.method.rawValue
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
