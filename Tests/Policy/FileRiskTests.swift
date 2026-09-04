import Foundation
import Testing

@testable import PRism

/// Pořadí souborů podle rizika (#506) — **vyčerpávající výčet**, protože z toho pořadí se čte
/// diff a je to jediné místo, kde se rozhoduje, co se čte první.
///
/// Sada souborů je ta ze **sekce 03 návrhu** (`SecretClient.php` s blokujícím nálezem,
/// `Encryptor.php` s nálezem, nový `SecretNotFound.php`, test, `composer.json`,
/// `composer.lock`, `phpunit.xml.dist`) — tedy skutečná data z toho obrázku, nad kterým se
/// o pořadí rozhodovalo.
@Suite("Policy — soubory podle rizika (#506)")
struct FileRiskTests {
    private let files = [
        ItineraryFileFactory.file("src/Vault/SecretClient.php", additions: 18, deletions: 6),
        ItineraryFileFactory.file("src/Vault/Encryptor.php", additions: 4, deletions: 2),
        ItineraryFileFactory.file("src/Vault/SecretNotFound.php", change: .added, additions: 21, deletions: 0),
        ItineraryFileFactory.file("tests/SecretClientTest.php", additions: 64, deletions: 0),
        ItineraryFileFactory.file("composer.json", additions: 2, deletions: 1),
        ItineraryFileFactory.file("composer.lock", additions: 1_402, deletions: 1_388),
        ItineraryFileFactory.file("phpunit.xml.dist", additions: 1, deletions: 1),
    ]

    private let markers: [String: FileMarker] = [
        "src/Vault/SecretClient.php": .blocking,
        "src/Vault/Encryptor.php": .findings,
    ]

    private func paths(_ items: [ItineraryFileItem]) -> [String] {
        items.flatMap { item in
            switch item {
            case .file(let file, _): [file.displayPath]
            case .bundle(let files): ["bundle(\(files.count))"]
            }
        }
    }

    /// **Pořadí ze zadání**: blokující → nález → vlákno → nový → ostatní → konfigurace a locky.
    @Test("Sekce 03 se seřadí blokující, nález, nový, ostatní, konfigurace")
    func section03OrdersByRisk() {
        let items = Policy.filesByRisk(files, markers: markers)
        #expect(paths(items) == [
            "src/Vault/SecretClient.php",
            "src/Vault/Encryptor.php",
            "src/Vault/SecretNotFound.php",
            "tests/SecretClientTest.php",
            "bundle(3)",
        ])
        #expect(items.map(\.risk) == [.blocking, .finding, .added, .other, .configuration])
    }

    /// Vlákno posadí soubor **mezi nález a nový** — někdo se na něj ptá a čeká na odpověď.
    @Test("Vlákno posadí soubor za nálezy a před nové")
    func threadsRankAfterFindings() {
        let items = Policy.filesByRisk(
            files,
            markers: markers,
            threadPaths: ["tests/SecretClientTest.php"]
        )
        #expect(paths(items) == [
            "src/Vault/SecretClient.php",
            "src/Vault/Encryptor.php",
            "tests/SecretClientTest.php",
            "src/Vault/SecretNotFound.php",
            "bundle(3)",
        ])
    }

    /// **Nález přebíjí konfiguraci.** `composer.json` s blokujícím nálezem je blokující soubor,
    /// ne šum na konci — bez toho by se nález schoval do složené položky.
    @Test("Nález vytáhne konfiguraci nahoru")
    func findingsOutrankConfiguration() {
        let items = Policy.filesByRisk(files, markers: ["composer.json": .blocking])
        #expect(paths(items).first == "composer.json")
        #expect(items.first?.risk == .blocking)
        // Zbylé dvě konfigurace se pořád složí.
        #expect(paths(items).last == "bundle(2)")
    }

    /// **Konfigurace přebíjí `nový` a `ostatní`, a je to rozhodnutí proti doslovnému čtení
    /// zadání.** Pořadí v issue má `nový` před konfigurací, takže by nový lock soubor vyšel jako
    /// `nový` — jenže nový `composer.lock` je pořád tisíc řádků, které nikdo nepíše rukou.
    /// Klasifikace tedy jde konfigurací dřív; **kreslí** se pořád poslední.
    @Test("Nová konfigurace se pořád složí do konfigurací")
    func newConfigurationStaysInTheBundle() {
        let items = Policy.filesByRisk([
            ItineraryFileFactory.file("composer.lock", change: .added, additions: 1_402, deletions: 0),
            ItineraryFileFactory.file("package-lock.json", change: .added, additions: 900, deletions: 0),
            ItineraryFileFactory.file("src/A.php", change: .added, additions: 10, deletions: 0),
        ])
        #expect(paths(items) == ["src/A.php", "bundle(2)"])
    }

    /// Uvnitř skupiny se řadí **podle cesty**, ne podle velikosti změny: hledá se v tom očima
    /// a stěhující se řádky jsou horší než neoptimální pořadí.
    @Test("Uvnitř skupiny se řadí podle cesty")
    func filesInsideAGroupSortByPath() {
        let items = Policy.filesByRisk([
            ItineraryFileFactory.file("src/Z.php", additions: 500),
            ItineraryFileFactory.file("src/A.php", additions: 1),
            ItineraryFileFactory.file("src/M.php", additions: 50),
        ])
        #expect(paths(items) == ["src/A.php", "src/M.php", "src/Z.php"])
    }

    /// **Jedna konfigurace se neskládá**: rozbalovací řádek `1 konfigurace a lock` by byl klik
    /// navíc k témuž souboru.
    @Test("Jedna konfigurace zůstane samostatným řádkem")
    func aSingleConfigurationFileIsNotBundled() {
        let items = Policy.filesByRisk([
            ItineraryFileFactory.file("src/A.php"),
            ItineraryFileFactory.file("composer.json"),
        ])
        #expect(paths(items) == ["src/A.php", "composer.json"])
        #expect(items.last?.risk == .configuration)
    }

    @Test("Popisek složené položky se skloňuje")
    func bundleLabelIsDeclined() {
        #expect(Policy.configurationBundleLabel(count: 1) == "1 konfigurace a lock")
        #expect(Policy.configurationBundleLabel(count: 3) == "3 konfigurace a locky")
        #expect(Policy.configurationBundleLabel(count: 12) == "12 konfigurací a locků")
    }

    /// Prázdný diff dá prázdný seznam — žádná skupina, žádný nadpis nad ničím.
    @Test("Prázdný diff nemá žádnou položku")
    func anEmptyDiffHasNoItems() {
        #expect(Policy.filesByRisk([]).isEmpty)
        #expect(Policy.itineraryGroups([]).isEmpty)
    }

    /// Skupiny se skládají **z hotového seznamu**, takže je jich nejvýš jedna na riziko a jsou
    /// v tom pořadí, ve kterém položky přišly.
    @Test("Skupiny mají identitu podle rizika a jsou v pořadí kresby")
    func groupsAreKeyedByRisk() {
        let groups = Policy.itineraryGroups(Policy.filesByRisk(files, markers: markers))
        #expect(groups.map(\.risk) == [.blocking, .finding, .added, .other, .configuration])
        #expect(groups.map(\.id) == groups.map(\.risk))
        #expect(groups.map(\.items.count) == [1, 1, 1, 1, 1])
        #expect(groups.map(\.risk.groupTitle) == [
            "Blokující", "S nálezem", "Nové", "Ostatní", "Konfigurace a locky",
        ])
    }

    // MARK: - Co je konfigurace

    /// **Výčet jmen a přípon, ne heuristika.** „Vypadá to na konfiguraci“ se nedá napsat tak,
    /// aby to nesnědlo soubory, které se číst mají.
    @Test("Konfigurace a locky se poznají z výčtu")
    func configurationIsRecognisedFromTheList() {
        for path in [
            "composer.json",
            "composer.lock",
            "package-lock.json",
            "pnpm-lock.yaml",
            "Package.resolved",
            "Gemfile.lock",
            "uv.lock",
            "phpunit.xml.dist",
            "config/services.yaml",
            "Cargo.toml",
            "setup.cfg",
            "tox.ini",
            "Info.plist",
            "Signing.xcconfig",
            ".gitignore",
            ".editorconfig",
        ] {
            #expect(Policy.isConfigurationPath(path), "\(path) má být konfigurace")
        }
    }

    /// **Kód konfigurace není**, i když má v cestě `config/` nebo v příponě `xml`: v XML se píšou
    /// Android layouty a XSLT, `config/routes.php` je kód.
    @Test("Kód konfigurace není")
    func codeIsNotConfiguration() {
        for path in [
            "src/Vault/SecretClient.php",
            "config/routes.php",
            "App/Policy/Policy.swift",
            "docs/navrh.html",
            "README.md",
            "res/layout/activity_main.xml",
            "bin/run.sh",
            "Dockerfile",
        ] {
            #expect(!Policy.isConfigurationPath(path), "\(path) konfigurace není")
        }
    }

    /// Rozhoduje **poslední složka cesty**, ne prefix — jinak by `.github/workflows/push.yml`
    /// prošlo kvůli tečce na začátku cesty a `src/.hidden/A.php` taky.
    @Test("Rozhoduje jméno souboru, ne cesta k němu")
    func onlyTheFileNameDecides() {
        #expect(!Policy.isConfigurationPath("src/.hidden/Client.php"))
        // `.yml` chytí přípona, ne tečka v cestě — a je to správný výsledek.
        #expect(Policy.isConfigurationPath(".github/workflows/push.yml"))
    }
}
