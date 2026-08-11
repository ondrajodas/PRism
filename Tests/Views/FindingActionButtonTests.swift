import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Řada akcí u nálezu v diffu (#283) — malá tlačítka podle návrhu místo modrých odkazů.
///
/// Testuje se dvojí, a obojí se rozbije **potichu**: rozměry, které se z návrhu opsaly (a odchylku
/// od nich by na screenshotu nikdo nezměřil), a popisky, které mají **dvě podoby** — přídavné jméno
/// do odznaku a tvrzení na tlačítko. Splynutí těch dvou je ta nejpravděpodobnější budoucí chyba:
/// z odznaku odmítnutého nálezu by se stalo `Zamítnout`, tedy akce v místě, kde se hlásí stav.
@Suite("Akce u nálezu — tlačítka podle návrhu")
struct FindingActionButtonTests {
    // MARK: - Rozměry z návrhu

    /// Hodnoty jsou z CSS mockupu (`.mini`, `.inline-find footer`) a berou se 1 : 1 jako body.
    /// Test je tady proto, že je to jediné tvrzení o vzhledu, které nestojí na obrázku — a obrázek
    /// se u čísel tohohle řádu (3 vs. 4 body) neposoudí.
    @Test("Rozměry malého tlačítka sedí na CSS návrhu")
    func metricsMatchTheMockup() {
        #expect(MiniButtonStyle.Metrics.fontSize == 11.5)
        #expect(MiniButtonStyle.Metrics.verticalPadding == 3)
        #expect(MiniButtonStyle.Metrics.horizontalPadding == 9)
        #expect(MiniButtonStyle.Metrics.cornerRadius == 6)
        #expect(MiniButtonStyle.Metrics.spacing == 7)
        #expect(MiniButtonStyle.Metrics.borderWidth == 1)
    }

    /// **Obtažení se musí připočítat k odsazení.** CSS ho má vně `padding`u, SwiftUI ho kreslí
    /// `overlay`em dovnitř rámce — takže padding opsaný z CSS 1 : 1 dá tlačítko o dva body nižší.
    /// Změřeno renderem vedle návrhu; bez tohohle vycházelo 23 bodů proti 25.
    @Test("Obtažení je součástí odsazení, jako v CSS boxu")
    func theBorderCountsTowardsTheBox() {
        #expect(MiniButtonStyle.Metrics.insetVertical == 4)
        #expect(MiniButtonStyle.Metrics.insetHorizontal == 10)
    }

    /// Výška, kterou návrh dává malým ovladačům (`.tbtn.key { height: 25px }`) a která u `.mini`
    /// vychází z paddingu a výšky řádku. Změřeno na renderu: návrh 25,0 bodu, aplikace 25,0.
    @Test("Tlačítko je 25 bodů vysoké jako v návrhu")
    func theButtonIsAsTallAsTheMockup() {
        #expect(abs(MiniButtonStyle.Metrics.height - 25) < 0.5)
    }

    @Test("Obtažené tlačítko má barvy z palety, ne ze systému")
    func theSecondaryButtonUsesThePalette() {
        let style = MiniButtonStyle(emphasis: .secondary)

        #expect(style.background == Palette.surface)
        #expect(style.border == Palette.line)
        #expect(style.foreground == Palette.ink2)
    }

    @Test("Plné tlačítko je akcentové, obrys nemá vlastní barvu")
    func thePrimaryButtonIsAccented() {
        let style = MiniButtonStyle(emphasis: .primary)

        #expect(style.background == Palette.accent)
        #expect(style.border == Palette.accent)
    }

    /// Návrh má `color: var(--panel)`, ne bílou — a rozdíl je vidět **jen v tmavém režimu**, kde
    /// by zadrátovaná bílá na světle fialovém akcentu byla slabší, než má být. Kdo to jednou
    /// „zjednoduší“ na `.white`, ve světlém režimu žádnou změnu neuvidí.
    @Test("Text plného tlačítka je barva panelu, ne zadrátovaná bílá")
    func thePrimaryLabelFollowsThePanelColor() throws {
        let style = MiniButtonStyle(emphasis: .primary)
        #expect(style.foreground == Palette.surface)

        let light = try resolve(style.foreground, in: .aqua)
        let dark = try resolve(style.foreground, in: .darkAqua)

        // Ve světlém režimu z toho bílá vyjde…
        #expect(light.redComponent == 1 && light.greenComponent == 1 && light.blueComponent == 1)
        // …a v tmavém ne, což je celý smysl toho, že se bere z palety.
        #expect(dark.redComponent < 0.2 && dark.greenComponent < 0.2 && dark.blueComponent < 0.2)
    }

    // MARK: - Popisky odmítnutí

    /// Návrh má na tlačítkách velké písmeno a žádné uvozující `Odmítnout:`, takže popisek musí
    /// obstát sám. Vyčerpávající výčet: každý důvod svůj popisek má a žádné dva nejsou stejné —
    /// dvě tlačítka vedle sebe se stejným textem jsou horší než menu.
    @Test("Každý důvod odmítnutí má vlastní popisek na tlačítko")
    func everyReasonHasItsOwnActionLabel() {
        let labels = FindingDismissal.Reason.allCases.map(\.actionLabel)

        #expect(labels == ["Neplatí", "Nepatří sem"])
        #expect(Set(labels).count == FindingDismissal.Reason.allCases.count)
        #expect(labels.allSatisfy { $0.first?.isUppercase == true })
    }

    /// **Tvrzení o tom, co se NEzměnilo.** `label` visí v odznaku odmítnutého nálezu a v kontextovém
    /// menu tabulky (`Označit jako …`), tedy na dvou místech, kde se hlásí **stav**. Kdyby se
    /// přejmenoval na popisek z návrhu, odznak by řekl `Zamítnout` — akci v místě, kde má být
    /// vlastnost.
    @Test("Popisek do odznaku zůstává přídavné jméno")
    func theBadgeLabelStaysAnAdjective() {
        #expect(FindingDismissal.Reason.invalid.label == "neplatný")
        #expect(FindingDismissal.Reason.irrelevant.label == "irelevantní")

        for reason in FindingDismissal.Reason.allCases {
            #expect(reason.label != reason.actionLabel)
            #expect(reason.label.first?.isLowercase == true)
        }
    }

    /// Nápověda u tlačítka je to jediné, co ty dva důvody rozliší do podrobna — popisek je krátký
    /// schválně. Bez ní by se `Neplatí` a `Nepatří sem` daly splést.
    @Test("Každý důvod má vysvětlení do nápovědy")
    func everyReasonExplainsItself() {
        for reason in FindingDismissal.Reason.allCases {
            #expect(!reason.explanation.isEmpty)
            #expect(reason.explanation != reason.actionLabel)
        }
    }

    // MARK: - Pomůcka

    /// Barvu z palety vyhodnotí až vzhled okna, takže se musí rozsvítit ručně. `NSColor` se
    /// převádí do sRGB, jinak nemá komponenty.
    ///
    /// Obojí přes `#require`, ne `?? .clear`: kdyby se převod nepovedl, test by porovnával
    /// průhlednou černou a **vypadalo by to jako chyba v paletě**, ne jako nepovedené měření.
    private func resolve(_ color: Color, in name: NSAppearance.Name) throws -> NSColor {
        let appearance = try #require(NSAppearance(named: name))
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB)
        }
        return try #require(resolved)
    }
}
