import Foundation

/// Pravidla jednoho jazyka pro obarvení kódu.
///
/// Není to gramatika — jen tolik, kolik stačí na komentáře, řetězce, čísla a klíčová
/// slova. Diff se čte, nekompiluje.
struct Language: Equatable, Sendable {
    let name: String
    /// Čím začíná komentář do konce řádku.
    let lineComments: [String]
    /// Blokový komentář; hledá se **v rámci jednoho řádku** (viz `SyntaxHighlighter`).
    let blockComment: (open: String, close: String)?
    /// Uvozovky, kterými se ohraničuje řetězec.
    let stringDelimiters: [Character]
    /// Znaky, kterými začíná proměnná (`$` v PHP a shellu). Prázdné u jazyků, kde je
    /// proměnná obyčejné jméno.
    let variableSigils: [Character]
    let keywords: Set<String>

    static func == (lhs: Language, rhs: Language) -> Bool { lhs.name == rhs.name }

    /// Jazyk podle cesty. `nil` u souboru, kterému nerozumíme — obarvit ho podle cizích
    /// pravidel je horší než neobarvit ho vůbec.
    init?(path: String) {
        let file = (path as NSString).lastPathComponent.lowercased()
        let suffix = (file as NSString).pathExtension

        guard let found = Language.byExtension[suffix] ?? Language.byFilename[file]
            // `service.Dockerfile` a spol.: jméno souboru je zároveň přípona.
            ?? Language.byFilename[suffix]
        else { return nil }
        self = found
    }

    private init(
        name: String,
        lineComments: [String] = [],
        blockComment: (open: String, close: String)? = nil,
        stringDelimiters: [Character] = [],
        variableSigils: [Character] = [],
        keywords: Set<String> = []
    ) {
        self.name = name
        self.lineComments = lineComments
        self.blockComment = blockComment
        self.stringDelimiters = stringDelimiters
        self.variableSigils = variableSigils
        self.keywords = keywords
    }
}

// MARK: - Jazyky

extension Language {
    /// Klíčová slova jsou výběr, ne úplný seznam: jde o to, aby se v kódu chytlo oko,
    /// ne aby se prošel standard.
    static let php = Language(
        name: "PHP",
        lineComments: ["//", "#"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'"],
        variableSigils: ["$"],
        keywords: [
            "abstract", "array", "as", "break", "case", "catch", "class", "const", "continue",
            "declare", "default", "do", "echo", "else", "elseif", "enum", "extends", "final",
            "finally", "fn", "for", "foreach", "function", "global", "if", "implements",
            "instanceof", "interface", "match", "namespace", "new", "null", "private",
            "protected", "public", "readonly", "return", "static", "switch", "throw", "trait",
            "try", "use", "var", "while", "yield", "true", "false",
            // Typy se v PHP píšou v hlavičkách metod všude, takže bez nich zůstane
            // nejčastější řádek souboru skoro celý černý.
            "bool", "callable", "float", "int", "iterable", "mixed", "never", "object",
            "parent", "self", "string", "void",
        ]
    )

    static let swift = Language(
        name: "Swift",
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\""],
        keywords: [
            "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch",
            "class", "continue", "default", "defer", "deinit", "do", "else", "enum", "extension",
            "fallthrough", "false", "for", "func", "guard", "if", "import", "in", "init",
            "inout", "internal", "is", "let", "mutating", "nil", "nonisolated", "operator",
            "private", "protocol", "public", "repeat", "return", "self", "some", "static",
            "struct", "subscript", "super", "switch", "throw", "throws", "true", "try",
            "typealias", "var", "where", "while",
        ]
    )

    static let yaml = Language(
        name: "YAML",
        lineComments: ["#"],
        stringDelimiters: ["\"", "'"],
        keywords: ["true", "false", "null", "yes", "no", "on", "off"]
    )

    static let json = Language(name: "JSON", stringDelimiters: ["\""], keywords: ["true", "false", "null"])

    private static let ecmaKeywords: Set<String> = [
        "as", "async", "await", "break", "case", "catch", "class", "const", "continue",
        "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally",
        "for", "from", "function", "if", "implements", "import", "in", "instanceof",
        "interface", "let", "new", "null", "of", "private", "protected", "public", "readonly",
        "return", "static", "super", "switch", "this", "throw", "true", "try", "type",
        "typeof", "undefined", "var", "void", "while", "yield",
    ]

    static let typescript = Language(
        name: "TypeScript",
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'", "`"],
        keywords: ecmaKeywords
    )

    static let javascript = Language(
        name: "JavaScript",
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'", "`"],
        keywords: ecmaKeywords
    )

    static let go = Language(
        name: "Go",
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "`"],
        keywords: [
            "break", "case", "chan", "const", "continue", "default", "defer", "else",
            "fallthrough", "false", "for", "func", "go", "goto", "if", "import", "interface",
            "map", "nil", "package", "range", "return", "select", "struct", "switch", "true",
            "type", "var",
        ]
    )

    static let shell = Language(
        name: "Shell",
        lineComments: ["#"],
        stringDelimiters: ["\"", "'"],
        variableSigils: ["$"],
        keywords: [
            "case", "do", "done", "elif", "else", "esac", "export", "fi", "for", "function",
            "if", "in", "local", "readonly", "return", "set", "then", "until", "while",
        ]
    )

    static let dockerfile = Language(
        name: "Dockerfile",
        lineComments: ["#"],
        stringDelimiters: ["\"", "'"],
        keywords: [
            "add", "arg", "cmd", "copy", "entrypoint", "env", "expose", "from", "healthcheck",
            "label", "run", "shell", "user", "volume", "workdir",
        ]
    )

    static let makefile = Language(name: "Makefile", lineComments: ["#"], stringDelimiters: ["\"", "'"])

    /// Markdown nemá klíčová slova ani komentáře; barví se v něm jen kód v zpětných
    /// apostrofech, protože to je to jediné, co má v textu jinou váhu.
    static let markdown = Language(name: "Markdown", stringDelimiters: ["`"])

    private static let byExtension: [String: Language] = [
        "php": php,
        "swift": swift,
        "yml": yaml, "yaml": yaml,
        "json": json,
        "ts": typescript, "tsx": typescript,
        "js": javascript, "jsx": javascript, "mjs": javascript,
        "go": go,
        "sh": shell, "bash": shell, "zsh": shell,
        "md": markdown, "markdown": markdown,
    ]

    private static let byFilename: [String: Language] = [
        "dockerfile": dockerfile,
        "makefile": makefile,
    ]
}
