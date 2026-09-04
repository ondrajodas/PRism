import AppKit
import Foundation
import Testing

@testable import PRism

/// Že odznak na dlaždici **doopravdy je nakreslený** (#529).
///
/// **Tuhle sadu si vynutila vada, kterou celé #529 v prvním kole minulo.** Odznak se tehdy
/// nasazoval přes `NSApp.dockTile.badgeLabel`, což je zápis jedné hodnoty — a tvrdit se o něm
/// dalo jedině to, že se nasadil (`FakeDockTile`) a že na dlaždici nesahá nikdo jiný (stráž nad
/// zdrojáky). Obojí bylo zelené a v Docku nebylo nic: `badgeLabel` je pod přepínačem `Odznaky`
/// v Oznámeních a u aplikace, která si o `.badge` neřekla, ho Dock **potichu zahodí**. To je
/// přesně měřidlo z #478 — vydá tutéž hodnotu pro „funguje“ i „nefunguje“.
///
/// Odznak se proto od té opravy kreslí sám (`DockBadgeTileView`) a **kresba se dá porovnat**.
/// Tvrzení jsou čtyři a každé chytá jinou třídu: že se odznak **objeví** (jinak je dlaždice jen
/// ikona), že se **bez čísla neobjeví**, že na něm stojí **to číslo** (jinak by stačil puntík)
/// a že **víc číslic odznak roztáhne, a když už nemůže, číslo se zmenší** (jinak by v Docku stálo
/// jiné číslo, než kolik jich čeká).
///
/// **Ikona se do view předává**, ne bere z `NSApp` — jinak by bitmapa závisela na ikoně hostitele
/// testů, tedy na tom, co si zrovna nainstaloval Xcode. Je to tentýž důvod, proč se v testech
/// nesahá na globální stav procesu (#367 a pět dalších podob).
@MainActor
@Suite("Odznak na dlaždici v Docku je nakreslený (#529)")
struct DockBadgeTileRenderTests {
    /// Dlaždice v Docku má podle nastavení systému 32 až 128 bodů; 128 je ta velikost, ve které
    /// jde z bitmapy něco poznat, a poměry v `Policy.dockBadgeLayout` jsou na rozměru nezávislé.
    private static let side: CGFloat = 128

    /// Ikona pod odznakem. **Plná plocha jedné barvy**, ne skutečná ikona aplikace: rozhoduje se
    /// nad rozdílem bitmap, takže potřebuju vědět, že všechno, co se od plochy liší, nakreslil
    /// odznak. A **ne bílá ani červená** — na bílé by nebyl vidět bílý text a na červené výplň.
    private func icon() -> NSImage {
        let image = NSImage(size: NSSize(width: Self.side, height: Self.side))
        image.lockFocus()
        NSColor(srgbRed: 0.11, green: 0.12, blue: 0.18, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: Self.side, height: Self.side).fill()
        image.unlockFocus()
        return image
    }

    private func bitmap(label: String?) throws -> NSBitmapImageRep {
        let view = DockBadgeTileView(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        view.icon = icon()
        view.label = label
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func png(label: String?) throws -> Data {
        try #require(try bitmap(label: label).representation(using: .png, properties: [:]))
    }

    /// Kolik pixelů na bitmapě je systémová červená odznaku. **Na tomhle čísle stojí celá sada**:
    /// nula znamená, že se odznak nenakreslil, ať už proto, že ho kresba vynechala, nebo proto,
    /// že ho někdo posunul mimo dlaždici.
    private func redPixels(label: String?) throws -> Int {
        let rep = try bitmap(label: label)
        var count = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                // Široké okno kolem `#FF3B30`: hrany pilulky jsou vyhlazené, takže přesná shoda
                // by počítala jen vnitřek — a ten by se dal splést s jakoukoli červenou plochou.
                if color.redComponent > 0.75, color.greenComponent < 0.45, color.blueComponent < 0.42 {
                    count += 1
                }
            }
        }
        return count
    }

    /// **Nejcennější tvrzení téhle sady**: dlaždice s odznakem se od dlaždice bez něj liší, a liší
    /// se **systémovou červenou**. Tohle padne přesně na té vadě, kterou #529 v prvním kole
    /// minulo — na odznaku, o kterém se dá tvrdit, že se „nasadil“, a přitom není vidět.
    @Test("Odznak s číslem je na dlaždici vidět")
    func drawsTheBadge() throws {
        let empty = try redPixels(label: nil)
        let badged = try redPixels(label: "6")

        #expect(empty == 0, "prázdná dlaždice má na sobě červenou, takže tvrzení níž nic neznamená")
        #expect(badged > 0, "odznak se nenakreslil")
    }

    /// **Prázdná dlaždice je ikona, nic víc.** `Policy.dockBadge` vrací `nil` u prázdné fronty,
    /// u nenačtené i u volby `nic` — a všechny tři mají v Docku vypadat stejně jako aplikace, na
    /// kterou nikdo nečeká.
    @Test("Bez čísla je dlaždice k nerozeznání od ikony")
    func drawsNothingWithoutALabel() throws {
        let plain = NSImage(size: NSSize(width: Self.side, height: Self.side))
        plain.lockFocus()
        NSColor(srgbRed: 0.11, green: 0.12, blue: 0.18, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: Self.side, height: Self.side).fill()
        plain.unlockFocus()

        // Prázdný řetězec se chová jako `nil` — odznak bez číslice netvrdí nic, a `badgeLabel = ""`
        // kreslil prázdný puntík. Že se sem prázdný řetězec z `Policy` nedostane, na věci nic
        // nemění: kresba je poslední místo, kde se to dá vyloučit.
        #expect(try png(label: nil) == png(label: ""))
        #expect(try redPixels(label: "") == 0)
    }

    /// **Na odznaku stojí to číslo, ne jen puntík.** Bez tohohle by prošla i kresba, která vždycky
    /// nakreslí červené kolečko — a odznak bez číslice říká „něco čeká“, kdežto celé zadání #529
    /// je „tolik jich čeká“.
    @Test("Jiné číslo je jiná kresba")
    func drawsTheNumberItself() throws {
        #expect(try png(label: "6") != png(label: "9"))
        #expect(try png(label: "1") != png(label: "7"))
    }

    /// **Dvojciferný počet odznak roztáhne**, místo aby z něj číslo vylezlo. Šest PR ve frontě je
    /// běžný stav, dvanáct taky — a ořezané číslo v Docku by lhalo o tom, kolik jich čeká.
    @Test("Víc číslic odznak roztáhne")
    func widensForMoreDigits() throws {
        let one = try redPixels(label: "6")
        let two = try redPixels(label: "12")
        let three = try redPixels(label: "123")

        #expect(two > one)
        #expect(three > two)
    }

    /// **Číslo se do odznaku vejde i tehdy, když pilulka narazí na strop.** Šířka pilulky je
    /// zastropovaná plochou dlaždice, takže od pěti znaků výš už neroste — a text se do ní musí
    /// **zmenšit**, ne z ní vylézt. Že odznak sám v dlaždici zůstává, tvrdí `DockBadgeTests` nad
    /// `Policy`; tady jde o to, co z toho vyleze v kresbě.
    @Test("Číslo, které se nevejde, se zmenší")
    func shrinksTheNumberToFit() throws {
        // **Sedm číslic, ne pět, a je to spočítané**: pilulka narazí na strop u pěti znaků, ale
        // text se do ní v původní velikosti pořád vejde (pět číslic je v tom písmu ~83 b, místa je
        // 108). Přeteče až u sedmi — a test nad pěti znaky by tedy prošel, i kdyby se nezmenšovalo
        // vůbec. Ověřeno vložením regrese: bez zmenšení tenhle test hlásí 76 bílých pixelů venku.
        let label = "1234567"
        let rep = try bitmap(label: label)
        let layout = Policy.dockBadgeLayout(
            characters: label.count,
            in: CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        )
        // **Bitmapa je v pixelech, `pill` v bodech, a na retina backingu to není totéž** — bez
        // převodu vyšlo 3218 „přetečených“ pixelů nad kresbou, která nikam nepřetéká. Podíl se
        // proto bere z bitmapy, ne z konstanty.
        let scale = CGFloat(rep.pixelsWide) / Self.side
        var strayWhite = 0

        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                // `colorAt` počítá `y` odshora, kdežto `pill` je v neobrácených souřadnicích view
                // — proto se převádí, ne porovnává přímo.
                let point = CGPoint(
                    x: CGFloat(x) / scale,
                    y: CGFloat(rep.pixelsHigh - 1 - y) / scale
                )
                guard !layout.pill.insetBy(dx: -1, dy: -1).contains(point) else { continue }
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.redComponent > 0.8, color.greenComponent > 0.8, color.blueComponent > 0.8 {
                    strayWhite += 1
                }
            }
        }

        #expect(strayWhite == 0, "číslo přeteklo mimo odznak (\(strayWhite) bílých pixelů)")
    }
}
