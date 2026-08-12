import SwiftUI
import Testing

@testable import PRism

/// Podpis bloku kódu — klíč, podle kterého se text **znovu nesází** (#157, #278).
///
/// Nejcennější tvrzení je tady to, že se dva různé stavy **nesejdou v jednom podpisu**: kdyby se
/// sešly, blok by se přeskočil jako nezměněný a v okně by zbyl kód obarvený podle předchozího
/// režimu — a potichu, protože text ani jazyk se nezměnily. Přesně to by po přepnutí vzhledu
/// nechalo v otevřeném diffu barvy z toho druhého režimu.
@Suite("Podpis bloku kódu")
struct DiffBlockSignatureTests {
    private let swift = Language(path: "Cart.swift")

    @Test("Světlý a tmavý režim mají různý podpis")
    func separatesTheColourSchemes() {
        let light = DiffBlockSignature.of(blockHash: 42, language: swift, colorScheme: .light)
        let dark = DiffBlockSignature.of(blockHash: 42, language: swift, colorScheme: .dark)

        #expect(light != dark)
    }

    @Test("Jiný obsah i jiný jazyk mají různý podpis")
    func separatesContentAndLanguage() {
        let base = DiffBlockSignature.of(blockHash: 42, language: swift, colorScheme: .dark)

        #expect(base != DiffBlockSignature.of(blockHash: 43, language: swift, colorScheme: .dark))
        #expect(base != DiffBlockSignature.of(blockHash: 42, language: Language(path: "app.php"), colorScheme: .dark))
    }

    /// Blok bez rozpoznaného jazyka je pořád jeden stav, ne chybějící klíč — a od bloku s jazykem se
    /// musí lišit, jinak by se obarvený a neobarvený text potkaly v cache.
    @Test("Blok bez jazyka má vlastní podpis")
    func handlesAMissingLanguage() {
        let none = DiffBlockSignature.of(blockHash: 42, language: nil, colorScheme: .light)

        #expect(none != DiffBlockSignature.of(blockHash: 42, language: swift, colorScheme: .light))
        #expect(none == DiffBlockSignature.of(blockHash: 42, language: nil, colorScheme: .light))
    }

    /// Tentýž stav musí dát tentýž podpis — jinak by se text sázel při každém přejezdu myší znovu
    /// a zrušil by se výběr (#157).
    @Test("Tentýž stav dá tentýž podpis")
    func isStableForTheSameState() {
        #expect(
            DiffBlockSignature.of(blockHash: 7, language: swift, colorScheme: .dark)
                == DiffBlockSignature.of(blockHash: 7, language: swift, colorScheme: .dark)
        )
    }
}
