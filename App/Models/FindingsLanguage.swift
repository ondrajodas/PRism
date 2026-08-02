import Foundation

/// Jazyk, ve kterém se nálezy **ukazují**.
///
/// Ne jazyk, ve kterém je reviewer píše — ten dostává pořád tentýž anglický prompt a o jazyku
/// se v něm nic neříká. Sem se překládá až po doběhnutí běhu, viz `FindingTranslating`.
///
/// **Není to `ProjectLanguage`** — ten říká, čím je repo psané, a vybírá podle toho sadu
/// skillů. Tohle je jazyk prózy v `summary`, `short_summary` a `failure_scenario`.
///
/// Uzavřený výčet, ne volný řetězec, i když ostatní volby v konfiguraci volné jsou
/// (skilly, kategorie, model). Důvod je, že hodnota jde do **anglické věty v promptu** a do
/// **českého popisku v okně** — u volného řetězce by první záviselo na tom, jak ho uživatel
/// napíše, a druhé by nešlo ukázat vůbec. Přidat jazyk je jeden case a dva řetězce.
enum FindingsLanguage: String, CaseIterable, Codable, Hashable, Sendable {
    case czech = "cs"
    case english = "en"

    /// Jak se jazyk píše v okně nastavení.
    var displayName: String {
        switch self {
        case .czech: "Česky"
        case .english: "Anglicky"
        }
    }

    /// Jak se jazyk jmenuje ve větě, kterou dostane **překladač** (`Translate … into
    /// Czech`). Anglicky, protože ten prompt je anglický a jméno se do něj dosazuje.
    /// Reviewer tenhle řetězec nikdy nevidí.
    var promptName: String {
        switch self {
        case .czech: "Czech"
        case .english: "English"
        }
    }
}
