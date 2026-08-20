import SwiftUI
import Testing

@testable import PRism

/// Klíče bloku kódu — podle nich se text **znovu nesází** (#157, #278) a `updateNSView` se vrátí,
/// aniž by cokoli přepočítal (#393).
///
/// Nejcennější tvrzení je tady to, že se dva různé stavy **nesejdou v jednom klíči**: kdyby se
/// sešly, blok by se přeskočil jako nezměněný a v okně by zbyl kód obarvený podle předchozího
/// režimu — a potichu, protože text ani jazyk se nezměnily. Přesně to by po přepnutí vzhledu
/// nechalo v otevřeném diffu barvy z toho druhého režimu.
///
/// Druhá polovina je **šířka**, a ta je v jednom klíči a ve druhém ne. Rámečky řádků se z ní
/// počítají, takže do `DiffBlockDrawing` patří; sazba na ní nezávisí, takže do `DiffBlockStyle`
/// nepatří — jinak by tažení za hranu okna rušilo rozdělaný výběr.
@Suite("Klíče bloku kódu")
struct DiffBlockStyleTests {
    private let swift = Language(path: "Cart.swift")

    private func lines(_ texts: [String]) -> [DiffLine] {
        texts.map { DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: $0) }
    }

    private func block(_ texts: [String]) -> DiffBlock {
        DiffBlock(lines: lines(texts))
    }

    @Test("Světlý a tmavý režim mají různý klíč")
    func separatesTheColourSchemes() {
        #expect(
            DiffBlockStyle(language: swift, colorScheme: .light)
                != DiffBlockStyle(language: swift, colorScheme: .dark)
        )
    }

    /// Paleta se bere **z klíče**, ne od volajícího (#393) — jinak by se dala nasadit paleta, která
    /// k režimu v klíči nepatří, a stráž nad sazbou by tiše nechala v okně barvy z minula.
    @Test("Paleta jde z barevného režimu v klíči")
    func paletteFollowsTheScheme() {
        #expect(DiffBlockStyle(language: swift, colorScheme: .light).palette == .intelliJLight)
        #expect(DiffBlockStyle(language: swift, colorScheme: .dark).palette == .darcula)
    }

    @Test("Jiný jazyk má jiný klíč")
    func separatesLanguages() {
        #expect(
            DiffBlockStyle(language: swift, colorScheme: .dark)
                != DiffBlockStyle(language: Language(path: "app.php"), colorScheme: .dark)
        )
    }

    /// Blok bez rozpoznaného jazyka je pořád jeden stav, ne chybějící klíč — a od bloku s jazykem se
    /// musí lišit, jinak by se obarvený a neobarvený text potkaly v cache.
    @Test("Blok bez jazyka má vlastní klíč")
    func handlesAMissingLanguage() {
        let none = DiffBlockStyle(language: nil, colorScheme: .light)

        #expect(none != DiffBlockStyle(language: swift, colorScheme: .light))
        #expect(none == DiffBlockStyle(language: nil, colorScheme: .light))
    }

    /// Tentýž stav musí dát tentýž klíč — jinak by se text sázel při každém přejezdu myší znovu
    /// a zrušil by se výběr (#157).
    @Test("Tentýž stav dá tentýž klíč")
    func isStableForTheSameState() {
        #expect(
            DiffBlockStyle(language: swift, colorScheme: .dark)
                == DiffBlockStyle(language: swift, colorScheme: .dark)
        )
    }

    /// **Obsah bloku je v klíči kreslení**, ne jeho hash: dva bloky o stejné délce a jiném textu se
    /// nesmí sejít, jinak by v okně zůstal kód z jiného úseku souboru.
    @Test("Jiný obsah bloku má jiný klíč kreslení")
    func drawingSeparatesContent() {
        let style = DiffBlockStyle(language: swift, colorScheme: .light)
        let base = DiffBlockDrawing(block: block(["let a = 1"]), style: style, width: 900)

        #expect(base != DiffBlockDrawing(block: block(["let b = 1"]), style: style, width: 900))
        #expect(base == DiffBlockDrawing(block: block(["let a = 1"]), style: style, width: 900))
    }

    /// **Šířka v klíči kreslení být musí.** Rámečky řádků z ní vycházejí a ve split pohledu z nich
    /// i hranice pravé poloviny (`DiffGutterGeometry.split`), takže bez ní by po změně šířky okna
    /// svítila pilulka jinde, než kde se táhne rozsah.
    @Test("Jiná šířka má jiný klíč kreslení")
    func drawingSeparatesWidth() {
        let style = DiffBlockStyle(language: swift, colorScheme: .light)

        #expect(
            DiffBlockDrawing(block: block(["let a = 1"]), style: style, width: 900)
                != DiffBlockDrawing(block: block(["let a = 1"]), style: style, width: 600)
        )
    }

    /// A režim i jazyk se do klíče kreslení promítnou taky — je v něm celý `DiffBlockStyle`, takže
    /// se přepnutí vzhledu nemá kde ztratit.
    @Test("Klíč kreslení nese i jazyk a režim")
    func drawingCarriesTheStyle() {
        let base = DiffBlockDrawing(
            block: block(["let a = 1"]),
            style: DiffBlockStyle(language: swift, colorScheme: .light),
            width: 900
        )

        #expect(base != DiffBlockDrawing(
            block: block(["let a = 1"]),
            style: DiffBlockStyle(language: swift, colorScheme: .dark),
            width: 900
        ))
        #expect(base != DiffBlockDrawing(
            block: block(["let a = 1"]),
            style: DiffBlockStyle(language: Language(path: "app.php"), colorScheme: .light),
            width: 900
        ))
    }

    /// Dvojice se porovnává po stranách — a **na prázdné straně taky** (#277): `nil` a prázdný
    /// kontextový řádek jsou v textu k nerozeznání, ale v modelu dva různé bloky.
    @Test("Dvojice se v klíči kreslení liší i prázdnou stranou")
    func drawingSeparatesMissingSide() {
        let style = DiffBlockStyle(language: swift, colorScheme: .light)
        let line = lines(["let a = 1"])[0]
        let both = DiffPairBlock(left: [line], right: [line])
        let onlyRight = DiffPairBlock(left: [nil], right: [line])

        #expect(
            DiffBlockDrawing(block: both, style: style, width: 900)
                != DiffBlockDrawing(block: onlyRight, style: style, width: 900)
        )
    }
}
