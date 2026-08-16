import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Mint proti akcentu (#309) — dvě barvy tam, kde okno mělo tři.
///
/// **Měří se, ne posuzuje.** Otázka „pozná se stav od akce“ se dá zodpovědět obrázkem
/// (`FindingActionColourProbe`), ale otázky „je ten odznak čitelný“ a „nesplynul mint s něčím, co
/// v okně už něco znamená“ se dojmem neuhlídají — tyrkysová, zelená prošlého checku a okrová
/// zastarání jsou na malém odznaku snadno zaměnitelné.
///
/// Dvě míry naráz, ze stejného důvodu jako v `DiffPaletteTests`: **WCAG** u textu na podkladu
/// (mint je popisek a odznak, tedy malé písmo, práh 4,5) a **ΔE2000** u dvojic barev, které se
/// mají od sebe poznat jako barvy. Kdyby se hlídala jen jedna, dala by se druhá pokazit potichu.
///
/// Prahy jsou svázané s dnešními naměřenými hodnotami a leží kus pod nimi, takže sada spadne na
/// zhoršení, ne na zaokrouhlení — tatáž kázeň jako v `AccentLinkButtonTests`.
@Suite("Mint proti akcentu")
struct MintTokenTests {
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

        /// Lab (D65) — z něj se počítá ΔE2000.
        var lab: (L: Double, a: Double, b: Double) {
            let r = channel(color.redComponent), g = channel(color.greenComponent), b = channel(color.blueComponent)
            let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
            let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
            let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
            func f(_ t: Double) -> Double { t > 0.008856 ? pow(t, 1.0 / 3) : (7.787 * t + 16.0 / 116) }
            let fx = f(x), fy = f(y), fz = f(z)
            return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
        }

        /// Barva s krytím složená nad podkladem — jediné místo, kde se v téhle sadě krytí skládá.
        /// Používá se na kapsli odznaku (`mint` na 15 %, `.pill.mint` z návrhu), na podbarvený
        /// živý řádek a na ztlumení odmítnutého řádku.
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

    /// CIEDE2000 — vzdálenost dvou barev včetně sytosti, kterou WCAG nevidí. Tentýž výpočet jako
    /// v `DiffPaletteTests`; kopie proto, že sady si měřidlo nesou samy a sdílený helper by je
    /// svázal do jednoho souboru, který by pak měřil dvě různé věci.
    private func deltaE(_ first: Measured, _ second: Measured) -> Double {
        let (l1, a1, b1) = first.lab
        let (l2, a2, b2) = second.lab
        let c1ab = (a1 * a1 + b1 * b1).squareRoot(), c2ab = (a2 * a2 + b2 * b2).squareRoot()
        let cBar = (c1ab + c2ab) / 2
        let g = 0.5 * (1 - (pow(cBar, 7) / (pow(cBar, 7) + pow(25, 7))).squareRoot())
        let a1p = (1 + g) * a1, a2p = (1 + g) * a2
        let c1p = (a1p * a1p + b1 * b1).squareRoot(), c2p = (a2p * a2p + b2 * b2).squareRoot()
        func hue(_ a: Double, _ b: Double) -> Double {
            guard a != 0 || b != 0 else { return 0 }
            let h = atan2(b, a) * 180 / .pi
            return h < 0 ? h + 360 : h
        }
        let h1p = hue(a1p, b1), h2p = hue(a2p, b2)
        let dLp = l2 - l1
        let dCp = c2p - c1p
        var dhp = 0.0
        if c1p * c2p != 0 {
            dhp = h2p - h1p
            if dhp > 180 { dhp -= 360 } else if dhp < -180 { dhp += 360 }
        }
        let dHp = 2 * (c1p * c2p).squareRoot() * sin(dhp * .pi / 360)
        let lBar = (l1 + l2) / 2
        let cBarP = (c1p + c2p) / 2
        var hBar = h1p + h2p
        if c1p * c2p != 0 {
            if abs(h1p - h2p) <= 180 { hBar = (h1p + h2p) / 2 }
            else if h1p + h2p < 360 { hBar = (h1p + h2p + 360) / 2 }
            else { hBar = (h1p + h2p - 360) / 2 }
        }
        let t = 1 - 0.17 * cos((hBar - 30) * .pi / 180) + 0.24 * cos(2 * hBar * .pi / 180)
            + 0.32 * cos((3 * hBar + 6) * .pi / 180) - 0.20 * cos((4 * hBar - 63) * .pi / 180)
        let dTheta = 30 * exp(-pow((hBar - 275) / 25, 2))
        let rc = 2 * (pow(cBarP, 7) / (pow(cBarP, 7) + pow(25, 7))).squareRoot()
        let sl = 1 + (0.015 * pow(lBar - 50, 2)) / (20 + pow(lBar - 50, 2)).squareRoot()
        let sc = 1 + 0.045 * cBarP
        let sh = 1 + 0.015 * cBarP * t
        let rt = -sin(2 * dTheta * .pi / 180) * rc
        return (pow(dLp / sl, 2) + pow(dCp / sc, 2) + pow(dHp / sh, 2) + rt * (dCp / sc) * (dHp / sh)).squareRoot()
    }

    // MARK: - Jeden režim

    /// **Všechno se čte uvnitř `performAsCurrentDrawingAppearance`, i samotné tokeny** — dynamické
    /// `NSColor` se rozsvítí až při čtení, takže `Palette.mint` přečtený mimo tu závorku vyjde
    /// v režimu **stroje**, ne v měřeném. Naražené na tom u #298.
    private struct Scheme {
        let name: String
        let mint: Measured
        let accent: Measured
        let systemMint: Measured
        let ok: Measured
        let stale: Measured
        let surface: Measured
        let chrome: Measured
        /// Živý řádek procházení — `accentWeak` už složený nad plochou.
        let currentRow: Measured
        /// Pruhy rozsahu v diffu, vyhodnocené tak, jak je čte `DiffTextView` (`NSColor(…)`).
        let rangeTint: Measured
        let dragTint: Measured

        var tokens: [(String, Measured)] {
            [
                ("mint", mint), ("akcent", accent), ("systémová mint", systemMint), ("ok", ok),
                ("stale", stale), ("plocha", surface), ("chrome", chrome), ("živý řádek", currentRow),
            ]
        }
    }

    private func scheme(_ name: NSAppearance.Name, label: String) throws -> Scheme {
        let appearance = try #require(NSAppearance(named: name))
        var result: Scheme?
        appearance.performAsCurrentDrawingAppearance {
            let surface = Measured(Palette.surface)
            result = Scheme(
                name: label,
                mint: Measured(Palette.mint),
                accent: Measured(Palette.accent),
                systemMint: Measured(Color.mint),
                ok: Measured(Palette.ok),
                stale: Measured(Palette.stale),
                surface: surface,
                chrome: Measured(Palette.chrome),
                currentRow: Measured(Palette.accentWeak).over(surface),
                rangeTint: Measured(DiffLineView.rangeTint),
                dragTint: Measured(DiffLineView.dragTint)
            )
        }
        return try #require(result)
    }

    private func schemes() throws -> [Scheme] {
        [try scheme(.aqua, label: "světlý"), try scheme(.darkAqua, label: "tmavý")]
    }

    // MARK: - Kontrola měřidla

    /// Obě větve tokenu musí být jiné, jinak by tvrzení níž vycházela i tehdy, kdyby se tmavý
    /// režim vůbec nevyhodnotil — a měřidlo by mlčelo o tom, že měří jeden režim dvakrát.
    @Test("Světlá a tmavá větev se liší")
    func lightAndDarkDiffer() throws {
        let schemes = try schemes()
        let light = try #require(schemes.first), dark = try #require(schemes.last)
        #expect(light.mint.color != dark.mint.color)
        #expect(light.surface.color != dark.surface.color)
    }

    @Test("Barvy jde přečíst v sRGB")
    func colorsConvertToSRGB() throws {
        for scheme in try schemes() {
            for (label, color) in scheme.tokens {
                #expect(color.isConverted, "\(scheme.name) režim: \(label) se nepřevedl do sRGB.")
            }
        }
    }

    // MARK: - Token

    /// Vyčíslená dvojice, ne odvozenina z akcentu — a **neprůhledná**, protože skrz krytí by
    /// prosvítal podklad a odznak by vyšel jinak na ploše řádku než na podbarveném živém řádku.
    @Test("Mint je vyčíslená hodnota, ne krytí nad podkladem")
    func mintIsAnEnumeratedValue() throws {
        for scheme in try schemes() {
            #expect(
                scheme.mint.color.alphaComponent == 1,
                "\(scheme.name) režim: mint má krytí \(scheme.mint.color.alphaComponent) místo jedničky."
            )
        }
    }

    /// **Stav se musí lišit od akce.** Kdyby se paleta jednou posunula, mohly by se ty dva tokeny
    /// potkat — a celé #309 by potichu zmizelo, protože v okně by zase byla jedna barva na obojí.
    /// Naměřeno: ΔE 39,7 světlá / 43,9 tmavá.
    @Test("Mint se nedá splést s akcentem")
    func mintIsNotTheAccent() throws {
        for scheme in try schemes() {
            let value = deltaE(scheme.mint, scheme.accent)
            #expect(value >= 25, "\(scheme.name): mint je od akcentu vzdálený jen ΔE \(value).")
        }
    }

    /// **Nesmí splynout s tím, co v okně už něco znamená**: `ok` je prošlý check a čisté review,
    /// `stale` je zastarání. Obojí je odznak podobné velikosti na téže ploše, takže rozhoduje
    /// barva, ne tvar.
    ///
    /// Naměřeno proti `ok` 16,6 světlá / 21,1 tmavá, proti `stale` 37,9 / 39,4. Práh 12 je nad
    /// hranicí „na první pohled jiná barva“ (~10) a pod dneškem — `ok` je z těch dvou ta těsnější,
    /// protože obě barvy jsou syté a tmavé; `stale` je okrová, tedy jinde na kruhu.
    @Test("Mint nesplyne s ok ani se stale")
    func mintStaysAwayFromOkAndStale() throws {
        for scheme in try schemes() {
            let ok = deltaE(scheme.mint, scheme.ok), stale = deltaE(scheme.mint, scheme.stale)
            #expect(ok >= 12, "\(scheme.name): mint proti ok jen ΔE \(ok).")
            #expect(stale >= 12, "\(scheme.name): mint proti stale jen ΔE \(stale).")
        }
    }

    /// **Ne systémová `.mint`**, kterou do #309 bralo odmítnuté review.
    ///
    /// Naměřeno ΔE **22,9** ve světlém režimu (`#00C8B3`) a **1,6** v tmavém (`#00DAC3`) — tedy ta
    /// nejhorší možná dvojice: v tmavém by ty dvě tyrkysové splynuly a ve světlém ne, takže by
    /// odmítnuté review vypadalo podle režimu jednou stejně jako `2×` a jednou jinak. Právě proto
    /// se sjednotily do jednoho tokenu, ne proto, že by systémová byla „ošklivá“.
    ///
    /// **Neasertuje se tu vzdálenost**, jen to, že barva ze systému nepochází: v tmavém režimu je
    /// ΔE 1,6, takže práh na vzdálenost by tvrdil pravý opak toho, co se změřilo.
    @Test("Mint není systémová tyrkysová")
    func mintIsNotTheSystemMint() throws {
        for scheme in try schemes() {
            #expect(
                scheme.mint.color != scheme.systemMint.color,
                "\(scheme.name): mint je totožný se systémovou `.mint`."
            )
        }
    }

    // MARK: - Čitelnost

    /// Mint jako **text** na každém podkladu, na jaký může padnout.
    ///
    /// Podklady jsou skutečné a jsou tři: plocha řádku (`✓ v mém review` v tabulce), `chrome`
    /// (bublina u kódu i souhrn fronty ve stavovém řádku) a podbarvený živý řádek procházení
    /// (#219) — akcentový podklad pod tyrkysovým textem, tedy to nejtěsnější místo.
    ///
    /// Naměřeno (světlý / tmavý): plocha **4,95 / 9,90**, chrome **4,70 / 9,35**, živý řádek
    /// **4,29 / 8,23**. Práh 4,5 je WCAG AA pro běžný text a odznak je `.caption2`, tedy malé
    /// písmo.
    ///
    /// **Na živém řádku je práh 4,0 a je to vlastnost řádku, ne barvy.** Podbarvení `accentWeak`
    /// stahuje pod hranici AA **celou rodinu** — `ok` tam má 4,40, `find` 4,25, `stale` 4,22 —,
    /// takže vyjmout z toho zrovna mint by znamenalo, že jeden odznak na živém řádku svítí jinak
    /// než ostatní. Hlídá se proto zhoršení: kdyby se mint posunul k ploše, zhasne nejdřív tady.
    @Test("Mint je čitelný na každém podkladu, na který může padnout")
    func mintIsReadableOnEveryBackground() throws {
        for scheme in try schemes() {
            let surface = contrast(scheme.mint, scheme.surface)
            let chrome = contrast(scheme.mint, scheme.chrome)
            let row = contrast(scheme.mint, scheme.currentRow)
            #expect(surface >= 4.5, "\(scheme.name): mint na ploše řádku má kontrast \(surface).")
            #expect(chrome >= 4.5, "\(scheme.name): mint na chrome má kontrast \(chrome).")
            #expect(row >= 4.0, "\(scheme.name): mint na živém řádku má kontrast \(row).")
        }
    }

    /// Odznak `2×` je **text na vlastní kapsli** (`.pill.mint`: mint na 15 % z návrhu), takže se
    /// neměří proti ploše, ale proti tomu, co pod textem doopravdy je. Kapsle leží střídavě na
    /// ploše řádku, na podbarveném živém řádku a v bublině na `chrome`.
    ///
    /// Naměřeno (světlý / tmavý): na ploše **4,06 / 7,42**, na živém řádku **3,54 / 6,01**, na
    /// chrome **3,87 / 6,92**.
    ///
    /// Práh **3,4**, ne 4,5: kapsle ztmavuje text pod hranici AA u **všech** odznaků v okně
    /// (`blokuje` má na ploše 4,21, `vyřešeno` 4,15, `1 nález` 4,02) — je to vlastnost konstrukce
    /// z návrhu, který ji kreslí u všech stejně (`color-mix(… 15 %, transparent)`). Vyjmout z toho
    /// `2×` by znamenalo jeden odznak v řadě, který vypadá jinak než ostatní. Mint je uvnitř téhle
    /// rodiny na horní půlce, ne pod ní.
    @Test("Odznak 2× je čitelný i na své kapsli")
    func theAgreementPillStaysReadable() throws {
        for scheme in try schemes() {
            let wash = Measured(scheme.mint.color.withAlphaComponent(0.15))
            for (label, background) in [
                ("ploše řádku", scheme.surface), ("živém řádku", scheme.currentRow), ("chrome", scheme.chrome),
            ] {
                let value = contrast(scheme.mint, wash.over(background))
                #expect(value >= 3.4, "\(scheme.name): `2×` na \(label) má kontrast \(value).")
            }
        }
    }

    /// Odmítnutý řádek je ztlumený na 52 % (#113: ztlumit, ne schovat) a `2×` na něm zůstat může —
    /// odmítnout se dá i nález, na kterém se shodli dva reviewery. Slabý kontrast je tam vlastnost
    /// **řádku**, ne barvy, takže se hlídá jen **zhoršení**: kdyby se mint posunul blíž k ploše,
    /// zmizel by nejdřív odsud a všude jinde by zůstal čitelný.
    ///
    /// Naměřeno 2,14 (světlý) a 3,49 (tmavý).
    @Test("Mint se neztratí ani ve ztlumení odmítnutého řádku")
    func mintSurvivesTheDismissedRow() throws {
        for scheme in try schemes() {
            let dimmed = Measured(scheme.mint.color.withAlphaComponent(FindingTableRowView.dismissedOpacity))
                .over(scheme.surface)
            let value = contrast(dimmed, scheme.surface)
            #expect(value >= 1.9, "\(scheme.name): mint na odmítnutém řádku má kontrast \(value).")
        }
    }

    /// **Proč se odmítnuté review přebarvilo ze systémové tyrkysové** (#309): ta byla ve světlém
    /// režimu na ploše okna pod hranicí čitelnosti, takže odznak `odmítnuto · 3` se dal spíš
    /// tušit než přečíst. Naměřeno **2,12** systémová proti **4,95** z palety.
    ///
    /// Je to tvrzení o **zlepšení**, ne jen o změně: kdyby se token jednou posunul zpátky ke
    /// světlejší tyrkysové, spadne to tady, ne až na obrazovce.
    @Test("Mint z palety je čitelnější než systémová tyrkysová")
    func thePaletteMintReadsBetterThanTheSystemOne() throws {
        let schemes = try schemes()
        let light = try #require(schemes.first)
        let system = contrast(light.systemMint, light.surface)
        let palette = contrast(light.mint, light.surface)
        #expect(
            palette > system,
            "světlý: systémová tyrkysová má na ploše kontrast \(system), paletová \(palette)."
        )
    }

    // MARK: - Kdo si mint bere

    /// Stavy v řádku nálezu berou mint, akce akcent — tvrzení o **obojím naráz**, protože rozpor
    /// vzniká tím, že se jedno z toho zapomene.
    ///
    /// **Porovnává se přes `Measured`, ne syrové `NSColor`.** `NSColor(dynamickáBarva)` vrací
    /// katalogovou barvu, která se sobě samé nerovná ani po vyhodnocení v témže režimu — bez
    /// převodu do sRGB by sada padala na typu obálky, ne na barvě.
    @Test("Stav bere mint, akce akcent")
    func statesTakeMintAndActionsTakeTheAccent() throws {
        for (name, scheme) in try zip([NSAppearance.Name.aqua, .darkAqua], schemes()) {
            let appearance = try #require(NSAppearance(named: name))
            var action: Measured?
            var dismissedState: Measured?
            var runningState: Measured?
            appearance.performAsCurrentDrawingAppearance {
                action = Measured(AccentLinkButtonStyle().foreground)
                dismissedState = Measured(ReviewStateAppearance.color(of: .dismissed(findings: 3)))
                runningState = Measured(ReviewStateAppearance.color(of: .running(finished: 1, total: 3)))
            }
            #expect(try #require(action).color == scheme.accent.color, "\(scheme.name): akce nemá barvu akcentu.")
            #expect(
                try #require(dismissedState).color == scheme.mint.color,
                "\(scheme.name): odmítnuté review nemá mint."
            )
            // Běžící review je stav, a přesto akcent — mint dělí stav od akce **tam, kde stojí
            // vedle sebe**, a v seznamu PR žádná akce není. Návrh to kreslí stejně (`.pill.run`).
            #expect(
                try #require(runningState).color == scheme.accent.color,
                "\(scheme.name): běžící review nemá akcent."
            )
            // A obojí naráz: kdyby se tokeny potkaly, obě tvrzení výš by platila i tak.
            #expect(scheme.mint.color != scheme.accent.color)
        }
    }

    /// **Tohle je celé #309.** Odznak shody `2×` a značka `✓ v mém review` stojí mezi akcemi
    /// a nesmí mít jejich barvu — jinak se na konstatování zkouší klikat.
    ///
    /// Tvrdí se **obojí**: že barva je mint a že to **není** akcent. Samotná rovnost s mintem by
    /// zůstala pravdivá i tehdy, kdyby se ty dva tokeny jednou potkaly, a rozpor by zmizel
    /// z dohledu — tatáž úvaha jako u `AccentLinkButtonTests` a systémového odkazu.
    @Test("Odznak stavu u nálezu není akcent")
    func theFindingStateBadgeIsNotTheAccent() throws {
        for (name, scheme) in try zip([NSAppearance.Name.aqua, .darkAqua], schemes()) {
            let appearance = try #require(NSAppearance(named: name))
            var badge: Measured?
            appearance.performAsCurrentDrawingAppearance {
                badge = Measured(FindingBadgeAppearance.stateTint)
            }
            let measured = try #require(badge)
            #expect(measured.color == scheme.mint.color, "\(scheme.name): odznak stavu u nálezu nemá mint.")
            #expect(
                measured.color != scheme.accent.color,
                "\(scheme.name): odznak stavu u nálezu má barvu akce — `2×` zase vypadá jako tlačítko."
            )
        }
    }

    /// Verdikt `Komentář` je **volba**, tedy akce — akcent, ne mint.
    @Test("Verdikt Komentář bere akcent")
    func theCommentVerdictTakesTheAccent() throws {
        for (name, scheme) in try zip([NSAppearance.Name.aqua, .darkAqua], schemes()) {
            let appearance = try #require(NSAppearance(named: name))
            var tint: Measured?
            appearance.performAsCurrentDrawingAppearance {
                tint = Measured(ReviewDraft.Verdict.comment.tint)
            }
            #expect(try #require(tint).color == scheme.accent.color, "\(scheme.name): verdikt `Komentář` nemá akcent.")
        }
    }

    /// **Pruhy rozsahu v diffu si musí akcent udržet i po krytí a po převodu na `NSColor`.**
    ///
    /// `DiffTextView` je AppKit a bere si barvu jako `NSColor(DiffLineView.rangeTint)`, tedy přes
    /// dva kroky, ve kterých se dynamická barva umí ztratit: `.opacity(…)` a převod. Kdyby se
    /// ztratila, pruh by v tmavém režimu zůstal světlý (nebo naopak) — a poznalo by se to jedině
    /// tažením myší přes diff v tom druhém režimu, tedy skoro nikdy.
    ///
    /// Tvrdí se proto trojí: krytí sedí, barva pod ním je akcent (ne systémová modrá) a **obě
    /// větve se od sebe liší**.
    @Test("Pruh rozsahu v diffu drží akcent v obou režimech")
    func theDiffRangeStripeKeepsTheAccent() throws {
        for scheme in try schemes() {
            #expect(abs(scheme.rangeTint.color.alphaComponent - 0.12) < 0.001, "\(scheme.name): jiné krytí pruhu.")
            #expect(abs(scheme.dragTint.color.alphaComponent - 0.16) < 0.001, "\(scheme.name): jiné krytí tažení.")
            let opaque = Measured(scheme.rangeTint.color.withAlphaComponent(1))
            #expect(
                deltaE(opaque, scheme.accent) < 1,
                "\(scheme.name): pruh rozsahu nemá pod krytím akcent (ΔE \(deltaE(opaque, scheme.accent)))."
            )
        }
        let schemes = try schemes()
        let light = try #require(schemes.first), dark = try #require(schemes.last)
        #expect(
            light.rangeTint.color != dark.rangeTint.color,
            "Pruh rozsahu vyšel v obou režimech stejně — dynamická barva se krytím nebo převodem ztratila."
        )
    }
}
