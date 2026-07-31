import Foundation

/// Externí binárka, na které aplikace stojí.
///
/// Hledá se absolutní cestou — aplikace spuštěná z Finderu nedědí `PATH` ze shellu, takže
/// podle jména by se nenašla ani jedna z nich.
enum Tool: String, CaseIterable, Sendable {
    case gh
    case git
    case claude

    /// Jméno souboru, který se hledá na disku.
    var executableName: String { rawValue }

    /// K čemu ji aplikace potřebuje. Text pro blokující obrazovku — na ní má být vidět,
    /// co se rozbije, ne jen že něco chybí.
    var purpose: String {
        switch self {
        case .gh: "Vyhledává pull requesty a čte jejich diff."
        case .git: "Klonuje repozitáře do cache aplikace."
        case .claude: "Spouští review session."
        }
    }

    /// Jak ji nainstalovat. Text pro blokující obrazovku.
    var installHint: String {
        switch self {
        case .gh: "brew install gh"
        case .git: "xcode-select --install"
        case .claude: "curl -fsSL https://claude.ai/install.sh | bash"
        }
    }
}
