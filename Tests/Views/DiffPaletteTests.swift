import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Barvy diffu proti tomu, co o nich tvrdí paleta (#277).
///
/// **Měří se dvěma mírami naráz, a je to celý smysl tohohle souboru.** WCAG kontrast závisí jen na
/// světlosti, takže nad dvěma plochami podobné světlosti (zelený a červený řádek) neřekne nic —
/// odlišení plochy proto nese ΔE2000. Naopak u textu nad plochou (znak `+`, obarvená syntaxe, obrys
/// bubliny) je správnou mírou WCAG. Kdyby se hlídala jen jedna, dala by se druhá pokazit potichu:
/// do #277 měla word-level vrstva v tmavém režimu ΔE 29,5 (plocha jak vyšitá) a kontrast řetězce
/// **1,27**, tedy nepřečtitelný kód právě na tom slově, kvůli kterému se člověk kouká.
///
/// Prahy jsou svázané s **dnešními změřenými hodnotami**, ne s ideálem: každý je o kus pod tím, co
/// vychází, takže test spadne na zhoršení, ne na zaokrouhlení. Čísla jsou v `Palette`.
@Suite("Barvy diffu")
@MainActor
struct DiffPaletteTests {
    // MARK: - míry

    private struct Measured {
        let color: NSColor
        /// Šla barva přečíst v sRGB? Bez převodu nedávají složky smysl, takže se to **nezamlčuje
        /// fallbackem** — hlídá to samostatný test níž, aby se zelená sada nedala splnit tím, že se
        /// všechno měří ve špatném prostoru.
        let isConverted: Bool

        init(_ color: Color) {
            let resolved = NSColor(color)
            let converted = resolved.usingColorSpace(.sRGB)
            self.color = converted ?? resolved
            isConverted = converted != nil
        }

        var alpha: Double { color.alphaComponent }

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
    }

    /// WCAG kontrast dvou barev.
    private func contrast(_ a: Measured, _ b: Measured) -> Double {
        let (la, lb) = (a.luminance, b.luminance)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// CIEDE2000 — vzdálenost dvou **ploch**, tedy včetně sytosti, kterou WCAG nevidí.
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

    /// Barvy diffu vyhodnocené v jednom režimu.
    ///
    /// **Vyhodnocuje se `performAsCurrentDrawingAppearance`**, tedy tak, jak se barva vyhodnotí při
    /// kreslení — dynamické `NSColor` z palety si režim bere odsud. (Nefunguje to jen kolem
    /// `ImageRenderer`u, viz `docs/testovani.md`; nad samotným `NSColor` ano a je to tady změřené
    /// tím, že se světlá a tmavá sada liší.)
    private struct Scheme {
        let name: String
        let surface: Measured
        let window: Measured
        let added: Measured, removed: Measured
        let addedWord: Measured, removedWord: Measured
        let stripe: Measured
        let addedSign: Measured, removedSign: Measured
        let critLine: Measured
        let syntax: (string: Measured, keyword: Measured, comment: Measured)
        let ink: Measured

        /// Všechno, co se v téhle sadě měří — pro kontrolu měřidla.
        var all: [(String, Measured)] {
            [
                ("plocha", surface), ("pozadí okna", window),
                ("přidaný řádek", added), ("odebraný řádek", removed),
                ("word-level přidaný", addedWord), ("word-level odebraný", removedWord),
                ("šrafa prázdného protějšku", stripe),
                ("znak +", addedSign), ("znak −", removedSign),
                ("obrys bubliny", critLine),
                ("řetězec", syntax.string), ("klíčové slovo", syntax.keyword), ("komentář", syntax.comment),
                ("text", ink),
            ]
        }
    }

    private func scheme(_ appearance: NSAppearance.Name, name: String, syntax palette: SyntaxPalette) throws -> Scheme {
        let appearance = try #require(NSAppearance(named: appearance))
        // Barva word-level vrstvy se vyžaduje **před** vyhodnocením, ne dosazuje `?? .clear`:
        // chybějící vrstva u přepsaného řádku je porucha, kdežto průhledná barva by se dala
        // změřit a sada by pak měřila nic. Na režimu to nezávisí — `nil` je vlastnost druhu řádku.
        let addedWord = try #require(DiffLineView.wordBackground(of: .added))
        let removedWord = try #require(DiffLineView.wordBackground(of: .removed))
        var result: Scheme?
        appearance.performAsCurrentDrawingAppearance {
            result = Scheme(
                name: name,
                surface: Measured(Palette.surface),
                window: Measured(Palette.background),
                added: Measured(DiffLineView.background(of: .added)),
                removed: Measured(DiffLineView.background(of: .removed)),
                addedWord: Measured(addedWord),
                removedWord: Measured(removedWord),
                stripe: Measured(Palette.diffMissingStripe),
                addedSign: Measured(DiffLineView.signColor(of: .added)),
                removedSign: Measured(DiffLineView.signColor(of: .removed)),
                critLine: Measured(Palette.critLine),
                syntax: (Measured(palette.string), Measured(palette.keyword), Measured(palette.comment)),
                ink: Measured(Palette.ink)
            )
        }
        return try #require(result)
    }

    private func schemes() throws -> [Scheme] {
        [
            try scheme(.aqua, name: "světlý", syntax: .intelliJLight),
            try scheme(.darkAqua, name: "tmavý", syntax: .darcula),
        ]
    }

    // MARK: - tvrzení

    /// **Tohle je celé #277**: barva plochy nesmí být výsledek krytí nad podkladem, protože pak
    /// není hodnotou, ale závisí na tom, na čem leží. Do #277 to byla systémová zelená na dvanáct
    /// procent a v tmavém režimu se mísila směrem k černé.
    ///
    /// Hlídá se **alfa**, protože právě ta z barvy dělá výsledek. Kdyby se sem někdo vrátil
    /// s `.opacity(…)`, spadne to tady, ne až na obrazovce.
    @Test("Barvy diffu jsou neprůhledné hodnoty, ne krytí nad podkladem")
    func diffColorsAreOpaqueValues() throws {
        for scheme in try schemes() {
            for (label, color) in [
                ("přidaný řádek", scheme.added), ("odebraný řádek", scheme.removed),
                ("word-level přidaný", scheme.addedWord), ("word-level odebraný", scheme.removedWord),
                ("šrafa prázdného protějšku", scheme.stripe),
            ] {
                #expect(color.alpha == 1, "\(scheme.name) režim: \(label) má krytí \(color.alpha) místo jedničky.")
            }
        }
    }

    /// **Kontrola měřidla.** Všechna čísla níž stojí na složkách přečtených v sRGB — kdyby se převod
    /// nepovedl, měřila by se sada v cizím prostoru a mlčela by o tom. Tvrdí se to zvlášť, aby se
    /// nevědělo jen z `??` uvnitř `Measured`.
    @Test("Barvy jde přečíst v sRGB")
    func colorsConvertToSRGB() throws {
        for scheme in try schemes() {
            for (label, color) in scheme.all {
                #expect(color.isConverted, "\(scheme.name) režim: \(label) se nepřevedl do sRGB.")
            }
        }
    }

    /// Obě větve tokenu musí být jiné. Kdyby se paleta v tmavém režimu nevyhodnotila (nebo kdyby
    /// někdo dosadil jednu hodnotu do obou), tvrzení výš i níž by pořád vycházela — a přitom by
    /// tmavý režim vypadal jako světlý. Je to zároveň důkaz, že měřidlo režim opravdu přepíná.
    @Test("Světlá a tmavá větev se liší")
    func lightAndDarkDiffer() throws {
        let schemes = try schemes()
        let light = try #require(schemes.first), dark = try #require(schemes.last)
        #expect(deltaE(light.added, dark.added) > 20)
        #expect(deltaE(light.removed, dark.removed) > 20)
        #expect(deltaE(light.stripe, dark.stripe) > 20)
    }

    /// Přidaný a odebraný řádek proti ploše, na které diff leží, a proti sobě.
    ///
    /// Prahy: ΔE 8,5 proti ploše ve světlém (vychází 13,0 u přidaného a 8,9 u odebraného — hodnoty
    /// jsou z návrhu, ne z optimalizace) a **18 v tmavém** (21,8 a 19,7), mezi sebou 20 (22,8 světlý,
    /// 36,8 tmavý). Do #277 vycházelo v tmavém 16,0 a 13,2.
    @Test("Přidaný a odebraný řádek se odlišují od plochy i od sebe")
    func changedLinesStandOut() throws {
        for scheme in try schemes() {
            let floor = scheme.name == "tmavý" ? 18.0 : 8.5
            let addedFromSurface = deltaE(scheme.added, scheme.surface)
            let removedFromSurface = deltaE(scheme.removed, scheme.surface)
            #expect(addedFromSurface >= floor, "\(scheme.name): přidaný řádek je od plochy jen ΔE \(addedFromSurface).")
            #expect(removedFromSurface >= floor, "\(scheme.name): odebraný řádek je od plochy jen ΔE \(removedFromSurface).")
            let between = deltaE(scheme.added, scheme.removed)
            #expect(between >= 20, "\(scheme.name): přidaný a odebraný se liší jen ΔE \(between).")
        }
    }

    /// Word-level vrstva (#153) se nesmí slít s pozadím svého řádku — a nesmí pod sebou zhasnout
    /// obarvení syntaxe. Práh ΔE 11 (vychází 13,9 a 13,2 v tmavém, 12,0 a 11,4 ve světlém)
    /// a kontrast řetězce 2,1 (vychází 2,16 tmavý, 4,01 světlý; do #277 to bylo 1,27).
    @Test("Word-level vrstva je jiná plocha než řádek a text na ní nezhasne")
    func wordLayerDiffersFromItsLine() throws {
        for scheme in try schemes() {
            for (label, word, line) in [
                ("přidaný", scheme.addedWord, scheme.added),
                ("odebraný", scheme.removedWord, scheme.removed),
            ] {
                let distance = deltaE(word, line)
                #expect(distance >= 11, "\(scheme.name), \(label): word-level je od řádku jen ΔE \(distance).")
                let readable = contrast(scheme.syntax.string, word)
                #expect(readable >= 2.1, "\(scheme.name), \(label): řetězec na word-level má kontrast \(readable).")
            }
        }
    }

    /// Sytější podklad nesmí sebrat čitelnost obarvenému kódu — proto se to měří na **barvách
    /// syntaxe**, ne na prázdném řádku. Nejslabší místo je zelený řetězec Darculy na zeleném
    /// podkladu; je to zapsaná daň palety a #277 ji nesmělo zvětšit.
    ///
    /// Prahy jsou dnešní hodnoty bez zaokrouhlení nahoru: řetězec 3,7 (vychází 3,76 na přidaném
    /// a 4,16 na odebraném; do #277 to bylo 3,73 a 4,07), klíčové slovo 4,4, komentář 3,7.
    @Test("Syntaxe zůstává čitelná na obou druzích řádku")
    func syntaxStaysReadable() throws {
        for scheme in try schemes() {
            for (label, line) in [("přidaném", scheme.added), ("odebraném", scheme.removed)] {
                let string = contrast(scheme.syntax.string, line)
                let keyword = contrast(scheme.syntax.keyword, line)
                let comment = contrast(scheme.syntax.comment, line)
                #expect(string >= 3.7, "\(scheme.name): řetězec na \(label) řádku má kontrast \(string).")
                #expect(keyword >= 4.4, "\(scheme.name): klíčové slovo na \(label) řádku má kontrast \(keyword).")
                #expect(comment >= 2.8, "\(scheme.name): komentář na \(label) řádku má kontrast \(comment).")
                let ink = contrast(scheme.ink, line)
                #expect(ink >= 10, "\(scheme.name): obyčejný text na \(label) řádku má kontrast \(ink).")
            }
        }
    }

    /// Znak `+`/`−` je text, takže se u něj měří kontrast — a to nad **svým** řádkem i nad plochou,
    /// protože tatáž barva nese `+12 −4` v hlavičce nad diffem (#156).
    ///
    /// Práh 4,4 (vychází 4,60 a 4,55 ve světlém, 5,95 a 4,99 v tmavém). Do #277 měla systémová
    /// zelená ve světlém režimu **2,01**, což je zrovna ten rozpor, kvůli kterému se #277 zakládalo.
    @Test("Znak změny je čitelný na svém řádku i v hlavičce")
    func signIsReadable() throws {
        for scheme in try schemes() {
            for (label, sign, line) in [
                ("+", scheme.addedSign, scheme.added),
                ("−", scheme.removedSign, scheme.removed),
            ] {
                let onLine = contrast(sign, line)
                #expect(onLine >= 4.4, "\(scheme.name): znak \(label) má na svém řádku kontrast \(onLine).")
                let onSurface = contrast(sign, scheme.surface)
                #expect(onSurface >= 4.4, "\(scheme.name): znak \(label) má na ploše kontrast \(onSurface).")
            }
        }
    }

    /// Znak změny a plocha řádku si berou **stejnou barvu** (`Palette.ok` / `crit`, viz #156):
    /// jeden zdroj zelené a červené v diffu. Tvrdí se to na odstínu, ne na hodnotě — plocha je ten
    /// tón zamíchaný do podkladu, takže shodná být nemá, ale rodina barev ano.
    @Test("Zelená a červená diffu jdou z palety, ne ze systému")
    func diffTonesComeFromThePalette() throws {
        for scheme in try schemes() {
            appearance(scheme.name) {
                #expect(NSColor(DiffLineView.signColor(of: .added)) == NSColor(Palette.ok))
                #expect(NSColor(DiffLineView.signColor(of: .removed)) == NSColor(Palette.crit))
            }
        }
    }

    /// Obrys bubliny nálezu (#185) je jedna barva pro všechny tři druhy řádku, takže se po změně
    /// pozadí musí zkontrolovat nad každým z nich. Práh 1,6 (vychází 1,69 na přidaném a 1,87 na
    /// odebraném v tmavém, 2,01 a 1,89 ve světlém) — a hlavně: proti stavu do #277 se to nesmělo
    /// zhoršit, tam vycházelo 1,68 a 1,83.
    @Test("Obrys bubliny nálezu funguje nad všemi druhy řádku")
    func findingOutlineWorksOnEveryKind() throws {
        for scheme in try schemes() {
            for (label, line) in [
                ("přidaný", scheme.added), ("odebraný", scheme.removed),
                ("kontext", scheme.surface), ("šrafu prázdného protějšku", scheme.stripe),
            ] {
                let value = contrast(scheme.critLine, line)
                #expect(value >= 1.6, "\(scheme.name): obrys nad \(label) řádkem má kontrast \(value).")
            }
        }
    }

    /// Prázdný protějšek (#277) nese **šrafa, ne plocha** — tak to kreslí návrh (`tr.empty-side`),
    /// a v tmavém režimu to jinak ani nejde: pod plochou obsahu není kam ztmavovat a zesvětlit ji by
    /// znamenalo, že díra křičí hlasitěji než změna vedle ní.
    ///
    /// Tvrdí se proto obojí naráz: pruh je od plochy **rozeznatelný** (ΔE 2 a víc — vychází 2,4 ve
    /// světlém a 3,3 v tmavém, do #277 to bylo 0,0, protože se nekreslilo nic) a zároveň **tišší než
    /// změna**, jinak by prázdné místo přebíjelo to, kvůli čemu se diff otevírá. Že se pozná i při
    /// takhle malém rozdílu, nese rozestup pruhů, ne kontrast — a to hlídá `DiffMissingRowTests`
    /// nad bitmapou.
    @Test("Prázdný protějšek se pozná šrafou, a je tišší než změna")
    func missingCounterpartIsQuietButVisible() throws {
        for scheme in try schemes() {
            let stripe = deltaE(scheme.stripe, scheme.surface)
            let added = deltaE(scheme.added, scheme.surface)
            #expect(stripe >= 2, "\(scheme.name): šrafa je od plochy jen ΔE \(stripe).")
            #expect(stripe < added, "\(scheme.name): šrafa (ΔE \(stripe)) křičí víc než přidaný řádek (ΔE \(added)).")
        }
    }

    /// Šrafa má z návrhu **rozestup, ne jen barvu**: pruh 5 bodů, mezera 5 bodů, sklon 45°. Kdyby se
    /// přepočet vodorovného kroku ztratil (√2 kvůli sklonu), vyšla by hustší, než jakou návrh kreslí
    /// — a to je rozdíl, který se na obrázku pozná, ale v barvě ne.
    @Test("Šrafa má rozestup z návrhu")
    func hatchKeepsTheDesignSpacing() {
        #expect(DiffMissingHatch.lineWidth == 5)
        #expect(DiffMissingHatch.period == 10)
        #expect(abs(DiffMissingHatch.step - 14.142) < 0.01)

        // Sklon 45°: úsečka se po výšce rámečku posune o tutéž výšku i vodorovně, a jde z levého
        // **dolního** koutu do pravého horního — směr je z vyrenderované sekce návrhu, ne z `45deg`
        // (gradient míří k pravému hornímu koutu, ale pruhy leží napříč jeho osou).
        let segments = DiffMissingHatch.segments(in: CGRect(x: 0, y: 0, width: 100, height: 20))
        let first = segments.first
        #expect(first?.from.y == 20)
        #expect(first?.to.y == 0)
        #expect(first.map { $0.to.x - $0.from.x } == 20)
        // Prošrafovaný musí být i levý kout, takže pruhy začínají o výšku vlevo od rámečku.
        #expect(first.map { $0.from.x <= -20 } == true)
    }

    private func appearance(_ name: String, _ body: () -> Void) {
        NSAppearance(named: name == "tmavý" ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance(body)
    }
}
