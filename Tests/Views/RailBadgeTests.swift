import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Odznak s počtem v railu (#366) — **červený a uvnitř rámu ikony**, jak ho kreslí návrh
/// (`.rail .ri .badge`).
///
/// Do #366 to byl fialový akcent posunutý o 6 bodů za rám. Obojí se dá pokazit potichu, protože
/// z kódu obojí vypadá jako záměr: `.tint` je v okně na dosah ruky a `offset` je jediný způsob,
/// jak odznak posunout. **Čte se proto bitmapa** — kde odznak leží a jakou má barvu, se z rámečků
/// ani z accessibility (v okně mimo obrazovku se nenaplní, #269) nedozvíme.
///
/// Tři třídy tvrzení:
///
/// - **kde leží**: kresba nesmí opustit rám ikony (34 × 30, tedy 9–43 na šířce railu 52) ani
///   vyčnívat nad jeho horní hranu;
/// - **jakou má barvu**: `crit`, ne akcent — a číslo v barvě plochy okna. Kontrast tokenu přitom
///   netvrdí nic o kresbě (#393), takže se hledá **v bitmapě**, ne v paletě;
/// - **že se nekreslí**: nula ani nenačteno odznak nedostanou.
///
/// **Barva se porovnává s nakreslenou, ne s tokenem** — a je to změřené, ne opatrnost: bitmapa
/// z `bitmapImageRepForCachingDisplay` je v profilu displeje (`Barevný LCD`), takže `crit` vyjde
/// v ní `0.799/0.292/0.272` proti `0.812/0.133/0.180` v sRGB, tedy 0,18 daleko — na absolutní
/// porovnání s paletou tolerance nestačí a musela by být tak velká, že by prošel i akcent. Tokeny
/// se proto vykreslí **týmž harnessem** jako vzorník a srovnává se kresba s kresbou.
///
/// **Vyzkoušené vložením regrese**: se starým `offset(x: 6, y: -2)` a `.background(.tint)` spadne
/// obojí — barevná tvrzení na tom, že v railu není ani jeden červený pixel, a poloha na tom, že
/// kresba přeteče na 49.
@MainActor
@Suite("Odznak v railu (#366)")
struct RailBadgeTests {
    /// Rám ikony v railu: 34 × 30 vystředěných v 52 bodech, tedy 9–43.
    private let frameRight = 43
    /// Svislé odsazení railu — nad ním už kresba položek být nemá.
    private let railTopPadding = 10

    // MARK: - Kde odznak leží

    /// Odznak **zůstává uvnitř rámu ikony**. To je celá první polovina #366: v pruhu o 52 bodech
    /// není 6 bodů, které si posunutý odznak bral, a v návrhu je `right: 0`, tedy zarovnaný
    /// s pravou hranou rámu.
    @Test("Odznak se kreslí uvnitř rámu ikony")
    func keepsTheBadgeInsideTheIconFrame() throws {
        for dark in [false, true] {
            let shot = try shot(dark: dark, queueCount: 5)
            let box = try #require(shot.badgeBox, "\(shot.name): odznak se nenakreslil červeně")

            #expect(box.right <= frameRight, "\(shot.name): odznak končí na \(box.right)")
            #expect(box.top >= railTopPadding, "\(shot.name): odznak začíná na \(box.top)")
        }
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
    }

    /// Vyrenderovaný rail i s nakreslenými tokeny.
    private struct Shot {
        let name: String
        let tokens: Tokens
        /// Pixely po řádcích, převedené na body.
        let pixels: [[Rgb]]

        /// Obálka pixelů, které jsou barvou `crit` — tedy plocha kapsle bez obtahu, který je
        /// barvou railu. `nil` = odznak se nenakreslil.
        var badgeBox: Box? {
            var box: Box?
            for (y, row) in pixels.enumerated() {
                for (x, pixel) in row.enumerated() where pixel.distance(to: tokens.crit) < 0.04 {
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
    private func shot(dark: Bool, queueCount: Int?) throws -> Shot {
        let rail = SidebarRail(
            section: .constant(.queue),
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

    /// Vzorník: čtyři plné plochy vedle sebe, každá 10 bodů, ve stejném harnessu jako rail.
    private func measureTokens(dark: Bool) throws -> Tokens {
        let swatch = HStack(spacing: 0) {
            ForEach([Palette.crit, Palette.accent, Palette.surface, Color.white], id: \.self) { color in
                Rectangle().fill(color).frame(width: 10, height: 10)
            }
        }
        let rows = try pixels(of: swatch, size: CGSize(width: 40, height: 10), dark: dark)
        let middle = try #require(rows.indices.contains(5) ? rows[5] : nil)
        let read = { (index: Int) throws -> Rgb in
            let pixel = try #require(middle.indices.contains(index) ? middle[index] : nil)
            #expect(pixel.isConverted)
            return pixel
        }
        return Tokens(crit: try read(5), accent: try read(15), surface: try read(25), white: try read(35))
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
                window.orderFront(nil)
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
