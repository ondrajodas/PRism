import Testing

@testable import PRism

/// Jazyk se pozná z cesty — nic chytřejšího (shebang, obsah) aplikace nedělá: diff je
/// útržek, ne celý soubor.
@Suite("Language")
struct LanguageTests {
    @Test("Přípona rozhodne o jazyku", arguments: [
        ("src/Kernel.php", "PHP"),
        ("App/Diff/DiffRow.swift", "Swift"),
        (".github/workflows/build.yml", "YAML"),
        ("config.yaml", "YAML"),
        ("package.json", "JSON"),
        ("src/index.ts", "TypeScript"),
        ("src/app.tsx", "TypeScript"),
        ("web/main.js", "JavaScript"),
        ("cmd/root.go", "Go"),
        ("README.md", "Markdown"),
        ("bin/run.sh", "Shell"),
    ])
    func detectsLanguageFromExtension(path: String, expected: String) {
        #expect(Language(path: path)?.name == expected)
    }

    /// Dockerfile a spol. příponu nemají — pozná je jméno souboru.
    @Test("Soubory bez přípony se poznají podle jména", arguments: [
        ("Dockerfile", "Dockerfile"),
        ("docker/Dockerfile", "Dockerfile"),
        ("service.Dockerfile", "Dockerfile"),
        ("Makefile", "Makefile"),
    ])
    func detectsLanguageFromFilename(path: String, expected: String) {
        #expect(Language(path: path)?.name == expected)
    }

    @Test("Velikost písmen v příponě nerozhoduje")
    func ignoresExtensionCase() {
        #expect(Language(path: "src/Kernel.PHP")?.name == "PHP")
    }

    /// Obarvit něco, čemu nerozumíme, je horší než neobarvit nic — vzory jednoho jazyka
    /// vypadají v cizím souboru jako náhodné skvrny.
    @Test("Neznámá přípona se neobarvuje", arguments: ["data.parquet", "LICENSE", "x.unknown"])
    func hasNoLanguageForUnknownFiles(path: String) {
        #expect(Language(path: path) == nil)
    }
}
