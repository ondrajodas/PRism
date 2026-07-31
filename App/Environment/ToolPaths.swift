import Foundation

/// Absolutní cesty ke všem binárkám, které aplikace potřebuje.
///
/// Pole nejsou optional a typ se nedá složit z nekompletního nálezu — vzniká jen když
/// preflight prošel. Zbytek aplikace tím dostane důkaz typem, že binárky existují, a
/// nemusí u každého volání znovu řešit, co když některá chybí.
struct ToolPaths: Sendable, Equatable {
    let gh: URL
    let git: URL
    let claude: URL

    /// Vznikne jen když je nalezená každá binárka. Jinak `nil`.
    init?(found: [Tool: URL]) {
        guard let gh = found[.gh], let git = found[.git], let claude = found[.claude] else {
            return nil
        }
        self.gh = gh
        self.git = git
        self.claude = claude
    }
}
