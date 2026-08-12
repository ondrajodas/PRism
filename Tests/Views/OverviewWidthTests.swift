import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Šířka `Přehledu` (#291): **nic se nesmí nakreslit mimo tab.**
///
/// Vzniklo z regrese, kterou přinesla #279: sazba Markdownu přešla z pružného `frame(maxWidth:
/// .infinity)` na `filling()`, tedy na **konkrétní šířku z prostředí** — a `OverviewView`
/// tu šířku nezúžil o svá odsazení, takže popis dostal celou šířku tabu a karta kolem něj vyšla
/// o 58 bodů širší. Vpravo pak chyběla hrana a `Otevřít na GitHubu` bylo odříznuté.
///
/// **Měří se pixely, ne rámečky.** `frame(width:)` z `filling()` je tvrdý rámec: dítě, které se do
/// něj nevejde, přeteče **vizuálně**, aniž by se rodičova velikost změnila. Ptát se rodiče na
/// `fittingSize` proto na tuhle chybu nestačí; ptá se toho, kdo o ní neví. Přetečení se dá spočítat
/// jedině tak, že se obsah nakreslí na plátno **širší** než tab a v tom přesahu se hledají pixely.
///
/// **Bez `ScrollView`u** (`content`, ne `body`): `NSScrollView` obsah na svou šířku ukrojí, takže
/// by se přetečení nekreslilo a rozbitý stav by od opraveného nešlo poznat — přesně to dělá tuhle
/// regresi v aplikaci tak nenápadnou.
///
/// **Pásmo šířek, ne jedna** (poučení z #236): chyba tohohle druhu je konstantní přesah, ale text
/// se v každé šířce zalomí jinak, takže jediná šířka umí projít náhodou.
@MainActor
@Suite("Šířka Přehledu (#291)")
struct OverviewWidthTests {
    /// Šířky, ve kterých `Přehled` doopravdy stojí. Spodní kraj je 128 bodů, a není to teoretické
    /// číslo: okno má podlahu 700, rail bere 52 a panel nálezů se dá vytáhnout na 520.
    private let widths: [CGFloat] = [128, 200, 320, 420, 560, 720, 900, 1180]

    /// Kolik se vpravo nechá volného místa na to, aby se přesah měl kam nakreslit. Přesah z #291
    /// dělal 42 bodů (13 + 13 odsazení karty a 16 na pravé straně tabu), takže 120 je s rezervou.
    private let margin: CGFloat = 120

    @Test("Popis PR nepřeteče mimo tab v žádné šířce")
    func markdownDescriptionStaysInside() throws {
        for width in widths {
            let overflow = try overflow(width: width, description: Self.description, label: "popis")
            #expect(overflow == 0, "šířka \(Int(width)): přeteklo \(overflow) bodů vpravo")
        }
    }

    /// Prázdné a nedoručené stavy `Přehledu` (`Načítám popis…` proti `Autor k PR nic nenapsal.`)
    /// zůstávají rozlišené — a ani jeden z nich nesmí přetéct. Jsou to jiné podstromy než sazba,
    /// takže se měří zvlášť.
    @Test("Nenačtený i prázdný popis zůstanou uvnitř")
    func placeholderStatesStayInside() throws {
        for width in widths {
            for description in [nil, ""] as [String?] {
                let label = description == nil ? "nenacteny" : "prazdny"
                let overflow = try overflow(width: width, description: description, label: label)
                #expect(overflow == 0, "šířka \(Int(width)), \(label) popis: přeteklo \(overflow) bodů")
            }
        }
    }

    /// Banner „od minule“ a dlaždice s fakty jsou v `Přehledu` sourozenci karty s popisem, takže
    /// se roztáhnou na její šířku. Přetéct proto umí i tehdy, když si o šířku samy neříkají.
    @Test("Banner a dlaždice nepřetečou ani nad širokým popisem")
    func siblingsStayInside() throws {
        for width in widths {
            let overflow = try overflow(
                width: width,
                description: Self.description,
                facts: Self.facts,
                changes: Self.changes,
                movedHead: "9c1de0212ab",
                label: "vse"
            )
            #expect(overflow == 0, "šířka \(Int(width)): přeteklo \(overflow) bodů vpravo")
        }
    }

    // MARK: - Měření

    /// Kolik bodů se nakreslilo vpravo za hranou tabu. Nula = nic nepřeteklo.
    private func overflow(
        width: CGFloat,
        description: String?,
        facts: PullRequestFacts = PullRequestFacts(tiles: []),
        changes: VisitChanges = .none,
        movedHead: String? = nil,
        label: String
    ) throws -> Int {
        let image = try render(
            width: width,
            description: description,
            facts: facts,
            changes: changes,
            movedHead: movedHead
        )
        let empty = try render(
            width: width,
            description: nil,
            facts: PullRequestFacts(tiles: []),
            changes: .none,
            movedHead: nil,
            hidesContent: true
        )
        try dump(image, as: "prehled-\(label)-\(Int(width))")
        return try rightmostPaintedColumn(of: image, against: empty, beyond: width)
    }

    /// Obsah tabu na plátně širším než tab, na purpurovém podkladu. `hidesContent` vykreslí **jen
    /// ten podklad** — z něj se pak bere referenční barva pixelu.
    private func render(
        width: CGFloat,
        description: String?,
        facts: PullRequestFacts,
        changes: VisitChanges,
        movedHead: String?,
        hidesContent: Bool = false
    ) throws -> NSBitmapImageRep {
        let scene = ZStack(alignment: .topLeading) {
            Rectangle().fill(Self.probeBackground)
            if !hidesContent {
                OverviewView(
                    description: description,
                    facts: facts,
                    changes: changes,
                    lastVisit: Date(timeIntervalSince1970: 1_754_000_000),
                    movedHead: movedHead,
                    pullRequest: Self.pullRequest
                )
                .content
                .availableWidth(width)
                .frame(width: width, alignment: .topLeading)
            }
        }
        .frame(width: width + margin, height: Self.canvasHeight, alignment: .topLeading)

        let renderer = ImageRenderer(content: scene)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        return try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
    }

    /// Nejvzdálenější sloupec, ve kterém se obsah liší od čistého podkladu, měřeno od hrany tabu.
    /// Vrací počet bodů přesahu, ať se z červeného testu pozná, **o kolik** to přeteklo.
    ///
    /// Porovnává se **proti druhému renderu**, ne proti zapsané hodnotě purpurové: bitmapa z
    /// `ImageRenderer`u je v systémovém barevném prostoru, takže literál `1,0,1` v ní přesně
    /// nesedí — a test by pak hlásil přetečení přes celé plátno i tam, kde se nic nenakreslilo.
    /// První verze sondy na tom stála a vypadalo to jako chyba v aplikaci.
    ///
    /// **Čtou se surové bajty, ne `NSColor` na pixel** (nález Copilota). `colorAt(x:y:)`
    /// s `usingColorSpace(.sRGB)` vyrobí na každý bod dva objekty, a plocha k prohledání je
    /// `přesah × výška` u každého případu a každé šířky — celkem ~5,4 milionu bodů, tedy ~21 milionů
    /// `NSColor`ů. Změřeno: **13,2 s → 2,5 s** za celou suitu; převod barevného prostoru přitom
    /// nebyl na nic potřeba, protože oba rendery jdou stejnou cestou a porovnávají se navzájem.
    private func rightmostPaintedColumn(
        of image: NSBitmapImageRep,
        against empty: NSBitmapImageRep,
        beyond width: CGFloat
    ) throws -> Int {
        let start = Int(width.rounded())
        // **Nesedící plátna se ohlásí, nevrátí nulu.** Nula by znamenala „nic nepřeteklo“, takže
        // by rozbitá sonda vyšla jako zelený test — a to je ten nejhorší možný způsob, jak se
        // tenhle test může pokazit: přestane měřit a nikdo se to nedozví. Platí to i o rozvržení
        // bajtů: bez shody v něm by se porovnávaly různé pixely.
        try #require(image.pixelsWide == empty.pixelsWide, "plátna se rozešla v šířce")
        try #require(image.pixelsHigh == empty.pixelsHigh, "plátna se rozešla ve výšce")
        try #require(image.bytesPerRow == empty.bytesPerRow, "plátna se rozešla v délce řádku")
        try #require(image.bitsPerPixel == empty.bitsPerPixel, "plátna se rozešla v bitech na pixel")
        try #require(!image.isPlanar && !empty.isPlanar, "planární bitmapa má jiné rozvržení bajtů")
        try #require(image.pixelsWide > start, "plátno není širší než tab, přesah se nemá kam vejít")

        let bytesPerPixel = image.bitsPerPixel / 8
        try #require(bytesPerPixel > 0, "bitmapa hlásí nulovou velikost pixelu")
        let painted = try #require(image.bitmapData, "z renderu obsahu se nedají čít bajty")
        let background = try #require(empty.bitmapData, "z renderu podkladu se nedají čít bajty")

        for x in stride(from: image.pixelsWide - 1, through: start, by: -1) {
            for y in 0..<image.pixelsHigh {
                let offset = y * image.bytesPerRow + x * bytesPerPixel
                for byte in 0..<bytesPerPixel
                where abs(Int(painted[offset + byte]) - Int(background[offset + byte])) > Self.tolerance {
                    return x - start + 1
                }
            }
        }
        return 0
    }

    /// O kolik se smí bajt lišit, než se to počítá za nakreslené. Pět z 255 je kvůli antialiasingu
    /// na hraně tabu; odpovídá to 0,02 v podílu, na kterém sonda stála, dokud četla `NSColor`.
    private static let tolerance = 5

    /// Snímek do scratchpadu, když si o to sonda řekne (`PRISM_RENDER_DIR`). Kouká se na to okem:
    /// z počtu bodů se nepozná, **co** přeteklo.
    private func dump(_ image: NSBitmapImageRep, as name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] else { return }
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try #require(image.representation(using: .png, properties: [:])).write(to: url)
    }

    private static let probeBackground = Color(.sRGB, red: 1, green: 0, blue: 1, opacity: 1)

    /// Plátno musí být vyšší než nejdelší popis, jinak by se dolní část neměla kam nakreslit
    /// a přesah v ní by se nezměřil.
    private static let canvasHeight: CGFloat = 1400

    private static let pullRequest = PullRequestSummary(
        id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013),
        title: "Route autolink requests through api.Client",
        author: "williammartin",
        url: URL(string: "https://github.com/cli/cli/pull/14013")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .open
    )

    /// Popis, ve kterém je od každého bloku aspoň jeden — nadpisy, próza, seznam, citace, výstraha
    /// i blok kódu. `filling()` je v každém z nich zvlášť, takže jeden odstavec by změřil jeden.
    private static let description = """
        ## Popis

        Odstavec s **tučným**, `inline kódem` a [odkazem](https://github.com), dost dlouhý na to,
        aby se v úzkém tabu zalomil na několik řádků a nešel vyřešit zkrácením.

        - první odrážka
        - [x] hotová položka
          - zanořená položka, taky dost dlouhá na zalomení v úzkém tabu

        1. číslovaná
        2. a druhá

        > citace od kolegy
        > ## nadpis v citaci

        > [!NOTE]
        > Poznámka od bota, opět dost dlouhá na to, aby se v úzkém tabu zalomila.

        ```swift
        let x = 1
        ```
        """

    private static let facts = PullRequestFacts(
        tiles: [
            .init(caption: "Commity", value: "12", note: "3 nové"),
            .init(caption: "Soubory", value: "8", note: "2 s nálezem"),
            .init(caption: "Hlava", value: "abc1234", isMonospaced: true),
            .init(caption: "Nálezy proti", value: "def5678", isMonospaced: true, isStale: true),
        ]
    )

    /// Banner „od minule“ potřebuje aspoň jednu položku, aby se vůbec nakreslil. Force push je na to
    /// nejhustší řádek — nese i větu o tom, která sha na větvi už není.
    private static let changes = VisitChanges(
        commits: [],
        forcePushes: [
            TimelineEvent(
                id: "1",
                kind: .forcePushed(before: "4f2ac9188cd", after: "9c1de0212ab"),
                actor: EventActor(login: "odinuv", avatarURL: nil, isBot: false),
                at: Date(timeIntervalSince1970: 1_753_900_000)
            )
        ],
        events: [],
        reviews: [],
        comments: []
    )
}
