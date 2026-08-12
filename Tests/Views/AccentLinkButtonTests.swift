import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Barva akcí v tabulce nálezů (#298) — akcent z palety místo systémové modré.
///
/// **Měří se, ne posuzuje.** Rozdíl fialové a systémové modré na jednom malém popisku se dojmem
/// neuhlídá, takže se tvrdí obojí: že barva **je** z palety (a v obou režimech jiná než
/// `NSColor.linkColor`) a že na každém podkladu, na jaký akce může padnout, **drží kontrast**.
/// Prahy jsou pod dnešními naměřenými hodnotami, takže test spadne na zhoršení, ne na zaokrouhlení
/// — tatáž kázeň jako v `DiffPaletteTests`.
///
/// Podklady jsou tři a všechny jsou skutečné: plocha řádku (`Palette.surface`), **živý** řádek
/// procházení nálezů (`accentWeak` nad plochou — akcentový text na akcentovém podkladu, tedy to
/// nejtěsnější místo) a stavový řádek (`Palette.chrome`), kde sedí `Připravit`.
@Suite("Barva akcí v tabulce nálezů")
struct AccentLinkButtonTests {
    // MARK: - Měřidlo

    /// Barva přečtená v sRGB. Neúspěch převodu se **nezamlčuje fallbackem** — hlídá ho vlastní
    /// tvrzení níž, aby se zelená sada nedala splnit měřením v cizím prostoru.
    private struct Measured {
        let color: NSColor
        let isConverted: Bool

        init(_ color: NSColor) {
            let converted = color.usingColorSpace(.sRGB)
            self.color = converted ?? color
            isConverted = converted != nil
        }

        init(_ color: Color) { self.init(NSColor(color)) }

        private func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        var luminance: Double {
            0.2126 * channel(color.redComponent) + 0.7152 * channel(color.greenComponent)
                + 0.0722 * channel(color.blueComponent)
        }

        /// Barva s krytím složená nad podkladem. **Jediné místo, kde se v téhle sadě krytí skládá**
        /// — `accentWeak` je průhledný podklad z návrhu a řádek pod ním je vždycky plocha, takže
        /// výsledek je hodnota, ne odhad.
        func over(_ bottom: Measured) -> Measured {
            let alpha = color.alphaComponent
            return Measured(
                NSColor(
                    srgbRed: color.redComponent * alpha + bottom.color.redComponent * (1 - alpha),
                    green: color.greenComponent * alpha + bottom.color.greenComponent * (1 - alpha),
                    blue: color.blueComponent * alpha + bottom.color.blueComponent * (1 - alpha),
                    alpha: 1
                )
            )
        }
    }

    private func contrast(_ first: Measured, _ second: Measured) -> Double {
        let (a, b) = (first.luminance, second.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Co se v jednom režimu měří.
    ///
    /// **Všechno se vyhodnocuje uvnitř `performAsCurrentDrawingAppearance`, i akcent sám** —
    /// dynamické `NSColor` se rozsvítí až při čtení, takže `Palette.accent` přečtený mimo tu závorku
    /// vyjde v režimu **stroje**, ne v měřeném. Bez toho sada tvrdila, že akce nemá barvu akcentu:
    /// levá strana byla světlá `#5B47E0`, pravá tmavá `#8B7CFF` z nastavení systému.
    private struct Scheme {
        let name: String
        let action: Measured
        /// Token, ze kterého má akce brát barvu — přečtený **v témže režimu** jako `action`.
        let paletteAccent: Measured
        let systemLink: Measured
        let surface: Measured
        let chrome: Measured
        /// Živý řádek procházení — `accentWeak` už složený nad plochou.
        let currentRow: Measured

        var all: [(String, Measured)] {
            [
                ("akce", action), ("akcent palety", paletteAccent), ("systémový odkaz", systemLink),
                ("plocha řádku", surface), ("stavový řádek", chrome), ("živý řádek", currentRow),
            ]
        }

        /// Podklady, na které akce může padnout, i s popiskem do hlášky.
        var backgrounds: [(String, Measured)] {
            [("ploše řádku", surface), ("živém řádku", currentRow), ("stavovém řádku", chrome)]
        }
    }

    /// **Režim se nasazuje `performAsCurrentDrawingAppearance`**, tedy tak, jak se barva vyhodnotí
    /// při kreslení — dynamické `NSColor` z palety si ho berou odsud. Že to opravdu přepíná, dokazuje
    /// test „Světlá a tmavá větev se liší“ níž.
    private func scheme(_ appearance: NSAppearance.Name, name: String) throws -> Scheme {
        let appearance = try #require(NSAppearance(named: appearance))
        var result: Scheme?
        appearance.performAsCurrentDrawingAppearance {
            let surface = Measured(Palette.surface)
            result = Scheme(
                name: name,
                action: Measured(AccentLinkButtonStyle().foreground),
                paletteAccent: Measured(Palette.accent),
                systemLink: Measured(NSColor.linkColor),
                surface: surface,
                chrome: Measured(Palette.chrome),
                currentRow: Measured(Palette.accentWeak).over(surface)
            )
        }
        return try #require(result)
    }

    private func schemes() throws -> [Scheme] {
        [try scheme(.aqua, name: "světlý"), try scheme(.darkAqua, name: "tmavý")]
    }

    // MARK: - Tvrzení

    /// **Tohle je celé #298.** Akce v tabulce si bere akcent z palety, ne systémovou `linkColor` —
    /// a tvrdí se to jako **rozdíl obou barev**, ne jen jako rovnost s `Palette.accent`: kdyby se
    /// paleta jednou posunula k modré, samotná rovnost by pořád platila a rozpor by zmizel z dohledu.
    ///
    /// Naměřeno: `#5B47E0` proti systémovému `#0068DA` ve světlém, `#8B7CFF` proti `#419CFF`
    /// v tmavém režimu.
    @Test("Akce jde z palety, ne ze systémové modré")
    func theActionColorComesFromThePalette() throws {
        for scheme in try schemes() {
            #expect(
                scheme.action.color == scheme.paletteAccent.color,
                "\(scheme.name) režim: akce nemá barvu akcentu."
            )
            #expect(
                scheme.action.color != scheme.systemLink.color,
                "\(scheme.name) režim: akce má tutéž barvu jako systémový odkaz."
            )
        }
    }

    /// **Barva je hodnota, ne krytí nad podkladem** (#277, #185). Akce leží střídavě na ploše řádku
    /// a na podbarveném živém řádku, takže `accent.opacity(…)` by se měnila podle toho, kde stojí.
    @Test("Barva akce je neprůhledná, ne krytí nad podkladem")
    func theActionColorIsOpaque() throws {
        for scheme in try schemes() {
            #expect(
                scheme.action.color.alphaComponent == 1,
                "\(scheme.name) režim: akce má krytí \(scheme.action.color.alphaComponent) místo jedničky."
            )
        }
    }

    /// **Kontrola měřidla** — všechna čísla stojí na složkách přečtených v sRGB.
    @Test("Barvy jde přečíst v sRGB")
    func colorsConvertToSRGB() throws {
        for scheme in try schemes() {
            for (label, color) in scheme.all {
                #expect(color.isConverted, "\(scheme.name) režim: \(label) se nepřevedl do sRGB.")
            }
        }
    }

    /// Obě větve tokenu musí být jiné, jinak by tvrzení výš i níž vycházela i tehdy, kdyby se tmavý
    /// režim vůbec nevyhodnotil — a měřidlo by mlčelo o tom, že měří jeden režim dvakrát.
    @Test("Světlá a tmavá větev se liší")
    func lightAndDarkDiffer() throws {
        let schemes = try schemes()
        let light = try #require(schemes.first), dark = try #require(schemes.last)
        #expect(light.action.color != dark.action.color)
        #expect(light.surface.color != dark.surface.color)
    }

    /// Kontrast akce na každém podkladu, na jaký může padnout, v obou režimech.
    ///
    /// Práh **4,5** je WCAG AA pro běžný text a akce je `.caption`, tedy malé písmo — slabší práh by
    /// tady nedával smysl. Naměřeno (světlý / tmavý): plocha řádku 6,14 / 5,64, živý řádek
    /// 5,30 / 4,70, stavový řádek 5,82 / 5,33.
    ///
    /// **V tmavém režimu je to výměna, ne zlepšení**: systémová modrá tam měla 6,51 / 5,43 / 6,16,
    /// tedy o kus víc. Ve světlém je to naopak (5,26 / 4,54 / 4,99). Rozhoduje jedna barva pro
    /// „klikni sem“ v celém okně, a rezerva nad AA zůstává v obou režimech na všech třech
    /// podkladech — je to tatáž úvaha jako u zelené diffu v #277 (7,42 → 5,95).
    @Test("Akce je čitelná na každém podkladu, na který může padnout")
    func theActionIsReadableOnEveryBackground() throws {
        for scheme in try schemes() {
            for (label, background) in scheme.backgrounds {
                let value = contrast(scheme.action, background)
                #expect(value >= 4.5, "\(scheme.name): akce na \(label) má kontrast \(value).")
            }
        }
    }

    /// Nejtěsnější místo si zaslouží vlastní tvrzení: **akcentový text na akcentovém podkladu**.
    /// Živý řádek procházení (#219) se podbarvuje `accentWeak`, takže kdyby se ten podklad zesílil,
    /// akce by na něm zhasla jako první — a stalo by se to jen na jednom řádku z tabulky, tedy
    /// přesně tam, kde si toho nikdo nevšimne.
    ///
    /// Práh 4,5 vychází z 5,30 ve světlém a 4,70 v tmavém režimu.
    @Test("Akce nezhasne ani na podbarveném živém řádku")
    func theActionSurvivesTheAccentedRow() throws {
        for scheme in try schemes() {
            let value = contrast(scheme.action, scheme.currentRow)
            #expect(value >= 4.5, "\(scheme.name): akce na živém řádku má kontrast \(value).")
        }
    }

    /// `Vrátit` na **odmítnutém** řádku — jediné místo, kde je akce ztlumená.
    ///
    /// Odmítnutí ztlumí **celý** řádek na 52 % (#113: ztlumit, ne schovat), takže se přes akci
    /// prosvítá plocha. Slabý kontrast tam je proto vlastnost **řádku**, ne barvy — a akci z toho
    /// ztlumení vyjmout nelze, jinak by odmítnutý řádek křičel jednou barvou víc než platný.
    /// Že se přeškrtává jen text nálezu a `blokuje` zůstává, hlídá `FindingSeverityBadgeTests`.
    ///
    /// Co ale hlídat jde, a co se rozbije potichu, je **zhoršení**: kdyby se akcent posunul blíž
    /// k ploše, `Vrátit` by z odmítnutého řádku zmizel jako první a všude jinde by zůstal čitelný.
    /// Naměřeno 2,35 (světlý) a 2,40 (tmavý); systémová modrá tam měla 2,26 a 2,63, takže se ve
    /// světlém režimu polepšilo a v tmavém je to tatáž výměna jako u ostatních podkladů.
    @Test("Vrátit se neztratí ani ve ztlumení odmítnutého řádku")
    func theRestoreActionSurvivesTheDismissedRow() throws {
        for scheme in try schemes() {
            let dimmed = Measured(scheme.action.color.withAlphaComponent(FindingTableRowView.dismissedOpacity))
                .over(scheme.surface)
            let value = contrast(dimmed, scheme.surface)
            #expect(value >= 2.2, "\(scheme.name): Vrátit na odmítnutém řádku má kontrast \(value).")
        }
    }
}
