import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Rail a přepínač vzhledu v něm (#278).
///
/// Dvě třídy tvrzení. **Že se něco nestalo:** přepínač není `RailSection`, takže se na vzhled nedá
/// „přepnout jako na obrazovku“ a nenabídne se v ⌘K mezi sekcemi. A **kde v railu leží:** to se
/// v úzkém pruhu o 52 bodech dá pokazit potichu, protože `Menu` si umí nakreslit indikátor a tím
/// ikonu vytlačit ze středu — z kódu to vidět není a v okně to vypadá jako křivě posazená ikona.
///
/// Poloha se čte z **bitmapy**, ne z rámečků: accessibility tree se v okně mimo obrazovku nenaplní
/// (změřeno u #269) a `fittingSize` railu je pevných 52 bodů, takže by na tuhle chybu neodpověděl
/// ani jeden z nich. **Vyzkoušené vložením regrese**: se stylem `.borderlessButton` (tedy s šipkou)
/// vyjde střed půlkolečka 25 místo 26 a test spadne.
@Suite("Rail")
@MainActor
struct SidebarRailTests {
    /// Sekce railu jsou **obrazovky**. Přepínač vzhledu žádnou neotevírá, takže sem nepatří — a je
    /// to ta chyba, která by se udělala nejsnáz, protože rail se kreslí z `allCases`.
    @Test("Vzhled není sekce railu")
    func theAppearanceIsNotARailSection() {
        // Pořadí je pořadí položek v railu: `Moje PR` leží mezi frontou a rozdělanými (#331).
        #expect(RailSection.allCases == [.overview, .queue, .mine, .drafts])
    }

    /// **Pátá položka se do 52 bodů vejde** (#331) — rail se kreslí z `allCases`, takže se do něj
    /// další sekce dostane sama, a v pruhu o 52 bodech se to dá pokazit potichu: ikona širší než
    /// rám (34 × 30, tedy 9–43) by se do svislice ostatních nevešla a rail by se rozjel.
    ///
    /// Měří se **bez odznaků**: ty visí jako `overlay` posunutý o 6 bodů doprava, takže z rámu
    /// vyčnívají schválně. Pásy se u toho **nepočítají** — ikona s mezerou uprostřed (šipka nad
    /// vaničkou u `Moje PR`) se do bitmapy zapíše jako dva pásy, takže by počet měřil kresbu
    /// glyfu, ne počet položek. Kolik sekcí rail má, tvrdí test výš.
    @Test("Sekce se vejdou do railu i s pátou položkou")
    func fitsEverySectionIntoTheRail() throws {
        let bands = try bands(mode: .system, queueCount: nil, mineCount: nil, draftCount: nil)
        let separator = try #require(bands.first { $0.height == 1 })
        let sections = bands.filter { $0.top < separator.top }

        #expect(!sections.isEmpty)
        for section in sections {
            #expect(section.center == 26)
            #expect(section.left >= 9)
            #expect(section.right <= 43)
        }
        // A celý rail se do své plochy vejde — poslední pás končí nad spodní hranou (260 bodů
        // s 10 body odsazení), takže se položky nepřekrývají a nic z nich nevypadlo.
        #expect(try #require(bands.last).bottom < 250)
    }

    /// A totéž z druhé strany: v paletě ⌘K se vzhled **nesmí** objevit mezi sekcemi. Kdyby byl
    /// případem `RailSection`, přišel by tam sám, protože položky sekcí se staví z `allCases`.
    @Test("Paleta nenabízí vzhled jako sekci")
    func theCommandPaletteOffersNoAppearanceSection() {
        let items = Policy.paletteActions(open: nil, section: .overview)

        let sections = items.compactMap { item -> RailSection? in
            guard case .action(.openSection(let section)) = item.target else { return nil }
            return section
        }
        // Sekcí je tolik, kolik jich rail má — bez té, na které se právě je.
        #expect(sections.count == RailSection.allCases.count - 1)
        #expect(!items.contains { $0.title.localizedCaseInsensitiveContains("vzhled") })
    }

    /// Oddělovač je z návrhu (`.rail .sep`): **20 × 1 bod**, vystředěný. Je to jediná vodorovná
    /// linka v railu, takže se pozná jako pás vysoký jeden bod.
    @Test("Oddělovač má rozměr z návrhu")
    func drawsTheSeparatorFromTheDesign() throws {
        let separator = try #require(bands(mode: .system).first { $0.height == 1 })

        #expect(separator.width == 20)
        #expect(separator.center == 26)
    }

    /// Přepínač stojí **pod oddělovačem** a v téže svislici jako ikony sekcí. Kdyby si tlačítko
    /// rozšířilo rám (nebo se do railu vešel indikátor nabídky), ikona se ze středu posune — a přesně
    /// to tady spadne.
    @Test("Přepínač vzhledu stojí pod oddělovačem a ve středu railu")
    func placesTheAppearanceItemBelowTheSeparator() throws {
        for mode in AppearanceMode.allCases {
            let bands = try bands(mode: mode)
            let separator = try #require(bands.first { $0.height == 1 })
            let below = try #require(bands.first { $0.top > separator.top })

            #expect(below.center == 26)
            // Vejde se do téhož rámu 34 × 30 jako ikony sekcí, tedy 9–43 na šířce railu 52.
            #expect(below.left >= 9)
            #expect(below.right <= 43)
            // A je to poslední věc v railu — pod přepínačem už nic není.
            #expect(bands.last?.top == below.top)
        }
    }

    /// Tři ikony na tři stavy (#278) **nesmí poskakovat**: klik je vyměňuje na tomtéž místě, takže
    /// když se liší velikostí, tlačítko při cyklení „skáče“ a rail vypadá roztřeseně.
    ///
    /// Naměřeno: slunce `16 × 16`, měsíc `15 × 16`, kolečko s „A“ `16 × 16` — tedy bod rozdílu na
    /// šířku a nic na výšku. Práh je 2 body, ne rovnost: SF Symbols se mezi verzemi systému
    /// překreslují a test má chytat **jinou** ikonu, ne zaokrouhlení.
    @Test("Tři ikony mají srovnatelnou velikost")
    func keepsTheThreeIconsComparable() throws {
        var icons: [AppearanceMode: Band] = [:]
        for mode in AppearanceMode.allCases {
            let bands = try bands(mode: mode)
            let separator = try #require(bands.first { $0.height == 1 })
            icons[mode] = try #require(bands.first { $0.top > separator.top })
        }

        let widths = icons.values.map(\.width)
        let heights = icons.values.map(\.height)
        #expect(try (widths.max() ?? 0) - #require(widths.min()) <= 2)
        #expect(try (heights.max() ?? 0) - #require(heights.min()) <= 2)
    }

    // MARK: - měřidlo

    /// Souvislý pás nakresleného obsahu v railu, v **bodech**.
    private struct Band {
        let top: Int
        let bottom: Int
        let left: Int
        let right: Int

        var height: Int { bottom - top + 1 }
        var width: Int { right - left + 1 }
        /// Střed pásu. Rail má 52 bodů, takže vystředěná položka má střed 26.
        var center: Int { (left + right + 1) / 2 }
    }

    /// Rail vykreslený do bitmapy a z ní pásy obsahu.
    ///
    /// Kreslí se ve **světlém** režimu; na poloze režim nic nemění a dvě sady by jen zdvojily běh —
    /// jak to vypadá v tmavém, ukazuje `AppearanceRenderProbe`.
    private func bands(
        mode: AppearanceMode,
        queueCount: Int? = 5,
        mineCount: Int? = 2,
        draftCount: Int? = 2
    ) throws -> [Band] {
        let scene = SidebarRail(
            section: .constant(.queue),
            queueCount: queueCount,
            mineCount: mineCount,
            draftCount: draftCount,
            appearance: mode
        )
            .frame(height: 260)
            .environment(\.colorScheme, .light)
            .tint(Palette.accent)
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: 52, height: 260)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať test nikomu neskočí před oči — vedle sebe běží víc instancí aplikace.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        // Hierarchie se doskládá až za jedním kolem smyčky.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let appearance = try #require(NSAppearance(named: .aqua))
        return Self.bands(in: appearance, rep: rep)
    }

    /// Pro každý řádek nejlevější a nejpravější pixel, který se liší od pozadí railu; souvislé
    /// řádky se slijí do pásu.
    ///
    /// Pozadí se bere z **levého okraje téhož řádku**, ne z konstanty: rail má v každém režimu
    /// jinou plochu a zadrátovaná barva by našla „obsah“ všude.
    private static func bands(in appearance: NSAppearance, rep: NSBitmapImageRep) -> [Band] {
        let scale = max(rep.pixelsWide / 52, 1)
        var pixels: [(top: Int, bottom: Int, left: Int, right: Int)] = []
        var current: (top: Int, bottom: Int, left: Int, right: Int)?

        appearance.performAsCurrentDrawingAppearance {
            for y in 0..<rep.pixelsHigh {
                let background = rep.colorAt(x: 1, y: y)
                var left: Int?
                var right = 0
                // Pravý okraj railu nese jeho obrys (1 bod), ten se do obsahu počítat nemá.
                for x in 2..<(rep.pixelsWide - scale) where !matches(rep.colorAt(x: x, y: y), background) {
                    if left == nil { left = x }
                    right = x
                }
                guard let left else {
                    if let current { pixels.append(current) }
                    current = nil
                    continue
                }
                current = (
                    top: current?.top ?? y,
                    bottom: y,
                    left: min(current?.left ?? left, left),
                    right: max(current?.right ?? right, right)
                )
            }
            if let current { pixels.append(current) }
        }

        return pixels.map {
            Band(top: $0.top / scale, bottom: $0.bottom / scale, left: $0.left / scale, right: $0.right / scale)
        }
    }

    /// Barvy se porovnávají s tolerancí — vyhlazování hran dělá i na jednolité ploše rozdíly
    /// v poslední cifře a přesná rovnost by z každého řádku udělala „obsah“.
    private static func matches(_ first: NSColor?, _ second: NSColor?) -> Bool {
        guard let first = first?.usingColorSpace(.sRGB), let second = second?.usingColorSpace(.sRGB) else {
            return true
        }
        return abs(first.redComponent - second.redComponent) < 0.02
            && abs(first.greenComponent - second.greenComponent) < 0.02
            && abs(first.blueComponent - second.blueComponent) < 0.02
    }
}
