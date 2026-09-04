import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Odznak s počtem v railu (#366, přesunutý do rohu #526) a **pruh aktivní sekce** (#526), jak je
/// kreslí návrh (`.rail .ri .badge`, `.rail .ri.on::before` v sekci 50).
///
/// Do #366 byl odznak fialový akcent posunutý o 6 bodů za rám; #366 ho udělalo červeným a zatáhlo
/// **dovnitř** rámu. Uvnitř rámu ale ikonu překryl — v běžícím okně byla pod `5`, `3` a `30` vidět
/// jen její spodní hrana —, takže ho **#526 posílá do rohu**, tedy zase ven, a identitu aktivní
/// sekce přebírá pruh na hraně railu. Obojí se dá pokazit potichu, protože z kódu obojí vypadá jako
/// záměr: `.tint` je v okně na dosah ruky a `offset` je jediný způsob, jak odznak posunout.
/// **Čte se proto bitmapa** — kde co leží a jakou to má barvu, se z rámečků ani z accessibility
/// (v okně mimo obrazovku se nenaplní, #269) nedozvíme.
///
/// Čtyři třídy tvrzení:
///
/// - **kde odznak leží**: v rohu, tedy **ven z rámu ikony** — a pořád uvnitř railu, ve kterém je
///   52 bodů a nic víc;
/// - **že ho nic neořezává** (#483): rail není `ScrollView` ani `clipShape`, ale kdyby se to
///   změnilo, odznak by se uřízl potichu — pozná se to podle toho, že mu chybí pravý sloupec;
/// - **jakou to má barvu**: odznak `crit`, ne akcent, číslo v barvě plochy okna, pruh v akcentu.
///   Kontrast tokenu přitom netvrdí nic o kresbě (#393), takže se hledá **v bitmapě**, ne v paletě;
/// - **že se to nekreslí**: nula ani nenačteno odznak nedostanou a pruh má **jedna** položka.
///
/// **Rám ikony se neopisuje, měří se** — z akcentového washu aktivní položky (`.ri.on`), který
/// leží přesně na jejích 34 × 30. Zadrátovaná čísla by po posunu odznaku tvrdila jen sama sebe;
/// takhle je každé tvrzení rozdíl proti rámu, který v tomtéž snímku doopravdy je.
///
/// **Barva se porovnává s nakreslenou, ne s tokenem** — a je to změřené, ne opatrnost: bitmapa
/// z `bitmapImageRepForCachingDisplay` je v profilu displeje (`Barevný LCD`), takže `crit` vyjde
/// v ní `0.799/0.292/0.272` proti `0.812/0.133/0.180` v sRGB, tedy 0,18 daleko — na absolutní
/// porovnání s paletou tolerance nestačí a musela by být tak velká, že by prošel i akcent. Tokeny
/// se proto vykreslí **týmž harnessem** jako vzorník a srovnává se kresba s kresbou.
///
/// **Vyzkoušené vložením regrese**: se starým `offset(y: 1)` spadne poloha (odznak nevyjde z rámu
/// ani nahoru, ani doprava), s vynechaným pruhem spadne sada o aktivní sekci a se starým
/// `.background(.tint)` spadnou barevná tvrzení.
@MainActor
@Suite("Odznak a pruh v railu (#366, #526)")
struct RailBadgeTests {
    /// O kolik odznak vyčnívá z rámu ikony (návrh, sekce 50: `top: −5, right: −7`). Červená plocha
    /// je uvnitř dvoubodového obtahu barvou railu, takže se v bitmapě začíná o ty dva body dřív.
    private let badgeOverhangRight = 7 - 2
    private let badgeOverhangTop = 5 - 2
    /// Šířka railu. Poslední bod patří jeho obrysu, do kterého odznak zasahovat nesmí.
    private let railWidth = 52

    // MARK: - Kde odznak leží

    /// Odznak sedí **v rohu ikony**, tedy o 5 bodů výš a o 7 vpravo od jejího rámu (#526).
    ///
    /// Je to obrácení druhé poloviny #366 a měří se proti **změřenému** rámu, ne proti konstantě:
    /// uvnitř rámu 34 × 30 nemá odznak 24 × 18 kam sednout, takže „uvnitř“ znamenalo „přes ikonu“.
    @Test("Odznak sedí v rohu, ven z rámu ikony")
    func putsTheBadgeIntoTheCorner() throws {
        for dark in [false, true] {
            let shot = try shot(dark: dark, queueCount: 5)
            let name = shot.name
            let box = try #require(shot.badgeBox, "\(name): odznak se nenakreslil červeně")
            let frame = try #require(shot.activeFrame, "\(name): rám aktivní položky se nenašel")

            #expect(box.right - frame.right == badgeOverhangRight, "\(name): odznak končí na \(box.right), rám na \(frame.right)")
            #expect(frame.top - box.top == badgeOverhangTop, "\(name): odznak začíná na \(box.top), rám na \(frame.top)")
        }
    }

    /// A pořád **uvnitř railu**: 52 bodů je celé místo, které rail má, a poslední z nich patří jeho
    /// obrysu. Sedm bodů vpravo je tedy strop, ne libovolná hodnota — proto je to tvrzení zvlášť.
    @Test("Odznak se vejde do šířky railu")
    func keepsTheBadgeInsideTheRail() throws {
        let shot = try shot(dark: true, queueCount: 30)
        let box = try #require(shot.badgeBox, "odznak se nenakreslil")

        // Vpravo od červené plochy je ještě dvoubodový obtah barvou railu a za ním obrys railu.
        #expect(box.right + 2 < railWidth - 1, "odznak sahá na \(box.right + 2)")
    }

    /// **Nic ho neořezává na rámu tlačítka** (#483), a je to přesně to místo, kde by se to stalo:
    /// řádek položky je 52 bodů, tlačítko v něm 34 a odznak z těch 34 od #526 **vyčnívá**. Kdyby
    /// nad rám tlačítka přišel ořezávající předek (`clipShape`, `ScrollView`, `.clipped()`),
    /// uřízne se odznak potichu a v kódu se nezmění nic.
    ///
    /// **Ořez na hraně railu tahle sada netvrdí, protože nastat nemůže** — odznak i s obtahem končí
    /// na 49 z 52, viz test výš. Uřízl by se jedině na 43, tedy na rámu tlačítka.
    ///
    /// Pozná se to podle **pravé hrany**: kapsle s poloměrem 5 dosáhne na svůj nejpravější sloupec
    /// jen kolem svislého středu, kdežto uříznutá má tu hranu svislou, takže na ni dosáhne **každý**
    /// řádek. Šířka řádku na to neodpovídá — číslo uvnitř odznaku z něj bere červené body uprostřed,
    /// takže by nejužší řádek měřilo písmo.
    @Test("Odznak nikdo neořezává")
    func clipsNothingOffTheBadge() throws {
        let shot = try shot(dark: true, queueCount: 5)
        let box = try #require(shot.badgeBox, "odznak se nenakreslil")
        let rightmost = shot.rightmostColumns(matching: shot.tokens.crit, in: box)

        // Naměřeno: **8 řádků ze 14** dosáhne na nejpravější sloupec (poloměr 5 nechá rovné 4 a
        // vyhlazení k nim přidá po dvou). Uříznutá hrana by dala všech 14, takže je práh
        // o dva řádky pod výškou — mezera je 8 proti 12, ne bod.
        //
        // `touching > 0` se netvrdí: `box.right` je z definice maximum přes shodné body, takže by
        // to byla tautologie. Že se odznak vůbec nakreslil, tvrdí `#require` výš.
        let touching = rightmost.count { $0 == box.right }
        #expect(touching < box.height - 2, "pravá hrana je svislá, tedy uříznutá — \(rightmost)")
    }

    /// Rozměr je z CSS doslova: obsah 14 × 14 a odsazení 3 na stranu dá **červenou plochu 20 × 14**
    /// (obtah 2 body je barvou railu, takže se v bitmapě neprojeví). Změřeno na vyrenderované
    /// sekci 02 návrhu, kde celý odznak vychází 24 × 18.
    ///
    /// Tolerance je bod na stranu, ne rovnost — poloměr 5 nechává na krajních řádcích vyhlazené
    /// pixely a test má chytat **jinou metriku**, ne antialiasing.
    @Test("Červená plocha odznaku má rozměr z návrhu")
    func drawsTheBadgeSizeFromTheDesign() throws {
        for count in [5, 12] {
            let shot = try shot(dark: true, queueCount: count)
            let box = try #require(shot.badgeBox, "počet \(count): odznak se nenakreslil")

            #expect(abs(box.width - 20) <= 1, "počet \(count): šířka \(box.width)")
            #expect(abs(box.height - 14) <= 1, "počet \(count): výška \(box.height)")
        }
    }

    // MARK: - Jakou má barvu

    /// **Červená, ne akcent.** Akcent v tomhle okně znamená „tady jsi“ (`.ri.on` je z něj celý),
    /// takže odznak v téže barvě neříkal nic; `crit` je „je co dělat“.
    @Test("Odznak je crit, ne akcent")
    func paintsTheBadgeWithCrit() throws {
        for dark in [false, true] {
            let shot = try shot(dark: dark, queueCount: 5)
            let box = try #require(shot.badgeBox, "\(shot.name): odznak se nenakreslil červeně")
            let name = shot.name
            let critPixels = shot.count(matching: shot.tokens.crit, in: box)
            let accentPixels = shot.count(matching: shot.tokens.accent, in: box)

            #expect(critPixels > 40, "\(name): červené plochy je málo (\(critPixels))")
            #expect(accentPixels == 0, "\(name): v odznaku je akcent (\(accentPixels))")
        }
    }

    /// A číslo je v barvě **plochy okna** (`--panel`), ne bíle. Kontrast tokenů by na to
    /// neodpověděl — hledá se proto pixel uvnitř odznaku, který je té barvě nejblíž (#393:
    /// k měření barvy patří i tvrzení, že se do kresby dostane).
    ///
    /// V **tmavém** režimu je to zároveň tvrzení, že tam bílá není: `#11141B` je od bílé sedm
    /// desetin daleko. Ve světlém režimu je `--panel` bílá, takže se ty dvě možnosti nedají
    /// rozlišit a rozhoduje tmavý — je to mez měřidla, ne mez pravidla.
    @Test("Číslo v odznaku je v barvě plochy okna")
    func paintsTheDigitWithTheSurfaceColour() throws {
        for dark in [false, true] {
            let shot = try shot(dark: dark, queueCount: 5)
            let box = try #require(shot.badgeBox, "\(shot.name): odznak se nenakreslil")
            let name = shot.name
            let toSurface = try #require(shot.closestDistance(to: shot.tokens.surface, in: box))

            #expect(toSurface < 0.08, "\(name): nejbližší pixel k ploše je \(toSurface) daleko")
            if dark {
                let toWhite = try #require(shot.closestDistance(to: shot.tokens.white, in: box))
                #expect(toWhite > 0.2, "\(name): v odznaku je bílá (\(toWhite))")
            }
        }
    }

    /// Kontrast čísla na kapsli, **v obou režimech** a nad hranicí 4,5 pro malé písmo.
    ///
    /// Tady se měří **tokeny**, ne bitmapa, a je to schválně: kontrast je vlastnost dvojice barev
    /// z palety, kdežto profil displeje je vlastnost harnessu. Že se ty barvy do kresby dostanou,
    /// tvrdí dva testy výš.
    ///
    /// Druhé tvrzení je záznam rozhodnutí: kdyby zůstala bílá z doby před #366, byl by v tmavém
    /// režimu kontrast **nižší** — červená z palety je světlá, takže na ní bílá nesvítí.
    @Test("Číslo na kapsli je čitelné v obou režimech")
    func keepsTheDigitReadable() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            var surfaceOnCrit = 0.0
            var whiteOnCrit = 0.0
            appearance.performAsCurrentDrawingAppearance {
                let crit = Rgb(Palette.crit)
                surfaceOnCrit = crit.contrast(with: Rgb(Palette.surface))
                whiteOnCrit = crit.contrast(with: Rgb(Color.white))
            }
            #expect(surfaceOnCrit >= 4.5, "\(name.rawValue): kontrast \(surfaceOnCrit)")
            if name == .darkAqua {
                #expect(whiteOnCrit < surfaceOnCrit, "tmavý režim: bílá by byla čitelnější")
            }
        }
    }

    // MARK: - Pruh aktivní sekce (#526)

    /// Pruh je **na hraně railu**, ne u ikony: `left: −10` od rámu ikony je přesně nula railu.
    /// Rozměr je z návrhu doslova — 2 body na šířku, 18 na výšku (`top: 6`, `bottom: 6` v rámu
    /// vysokém 30) — a **svisle je vystředěný na rám aktivní položky**, takže se s ním hýbe.
    ///
    /// Tolerance je bod, ne rovnost: poloměr 1 nechává na krajních řádcích vyhlazené pixely,
    /// a test má chytat **jinou** geometrii, ne antialiasing.
    @Test("Pruh aktivní sekce leží na hraně railu a má rozměr z návrhu")
    func drawsTheActiveStripeOnTheRailEdge() throws {
        for dark in [false, true] {
            let shot = try shot(dark: dark, queueCount: 5)
            let name = shot.name
            let stripe = try #require(shot.stripeBox, "\(name): pruh se nenakreslil")
            let frame = try #require(shot.activeFrame, "\(name): rám aktivní položky se nenašel")

            #expect(stripe.left == 0, "\(name): pruh začíná na \(stripe.left)")
            #expect(stripe.width == 2, "\(name): pruh je široký \(stripe.width)")
            #expect(abs(stripe.height - 18) <= 1, "\(name): pruh je vysoký \(stripe.height)")
            #expect(
                abs((stripe.top + stripe.bottom) - (frame.top + frame.bottom)) <= 1,
                "\(name): pruh není vystředěný na rám (\(stripe.top)–\(stripe.bottom) proti \(frame.top)–\(frame.bottom))"
            )
        }
    }

    /// A **jenom jedna** položka ho má. Rail se kreslí z `allCases`, takže pruh na každé položce je
    /// chyba, která se napíše nejsnáz — a v okně by z něj byla svislá čára přes celý rail.
    ///
    /// Měří se **celý sloupec hrany**, ne okolí aktivní položky: kdyby pruh dostaly i ostatní,
    /// vyjde akcentových bodů pětkrát tolik. Přepínač vzhledu ho nedostane taky (`.ri.on` znamená
    /// „jsem na téhle obrazovce“ a vzhled žádnou neotevírá, #278), a to je tímtéž počtem řečeno.
    @Test("Pruh má jedna položka, ne každá")
    func drawsTheStripeOnlyForTheActiveSection() throws {
        for section in RailSection.allCases {
            let shot = try shot(dark: true, queueCount: 5, section: section)
            let stripe = try #require(shot.stripeBox, "\(section): pruh se nenakreslil")
            let painted = shot.countInEdgeColumn(matching: shot.tokens.accent)

            // Naměřeno **přesně** `2 × výška` (34 bodů na 17 řádcích): pruh má ostré svislé hrany,
            // takže se na nich nic nevyhlazuje. Tolerance 4 je tedy rezerva na vyhlazení zaoblených
            // konců, ne mez měřidla — dvě položky by daly dvojnásobek, tedy 68.
            #expect(abs(painted - 2 * stripe.height) <= 4, "\(section): akcentu na hraně \(painted)")
        }
    }

    /// **Aktivní položka má pruh i odznak** (#526) — a to je celý ten obchod: odznak na ní zůstává
    /// právě proto, že identitu sekce nese pruh, ne barva ikony pod odznakem. Do #526 se na aktivní
    /// sekci nekreslil (`Policy.activityBadge`, poznámka 95 v návrhu).
    ///
    /// Že je to odznak **té** položky, se pozná z polohy: leží nad její horní hranou, tedy v jejím
    /// rohu, ne u některé ze sousedních.
    @Test("Aktivní sekce má pruh i odznak")
    func drawsBothTheStripeAndTheBadgeOnTheActiveSection() throws {
        let shot = try shot(dark: true, queueCount: 30, section: .queue)
        let frame = try #require(shot.activeFrame, "rám aktivní položky se nenašel")
        let badge = try #require(shot.badgeBox, "odznak na aktivní položce chybí")

        #expect(shot.stripeBox != nil, "pruh na aktivní položce chybí")
        #expect(badge.top < frame.top, "odznak nesedí v rohu aktivní položky")
        #expect(badge.bottom < frame.bottom, "odznak nesedí v rohu aktivní položky")
    }

    // MARK: - Že se nekreslí

    /// **Nula se nekreslí a `nil` taky ne** (#366 to výslovně jmenuje jako to, co se nesmí
    /// rozbít). Prázdná fronta je dobrá zpráva, ne položka k vyřízení — a nenačtený stav se od
    /// nuly musí lišit, jinak okno po startu tvrdí „nic tu není“ nad daty, která nedorazila.
    ///
    /// Tvrdí to, že se něco **ne**stalo, takže je u toho i protějšek s počtem: bez něj by sada
    /// vycházela zeleně i tehdy, kdyby se odznak přestal kreslit vůbec.
    @Test("Nula ani nenačteno odznak nedostanou")
    func drawsNoBadgeForZeroOrUnknown() throws {
        for count in [nil, 0] as [Int?] {
            let box = try shot(dark: true, queueCount: count).badgeBox
            #expect(box == nil, "počet \(String(describing: count)): odznak se nakreslil")
        }
        let drawn = try shot(dark: true, queueCount: 1).badgeBox
        #expect(drawn != nil, "s počtem 1 se odznak nakreslit má")
    }

    // MARK: - Měřidlo

    /// Obdélník v **bodech**, hranice včetně.
    private struct Box {
        let left: Int
        let right: Int
        let top: Int
        let bottom: Int

        var width: Int { right - left + 1 }
        var height: Int { bottom - top + 1 }
    }

    /// Barva v sRGB. Neúspěch převodu se **nezamlčuje** — hlídá ho tvrzení v `tokens(dark:)`.
    private struct Rgb {
        let red: Double
        let green: Double
        let blue: Double
        let isConverted: Bool

        init(_ color: NSColor) {
            let converted = color.usingColorSpace(.sRGB)
            let value = converted ?? color
            red = value.redComponent
            green = value.greenComponent
            blue = value.blueComponent
            isConverted = converted != nil
        }

        init(_ color: Color) { self.init(NSColor(color)) }

        /// Vzdálenost dvou barev po složkách — na „je to ta barva“ stačí a na rozdíl od ΔE
        /// nepotřebuje Lab. Prahy níž jsou z naměřených hodnot.
        func distance(to other: Rgb) -> Double {
            ((red - other.red) * (red - other.red)
                + (green - other.green) * (green - other.green)
                + (blue - other.blue) * (blue - other.blue)).squareRoot()
        }

        private var luminance: Double {
            func channel(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
        }

        func contrast(with other: Rgb) -> Double {
            let (a, b) = (luminance, other.luminance)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
    }

    /// Tokeny **tak, jak je harness nakreslí** — vzorník projde tou samou cestou jako rail, takže
    /// se profil displeje vykrátí.
    private struct Tokens {
        let crit: Rgb
        let accent: Rgb
        let surface: Rgb
        let white: Rgb
        /// Podklad aktivní položky (`.ri.on`): akcent s krytím 15 % **na ploše railu**. Míchá se
        /// v kresbě, ne v paletě, takže se musí namíchat i ve vzorníku — jinak by se hledala barva,
        /// která v bitmapě nikde není.
        let activeWash: Rgb
    }

    /// Vyrenderovaný rail i s nakreslenými tokeny.
    private struct Shot: CustomStringConvertible {
        let name: String
        let tokens: Tokens
        /// Pixely po řádcích, převedené na body.
        let pixels: [[Rgb]]

        /// **Do hlášky se tiskne jméno režimu, ne bitmapa.** Swift Testing rozepisuje podvýrazy
        /// tvrzení, takže `#require(shot.stripeBox)` vypíše i `shot` — a s ním třináct tisíc
        /// pixelů: změřeno **4,2 MB logu na jedno spadlé tvrzení**, ve kterém pak nejde najít
        /// zbytek běhu. Je to vlastnost typu, ne jednoho tvrzení, proto to řeší `description`
        /// a ne opis do lokální proměnné u každého `#require`.
        var description: String { "snímek railu (\(name))" }

        /// Obálka pixelů, které jsou barvou `crit` — tedy plocha kapsle bez obtahu, který je
        /// barvou railu. `nil` = odznak se nenakreslil.
        var badgeBox: Box? { box(matching: tokens.crit) }

        /// Rám aktivní položky, změřený z jejího akcentového washe. Je to přesně těch 34 × 30,
        /// proti kterým se poměřuje odznak i pruh — **měří se, neopisuje**.
        ///
        /// **Tolerance je poloviční, a je to změřené, ne opatrnost**: ve světlém režimu je wash
        /// (`0.90/0.90/0.97`) od `Palette.line` (`0.90/0.91/0.94`) jen **0,032** daleko, takže by se
        /// do obálky připočítal obrys railu i oddělovač pod sekcemi — a rám by vyšel přes celou
        /// výšku railu (změřeno: `top: 0, bottom: 259` místo `44…73`). Plocha washu je jednolitá
        /// výplň, takže na ni **0,02 stačí**; wash a `--line` se v tmavém režimu nepotkají vůbec.
        var activeFrame: Box? { box(matching: tokens.activeWash, tolerance: 0.02) }

        /// Pruh aktivní sekce: akcent **na hraně railu**, tedy v prvních čtyřech sloupcích. Užší
        /// výřez než celá bitmapa je podmínka, ne úspora: v témž akcentu se kreslí i glyf aktivní
        /// položky, takže by obálka nad celým railem změřila ikonu.
        var stripeBox: Box? { box(matching: tokens.accent, columns: Self.edge) }

        /// Výřez hrany railu. Pruh je 2 body široký; čtyři jsou proto, aby se ve výřezu poznalo
        /// i to, že se rozšířil — a pořád je to daleko od glyfu, který začíná na 18.
        static let edge = 0..<4

        func countInEdgeColumn(matching color: Rgb) -> Int {
            var found = 0
            for row in pixels {
                for (x, pixel) in row.enumerated() where Self.edge.contains(x) && pixel.distance(to: color) < 0.04 {
                    found += 1
                }
            }
            return found
        }

        /// Nejpravější bod dané barvy na každém řádku obdélníku (`-1` = na řádku není žádný). Na
        /// tvar pravé hrany — zaoblená proti uříznuté — odpovídá tohle, kdežto obálka vydá na obojí
        /// týž obdélník.
        func rightmostColumns(matching color: Rgb, in box: Box) -> [Int] {
            (box.top...box.bottom).compactMap { y -> Int? in
                guard y < pixels.count else { return nil }
                let row = pixels[y]
                var found = -1
                for x in box.left...box.right where x < row.count {
                    if row[x].distance(to: color) < 0.04 { found = x }
                }
                return found
            }
        }

        /// Obálka bodů dané barvy, volitelně jen ve výřezu sloupců. `nil` = žádný takový bod není.
        private func box(matching color: Rgb, columns: Range<Int>? = nil, tolerance: Double = 0.04) -> Box? {
            var box: Box?
            for (y, row) in pixels.enumerated() {
                for (x, pixel) in row.enumerated()
                where (columns?.contains(x) ?? true) && pixel.distance(to: color) < tolerance {
                    box = Box(
                        left: min(box?.left ?? x, x),
                        right: max(box?.right ?? x, x),
                        top: box?.top ?? y,
                        bottom: y
                    )
                }
            }
            return box
        }

        func count(matching color: Rgb, in box: Box) -> Int {
            var found = 0
            for y in box.top...box.bottom where y < pixels.count {
                for x in box.left...box.right where x < pixels[y].count {
                    if pixels[y][x].distance(to: color) < 0.04 { found += 1 }
                }
            }
            return found
        }

        /// Jak blízko je nejbližší pixel dané barvě. `nil` = obdélník je mimo bitmapu.
        func closestDistance(to color: Rgb, in box: Box) -> Double? {
            var best: Double?
            for y in box.top...box.bottom where y < pixels.count {
                for x in box.left...box.right where x < pixels[y].count {
                    let distance = pixels[y][x].distance(to: color)
                    best = min(best ?? distance, distance)
                }
            }
            return best
        }
    }

    /// Rail vyrenderovaný v jednom režimu.
    ///
    /// **Režim se nastavuje dvakrát** (jako v `AppearanceRenderProbe`): `NSAppearance` kvůli
    /// paletě a `colorScheme` kvůli `.primary`/`.secondary`. A nastavuje se **na vlastním
    /// kreslení**, ne na `NSApp` — ten je jeden na celý testovací host a píše do něj i hostitel
    /// sám (#367).
    private func shot(dark: Bool, queueCount: Int?, section: RailSection = .queue) throws -> Shot {
        let rail = SidebarRail(
            section: .constant(section),
            queueCount: queueCount,
            mineCount: nil,
            draftCount: nil,
            appearance: .system
        )
            .frame(height: 260)
        return Shot(
            name: dark ? "tmavý režim" : "světlý režim",
            tokens: try tokens(dark: dark),
            pixels: try pixels(of: rail, size: CGSize(width: 52, height: 260), dark: dark)
        )
    }

    /// Nakreslený vzorník na režim. **Drží se mezi testy schválně**: hodnota závisí jen na režimu,
    /// takže druhý render téhož je jen další `NSHostingView` v procesu — a metrika písma je stav
    /// procesu, který se pod paralelní zátěží umí vyřešit jinak (#367, `CommitPanelRoomTests`).
    @MainActor private static var drawnTokens: [Bool: Tokens] = [:]

    private func tokens(dark: Bool) throws -> Tokens {
        if let cached = Self.drawnTokens[dark] { return cached }
        let measured = try measureTokens(dark: dark)
        Self.drawnTokens[dark] = measured
        return measured
    }

    /// Vzorník: pět plných ploch vedle sebe, každá 10 bodů, ve stejném harnessu jako rail.
    ///
    /// Pátá je **namíchaná, ne z palety**: podklad aktivní položky vzniká až v kresbě (akcent
    /// s krytím 15 % na ploše railu), takže se musí namíchat i tady — jinak by se v bitmapě hledala
    /// barva, kterou nikdo nenakreslil.
    private func measureTokens(dark: Bool) throws -> Tokens {
        let swatch = HStack(spacing: 0) {
            ForEach([Palette.crit, Palette.accent, Palette.surface, Color.white], id: \.self) { color in
                Rectangle().fill(color).frame(width: 10, height: 10)
            }
            Rectangle()
                .fill(Palette.chrome)
                .overlay { Rectangle().fill(Palette.accent.opacity(0.15)) }
                .frame(width: 10, height: 10)
        }
        let rows = try pixels(of: swatch, size: CGSize(width: 50, height: 10), dark: dark)
        let middle = try #require(rows.indices.contains(5) ? rows[5] : nil)
        let read = { (index: Int) throws -> Rgb in
            let pixel = try #require(middle.indices.contains(index) ? middle[index] : nil)
            #expect(pixel.isConverted)
            return pixel
        }
        return Tokens(
            crit: try read(5),
            accent: try read(15),
            surface: try read(25),
            white: try read(35),
            activeWash: try read(45)
        )
    }

    /// Kresba view v daném režimu, po bodech.
    private func pixels(of view: some View, size: CGSize, dark: Bool) throws -> [[Rgb]] {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var result: Result<[[Rgb]], any Error>?
        appearance.performAsCurrentDrawingAppearance {
            result = Result {
                let scene = view
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .tint(Palette.accent)
                let hosting = NSHostingView(rootView: scene)
                hosting.frame = NSRect(origin: .zero, size: size)
                let window = NSWindow(
                    contentRect: hosting.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hosting
                // Mimo obrazovku, ať test nikomu neskočí před oči — vedle sebe běží víc instancí.
                window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
                window.orderFrontUnanimated()
                defer { window.orderOut(nil) }
                // Hierarchie se doskládá až za jedním kolem smyčky.
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))

                let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                let scale = max(rep.pixelsWide / Int(size.width), 1)
                var rows: [[Rgb]] = []
                for y in stride(from: 0, to: rep.pixelsHigh, by: scale) {
                    var row: [Rgb] = []
                    for x in stride(from: 0, to: rep.pixelsWide, by: scale) {
                        // **Nepřečtený pixel není průhledný pixel.** `?? .clear` by z nečitelné
                        // bitmapy udělal railu bez odznaku, tedy zeleného „nekreslí se“ — a to je
                        // zrovna to tvrzení, které tahle sada dělá.
                        row.append(Rgb(try #require(rep.colorAt(x: x, y: y))))
                    }
                    rows.append(row)
                }
                return rows
            }
        }
        return try #require(result).get()
    }
}
