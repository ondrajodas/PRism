import Foundation

/// Značka `Prošlo` u jednoho souboru v diffu (#500).
///
/// **Je o obsahu, ne o hlavě.** Nese otisk souboru z doby, kdy se zaškrtla (`FileDiff.blobs`),
/// takže nový commit, který soubor nemění, ji nechá — a commit, který ho mění, z ní udělá
/// `změněno od prošlého`. Nikdy tedy netvrdí „prošlo“ nad kódem, který už není: je to tvrdá
/// podmínka č. 5 v duchu, jen nad souborem místo nad nálezem.
struct ReadMark: Codable, Hashable, Sendable {
    /// Otisk obsahu v době zaškrtnutí. `nil` = diff ho v tu chvíli nenesl (přejmenování beze
    /// změny obsahu) — a je to hodnota, ne chybějící údaj, viz `FileDiff.blobs`.
    var blobs: String?
    /// Kdy se zaškrtlo. Kreslí se v hlavičce souboru (`Prošlo · před 5 min`): značka bez času
    /// neodpoví na otázku „bylo to před tím pushem, nebo po něm“.
    var markedAt: Date
}

/// Značky jednoho pull requestu — klíčem je `FileDiff.displayPath`, tedy to jméno, pod kterým
/// soubor vystupuje ve stromu i v hlavičce.
///
/// **Ukládá se k PR, ne k `headSha`** (jako rozhovor, #452). Klíčovat to commitem by značku
/// smazalo právě tím pushem, kvůli kterému se člověk do diffu vrací — a rozlišit „prošlo“ od
/// „změněno od prošlého“ by pak nebylo z čeho.
struct ReadMarks: Codable, Hashable, Sendable {
    let pullRequest: PRIdentifier
    var marks: [String: ReadMark] = [:]

    var isEmpty: Bool { marks.isEmpty }

    func mark(of path: String) -> ReadMark? { marks[path] }
}
