import Foundation
import Testing

@testable import PRism

/// Odkazy na místo v kódu v odpovědi (#452).
@Suite("Odkazy z odpovědi (#452)")
struct AskReferencesTests {
    @Test("Najde cestu s řádkem, i uprostřed věty a v inline kódu")
    func findsReferences() {
        #expect(
            Policy.askReferences(in: "Stojí to na `App/Views/Palette.swift:42`, jinde ne.")
                == [AskReference(file: "App/Views/Palette.swift", line: 42)]
        )
        #expect(
            Policy.askReferences(in: "SecretClient.php:80")
                == [AskReference(file: "SecretClient.php", line: 80)]
        )
    }

    /// **Duplicity se zahazují a pořadí zůstává textové**: model tentýž řádek zmíní v odstavci
    /// i v shrnutí a dvě stejné kapsle vypadají jako dvě různá místa.
    @Test("Duplicita je jedna kapsle, pořadí je pořadí v textu")
    func deduplicatesKeepingOrder() {
        let text = "b.swift:2 a pak a.swift:1 a znovu b.swift:2"

        #expect(Policy.askReferences(in: text) == [
            AskReference(file: "b.swift", line: 2),
            AskReference(file: "a.swift", line: 1),
        ])
    }

    /// **Tvrdí, že se něco NEstalo**: z URL se odkaz nevyrobí. Dvojtečka s číslem je v ní port,
    /// takže by kapsle ukazovala na řádek, který nikdo nezmínil.
    @Test("Z URL se odkaz nevyrábí")
    func ignoresURLs() {
        #expect(Policy.askReferences(in: "viz https://example.com:8080/x").isEmpty)
        #expect(Policy.askReferences(in: "http://host.io:443").isEmpty)
    }

    /// Přípona je povinná a číslo musí být kladné — bez toho by se `verze 1.2:0` četla jako cesta.
    @Test("Bez přípony a s nulovým řádkem se odkaz nevyrobí")
    func requiresAnExtensionAndAPositiveLine() {
        #expect(Policy.askReferences(in: "issue #452:12").isEmpty)
        #expect(Policy.askReferences(in: "soubor:80").isEmpty)
        #expect(Policy.askReferences(in: "a.swift:0").isEmpty)
    }

    /// Strop je tu proto, že odpověď umí vyjmenovat dvacet míst — a dvacet kapslí pod bublinou
    /// přestane být odkazem a stane se tabulkou.
    @Test("Odkazů se z jedné odpovědi vydá nejvýš šest")
    func stopsAtTheLimit() {
        let text = (1...20).map { "f\($0).swift:\($0)" }.joined(separator: " ")

        #expect(Policy.askReferences(in: text).count == Policy.askReferenceLimit)
        #expect(Policy.askReferenceLimit == 6)
    }
}
