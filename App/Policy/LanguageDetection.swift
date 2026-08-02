import Foundation

extension Policy {
    /// Jazyky projektu podle výpisu verzovaných souborů.
    ///
    /// Čistá funkce nad seznamem cest — kdo ten seznam sežene, sem nepatří. Dvě pravidla
    /// se sčítají:
    ///
    /// - **Marker** (`composer.json`, `go.mod`, …) jazyk zařadí bez ohledu na počty. Jeden
    ///   soubor, který o projektu prohlašuje, čím je, váží víc než statistika přípon.
    /// - **Podíl přípon**: jazyk se zařadí, když má aspoň desetinu rozpoznaných zdrojáků.
    ///   „Převažující“ znamená prominentní, ne „vyskytl se“ — jeden zatoulaný `.py` skript
    ///   v PHP repu nemá pouštět Python reviewery.
    ///
    /// Do jmenovatele jdou **jen rozpoznané zdrojáky**. S Markdownem a YAMLem uvnitř by
    /// podíl neříkal nic o kódu, protože konfigurace a dokumentace jsou v každém repu.
    ///
    /// Řadí se podle počtu souborů sestupně, při shodě podle jména. Druhé kritérium není
    /// kosmetika: množina pořadí nemá, takže by se bez něj pořadí (a s ním i pořadí skillů)
    /// měnilo mezi běhy.
    static func projectLanguages(in paths: [String]) -> [ProjectLanguage] {
        var counts: [ProjectLanguage: Int] = [:]
        var marked: Set<ProjectLanguage> = []

        for path in paths {
            let file = (path as NSString).lastPathComponent.lowercased()
            if let declared = markers[file] { marked.insert(declared) }
            if let language = languagesByExtension[(file as NSString).pathExtension] {
                counts[language, default: 0] += 1
            }
        }

        let total = counts.values.reduce(0, +)
        let floor = max(1, Int((Double(total) * prominentShare).rounded(.up)))
        let prominent = counts.filter { $0.value >= floor }.keys

        return marked.union(prominent).sorted { left, right in
            let byCount = (counts[left] ?? 0, counts[right] ?? 0)
            if byCount.0 != byCount.1 { return byCount.0 > byCount.1 }
            return left.rawValue < right.rawValue
        }
    }

    /// Kolik z rozpoznaných zdrojáků musí jazyk mít, aby se počítal.
    private static let prominentShare = 0.1

    /// Soubory, které o projektu prohlašují, čím je.
    ///
    /// **`package.json` tu schválně není**, i když ho zadání issue #24 jmenovalo: má ho
    /// každý TypeScript projekt stejně jako JavaScriptový, takže by jako marker přidával
    /// JavaScript ke každému TS repu. Čím je node projekt psaný, řeknou přípony;
    /// `tsconfig.json` je oproti tomu jednoznačný.
    private static let markers: [String: ProjectLanguage] = [
        "composer.json": .php,
        "go.mod": .go,
        "tsconfig.json": .typescript,
        "package.swift": .swift,
        "pyproject.toml": .python,
        "setup.py": .python,
        "requirements.txt": .python,
        "cargo.toml": .rust,
        "gemfile": .ruby,
        "pom.xml": .java,
        "build.gradle": .java,
        "build.gradle.kts": .kotlin,
    ]

    private static let languagesByExtension: [String: ProjectLanguage] = [
        "php": .php,
        "go": .go,
        "ts": .typescript, "tsx": .typescript,
        "js": .javascript, "jsx": .javascript, "mjs": .javascript, "cjs": .javascript,
        "swift": .swift,
        "py": .python,
        "rs": .rust,
        "rb": .ruby,
        "java": .java,
        "kt": .kotlin, "kts": .kotlin,
    ]
}
