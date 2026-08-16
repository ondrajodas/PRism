import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Měření nad vyrendrovaným tabem — **jedno místo** pro `Přehled` (#291), taby bez panelu (#294)
/// i pořadí prvků v `Přehledu` (#280).
///
/// Odpovídá na dvě otázky nad **týmž plátnem**: „přeteklo něco vpravo za hranu tabu“
/// (`overflow(of:)`) a „kde v tomhle sloupci obsah začíná“ (`firstPaintedRow(of:atColumn:)`).
/// Držet je pohromadě je záměr — plátno, podklad i tolerance toho, co se počítá za nakreslené,
/// mají být jedny. Dvě sondy nad stejnou scénou znamenají dvě měřítka, která se rozejdou potichu.
///
/// **Měří se pixely, ne rámečky.** `frame(width:)` z `filling()` je tvrdý rámec: dítě, které se do
/// něj nevejde, přeteče **vizuálně**, aniž by se rodičova velikost změnila. Ptát se rodiče na
/// `fittingSize` proto na tuhle chybu nestačí; ptá se toho, kdo o ní neví. Přetečení se dá spočítat
/// jedině tak, že se obsah nakreslí na plátno **širší** než tab a v tom přesahu se hledají pixely.
///
/// **Obsah musí přijít bez `ScrollView`u** (`content`, ne `body`): `NSScrollView` obsah na svou
/// šířku ukrojí, takže by se přetečení nekreslilo a rozbitý stav by od opraveného nešlo poznat —
/// přesně to dělá tuhle třídu regresí v aplikaci tak nenápadnou.
///
/// **Šířka se předává tak, jak ji předává okno**: `availableWidth` z prostředí (#220) plus rámec
/// téže šířky, tedy totéž, co dělá `GeometryReader` v `PullRequestDetailView`. Kdyby si to každá
/// sonda skládala sama, měřila by každá jiný tab.
@MainActor
struct OverflowProbe {
    /// Šířka tabu, na které se měří.
    let width: CGFloat
    /// Kolik se vpravo nechá volného místa na to, aby se přesah měl kam nakreslit. Přesah z #291
    /// dělal 42 bodů (13 + 13 odsazení karty a 16 na pravé straně tabu), takže 120 je s rezervou.
    var margin: CGFloat = 120
    /// Plátno musí být vyšší než nejdelší obsah, jinak by se dolní část neměla kam nakreslit
    /// a přesah v ní by se nezměřil.
    var height: CGFloat = 1400
    /// Jméno snímku do scratchpadu, když si o to sonda řekne (`PRISM_RENDER_DIR`). Kouká se na to
    /// okem: z počtu bodů se nepozná, **co** přeteklo.
    var name: String?

    /// Kolik bodů se nakreslilo vpravo za hranou tabu. Nula = nic nepřeteklo.
    func overflow(of content: some View) throws -> Int {
        let (painted, empty) = try canvases(of: content)
        return try rightmostPaintedColumn(of: painted, against: empty)
    }

    /// Nejvyšší řádek, ve kterém se v zadaných **sloupcích** obsah liší od čistého podkladu —
    /// v tomtéž pořadí, v jakém sloupce přišly. `-1` = v tom sloupci se nenakreslilo nic.
    ///
    /// Je to druhá otázka nad tímtéž plátnem (#280): ne „přeteklo to vpravo“, ale „co je výš“.
    /// Sedí tady, aby plátno, podklad a tolerance zůstaly na jednom místě — dvě sondy nad stejnou
    /// scénou by znamenaly dvě různá měřítka toho, co se počítá za nakreslené.
    ///
    /// **Svislý pruh je ta rozlišovací pomůcka.** Prvky přes celou šířku (karta, banner) kreslí
    /// v každém sloupci, kdežto mřížka dlaždic nechává mezi nimi mezeru nedotčenou — z porovnání
    /// dvou sloupců se tedy pozná pořadí, aniž by se sahalo do hierarchie.
    ///
    /// **Bere sloupce najednou, ne po jednom, a je to podstatné**: jeden dotaz znamená dva rendery
    /// (obsah a podklad), takže ptát se dvakrát na totéž plátno je čtyřnásobek práce za tutéž
    /// odpověď — u osmi šířek to bylo měřitelné, 5,8 s proti 2,9 s.
    func firstPaintedRows(of content: some View, atColumns columns: [CGFloat]) throws -> [Int] {
        let (painted, empty) = try canvases(of: content)
        return try columns.map {
            try firstPaintedRow(of: painted, against: empty, atColumn: $0)
        }
    }

    /// Obsah a čistý podklad na jednom plátně — a ověřené, že se dají porovnávat bajt po bajtu.
    private func canvases(of content: some View) throws -> (NSBitmapImageRep, NSBitmapImageRep) {
        let painted = try render(scene(of: content))
        let empty = try render(scene(of: EmptyView()))
        if let name { try dump(painted, as: name) }
        try requireComparable(painted, empty)
        return (painted, empty)
    }

    /// **Nesedící plátna se ohlásí, nevrátí nulu.** Nula by znamenala „nic nepřeteklo“, takže by
    /// rozbitá sonda vyšla jako zelený test — a to je ten nejhorší možný způsob, jak se tahle
    /// třída může pokazit: přestane měřit a nikdo se to nedozví. Platí to i o rozvržení bajtů:
    /// bez shody v něm by se porovnávaly různé pixely.
    private func requireComparable(_ image: NSBitmapImageRep, _ empty: NSBitmapImageRep) throws {
        try #require(image.pixelsWide == empty.pixelsWide, "plátna se rozešla v šířce")
        try #require(image.pixelsHigh == empty.pixelsHigh, "plátna se rozešla ve výšce")
        try #require(image.bytesPerRow == empty.bytesPerRow, "plátna se rozešla v délce řádku")
        try #require(image.bitsPerPixel == empty.bitsPerPixel, "plátna se rozešla v bitech na pixel")
        try #require(!image.isPlanar && !empty.isPlanar, "planární bitmapa má jiné rozvržení bajtů")
    }

    /// Obsah na plátně širším než tab, na purpurovém podkladu.
    private func scene(of content: some View) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Self.background)
            content
                .availableWidth(width)
                .frame(width: width, alignment: .topLeading)
        }
        .frame(width: width + margin, height: height, alignment: .topLeading)
    }

    private func render(_ scene: some View) throws -> NSBitmapImageRep {
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
    /// **Čtou se surové bajty, ne `NSColor` na pixel** (nález Copilota u #291). `colorAt(x:y:)`
    /// s `usingColorSpace(.sRGB)` vyrobí na každý bod dva objekty, a plocha k prohledání je
    /// `přesah × výška` u každého případu a každé šířky — celkem ~5,4 milionu bodů, tedy ~21 milionů
    /// `NSColor`ů. Změřeno: **13,2 s → 2,5 s** za celou suitu; převod barevného prostoru přitom
    /// nebyl na nic potřeba, protože oba rendery jdou stejnou cestou a porovnávají se navzájem.
    private func rightmostPaintedColumn(
        of image: NSBitmapImageRep,
        against empty: NSBitmapImageRep
    ) throws -> Int {
        let start = Int(width.rounded())
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

    /// Nejvyšší nakreslený řádek v jednom sloupci — svislá obdoba `rightmostPaintedColumn`.
    /// Čte se stejně: surové bajty proti druhému renderu, ne `NSColor` a ne zapsaná barva.
    private func firstPaintedRow(
        of image: NSBitmapImageRep,
        against empty: NSBitmapImageRep,
        atColumn column: CGFloat
    ) throws -> Int {
        let x = Int(column.rounded())
        try #require(x >= 0 && x < image.pixelsWide, "měřený sloupec \(x) je mimo plátno")

        let bytesPerPixel = image.bitsPerPixel / 8
        try #require(bytesPerPixel > 0, "bitmapa hlásí nulovou velikost pixelu")
        let painted = try #require(image.bitmapData, "z renderu obsahu se nedají čít bajty")
        let background = try #require(empty.bitmapData, "z renderu podkladu se nedají čít bajty")

        for y in 0..<image.pixelsHigh {
            let offset = y * image.bytesPerRow + x * bytesPerPixel
            for byte in 0..<bytesPerPixel
            where abs(Int(painted[offset + byte]) - Int(background[offset + byte])) > Self.tolerance {
                return y
            }
        }
        return -1
    }

    /// O kolik se smí bajt lišit, než se to počítá za nakreslené. Pět z 255 je kvůli antialiasingu
    /// na hraně tabu; odpovídá to 0,02 v podílu, na kterém sonda stála, dokud četla `NSColor`.
    private static let tolerance = 5

    private static let background = Color(.sRGB, red: 1, green: 0, blue: 1, opacity: 1)

    private func dump(_ image: NSBitmapImageRep, as name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] else { return }
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try #require(image.representation(using: .png, properties: [:])).write(to: url)
    }
}
