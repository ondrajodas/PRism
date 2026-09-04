import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Dělící čáry v pruhu desky (#371, přeneseno na desku #515) — a hlavně **ta jedna nad patkou**.
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
@Suite("Dělící čáry pruhu na desce")
@MainActor
struct BoardSeparatorTests {
    /// Kolik vodorovných čar má levý sloupec desky v tomhle scénáři.
    ///
    /// Scéna má **tři neprázdné pruhy ze šesti** (draft, doběhlé review, zbytek `neběželo`):
    ///
    /// - `Dopsat a odeslat` s jedním řádkem: obrys, spodní linka hlavičky, obrys — **tři**;
    /// - `Rozhodnout` s jedním řádkem — taky **tři**;
    /// - `Přečíst` se sedmi v pruhu, z nichž se kreslí pět: obrys, hlavička, čtyři mezi řádky,
    ///   **jedna nad patkou** a obrys — **osm**.
    ///
    /// Celkem **čtrnáct**. **Prázdné pruhy nepřidávají nic**, a je to to podstatné tvrzení
    /// (z proklikání #515): kdyby se začaly kreslit i s nulou, jak to bylo do proklikání, přiskočí
    /// tři × tři a vyjde třiadvacet — tedy přesně to číslo, které tu stálo předtím. Test tím drží
    /// **obojí**: že se patka kreslí jednou čárou, i že se prázdný pruh nekreslí vůbec.
    ///
    /// **Blok `Dění` (#443) se do počtu nepromítá**: stojí v **pravém** sloupci, kdežto vzorek
    /// jde přes levý (viz `bands(in:)`).
    ///
    /// Počet je v tvrzení schválně: bez něj by test prošel i tehdy, kdyby se patka nenakreslila
    /// vůbec — třináct stejně silných čar je taky „všechny stejně silné“.
    private static let expectedLines = 14

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
        let scene = BoardView(store: store, open: { _ in })
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
        window.orderFrontUnanimated()
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

    /// Deska s devíti cizími PR: na jednom leží draft, na druhém doběhlé review, sedm zbylých
    /// `neběželo` (z nich se kreslí pět a patka hlásí `+2`). Kreslí se tedy **tři pruhy ze šesti** a tři se skrývají — bez toho by scéna
    /// o skrývání netvrdila nic (jeden pruh vypadá stejně, ať se prázdné kreslí, nebo ne).
    ///
    /// Kreslí se přes `NSHostingView` a `cacheDisplay`, ne `ImageRenderer`: deska je `ScrollView`
    /// a ten se offscreen nerasterizuje (změřeno u #237).
    private func store() async -> AppStore {
        // **Devět, ne sedm**: draft a doběhlé review si vezmou po jednom, takže na `Přečíst`
        // zbude sedm — pět nakreslených a patka `+2`. Se sedmi v celku by v pruhu zbylo přesně
        // pět, patka by odpadla a test by o čáře nad patkou netvrdil nic.
        let queue = (1...9).map { number in
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
        // **Draft se sází přímo do `drafts`**: `setDraftBody` si bere `headSha` z načteného
        // detailu, a ten scéna nenačítá.
        store.drafts[queue[0].id] = ReviewDraft(
            pullRequest: queue[0].id,
            headSha: "aaaa1111",
            body: "Zbytek vypadá dobře."
        )
        store.reviewRecords[queue[1].id] = ReviewRecord(
            pullRequest: queue[1].id,
            headSha: "aaaa1111",
            runs: [makeStoredRun(findings: [], headSha: "aaaa1111")]
        )
        return store
    }

    /// Nejvyšší pás, který se ještě bere za čáru. Jednobodová čára má na Retině 2 px; strop je
    /// **6 px** schválně vyšší, aby dvojitá čára (4 px) do měření spadla a spadl na ní test —
    /// s těsným stropem by z výsledku jen tiše vypadla.
    private static let hairline = 6
    private static let tolerance = 2.0 / 255
    private static let width = 900.0
    private static let height = 1400.0
}
