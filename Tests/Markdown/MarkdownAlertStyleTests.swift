import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Vzhled výstrah (#279). Nejcennější je tady to, co tvrdí, že se něco **NEstalo**: že se
/// `[!CAUTION]` nesešel s červenou blokujícího nálezu a `[!WARNING]` s okrovou zastarání. GitHub
/// jim dává přesně tyhle dvě barvy, takže by to bylo snadné převzít — a v tomhle okně už obě
/// něco znamenají.
@Suite("MarkdownAlertStyle")
struct MarkdownAlertStyleTests {
    /// Barva se řeší **v obou režimech**: token je dynamický, takže shoda může být jen v jednom
    /// z nich a ve druhém ne.
    ///
    /// Nepovedený převod se **neschovává za výchozí barvu**: dva neúspěchy by daly dvakrát černou
    /// a z porovnání by vyšlo, že se dvě barvy rovnají — tedy hlášení o paletě nad chybou v sondě.
    /// Proto `#require`, ne `?? .black`.
    private func hex(_ color: Color, dark: Bool) throws -> String {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var converted: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            converted = NSColor(color).usingColorSpace(.sRGB)
        }
        let resolved = try #require(converted)
        return String(
            format: "%02X%02X%02X%.2f",
            Int((resolved.redComponent * 255).rounded()),
            Int((resolved.greenComponent * 255).rounded()),
            Int((resolved.blueComponent * 255).rounded()),
            resolved.alphaComponent
        )
    }

    @Test("Každý druh má vlastní barvu")
    func givesEveryKindItsOwnColor() throws {
        for dark in [false, true] {
            let colors = try MarkdownBlock.Alert.allCases.map { try hex(MarkdownAlertStyle.of($0).color, dark: dark) }
            #expect(Set(colors).count == MarkdownBlock.Alert.allCases.count, "tmavý: \(dark), \(colors)")
        }
    }

    @Test("`[!CAUTION]` nesplyne s červenou blokujícího nálezu")
    func keepsCautionApartFromCrit() throws {
        for dark in [false, true] {
            #expect(try hex(MarkdownAlertStyle.of(.caution).color, dark: dark) != hex(Palette.crit, dark: dark))
        }
    }

    @Test("`[!WARNING]` nesplyne s okrovou zastarání")
    func keepsWarningApartFromStale() throws {
        for dark in [false, true] {
            #expect(try hex(MarkdownAlertStyle.of(.warning).color, dark: dark) != hex(Palette.stale, dark: dark))
        }
    }

    /// Význam nesmí stát jen na barvě: titulek je česky (je to popisek aplikace, ve zdroji je jen
    /// `[!NOTE]`) a ikona je vyplněná, aby byla při dvanácti bodech vidět.
    @Test("Každý druh má český titulek a ikonu")
    func namesEveryKind() {
        let titles = MarkdownBlock.Alert.allCases.map { MarkdownAlertStyle.of($0).title }

        #expect(Set(titles).count == titles.count, "titulky se opakují: \(titles)")
        #expect(!titles.contains { $0.isEmpty })
        for kind in MarkdownBlock.Alert.allCases {
            let symbol = MarkdownAlertStyle.of(kind).symbol
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(kind): \(symbol)")
        }
    }
}
