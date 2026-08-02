import Foundation
import Testing

@testable import PRism

/// Odhad jazyka projektu z výpisu verzovaných souborů. Čistá funkce, nemockuje se nic.
@Suite("Policy — jazyk projektu")
struct LanguageDetectionTests {
    private func detect(_ paths: [String]) -> [ProjectLanguage] {
        Policy.projectLanguages(in: paths)
    }

    /// Násobení souborů, ať se testy netočí kolem prahu, když jde o něco jiného.
    private func files(_ template: String, _ count: Int) -> [String] {
        (0..<count).map { template.replacingOccurrences(of: "#", with: "\($0)") }
    }

    // MARK: - Jednojazyčné projekty

    @Test("PHP projekt")
    func detectsPHP() {
        let paths = ["composer.json", "README.md", ".github/workflows/ci.yml"] + files("src/Service#.php", 20)

        #expect(detect(paths) == [.php])
    }

    @Test("Go projekt")
    func detectsGo() {
        #expect(detect(["go.mod", "go.sum", "main.go", "internal/server/http.go"]) == [.go])
    }

    @Test("TypeScript projekt")
    func detectsTypeScript() {
        let paths = ["package.json", "tsconfig.json", "package-lock.json"] + files("src/component#.ts", 15)

        #expect(detect(paths) == [.typescript])
    }

    /// `package.json` **není** marker: má ho každý TypeScript projekt stejně jako
    /// JavaScriptový, takže by JavaScript přidával úplně všude.
    @Test("Samotný package.json JavaScript nezpůsobí")
    func doesNotTreatPackageJsonAsAMarker() {
        #expect(detect(["package.json", "README.md"]).isEmpty)
    }

    @Test("Swift projekt")
    func detectsSwift() {
        #expect(detect(["Package.swift", "Sources/App/main.swift"]) == [.swift])
    }

    // MARK: - Smíšené a hraniční

    /// Řadí se od nejsilnějšího, protože z toho pořadí vyjde pořadí skillů.
    @Test("Smíšený projekt vrací oba jazyky od nejsilnějšího")
    func ordersAMixedProjectByWeight() {
        let paths = files("app/Model#.php", 30) + files("assets/script#.ts", 10)

        #expect(detect(paths) == [.php, .typescript])
    }

    /// „Převažující“ znamená prominentní, ne „vyskytl se“. Jeden zatoulaný skript nemá
    /// pouštět další reviewery — session stojí peníze.
    @Test("Jeden zatoulaný soubor cizího jazyka se nepočítá")
    func ignoresAStraySourceFile() {
        let paths = files("src/Service#.php", 50) + ["bin/prevod.py"]

        #expect(detect(paths) == [.php])
    }

    /// Marker přebíjí počty: soubor, který o projektu prohlašuje, čím je, váží víc než
    /// statistika přípon.
    @Test("Marker zařadí jazyk i bez souborů")
    func trustsAMarkerOverCounts() {
        let paths = files("src/Service#.php", 50) + ["go.mod"]

        #expect(detect(paths) == [.php, .go])
    }

    @Test("Prázdný repozitář nevrací nic")
    func returnsNothingForAnEmptyRepository() {
        #expect(detect([]).isEmpty)
    }

    @Test("Repozitář bez zdrojáků nevrací nic")
    func returnsNothingWithoutSourceFiles() {
        #expect(detect(["README.md", "docs/navrh.md", ".gitignore", "config.yml"]).isEmpty)
    }

    /// Bez druhého kritéria by pořadí určovala množina, tedy náhoda — a s ním by se měnilo
    /// pořadí skillů mezi běhy.
    @Test("Při shodě počtů rozhoduje jméno")
    func breaksTiesByName() {
        let paths = files("a/x#.go", 10) + files("b/y#.php", 10)

        #expect(detect(paths) == [.go, .php])
    }

    @Test("Na velikosti písmen v markeru nezáleží")
    func matchesMarkersCaseInsensitively() {
        #expect(detect(["CARGO.TOML"]) == [.rust])
    }

    @Test("Marker se pozná i v podsložce")
    func findsAMarkerInASubdirectory() {
        #expect(detect(["services/api/go.mod"]) == [.go])
    }
}
