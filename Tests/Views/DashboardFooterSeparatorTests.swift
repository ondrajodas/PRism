import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Dělící čáry v bloku dashboardu (#371) — a hlavně **ta jedna nad patkou**.
///
/// Patka stojí za posledním řádkem, takže se na něj přestane vztahovat „poslední řádek čáru nemá“.
/// Kdyby si patka nakreslila vlastní horní linku, sečetly by se: v mockupu z toho bylo 1 px + 1 px
/// = 2 px (změřeno sondou nad `getComputedStyle`), v aplikaci by to byl týž dvojitý oddělovač.
/// **Z kódu to vidět není** — dvě jednobodové čáry pod sebou vypadají v obou souborech správně —,
/// takže se to měří z bitmapy.
///
/// Měří se **všechny vodorovné čáry v levém sloupci naráz**, ne jen ta nad patkou: v tomhle návrhu
/// je každá z nich jednobodová, takže „všechny stejně silné“ je tvrzení, které dvojitou čáru chytí
/// a přitom nezávisí na tom, kolikátá zhora patka je.
///
/// **Barvy se neporovnávají s paletou**, a je to změřené, ne opatrnost: `Palette.lineSoft`
/// (`#E9ECF4`) vyjde v bitmapě jako `0.934 0.941 0.963`, tedy o kus světlejší než nominálních
/// `0.914 0.925 0.957` — okno kreslí do širšího barevného prostoru. Čára se proto pozná **tvarem**
/// (tenký jednolitý pás, který se barvou liší od pásů nad ním i pod ním), ne odstínem.
///
/// **Vyzkoušené vložením regrese**: s `overlay(alignment: .top)` navíc nad patkou vyjde jedna čára
/// 4 px vedle deseti dvoupixelových a test spadne na obojím — na počtu i na síle.
@Suite("Dělící čáry bloku dashboardu")
@MainActor
struct DashboardFooterSeparatorTests {
    /// Kolik vodorovných čar má levý sloupec dashboardu v tomhle scénáři.
    ///
    /// Blok `Čeká na moje review`: obrys nahoře, spodní linka hlavičky, čtyři mezi pěti řádky,
    /// **jedna nad patkou** a obrys dole — tedy osm. Blok `Moje PR` je prázdný (vlastní PR ve
    /// scénáři žádné nejsou), takže z něj jsou tři: obrys, hlavička, obrys. Celkem jedenáct.
    ///
    /// Počet je v tvrzení schválně: bez něj by test prošel i tehdy, kdyby se patka nenakreslila
    /// vůbec — deset stejně silných čar je taky „všechny stejně silné“.
    private static let expectedLines = 11

    @Test("Nad patkou je jedna čára, ne dvě")
    func drawsASingleHairlineAboveTheFooter() async throws {
        let store = await store()

        let lines = try horizontalLines(of: store)

        #expect(
            lines.count == Self.expectedLines,
            "Čar je \(lines.count) místo \(Self.expectedLines): \(lines)"
        )
        #expect(
            Set(lines.map(\.thickness)).count == 1,
            "Čáry nejsou stejně silné: \(lines)"
        )
    }

    // MARK: - měřidlo

    /// Vodorovná čára: kde začíná a jak je silná, v **pixelech bitmapy**.
    ///
    /// Pixely, ne body: dvojitá čára je dvakrát jeden bod, takže zaokrouhlením na body by se
    /// ztratila polovina rozdílu, který se hledá.
    private struct Line: CustomStringConvertible {
        let top: Int
        let thickness: Int

        var description: String { "y=\(top) × \(thickness)px" }
    }

    /// Jednolitý pás pixelových řádků téže barvy. `color == nil` = řádky, ve kterých je text nebo
    /// odznak, tedy pás, který se za čáru brát nemá.
    private struct Band {
        let top: Int
        let height: Int
        let color: NSColor?
    }

    /// Čáry z hotové kresby dashboardu.
    ///
    /// **Čeká se na jev se stropem** (#269), ne pevnou odmlkou: hierarchie se doskládá až za pár
    /// koly smyčky a kolik jich bude potřeba, rozhoduje zátěž stroje. Strop je `TestWait.deadline`,
    /// tedy tentýž jako u každého jiného čekání v repu — a když se nedočká, měří se poslední snímek
    /// a tvrzení nad ním spadne i s výpisem.
    /// **Okno drží tenhle scope**, ne návratová hodnota z pomocné funkce (nález Copilota): `NSWindow`
    /// vrácený jinde by měl vlastníka jedině v AppKitu a `hosting.window` by z toho bylo implicitní —
    /// kdyby se uvolnil, `cacheDisplay` by měřil view mimo okno a `orderOut` by tiše nedělal nic.
    /// Ostatní sondy v repu (`ChecksTabRenderProbe`, `SidebarRailTests`) ho drží stejně.
    private func horizontalLines(of store: AppStore) throws -> [Line] {
        let scene = DashboardView(store: store, open: { _ in })
            .frame(width: Self.width, height: Self.height)
            .environment(\.colorScheme, .light)
            .tint(Palette.accent)
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
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

        let limit = ContinuousClock.now.advanced(by: TestWait.deadline)
        var lines = try lines(in: hosting)
        while ContinuousClock.now < limit, lines.count != Self.expectedLines {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            lines = try self.lines(in: hosting)
        }
        return lines
    }

    /// Tenké pásy, které se barvou liší od nejbližšího jednolitého pásu nad sebou i pod sebou.
    ///
    /// Podmínka na okolí je tam kvůli **mezerám v textu**: mezi titulkem a souřadnicemi řádku je pár
    /// pixelů čisté plochy bloku, což je taky tenký jednolitý pás — jen má tutéž barvu jako plocha
    /// kolem, takže čára to není. Text sám se za okolí nebere (`color == nil`), jinak by mezera
    /// v textu vyšla jako čára.
    private func lines(in hosting: NSHostingView<some View>) throws -> [Line] {
        let bands = try bands(in: hosting)
        return bands.indices.compactMap { index in
            let band = bands[index]
            guard let color = band.color, band.height <= Self.hairline else { return nil }
            let above = bands[..<index].last { $0.color != nil }?.color
            let below = bands[(index + 1)...].first { $0.color != nil }?.color
            guard let above, let below, !matches(above, color), !matches(below, color) else { return nil }
            return Line(top: band.top, thickness: band.height)
        }
    }

    /// Bitmapa rozdělená na pásy podle toho, jak se barva mění po řádcích.
    ///
    /// Vzorkuje se **uvnitř levého sloupce** (`x` 60–400 bodů): tam vedou čáry bloku přes celý pás,
    /// kdežto karty nad blokem ne — mezi nimi je mezera v barvě plochy dashboardu, takže řádek
    /// s obrysem karty jednolitý není. Pravý sloupec (legenda a `Co teď`) leží za `x = 518`, takže
    /// se do vzorku nedostane vůbec.
    private func bands(in hosting: NSHostingView<some View>) throws -> [Band] {
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let scale = max(rep.pixelsWide / Int(Self.width), 1)
        let range = (60 * scale)..<(400 * scale)

        var bands: [Band] = []
        var current: (top: Int, height: Int, color: NSColor?)?
        for y in 0..<rep.pixelsHigh {
            let color = uniformColor(of: rep, row: y, in: range)
            if let open = current, matches(open.color, color) {
                current = (open.top, open.height + 1, open.color)
                continue
            }
            if let open = current { bands.append(Band(top: open.top, height: open.height, color: open.color)) }
            current = (y, 1, color)
        }
        if let open = current { bands.append(Band(top: open.top, height: open.height, color: open.color)) }
        return bands
    }

    /// Barva řádku, když je celý pás v jedné barvě; `nil`, když v něm něco je (text, odznak, proužek
    /// stavu).
    private func uniformColor(of rep: NSBitmapImageRep, row y: Int, in range: Range<Int>) -> NSColor? {
        guard let first = rep.colorAt(x: range.lowerBound, y: y) else { return nil }
        for x in range where !matches(rep.colorAt(x: x, y: y), first) { return nil }
        return first
    }

    /// Barvy se porovnávají s tolerancí — kresba se zaokrouhluje na osm bitů na kanál —, ale
    /// **těsnou**: jednotlivé odstíny palety leží pět stupňů od sebe.
    private func matches(_ left: NSColor?, _ right: NSColor?) -> Bool {
        switch (left?.usingColorSpace(.sRGB), right?.usingColorSpace(.sRGB)) {
        case (nil, nil): true
        case let (left?, right?):
            abs(left.redComponent - right.redComponent) < Self.tolerance
                && abs(left.greenComponent - right.greenComponent) < Self.tolerance
                && abs(left.blueComponent - right.blueComponent) < Self.tolerance
        default: false
        }
    }

    /// Dashboard se sedmi PR ve frontě — pět řádků a patka `+2`.
    ///
    /// Kreslí se přes `NSHostingView` a `cacheDisplay`, ne `ImageRenderer`: dashboard je `ScrollView`
    /// a ten se offscreen nerasterizuje (změřeno u #237).
    private func store() async -> AppStore {
        let queue = (1...7).map { number in
            PullRequestSummary(
                id: PRIdentifier(repo: RepoID("cli/cli")!, number: number),
                title: "titulek \(number)",
                author: "kdosi",
                url: URL(string: "https://github.com/cli/cli/pull/\(number)")!,
                updatedAt: Date(timeIntervalSince1970: Double(number) * 100),
                state: .open
            )
        }
        let store = AppStore(gateway: FakeGitHubGateway(always: .success(queue)), time: FakeTimeSource())
        await store.refresh()
        return store
    }

    /// Nejvyšší pás, který se ještě bere za čáru. Jednobodová čára má na Retině 2 px; strop je
    /// **6 px** schválně vyšší, aby dvojitá čára (4 px) do měření spadla a spadl na ní test —
    /// s těsným stropem by z výsledku jen tiše vypadla.
    private static let hairline = 6
    private static let tolerance = 2.0 / 255
    private static let width = 900.0
    private static let height = 1000.0
}
