import Foundation

/// Jedna anotace z `gh api repos/{o}/{r}/check-runs/{id}/annotations` (#214).
///
/// Vlastní typ, ne dekódování rovnou do `CheckAnnotation`: tvar odpovědi patří GitHubu, kdežto
/// model patří aplikaci — tatáž hranice jako u `GhCheck` a `GhSearchItem`.
/// Vlastní `CodingKeys` proto, že tohle je **REST**, ne `gh --json`: pole se jmenují
/// `start_line` a `annotation_level`. `GhOutput.decoder` snake case nepřevádí a zapínat mu ho
/// globálně by změnilo dekódování všech ostatních typů — tatáž úvaha jako u `GhRelease`.
struct GhAnnotation: Decodable, Sendable {
    let path: String?
    let startLine: Int?
    let annotationLevel: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case path, message
        case startLine = "start_line"
        case annotationLevel = "annotation_level"
    }

    var annotation: CheckAnnotation {
        CheckAnnotation(
            // Anotace bez cesty se stává: `Process completed with exit code 1` u některých
            // workflow přijde s prázdnou cestou. Prázdný řetězec by v odkazu vypadal jako soubor
            // bez jména, takže se z toho stane poznatelné „bez místa“.
            path: path.flatMap { $0.isEmpty ? nil : $0 } ?? "(bez souboru)",
            // `start_line` je u anotací mimo soubor `0` — a nula není řádek, takže se z ní musí
            // stát „nevím“, jinak by odkaz skákal na začátek souboru.
            line: startLine.flatMap { $0 > 0 ? $0 : nil },
            level: CheckAnnotation.Level(rawValue: annotationLevel ?? ""),
            // Bez zprávy je anotace k ničemu, ale zahodit ji taky nejde — počet by pak
            // nesouhlasil s tím, co CI nahlásilo.
            message: message.flatMap { $0.isEmpty ? nil : $0 } ?? "(bez zprávy)"
        )
    }
}
