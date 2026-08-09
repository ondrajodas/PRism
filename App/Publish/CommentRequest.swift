import Foundation

/// Dotaz, kterým se píše komentář do diskuze pod PR (#216). Čisté funkce, žádné I/O.
///
/// **REST, ne GraphQL — opačně než u vláken** (#73, `ThreadRequest`). Tam rozhodlo, že mutace
/// bere `id`, které v modelu už je; tady je to naopak: `addComment` chce `subjectId`, tedy node
/// ID pull requestu, a to se dnes netahá nikde — ani `PRIdentifier`, ani `PullRequest` ho nemá.
/// Doplnit ho by znamenalo rozšířit dotaz, model i mapování jen kvůli jednomu volání, kdežto
/// REST si vystačí s `repo` a číslem, které v `PRIdentifier` jsou.
///
/// Komentář pod PR je z pohledu API **issue comment**, ne review comment: nepatří k řádku ani
/// k review, a proto pro něj neexistuje nic v `/pulls/`.
enum CommentRequest {
    /// Argumenty pro `gh api`.
    ///
    /// Tělo jde přes `-f` (`--raw-field`), ne `-F`: `--field` čte hodnotu začínající `@` jako
    /// jméno souboru, takže by komentář začínající zmínkou (`@ondrajodas ...`) skončil jako
    /// pokus o čtení souboru. Tatáž volba jako u odpovědi do vlákna.
    static func arguments(for pr: PRIdentifier, body: String) -> [String] {
        [
            "api", "repos/\(pr.repo)/issues/\(pr.number)/comments",
            "-X", "POST",
            "-f", "body=\(body)",
        ]
    }
}
