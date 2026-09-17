import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Že blok `Reviewery · 30 dní` (#514) a tabulka v Nastavení **doopravdy kreslí to, co v datech
/// je** — dva stavy vedle sebe a rozdíl bitmap.
///
/// Existuje kvůli mezeře, kterou `ReviewerTallyTests` nezavřou: ty tvrdí, co `Policy` vydá, takže
/// by prošly i nad view, které věty vůbec nevykreslí, nebo které kreslí pořád tentýž pruh.
/// **Rozdíl bitmap, ne čtení textu** (jako u #389): accessibility tree se v hostovaném okně
/// nenaplní, takže „je vidět“ se dá tvrdit jedině z pixelů. Tvrzení je slabší (neříká *co* se
/// změnilo), ale nenapojený pruh chytá stejně dobře.
///
/// `NSHostingView` v okně, ne `ImageRenderer`; okno se ukazuje **bez animace** (#462).
@MainActor
@Suite("Blok Reviewery a tabulka se kreslí z dat (#514)")
struct ReviewerTallyRenderTests {
    /// Šířka pravého sloupce desky v okně na jeho minimu (700): `1fr` z `1.45fr 1fr` po odečtení
    /// railu a odsazení. Je to ta zajímavá — v ní se věta vejde nejhůř.
    private static let blockWidth: CGFloat = 237
    private let repo = RepoID(owner: "keboola", name: "job-queue")

    private func tally(
        _ reviewer: String = "code-review",
        taken: Int = 0,
        invalid: Int = 0,
        irrelevant: Int = 0,
        undecided: Int = 0
    ) -> ReviewerTally {
        ReviewerTally(
            reviewer: reviewer,
            repo: repo,
            taken: taken,
            invalid: invalid,
            irrelevant: irrelevant,
            undecided: undecided
        )
    }

    // MARK: - Blok na domově

    @Test("Poměr v pruhu je vidět — dva různé součty se nekreslí stejně")
    func theBarFollowsTheNumbers() throws {
        let mostlyTaken = try rows("pruh-prevzato", [tally(taken: 12, invalid: 1)])
        let mostlyInvalid = try rows("pruh-neplati", [tally(taken: 1, invalid: 12)])

        #expect(mostlyTaken != mostlyInvalid)
    }

    /// **Srovnává se jen konec věty, ne celý řádek — a na tom stojí celé měřidlo.**
    ///
    /// Dvě předchozí podoby tohohle testu **netvrdily nic** (#478) a byly u toho zelené. Nejdřív
    /// se srovnávalo `neplatí` proti `nepatří sem` nad celým řádkem: ty dva se liší i **barvou
    /// dílku v pruhu**, takže bitmapy vyšly různé i s větou, která se z `Policy` vůbec nebrala.
    /// Pak se srovnával týž poměr pod a nad podlahou (1 : 3 proti 2 : 6): pruh byl sice pixel na
    /// pixel týž, jenže **neutrální věta se v těch dvou stavech taky liší** (`1 z 4` proti
    /// `2 z 8`). Třetí pokus zúžil výřez na pravých 200 bodů — a do těch se pruh vejde taky.
    ///
    /// Tohle je ta izolace. Oba řádky mají **týž součet i totéž `převzato`** (0 z 9), takže
    /// neutrální věta zní v obou **doslova stejně**, kdežto věta z `Policy` řekne jednou
    /// `9 z 9 neplatí → skill` a jednou `9 z 9 nepatří sem → pravidla repa`. Výřez je posledních
    /// **55 bodů** řádku, tedy konec věty — pruh je od pravého okraje dál než nejkratší z těch
    /// dvou vět. Ověřeno vložením regrese: s neutrální větou u obou stavů tenhle test **padá**
    /// (bitmapy vyšly shodně, 3 160 bajtů).
    @Test("Věta se kreslí z Policy — týž součet, jiný důvod")
    func theSentenceComesFromPolicy() throws {
        let skill = try sentence("veta-skill", tally(invalid: 9))
        let rules = try sentence("veta-pravidla", tally(irrelevant: 9))

        #expect(skill != rules)
    }

    @Test("V úzkém sloupci se řádek složí pod sebe, v širokém ne")
    func theRowStacksWhenItIsNarrow() throws {
        let narrow = try rows("radek-uzky", [tally(taken: 5, invalid: 1, irrelevant: 5)])
        let wide = try rows("radek-siroky", [tally(taken: 5, invalid: 1, irrelevant: 5)], width: 640)

        #expect(try height(of: narrow) > height(of: wide))
    }

    // MARK: - Tabulka v Nastavení

    @Test("Tabulka bez dat říká proč, s daty kreslí řádky")
    func theTableExplainsItsEmptiness() throws {
        let empty = try table("tabulka-prazdna", [])
        let filled = try table("tabulka-plna", [tally(taken: 6, invalid: 1)])

        #expect(empty != filled)
    }

    /// `Otevřít skill ↗` se kreslí **jen** u skillu se zapsanou cestou — a nekreslí se zašedle,
    /// takže rozdíl musí být vidět.
    @Test("Tlačítko Otevřít skill se objeví teprve se zapsanou cestou")
    func theSkillButtonAppearsOnlyWithAFolder() throws {
        let without = try table("tabulka-bez-cesty", [tally(taken: 6, invalid: 1)])
        let with = try table(
            "tabulka-s-cestou",
            [tally(taken: 6, invalid: 1)],
            folders: ["code-review": "/opt/skills/code-review"]
        )

        #expect(without != with)
    }

    @Test("Cesta k cizímu skillu tlačítko nepřidá")
    func aFolderForAnotherSkillChangesNothing() throws {
        let mine = try table("tabulka-cizi-cesta", [tally(taken: 6, invalid: 1)])
        let other = try table(
            "tabulka-cizi-cesta-2",
            [tally(taken: 6, invalid: 1)],
            folders: ["security-review": "/opt/skills/security-review"]
        )

        #expect(mine == other)
    }

    // MARK: - Kreslení

    private func rows(
        _ name: String,
        _ tallies: [ReviewerTally],
        width: CGFloat = ReviewerTallyRenderTests.blockWidth
    ) throws -> Data {
        try bitmap(name, width: width) { ReviewerTallyRowsView(tallies: tallies) }
    }

    private func table(
        _ name: String,
        _ tallies: [ReviewerTally],
        folders: [String: String] = [:]
    ) throws -> Data {
        try bitmap(name, width: 509) {
            Form {
                Section {
                    ReviewerTallyTable(tallies: tallies, skillFolders: folders)
                }
            }
            .formStyle(.grouped)
        }
    }

    /// Posledních 55 bodů širokého řádku, tedy **konec věty**. Pruh ani jméno do výřezu
    /// nespadnou — a je to úzké schválně: širší výřez pruh **chytí** (viz doc u testu výš).
    private func sentence(_ name: String, _ tally: ReviewerTally) throws -> Data {
        let width: CGFloat = 640
        let png = try rows(name, [tally], width: width)
        return try crop(png, from: CGRect(x: width - 55, y: 0, width: 55, height: 40))
    }

    /// Výřez v **bodech**; převod na pixely obstará poměr rozměrů bitmapy (Retina má dvojnásobek).
    private func crop(_ png: Data, from rect: CGRect) throws -> Data {
        let rep = try #require(NSBitmapImageRep(data: png))
        let image = try #require(rep.cgImage)
        let scale = CGFloat(image.width) / CGFloat(rep.size.width)
        let scaled = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        let cut = try #require(image.cropping(to: scaled))
        return try #require(NSBitmapImageRep(cgImage: cut).representation(using: .png, properties: [:]))
    }

    /// Výška bitmapy — z ní se pozná, jestli se řádek složil pod sebe.
    private func height(of png: Data) throws -> Int {
        try #require(NSBitmapImageRep(data: png)).pixelsHigh
    }

    private func bitmap<Content: View>(
        _ name: String,
        width: CGFloat,
        _ content: () -> Content
    ) throws -> Data {
        let appearance = try #require(NSAppearance(named: .darkAqua))
        var result: Result<Data, any Error>?
        appearance.performAsCurrentDrawingAppearance {
            do {
                let scene = content()
                    .frame(width: width)
                    .background(Palette.chrome)
                    .environment(\.colorScheme, .dark)
                    .tint(Palette.accent)
                let hosting = NSHostingView(rootView: scene)
                // Výška se **měří**, nenasazuje: podle ní se pozná složený řádek.
                hosting.frame = NSRect(
                    x: 0,
                    y: 0,
                    width: width,
                    height: max(hosting.fittingSize.height, 40)
                )
                let window = NSWindow(
                    contentRect: hosting.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = hosting
                // Mimo obrazovku, ať test nikomu neskočí před oči — v paralelním běhu stojí vedle
                // sebe víc instancí.
                window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
                window.orderFrontUnanimated()
                defer { window.orderOut(nil) }
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                if let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] {
                    let url = URL(filePath: directory).appending(path: "reviewery-\(name).png")
                    try png.write(to: url)
                    print("RENDER \(url.path)")
                }
                result = .success(png)
            } catch {
                result = .failure(error)
            }
        }
        return try #require(result).get()
    }
}
