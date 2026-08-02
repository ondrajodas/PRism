import Foundation

/// Pokus o nástroj: co si reviewer vyžádal a nad čím.
///
/// **Pokus, ne použití** — odmítnutý nástroj vypadá stejně. Že prošel, říká teprve to, že
/// není v `deniedTools`.
struct ToolAttempt: Hashable, Sendable {
    let name: String
    /// Soubor, vzor nebo příkaz — podle nástroje. `nil`, když se z volání nedá vytáhnout
    /// nic užitečného. Samotné „Read“ v tabu Průběh nic neřekne.
    let detail: String?

    /// Klíče, pod kterými nástroje `claude` nesou to podstatné, v pořadí, v jakém se
    /// zkoušejí. Neznámý nástroj detail prostě nemá — hádat by znamenalo ukázat cizí číslo
    /// jako cestu.
    /// `skill` je mezi nimi od #78: bez něj je v ose vidět holé „Skill“ a nepozná se,
    /// **který** se načetl — a právě to je u něj ta zajímavá informace.
    static let detailKeys = [
        "file_path", "notebook_path", "pattern", "command", "path", "query", "url", "skill",
    ]

    init(name: String, input: [String: Any]?) {
        self.name = name
        detail = ToolAttempt.detailKeys
            .lazy
            .compactMap { input?[$0] as? String }
            .first { !$0.isEmpty }
    }

    init(name: String, detail: String?) {
        self.name = name
        self.detail = detail
    }

    /// Detail bez toho, co je na každém řádku stejné.
    ///
    /// Reviewer běží v pracovním stromě, takže **každá** cesta začíná sedmdesáti znaky
    /// cache a příkazy navíc uvozuje `cd <strom> &&`. V ose z toho není poznat nic — a
    /// zajímavý je soubor, ne kde ho aplikace má.
    func shortened(inside worktree: URL?) -> String? {
        guard let detail, let worktree else { return detail }
        let path = worktree.path(percentEncoded: false)

        var result = detail
        for prefix in ["cd \"\(path)\" && ", "cd '\(path)' && ", "cd \(path) && "] {
            if result.hasPrefix(prefix) {
                result.removeFirst(prefix.count)
                break
            }
        }
        // Zbylé výskyty jsou cesty uvnitř příkazu (`grep … <strom>/apps`).
        result = result.replacingOccurrences(of: path + "/", with: "")
        result = result.replacingOccurrences(of: path, with: "")
        return result
    }

    /// Ořezávat zprava, nebo zleva? U cesty je zajímavý konec (jméno souboru), u příkazu
    /// začátek (co se spouští).
    var keepsTail: Bool {
        ToolAttempt.pathTools.contains(name)
    }

    private static let pathTools: Set<String> = ["Read", "NotebookRead", "Edit", "Write"]
}
