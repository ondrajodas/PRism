#!/usr/bin/env swift

// Vykreslí ikonu aplikace do `App/Assets.xcassets/AppIcon.appiconset/`.
//
//     swift bin/make-icon.swift                     # nasazená varianta
//     swift bin/make-icon.swift split               # původní barvy Claude
//     swift bin/make-icon.swift split /tmp/náhled   # jen vykreslit, do zadané složky
//
// **Motiv:** znaky obou nástrojů rozpůlené diagonálou zleva zdola doprava nahoru — vlevo
// nahoře Claude, vpravo dole GitHub. Ikona tím říká, co ta aplikace je: GitHub jako zdroj
// pull requestů a Claude jako to, co je čte.
//
// **Dvě barevné varianty, obě v repu.** Nasazená je `split-inverted` (krémový znak na
// oranžové), protože je výrazně bolder a oranžové pole se pozná i v malé velikosti;
// `split` je Claude v původních barvách (oranžový znak na krémové). Druhá zůstává schválně:
// ikona se posuzuje očima, ne v zadání, takže musí být z čeho vybrat a k čemu se vrátit.
//
// **Zdroj je kód a dvě oficiální SVG v `bin/icon-sources/`**, ne hotová binárka: jde z něj
// ikonu vyrobit znovu, změnit řez nebo barvy, a nepotřebuje k tomu externí závislost —
// repozitář zatím žádnou nemá a kvůli ikoně za to nemá cenu platit. Značky se navíc
// nekreslí zpaměti.
//
// **Malé velikosti nejsou zmenšená velká.** Pod 64 px se kreslí hruběji (znaky větší proti
// plátnu, širší spára, žádný obrys) — jinak z ikony ve 16 bodech vyjde šmouha, a to je
// právě velikost, ve které skončí v přepínači aplikací.

import AppKit
import SwiftUI

// MARK: - SVG cesta

/// Minimální překlad SVG `d` na `Path`.
///
/// Umí `M`, `L`, `H`, `V`, `C`, `Z` v **absolutní** podobě — víc obě značky nepotřebují
/// (ověřeno grepem nad oběma soubory). Relativní varianty schválně nejsou: co se nepoužívá,
/// se nedá otestovat, a mlčky špatně vykreslená značka je horší než chyba při načtení.
private enum SVGPath {
    static func parse(_ d: String, viewBox: CGFloat, into rect: CGRect) -> Path {
        let scale = rect.width / viewBox
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()
        var current = CGPoint.zero
        for (command, numbers) in tokenize(d) {
            var index = 0
            func next() -> CGFloat {
                defer { index += 1 }
                return index < numbers.count ? numbers[index] : 0
            }
            // SVG dovoluje za jedním příkazem víc sad souřadnic. `Z` žádnou nemá, takže by
            // na prázdném seznamu `while` nikdy neskončilo — proto `repeat`.
            repeat {
                switch command {
                case "M":
                    current = CGPoint(x: next(), y: next())
                    path.move(to: point(current.x, current.y))
                case "L":
                    current = CGPoint(x: next(), y: next())
                    path.addLine(to: point(current.x, current.y))
                case "H":
                    current.x = next()
                    path.addLine(to: point(current.x, current.y))
                case "V":
                    current.y = next()
                    path.addLine(to: point(current.x, current.y))
                case "C":
                    let control1 = CGPoint(x: next(), y: next())
                    let control2 = CGPoint(x: next(), y: next())
                    current = CGPoint(x: next(), y: next())
                    path.addCurve(
                        to: point(current.x, current.y),
                        control1: point(control1.x, control1.y),
                        control2: point(control2.x, control2.y)
                    )
                case "Z":
                    path.closeSubpath()
                default:
                    print("neznámý příkaz SVG cesty: \(command)")
                    exit(1)
                }
            } while index < numbers.count
        }
        return path
    }

    /// Rozseká `d` na příkazy a jejich čísla.
    private static func tokenize(_ d: String) -> [(Character, [CGFloat])] {
        var result: [(Character, [CGFloat])] = []
        var command: Character?
        var numbers: [CGFloat] = []
        var literal = ""

        func flushNumber() {
            defer { literal = "" }
            guard !literal.isEmpty, let value = Double(literal) else { return }
            numbers.append(CGFloat(value))
        }

        for character in d {
            if character.isLetter {
                flushNumber()
                if let command { result.append((command, numbers)) }
                command = character
                numbers = []
            } else if character == "-" {
                // Minus je i oddělovač: `10-5` jsou dvě čísla.
                flushNumber()
                literal = "-"
            } else if character == "," || character.isWhitespace {
                flushNumber()
            } else {
                literal.append(character)
            }
        }
        flushNumber()
        if let command { result.append((command, numbers)) }
        return result
    }

    /// Načte jedinou cestu ze souboru a řekne, jak velký má viewBox.
    static func load(_ url: URL) -> Mark {
        guard let svg = try? String(contentsOf: url, encoding: .utf8) else {
            print("nešlo přečíst \(url.lastPathComponent)")
            exit(1)
        }
        guard let d = between(svg, #" d=""#, #"""#) else {
            print("v \(url.lastPathComponent) není cesta")
            exit(1)
        }
        guard let box = between(svg, #"viewBox="0 0 "#, " "), let side = Double(box) else {
            print("v \(url.lastPathComponent) není čtvercový viewBox")
            exit(1)
        }
        return Mark(d: d, viewBox: CGFloat(side))
    }

    private static func between(_ text: String, _ open: String, _ close: String) -> String? {
        guard let start = text.range(of: open) else { return nil }
        let rest = text[start.upperBound...]
        guard let end = rest.range(of: close) else { return nil }
        return String(rest[..<end.lowerBound])
    }
}

/// Značka načtená ze SVG.
private struct Mark {
    let d: String
    let viewBox: CGFloat
}

// MARK: - Geometrie a barvy

/// Mřížka ikony macOS: na plátně 1024 je tělo 824 × 824 se zaoblením 185,4.
///
/// Okraj **kreslíme sami**, nespoléháme na to, že systém obrázek zamaskuje: ikona se na
/// macOS vykresluje tak, jak je, a zaoblený čtverec s okrajem je tvar, který se od ní čeká.
private enum Grid {
    static let canvas: CGFloat = 1024
    static let plate: CGFloat = 824
    static let corner: CGFloat = 185.4

    static func scaled(_ value: CGFloat, to size: CGFloat) -> CGFloat {
        value / canvas * size
    }

    /// Zaoblený čtverec ikony v souřadnicích plátna.
    static func plateRect(in size: CGFloat) -> CGRect {
        let side = scaled(plate, to: size)
        return CGRect(x: (size - side) / 2, y: (size - side) / 2, width: side, height: side)
    }

    static func plateShape(in size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: scaled(corner, to: size), style: .continuous)
    }
}

/// Barvy `split` jsou z **oficiálních** značek, ne odhadnuté: `#D97757` má Claude ve své
/// faviconě, `#24292E` GitHub ve své a `#F5EDDE` je krémová z ikony aplikace Claude. Krémová
/// se používá v **obou** polovinách (podklad vlevo, znak vpravo), takže ikona drží pohromadě
/// i po přeříznutí.
private enum Palette {
    static let cream = Color(red: 0.961, green: 0.929, blue: 0.871)
    static let claude = Color(red: 0.851, green: 0.467, blue: 0.341)
    static let github = Color(red: 0.141, green: 0.161, blue: 0.180)
}

// MARK: - Motiv: rozpůlené znaky

private struct SplitIcon: View {
    /// Hrana plátna v pixelech. Rozhoduje i o tom, jak hrubě se kreslí.
    let size: CGFloat
    let claude: Mark
    let github: Mark
    /// Claude má i **obrácenou** barevnou variantu: krémový znak na oranžové místo
    /// oranžového na krémové. Krémová pak nese znak v obou polovinách a barevné jsou
    /// podklady — což je bolder a v malých velikostech čitelnější.
    let inverted: Bool

    private var isSmall: Bool { size < 64 }
    private var plateRect: CGRect { Grid.plateRect(in: size) }

    /// Znak zabírá v malé velikosti víc místa — jinak z něj nezbude nic.
    ///
    /// Každý je navíc **posunutý do svého rohu** (`shift`), ne vystředěný na plátno. Řez mu
    /// tak ubere jen kus místo poloviny: vystředěná kočka se rozřízne přes hlavu a čte se
    /// pak jako abstraktní srpek. Ověřeno vykreslením obou variant.
    private func markRect(topLeft: Bool) -> CGRect {
        let side = plateRect.width * (isSmall ? 0.74 : 0.62)
        let shift = plateRect.width * 0.13
        return CGRect(
            x: plateRect.midX - side / 2 + (topLeft ? -shift : shift),
            y: plateRect.midY - side / 2 + (topLeft ? -shift : shift),
            width: side,
            height: side
        )
    }

    var body: some View {
        ZStack {
            half(topLeft: true, background: inverted ? Palette.claude : Palette.cream) {
                SVGPath.parse(claude.d, viewBox: claude.viewBox, into: markRect(topLeft: true))
                    .fill(inverted ? Palette.cream : Palette.claude)
            }
            half(topLeft: false, background: Palette.github) {
                SVGPath.parse(github.d, viewBox: github.viewBox, into: markRect(topLeft: false))
                    // GitHub má v cestě `fill-rule="evenodd"`; bez toho se vyplní i díry
                    // a z kočky vyjde placka.
                    .fill(Palette.cream, style: FillStyle(eoFill: true))
            }
            // Spára podél řezu. Bez ní se paprsky Claude a hlava kočky potkají hranou na
            // hranu a slijí se v jednu šmouhu — nejvíc v malých velikostech, kde jsou od
            // sebe dva pixely.
            seam

            // Obrys drží tvar i na světlém pozadí Docku. V malé velikosti se vynechá — na
            // třinácti pixelech by sežral půlku znaku.
            if !isSmall {
                Grid.plateShape(in: size)
                    .stroke(Color.black.opacity(0.18), lineWidth: Grid.scaled(6, to: size))
                    .frame(width: plateRect.width, height: plateRect.height)
            }
        }
        .frame(width: size, height: size)
    }

    /// Jedna polovina ikony: podklad a znak, oříznuté diagonálou.
    ///
    /// Řez jde **zleva zdola doprava nahoru** a oba znaky jsou vystředěné na stejné plátno,
    /// takže se v ose potkají — nejsou to dvě malá loga vedle sebe, je to jedno rozříznuté.
    private func half<Content: View>(
        topLeft: Bool,
        background: Color,
        @ViewBuilder mark: () -> Content
    ) -> some View {
        ZStack {
            background
            mark()
        }
        .frame(width: size, height: size)
        .clipShape(diagonal(topLeft: topLeft))
        .clipShape(Grid.plateShape(in: size).path(in: plateRect))
    }

    private var seam: some View {
        Path { path in
            path.move(to: CGPoint(x: plateRect.minX, y: plateRect.maxY))
            path.addLine(to: CGPoint(x: plateRect.maxX, y: plateRect.minY))
        }
        // Barvou, která v té variantě nese znaky — u obrácené je to krémová na obou
        // stranách, u původní podklad levé poloviny.
        .stroke(Palette.cream, lineWidth: plateRect.width * (isSmall ? 0.055 : 0.03))
        .clipShape(Grid.plateShape(in: size).path(in: plateRect))
    }

    private func diagonal(topLeft: Bool) -> Path {
        var path = Path()
        let rect = plateRect
        if topLeft {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Zápis

/// Velikosti, které macOS chce: bod a jeho `@1x`/`@2x`.
private let slots: [(point: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

private let root = URL(filePath: FileManager.default.currentDirectoryPath)

/// Značky se načtou **jednou**, ne u každé velikosti: jsou to deset průchodů nad týmž
/// souborem a týmž parserem.
private let marks = (
    claude: SVGPath.load(root.appending(path: "bin/icon-sources/claude-mark.svg")),
    github: SVGPath.load(root.appending(path: "bin/icon-sources/github-mark.svg"))
)

@MainActor
private func png(inverted: Bool, at pixels: CGFloat) -> Data? {
    let renderer = ImageRenderer(
        content: SplitIcon(
            size: pixels,
            claude: marks.claude,
            github: marks.github,
            inverted: inverted
        )
    )
    // Kreslí se rovnou v cílovém počtu pixelů, ne zvětšením — `scale` by z 16 px udělalo
    // zmenšenou velkou ikonu a hrubší kresba malých velikostí by neměla smysl.
    renderer.scale = 1
    guard let image = renderer.cgImage else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

private func contentsJSON() -> Data {
    let images = slots.map { slot in
        """
            {
              "filename" : "icon-\(slot.point)x\(slot.point)@\(slot.scale)x.png",
              "idiom" : "mac",
              "scale" : "\(slot.scale)x",
              "size" : "\(slot.point)x\(slot.point)"
            }
        """
    }
    return Data(
        """
        {
          "images" : [
        \(images.joined(separator: ",\n"))
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }

        """.utf8
    )
}

MainActor.assumeIsolated {
    // Výchozí je ta **nasazená**, ať `swift bin/make-icon.swift` bez argumentu nepřepíše
    // ikonu druhou variantou.
    let variant = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "split-inverted"
    // Varianta se ověří **jednou**, před smyčkou: uvnitř by se ta kontrola opakovala u každé
    // z deseti velikostí.
    guard variant == "split" || variant == "split-inverted" else {
        print("variantu \(variant) neznám — čekám `split` nebo `split-inverted`")
        exit(1)
    }
    // Druhý argument = jen vykreslit do složky, bez zásahu do asset catalogu. Na porovnání
    // variant, ať se v repu nestřídají soubory, které se stejně zahodí.
    let preview = CommandLine.arguments.count > 2 ? URL(filePath: CommandLine.arguments[2]) : nil
    let iconSet = preview ?? root.appending(path: "App/Assets.xcassets/AppIcon.appiconset")
    try? FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

    for slot in slots {
        let pixels = CGFloat(slot.point * slot.scale)
        guard let data = png(inverted: variant == "split-inverted", at: pixels) else {
            print("ikonu \(Int(pixels)) px se nepodařilo vykreslit")
            exit(1)
        }
        let name = "icon-\(slot.point)x\(slot.point)@\(slot.scale)x.png"
        do {
            try data.write(to: iconSet.appending(path: name))
            print("\(name)  \(Int(pixels)) px  \(data.count) B")
        } catch {
            print("zápis \(name) selhal: \(error)")
            exit(1)
        }
    }

    guard preview == nil else { exit(0) }
    do {
        try contentsJSON().write(to: iconSet.appending(path: "Contents.json"))
        try Data(#"{"info":{"author":"xcode","version":1}}"#.utf8)
            .write(to: root.appending(path: "App/Assets.xcassets/Contents.json"))
    } catch {
        print("zápis Contents.json selhal: \(error)")
        exit(1)
    }
}
