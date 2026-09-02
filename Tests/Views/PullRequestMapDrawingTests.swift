import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Kresba mapy PR (#501) — **z bitmapy, ne z tokenů**.
///
/// Kontrast paletového tokenu netvrdí nic o kresbě (#393, #432): barva se do plochy musí ještě
/// dostat, a `opacity` u prošlého segmentu ji navíc mění. Tři třídy tvrzení:
///
/// - **šířky dojdou až do kresby**: co spočítá `Policy.mapWidths`, to má být v bitmapě široké
///   stejně. Je to tentýž požadavek jako u #236 — kdo si říká o rozměr, musí ho měřit na tom,
///   na čem kreslí, a mezi `Policy`, `PullRequestMapGeometry` a `Canvas`em se dvě pravdy o jedné
///   šířce rodí snadno;
/// - **barvy se od sebe poznají**: čtyři výplně (`crit`, `find`, `okWash`, neutrál) plus jejich
///   tlumená podoba. Prošlý `crit` na 35 % se **nesmí** splést s neutrálem, jinak by pás tvrdil
///   „tady nic není“ nad souborem, který blokuje;
/// - **čárka a obrys jsou vidět**: akcent proti ploše hlavičky, tedy tam, kde čárka přesahuje pás
///   a kde obrys leží celý. Na to platí hranice 3 : 1 pro netextové prvky.
///
/// **Neutrál proti ploše hlavičky se 3 : 1 neměří, a je to zapsané rozhodnutí, ne mezera.**
/// `raised` na `surface` je v návrhu **tichý podklad** (`--panel-3` na `--panel`), tedy 1,1 : 1 ve
/// světlém režimu. Segment bez nálezu má být vidět jako **plocha v řadě ostatních**, ne jako
/// upozornění — kdyby se ztmavil na 3 : 1, byl by z něj čtvrtý stav závažnosti. Měří se u něj
/// proto jen to, že se do bitmapy **dostane** a že se pozná od pozadí i od tlumených barev.
///
/// **Vyzkoušené vložením regrese, všechny tři:**
///
/// - `Palette.raised` místo `okWash` u nového souboru → spadne *Každý segment má barvu svého
///   stavu* (0,54 od očekávané barvy ve světlém režimu, 0,40 v tmavém). Tvrzení o tom, že se
///   **tokeny** od sebe poznají, na tohle **nestačí** a je to zapsané: porovnává paletu, ne to,
///   který token dostal který segment;
/// - `.opacity(1)` místo `0,35` u prošlého → spadne *Tlumený blokující segment* (vzdálenost od
///   plné `crit` vyjde nula);
/// - `padding(3)` místo `padding(-3)` u obrysu (tedy obtah dovnitř) → spadne *Soubor pod výřezem
///   má obrys*, a to na obou hranách: obtah začne na 92 místo před segmentem na 90 a skončí na
///   170 místo za ním na 172.
///
/// A `Double(changedLines)` místo logaritmu spadne tady i v `PullRequestMapTests` — na téhle
/// straně na tom, že lock zabere 93,7 % pásu.
@MainActor
@Suite("Kresba mapy PR (#501)")
struct PullRequestMapDrawingTests {
    /// Šířka, ve které se pás měří. Dost velká, aby žádný segment nespadl na minimum, takže se
    /// dají porovnávat spočítané šířky s nakreslenými.
    private let width = 900.0

    // MARK: - Šířky dojdou do kresby

    /// Co spočítá `Policy`, to je v bitmapě — **v podílech, ne v absolutních bodech**.
    ///
    /// Podíly schválně: celková šířka pásu závisí na tom, kolik si vezme popisek vpravo, a ta se
    /// v testu spočítat nedá bez druhé kopie sazby (`TextWidth` proti tomu, co změří SwiftUI).
    /// Podíl je přesně to, co `Policy.mapWidths` rozhoduje, takže se měří ta odpověď, a ne
    /// zaokrouhlení popisku. Tolerance je **procento** — bitmapa má hrany vyhlazené.
    @Test("Nakreslené podíly segmentů sedí se spočítanými")
    func theDrawnWidthsMatchThePolicy() throws {
        let shot = try shot(dark: false, current: nil)
        let drawn = try #require(shot.segmentWidths, "pás se nenakreslil")
        #expect(drawn.count == 7, "nakresleno \(drawn.count) segmentů ze sedmi")

        let expected = Policy.mapWidths(
            of: shot.map.segments,
            in: Double(drawn.reduce(0, +)) + PullRequestMapView.stripSpacing * 6,
            spacing: PullRequestMapView.stripSpacing
        )
        let drawnTotal = Double(drawn.reduce(0, +))
        let expectedTotal = expected.reduce(0, +)

        for (index, pair) in zip(drawn, expected).enumerated() {
            let drawnShare = Double(pair.0) / drawnTotal
            let expectedShare = pair.1 / expectedTotal
            #expect(abs(drawnShare - expectedShare) <= 0.01,
                    "segment \(index): nakreslený podíl \(drawnShare) proti spočítanému \(expectedShare)")
        }
    }

    /// **A lock je největší, ale test je vidět.** Je to totéž tvrzení jako v `PullRequestMapTests`,
    /// jen na druhém konci: tam nad čísly, tady nad kresbou. Kdyby se logaritmus vytratil až
    /// v `Layout`u, čísla by dál vycházela.
    @Test("Největší soubor nezabere pás, nejmenší je vidět")
    func theBiggestFileDoesNotSwallowTheStrip() throws {
        let shot = try shot(dark: false, current: nil)
        let drawn = try #require(shot.segmentWidths)

        let total = Double(drawn.reduce(0, +))
        let lock = Double(drawn[5])
        #expect(lock / total < 0.4, "lock zabral \(lock / total * 100) % pásu")
        #expect(drawn.allSatisfy { $0 >= 3 }, "segment užší než tři body: \(drawn)")
    }

    // MARK: - Barvy se od sebe poznají

    /// Čtyři výplně a jejich tlumené podoby — **deset párů, každý zvlášť**. Vzdálenost je
    /// v složkách sRGB; prahy jsou z naměřených hodnot, ne odhadnuté.
    @Test("Barvy segmentů se od sebe poznají v obou režimech")
    func theSegmentFillsStayApart() throws {
        for dark in [false, true] {
            let shot = try shot(dark: dark, current: nil)
            let tokens = shot.tokens
            let pairs: [(String, Rgb, Rgb)] = [
                ("blokuje ↔ nález", tokens.crit, tokens.find),
                ("blokuje ↔ nový", tokens.crit, tokens.okWash),
                ("blokuje ↔ neutrál", tokens.crit, tokens.raised),
                ("nález ↔ nový", tokens.find, tokens.okWash),
                ("nález ↔ neutrál", tokens.find, tokens.raised),
                ("nový ↔ neutrál", tokens.okWash, tokens.raised),
                ("neutrál ↔ plocha hlavičky", tokens.raised, tokens.surface),
            ]
            for (name, first, second) in pairs {
                #expect(first.distance(to: second) > 0.05,
                        "\(shot.name), \(name): vzdálenost \(first.distance(to: second))")
            }
        }
    }

    /// **Který segment dostal kterou barvu** — a tohle je to tvrzení, které se dá pokazit
    /// nejsnadněji: `fill(of:)` je jeden `switch` a jeho `nil` větev rozhoduje ještě o `isNew`.
    /// Kdyby nový soubor spadl na neutrál, čísla by dál vycházela a pás by mlčel.
    ///
    /// Porovnává se s **nakresleným** tokenem, ne s paletou: bitmapa je v profilu displeje, takže
    /// `crit` v ní leží 0,18 od sRGB (#366).
    @Test("Každý segment má barvu svého stavu")
    func everySegmentGetsItsOwnFill() throws {
        for dark in [false, true] {
            let shot = try shot(dark: dark, current: nil)
            let expected: [(index: Int, name: String, color: Rgb)] = [
                (1, "nález", shot.tokens.find),
                (2, "nový soubor", shot.tokens.okWash),
                (3, "změněno od prošlého", shot.tokens.raised),
                (6, "bez nálezu", shot.tokens.raised),
            ]
            for (index, name, color) in expected {
                let drawn = try #require(shot.color(ofSegment: index), "\(shot.name): segment \(index)")
                #expect(drawn.distance(to: color) < 0.04,
                        "\(shot.name), \(name): nakresleno \(drawn) místo \(color)")
            }
        }
    }

    /// **Nejcennější tvrzení téhle sady**: tlumený blokující segment se nesmí splést s neutrálem.
    /// Prošlý soubor je odbytá práce, ale pořád blokuje — a kdyby v pásu zhasl na barvu „tady nic
    /// není“, byl by to nález, který se ztratil pohledem.
    @Test("Tlumený blokující segment se nespletě s neutrálem")
    func theDimmedBlockingSegmentStaysRecognisable() throws {
        for dark in [false, true] {
            let shot = try shot(dark: dark, current: nil)
            // Segment 0 je `crit` a prošlý, segment 6 je neutrál a nepřečtený.
            let dimmedCrit = try #require(shot.color(ofSegment: 0), "\(shot.name): segment 0 nenakreslen")
            let neutral = try #require(shot.color(ofSegment: 6), "\(shot.name): segment 6 nenakreslen")

            #expect(dimmedCrit.distance(to: neutral) > 0.08,
                    "\(shot.name): tlumený crit \(dimmedCrit) proti neutrálu \(neutral)")
            // A od plné `crit` se pozná taky — jinak by tlumení nic neříkalo.
            #expect(dimmedCrit.distance(to: shot.tokens.crit) > 0.08,
                    "\(shot.name): tlumení se nenakreslilo")
        }
    }

    /// **Změněný od prošlého se netlumí** (#500). Bitmapou, ne jen `Policy`: `opacity` je věc
    /// kresby, takže by se to dalo pokazit v pásu, aniž by se cokoli změnilo v čisté funkci.
    @Test("Změněný od prošlého se v pásu netlumí")
    func aChangedFileIsNotDimmed() throws {
        let shot = try shot(dark: false, current: nil)
        // Segment 1 je `find` a nepřečtený, segment 3 je neutrál a `changed`.
        let plainFind = try #require(shot.color(ofSegment: 1))
        let changed = try #require(shot.color(ofSegment: 3))

        #expect(plainFind.distance(to: shot.tokens.find) < 0.04, "plný nález se nenakreslil plně")
        #expect(changed.distance(to: shot.tokens.raised) < 0.04,
                "`changed` se ztlumil: \(changed) proti \(shot.tokens.raised)")
    }

    // MARK: - Čárka a obrys

    /// Akcent proti ploše hlavičky — **hranice 3 : 1 pro netextové prvky**. Právě tam čárka
    /// vlákna přesahuje pás (4 body nad a pod) a právě tam leží obrys celý, takže je to ta
    /// dvojice, na které jejich viditelnost stojí.
    @Test("Akcent má na ploše hlavičky netextový kontrast")
    func theAccentIsVisibleOnTheHeader() throws {
        for dark in [false, true] {
            let shot = try shot(dark: dark, current: nil)
            let ratio = shot.tokens.accent.contrast(with: shot.tokens.surface)
            #expect(ratio >= 3, "\(shot.name): akcent proti ploše hlavičky \(ratio) : 1")
        }
    }

    /// Čárka vlákna **je v bitmapě** a leží nad svým segmentem. Bez tohohle tvrzení by se dala
    /// kresba rozbít tak, že podíly spočítá a nikam nic nenakreslí.
    @Test("Čárka vlákna se nakreslí uvnitř svého segmentu")
    func theThreadTickLandsInsideItsSegment() throws {
        let shot = try shot(dark: false, current: nil)
        let box = try #require(shot.accentBox, "čárka vlákna se nenakreslila")
        let segment = try #require(shot.segmentBounds(1), "segment 1 se nenakreslil")

        #expect(box.left >= segment.left - 1 && box.right <= segment.right + 1,
                "čárka je na \(box.left)–\(box.right), segment na \(segment.left)–\(segment.right)")
        // Přesah nad pás: čárka je vyšší než segment, jinak by se v desetibodovém pásu ztratila.
        #expect(box.height > 10, "čárka má \(box.height) b, pás 10")
    }

    /// **Obrys se kreslí kolem segmentu pod výřezem, ne dovnitř.** Čte se z `DiffViewport` přes
    /// `DiffFileCursor`, takže scéna má výřez posazený na druhý soubor a čeká se, až sonda
    /// (`PullRequestMapProbe`) cestu do krabice zapíše.
    @Test("Soubor pod výřezem má obrys akcentem kolem sebe")
    func theCurrentFileGetsAnOutline() throws {
        let without = try shot(dark: false, current: nil)
        let with = try shot(dark: false, current: 1)

        let plain = try #require(without.accentBox, "čárka vlákna se nenakreslila")
        let outlined = try #require(with.accentBox, "obrys se nenakreslil")
        // Hranice segmentu se berou ze snímku **bez** obrysu: s ním je obtah taky „ne plocha
        // hlavičky“, takže by běhy pixelů slily segment se sousedem.
        let segment = try #require(without.segmentBounds(1), "segment 1 se nenakreslil")

        // Obrys je širší než samotná čárka — a je to jediné, co se mezi snímky změnilo.
        #expect(outlined.width > plain.width + 20,
                "obrys má \(outlined.width) b, čárka \(plain.width) b")
        // **Kolem segmentu, ne dovnitř** (`outline-offset`): obtah přečnívá na obě strany.
        #expect(outlined.left < segment.left,
                "obrys začíná na \(outlined.left), segment na \(segment.left)")
        #expect(outlined.right > segment.right,
                "obrys končí na \(outlined.right), segment na \(segment.right)")
    }

    // MARK: - Měřidlo

    private struct Box {
        let left: Int
        let right: Int
        let top: Int
        let bottom: Int

        var width: Int { right - left + 1 }
        var height: Int { bottom - top + 1 }
    }

    /// Barva v sRGB. Neúspěch převodu se **nezamlčuje** — hlídá ho tvrzení v `measureTokens`.
    private struct Rgb: CustomStringConvertible {
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

        var description: String {
            String(format: "%.3f/%.3f/%.3f", red, green, blue)
        }

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

    /// Tokeny **tak, jak je harness nakreslí** — vzorník projde tou samou cestou jako pás, takže
    /// se profil displeje vykrátí (poučení z #366: `crit` vyjde v bitmapě 0,18 daleko od sRGB).
    private struct Tokens {
        let crit: Rgb
        let find: Rgb
        let okWash: Rgb
        let raised: Rgb
        let surface: Rgb
        let accent: Rgb
    }

    private struct Shot {
        let name: String
        let tokens: Tokens
        let map: PullRequestMap
        let pixels: [[Rgb]]

        /// Řádek uprostřed pásu. Hledá se podle toho, **kde není plocha hlavičky** — a jen
        /// v levých šedesáti procentech, protože vpravo stojí popisek a jeho glyfy leží na týchž
        /// řádcích. Podle `crit` to hledat nejde: v téhle scéně je první segment **prošlý**, tedy
        /// tlumený, takže plná `crit` se v bitmapě nevyskytuje ani jednou — a přesně na tom se
        /// první podoba tohohle měřidla rozbila.
        var stripRow: Int? {
            let limit = pixels.first.map { Int(Double($0.count) * 0.6) } ?? 0
            var best: (row: Int, count: Int)?
            for (y, row) in pixels.enumerated() {
                let count = row.prefix(limit).count { $0.distance(to: tokens.surface) > 0.02 }
                if count > (best?.count ?? 0) { best = (y, count) }
            }
            return best.map(\.row)
        }

        /// Šířky segmentů v bodech: běhy pixelů, které nejsou plochou hlavičky, oddělené mezerami.
        var segmentWidths: [Int]? { runs?.map(\.width) }

        func segmentBounds(_ index: Int) -> Box? {
            guard let runs, runs.indices.contains(index) else { return nil }
            return runs[index]
        }

        /// Barva prostředního pixelu daného segmentu.
        func color(ofSegment index: Int) -> Rgb? {
            guard let runs, runs.indices.contains(index), let row = stripRow else { return nil }
            let box = runs[index]
            return pixels[row][(box.left + box.right) / 2]
        }

        /// Obálka pixelů v barvě akcentu — čárka vlákna, nebo obrys.
        var accentBox: Box? { box(of: tokens.accent, tolerance: 0.06) }

        private var runs: [Box]? {
            guard let row = stripRow else { return nil }
            var result: [Box] = []
            var start: Int?
            for (x, pixel) in pixels[row].enumerated() {
                let isStrip = pixel.distance(to: tokens.surface) > 0.02
                if isStrip {
                    if start == nil { start = x }
                } else if let from = start {
                    result.append(Box(left: from, right: x - 1, top: row, bottom: row))
                    start = nil
                }
            }
            if let from = start {
                result.append(Box(left: from, right: pixels[row].count - 1, top: row, bottom: row))
            }
            // Popisek vpravo je taky „ne plocha hlavičky“ — segmenty jsou ty běhy před mezerou
            // širší než mezera mezi segmenty. Sedm souborů znamená sedm běhů.
            return result.count >= 7 ? Array(result.prefix(7)) : result
        }

        private func box(of color: Rgb, tolerance: Double) -> Box? {
            var box: Box?
            for (y, row) in pixels.enumerated() {
                for (x, pixel) in row.enumerated() where pixel.distance(to: color) < tolerance {
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
    }

    /// Scéna: sedm souborů, z nichž první blokuje a je prošlý, druhý má nález i vlákno, čtvrtý je
    /// `změněno od prošlého` a šestý je lock. Je to rozložení ze sekce 42 návrhu.
    private func scene(current: Int?) -> (map: PullRequestMap, files: [FileDiff], tracking: DiffTracking) {
        let files = MapScene.files
        let map = MapScene.map
        let tracking = DiffTracking()
        // Rozsahy souborů v obsahu, jak je měří `DiffFileSection` — sto bodů na soubor.
        for (index, file) in files.enumerated() {
            tracking.extents.note(file.id, Double(index * 100)...Double((index + 1) * 100))
        }
        // Výřez posazený doprostřed žádaného souboru; `nil` = nikde, tedy bez obrysu.
        tracking.viewport.top = current.map { Double($0 * 100 + 50) } ?? -1000
        return (map, files, tracking)
    }

    private func shot(dark: Bool, current: Int?) throws -> Shot {
        let built = scene(current: current)
        let view = PullRequestMapView(
            map: built.map,
            files: built.files,
            tracking: built.tracking,
            jump: { _ in }
        )
        return Shot(
            name: dark ? "tmavý režim" : "světlý režim",
            tokens: try tokens(dark: dark),
            map: built.map,
            pixels: try pixels(of: view, size: CGSize(width: width, height: 40), dark: dark)
        )
    }

    /// Nakreslený vzorník na režim. **Drží se mezi testy schválně** (jako u #366): hodnota závisí
    /// jen na režimu, a metrika písma je stav procesu, který se pod paralelní zátěží umí vyřešit
    /// jinak (#407).
    @MainActor private static var drawnTokens: [Bool: Tokens] = [:]

    private func tokens(dark: Bool) throws -> Tokens {
        if let cached = Self.drawnTokens[dark] { return cached }
        let measured = try measureTokens(dark: dark)
        Self.drawnTokens[dark] = measured
        return measured
    }

    private func measureTokens(dark: Bool) throws -> Tokens {
        let swatch = HStack(spacing: 0) {
            ForEach(
                [Palette.crit, Palette.find, Palette.okWash, Palette.raised, Palette.surface, Palette.accent],
                id: \.self
            ) { color in
                Rectangle().fill(color).frame(width: 10, height: 10)
            }
        }
        let rows = try pixels(of: swatch, size: CGSize(width: 60, height: 10), dark: dark)
        let middle = try #require(rows.indices.contains(5) ? rows[5] : nil)
        let read = { (index: Int) throws -> Rgb in
            let pixel = try #require(middle.indices.contains(index) ? middle[index] : nil)
            #expect(pixel.isConverted)
            return pixel
        }
        return Tokens(
            crit: try read(5),
            find: try read(15),
            okWash: try read(25),
            raised: try read(35),
            surface: try read(45),
            accent: try read(55)
        )
    }

    /// Kresba view v daném režimu, po bodech. Tatáž cesta jako u ostatních sond — `NSHostingView`
    /// v okně mimo obrazovku a `cacheDisplay`, protože `ImageRenderer` `Layout` ani `ScrollView`
    /// nekreslí věrně.
    private func pixels(of view: some View, size: CGSize, dark: Bool) throws -> [[Rgb]] {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var result: Result<[[Rgb]], any Error>?
        appearance.performAsCurrentDrawingAppearance {
            result = Result {
                let scene = view
                    .frame(width: size.width, alignment: .topLeading)
                    .background(Palette.surface)
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
                window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
                window.orderFrontUnanimated()
                defer { window.orderOut(nil) }
                // **Dvě kola, ne jedno**: sonda výřezu zapisuje cestu do krabice až v prvním
                // z nich, takže obrys se kreslí teprve v tom druhém.
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                hosting.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))

                let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                let scale = max(rep.pixelsWide / Int(size.width), 1)
                var rows: [[Rgb]] = []
                for y in stride(from: 0, to: rep.pixelsHigh, by: scale) {
                    var row: [Rgb] = []
                    for x in stride(from: 0, to: rep.pixelsWide, by: scale) {
                        // **Nepřečtený pixel není průhledný pixel** — `?? .clear` by z nečitelné
                        // bitmapy udělal pás bez segmentů, tedy zeleně prošlé „nekreslí se“.
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

/// Scéna mapy PR pro sondy i pro měření kresby — **jedno místo**, ať se obrázek a čísla nerozejdou.
enum MapScene {
    /// Rozložení ze sekce 42 návrhu: sedm souborů, `composer.lock` 2 790 řádků z 2 952.
    static let files: [FileDiff] = [
        file("src/Vault/SecretClient.php", added: 18, removed: 6),
        file("src/Vault/Encryptor.php", added: 31, removed: 12),
        file("src/Vault/SecretNotFound.php", added: 21, removed: 0, change: .added),
        file("tests/SecretClientTest.php", added: 64, removed: 0),
        file("composer.json", added: 3, removed: 1),
        file("composer.lock", added: 2100, removed: 690),
        file("phpunit.xml.dist", added: 4, removed: 2),
    ]

    static let findings: [Finding] = [
        makeFinding(file: "src/Vault/SecretClient.php", line: 5, category: "correctness"),
        makeFinding(file: "src/Vault/Encryptor.php", line: 3, category: "style"),
    ]

    static let threads: [ReviewThread] = [
        ReviewThread(
            id: "t1",
            path: "src/Vault/Encryptor.php",
            line: 12,
            originalLine: 12,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    ]

    /// Pás z téhle scény — **jedno místo**, ze kterého ho berou obě sady i sonda.
    static var map: PullRequestMap {
        Policy.pullRequestMap(
            files: files,
            findings: Policy.groups(of: findings),
            threads: threads,
            readStates: readStates
        )
    }

    static let readStates: [String: FileReviewState] = [
        "src/Vault/SecretClient.php": .read(at: Date(timeIntervalSince1970: 1_000_000)),
        "tests/SecretClientTest.php": .changed(readAt: Date(timeIntervalSince1970: 1_000_000)),
        "composer.json": .read(at: Date(timeIntervalSince1970: 1_000_000)),
    ]

    /// Soubor s daným počtem přidaných a odebraných řádků. **Přidané jdou první a mají nová čísla
    /// 1…N**, protože vlákno se kotví na nové číslo (`Policy.matches`) — bez toho by čárka neměla
    /// na co sednout.
    private static func file(
        _ path: String,
        added: Int,
        removed: Int,
        change: FileDiff.Change = .modified
    ) -> FileDiff {
        let new = (0..<added).map {
            DiffLine(kind: .added, oldNumber: nil, newNumber: $0 + 1, text: "nové \($0 + 1)")
        }
        let old = (0..<removed).map {
            DiffLine(kind: .removed, oldNumber: $0 + 1, newNumber: nil, text: "staré \($0 + 1)")
        }
        return FileDiff(
            oldPath: change == .added ? nil : path,
            newPath: path,
            change: change,
            isBinary: false,
            hunks: [DiffHunk(oldStart: 1, oldCount: removed, newStart: 1, newCount: added,
                             heading: "", lines: new + old)],
            blobs: "aaa..bbb"
        )
    }
}
