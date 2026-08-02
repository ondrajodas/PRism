import Foundation

/// Jazyk projektu — to, podle čeho se vybírá výchozí sada review skillů.
///
/// **Není to `Language` z `App/Syntax/`.** Ta odpovídá na „jak tenhle řádek obarvit“
/// a patří k ní YAML, JSON i Markdown; tady jde o „co je tohle za projekt“, kde soubor
/// `README.md` neznamená nic. Spojit je do jednoho výčtu by znamenalo, že rozpoznat
/// Python vyžaduje umět ho obarvit — a naopak že každý repozitář vyjde jako „YAML“.
///
/// `CodingKeyRepresentable` proto, aby mapa `[ProjectLanguage: [String]]` vyšla v JSONu
/// jako čitelný objekt, ne jako pole střídavých klíčů a hodnot. Soubor se edituje ručně.
enum ProjectLanguage: String, CaseIterable, Codable, CodingKeyRepresentable, Hashable, Sendable {
    case php
    case go
    case typescript
    case javascript
    case swift
    case python
    case rust
    case ruby
    case java
    case kotlin

    /// Jak se jazyk píše v UI. Raw value je klíč do konfigurace, ne text pro člověka.
    var displayName: String {
        switch self {
        case .php: "PHP"
        case .go: "Go"
        case .typescript: "TypeScript"
        case .javascript: "JavaScript"
        case .swift: "Swift"
        case .python: "Python"
        case .rust: "Rust"
        case .ruby: "Ruby"
        case .java: "Java"
        case .kotlin: "Kotlin"
        }
    }
}
