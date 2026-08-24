import AppKit
import Testing

@testable import PRism

/// Trvale viditelný vodorovný pruh v bloku dvojic (#422) — a hlavně **výška, kterou si bere**.
///
/// Je to nová podoba jedné třídy chyby z #236: blok si v `LazyVStack`u říká o výšku sám, a od #422
/// ta výška **závisí na šířce** (na šířce záleží, jestli se pruh kreslí). Kdyby se rezervace
/// spočítala jinde než tam, kde se rozhoduje o pruhu, byly by to dvě pravdy o jedné výšce — a text
/// by přetekl pod pruh, případně by pod blokem zbylo 17 bodů prázdna.
///
/// **Referencí je `NSScrollView` sám**, ne druhý výpočet: testy laid out kontejner a čtou, jestli
/// AppKit scroller doopravdy ukázal a kolik výšky si vzal. A jde se **přes pásmo šířek** — rozejde
/// se to jenom v pásmu, kde nejdelší řádek padne mezi šířku sloupce a šířku dokumentu; u jedné
/// „hezké“ šířky by test prošel.
@Suite("Pruh v bloku dvojic")
@MainActor
struct DiffPairScrollerTests {
    private static let gutter = DiffLineView.contentInset(for: .split)

    private func lines(_ count: Int, chars: Int) -> [DiffLine?] {
        (0..<count).map {
            DiffLine(kind: .context, oldNumber: $0 + 1, newNumber: $0 + 1, text: String(repeating: "x", count: chars))
        }
    }

    /// Kontejner s nasazeným blokem. Rámec se nastavuje **až po** `show`, jako to dělá SwiftUI
    /// (`sizeThatFits`, pak `frame`) — a výška je ta, o kterou si blok sám řekne.
    private func container(left: [DiffLine?], right: [DiffLine?], width: Double) -> DiffPairBlockContainer {
        let container = DiffPairBlockContainer()
        container.show(
            DiffPairBlock(left: left, right: right),
            style: DiffBlockStyle(language: Language(path: "Cart.swift"), colorScheme: .light),
            gutter: Self.gutter
        )
        container.frame = NSRect(x: 0, y: 0, width: width, height: container.height(forWidth: width))
        container.layoutSubtreeIfNeeded()
        return container
    }

    /// Rolovací plochy zleva doprava. **Vyžadují se obě** — kdyby je hledání v podviews přestalo
    /// najít, vycházely by tvrzení o pásu z prázdného pole a sada by procházela nad rozbitým blokem.
    private func scrollers(in container: DiffPairBlockContainer) throws -> [DiffPairScrollView] {
        let found = container.subviews.compactMap { $0 as? DiffPairScrollView }
            .sorted { $0.frame.minX < $1.frame.minX }
        return try #require(found.count == 2 ? found : nil, "plochy dvojice v podviews nejsou dvě, ale \(found.count)")
    }

    /// Vzal si AppKit v téhle ploše pás na scroller? Čte se to **z plochy, ne z našeho výpočtu**:
    /// `contentSize` je to, co zbylo na obsah.
    private func reservedBand(of scroll: DiffPairScrollView) -> Double {
        scroll.frame.height - scroll.contentSize.height
    }

    /// **Tenhle test je celé #422.** Předpověď kontejneru proti tomu, co scroller doopravdy udělal —
    /// přes pásmo šířek a přes několik délek nejdelšího řádku, takže hranice „vejde se / nevejde“
    /// projede sloupcem několikrát.
    ///
    /// `isHidden` u toho **nevypovídá o kreslení**: overlay scroller hlásí totéž a nenakreslí nic
    /// (změřeno u #422). Odsud se tedy pozná jen to, jestli AppKit pruh **považuje** za potřebný;
    /// že se opravdu kreslí a co to stojí, drží `heightCoversTheBand` a `styleStaysLegacy` níž —
    /// obojí přes pás výšky, o který se overlay nehlásí.
    @Test("Pruh se objeví právě tam, kde ho AppKit ukáže")
    func predictionMatchesAppKit() throws {
        for chars in [4, 12, 20, 28, 40, 60] {
            for width in stride(from: 260.0, through: 1_000.0, by: 19.0) {
                let container = container(left: lines(3, chars: chars), right: lines(3, chars: chars), width: width)
                let visible = try scrollers(in: container).contains { $0.horizontalScroller?.isHidden == false }
                #expect(
                    container.showsScroller(forWidth: width) == visible,
                    "šířka \(width), \(chars) znaků: předpověď \(container.showsScroller(forWidth: width)), scroller \(visible)"
                )
            }
        }
    }

    /// Rezervace je **přesně ten pás**, který si plocha vzala, a řádky se do zbytku vejdou. Kdyby
    /// byla menší, zmizel by poslední řádek pod pruhem; kdyby větší, zbylo by pod blokem prázdno.
    @Test("Blok si řekne o výšku i s pásem pruhu")
    func heightCoversTheBand() throws {
        for chars in [4, 20, 60] {
            for width in stride(from: 260.0, through: 1_000.0, by: 19.0) {
                let container = container(left: lines(6, chars: chars), right: lines(6, chars: chars), width: width)
                let rows = try #require(container.lineFrames().last).rect.maxY
                let band = try #require(scrollers(in: container).map { reservedBand(of: $0) }.max())

                #expect(band == container.height(forWidth: width) - rows - 2, "šířka \(width), \(chars) znaků")
                // Řádky končí nad pruhem — jinak je text pod ním a nedá se přečíst.
                #expect(rows <= container.bounds.height - band, "šířka \(width), \(chars) znaků")
                // A pás je buď celý, nebo žádný: 17 bodů na sdělení „tady nic není“ se nekreslí.
                #expect(band == 0 || band == DiffPairScrollView.scrollerHeight, "šířka \(width), \(chars) znaků")
            }
        }
    }

    /// Tentýž blok se stejným obsahem je s pruhem **o 17 bodů vyšší** než bez něj. Číslo je z AppKitu
    /// (`scrollerWidth(for:scrollerStyle:)`), ne zapsané v testu — a `heightCoversTheBand` výš tvrdí,
    /// že se rovná pásu, který si plocha doopravdy vzala.
    @Test("Blok s pruhem je o pás vyšší než tentýž bez pruhu")
    func barCostsExactlyTheBand() throws {
        let container = container(left: lines(6, chars: 40), right: lines(6, chars: 40), width: 400)
        let narrow = container.height(forWidth: 400)
        let wide = container.height(forWidth: 2_000)

        #expect(container.showsScroller(forWidth: 400))
        #expect(!container.showsScroller(forWidth: 2_000))
        #expect(narrow - wide == DiffPairScrollView.scrollerHeight)
    }

    /// Konec nejdelšího řádku musí být **dosažitelný** — dokument sloupce nesmí být užší než to, kam
    /// text sahá.
    ///
    /// Do #422 to neplatilo a bylo to horší než neviditelný pruh: `sizeToFit()` vrací nulovou šířku
    /// (`maxSize` je `(0, 0)`), takže dokument byl vždycky přesně tak široký jako plocha — **nebylo
    /// co rolovat** a autohide pruh schoval i nad přetékajícím kódem. Ověřeno vloženou regresí:
    /// s `sizeToFit()` zpátky padne tenhle test na každé šířce, kde se kód nevejde (182 tvrzení).
    ///
    /// **Nejdelší řádek je poslední** a hledá se maximum přes všechny: šířka se čte z `usedRect`,
    /// a ten je pravdivý jedině tehdy, když je vysázený celý blok. Změřeno, že je
    /// (`allowsNonContiguousLayout` je u těchhle sloupců `false`) — ale je to vlastnost layout
    /// manageru, ne naše, takže se tvrdí, ne předpokládá.
    @Test("Na konec dlouhého řádku se dá dorolovat")
    func theEndOfTheLongestLineIsReachable() throws {
        for chars in [20, 60, 200] {
            let rows: [DiffLine?] = lines(3, chars: 8) + lines(1, chars: chars)
            for width in stride(from: 260.0, through: 1_000.0, by: 19.0) {
                let container = container(left: rows, right: rows, width: width)
                for scroll in try scrollers(in: container) {
                    let column = try #require(scroll.documentView as? DiffTextView)
                    let drawn = try (0..<rows.count).map { try #require(column.frame(ofLine: $0)).maxX }
                    let text = try #require(drawn.max())
                    #expect(column.frame.width >= text, "šířka \(width), \(chars) znaků")
                }
            }
        }
    }

    /// **Styl se drží legacy, ať ho někdo přiřadí jakkoli** — tohle je test na to, co se má
    /// NEstát: overlay scroller se bez rolování nenakreslí (změřeno u #422: 0 pixelů i s vypnutým
    /// autohide), takže přepnutí na `.overlay` odsud pruh potichu odstraní.
    ///
    /// Měří se to na tom, co je z venku vidět — **na pásu výšky**, ne jen na `scrollerStyle`:
    /// legacy plocha si ho vezme, overlay nikoli (0 bodů), a to je i doklad, proč se overlay
    /// natrvalo nedá použít.
    @Test("Přiřazení overlay pruh nesebere")
    func styleStaysLegacy() throws {
        let pinned = DiffPairScrollView()
        #expect(pinned.scrollerStyle == .legacy)
        pinned.scrollerStyle = .overlay
        #expect(pinned.scrollerStyle == .legacy)
        // Systémové *Zobrazovat posuvníky* se tudy nepřebíjí, ale odsud se pruh vzít nesmí.
        NotificationCenter.default.post(
            name: NSNotification.Name("NSPreferredScrollerStyleDidChangeNotification"),
            object: nil
        )
        #expect(pinned.scrollerStyle == .legacy)

        // A totéž na pásu výšky: tentýž dokument, dvě plochy, jeden rozdíl.
        #expect(Self.bandTaken(by: pinned, docWidth: 900) == DiffPairScrollView.scrollerHeight)
        let overlay = NSScrollView()
        overlay.scrollerStyle = .overlay
        #expect(Self.bandTaken(by: overlay, docWidth: 900) == 0)
    }

    /// Pás výšky, který si plocha vezme pro dokument dané šířky.
    private static func bandTaken(by scroll: NSScrollView, docWidth: Double) -> Double {
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        let document = NSView(frame: NSRect(x: 0, y: 0, width: docWidth, height: 100))
        document.autoresizingMask = []
        scroll.documentView = document
        scroll.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        scroll.tile()
        return scroll.frame.height - scroll.contentSize.height
    }

    /// Prázdná strana dvojice **nesmí vyjít nulově vysoká**: řádky si musí odpovídat i tam, kde jedna
    /// strana chybí, a to je celý smysl pohledu vedle sebe. Drží to prázdný řádek (`DiffLine.blank`),
    /// ne minimální výška — takže se to dá tvrdit na rámečcích.
    @Test("Prázdná strana dvojice drží řádky zarovnané")
    func theEmptySideKeepsTheRowsAligned() throws {
        let filled = lines(4, chars: 40)
        let full = container(left: filled, right: filled, width: 500)
        let half = container(left: [nil, nil, nil, nil], right: filled, width: 500)

        #expect(half.lineFrames().count == 4)
        #expect(half.lineFrames().map(\.rect) == full.lineFrames().map(\.rect))
        #expect(half.height(forWidth: 500) == full.height(forWidth: 500))
    }

    /// Když pruh potřebuje **jen jedna** půlka, rezervuje se pás **jednou** a druhá má v něm prázdno.
    /// Blok je jeden, takže obě strany mají pořád stejně vysoké řádky.
    @Test("Pás se rezervuje jednou, i když pruh potřebuje jedna strana")
    func theBandIsReservedOnceForTheWholeBlock() throws {
        let container = container(left: lines(4, chars: 4), right: lines(4, chars: 60), width: 500)
        let rows = container.lineFrames().map(\.rect)
        let both = try scrollers(in: container)
        let bottom = try #require(container.lineFrames().last).rect.maxY

        #expect(container.height(forWidth: 500) == bottom + 2 + DiffPairScrollView.scrollerHeight)
        #expect(both.first?.horizontalScroller?.isHidden == true)
        #expect(both.last?.horizontalScroller?.isHidden == false)
        #expect(reservedBand(of: try #require(both.first)) == 0)
        #expect(reservedBand(of: try #require(both.last)) == DiffPairScrollView.scrollerHeight)
        // Řádky zůstávají tam, kde by byly bez pruhu — pás si plocha bere zespodu.
        let reference = self.container(left: lines(4, chars: 4), right: lines(4, chars: 4), width: 500)
        #expect(rows == reference.lineFrames().map(\.rect))
    }
}

/// Druhá polovina rozhodnutí #422: **pohled pod sebou se nemění**. Zůstává zalamovací, takže v něm
/// pruh není a 17 bodů na blok se v něm neplatí.
///
/// Je to test na to, co se má **NEstát**: kdyby se unified přepnul na vodorovný posun (nebo si začal
/// rezervovat pás), přestalo by platit, že se zalomený řádek přečte celý bez rolování — a to byla
/// volba ze tří možností, ne opomenutí.
@Suite("Pohled pod sebou se pruhem nemění")
@MainActor
struct UnifiedBlockWrappingTests {
    private func unified(_ text: String) -> DiffTextView {
        let view = DiffTextView.wrappingBlock()
        view.gutterWidth = DiffLineView.contentInset(for: .unified)
        view.show(
            DiffBlock(lines: [DiffLine(kind: .added, oldNumber: nil, newNumber: 1, text: text)]),
            style: DiffBlockStyle(language: Language(path: "Cart.swift"), colorScheme: .light),
            words: { [:] }
        )
        return view
    }

    /// Kolik vizuálních řádků layout manager doopravdy vysází. Reference, která **není** druhým
    /// výpočtem výšky — ptá se na fragmenty, ne na `usedRect`, ze kterého výška vychází.
    private func fragments(in view: DiffTextView, width: Double) throws -> Int {
        _ = view.height(forWidth: width)
        let layout = try #require(view.layoutManager)
        let container = try #require(view.textContainer)
        var count = 0
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, _, _ in
            count += 1
        }
        return count
    }

    /// Dlouhý řádek se **zalomí** a výška je přesně tolik vizuálních řádků, kolik jich layout
    /// manager vysází — žádný pás navíc. Přes pásmo šířek, aby se hranice zalomení projela
    /// několikrát.
    @Test("Unified zalamuje a pás pruhu si nebere")
    func wrapsWithoutReservingTheBand() throws {
        let view = unified(String(repeating: "x", count: 120))
        let widths = Array(stride(from: 300.0, through: 900.0, by: 17.0))
        var wrapped = 0
        for width in widths {
            let count = try fragments(in: view, width: width)
            let expected = Double(count) * view.singleLineHeight + 4
            #expect(try #require(view.height(forWidth: width)) == expected, "šířka \(width), \(count) fragmentů")
            if count > 1 { wrapped += 1 }
        }
        // A z druhé strany, ať test neprojde bloku, který nezalamuje vůbec: v tom pásmu se zalomit
        // musel na každé šířce — 120 znaků se pod 900 bodů na jeden řádek nevejde.
        #expect(wrapped == widths.count)
    }

    /// Každý blok si drží **svůj** textový kontejner: zalamovací se zalomí na šířce, na které kreslí,
    /// sloupec dvojice se nezalamuje vůbec. Kdyby se to sjednotilo, přišel by jeden z nich o to,
    /// kvůli čemu existuje.
    @Test("Zalamovací blok má kontejner na šířku plochy, sloupec dvojice neomezený")
    func theTwoBlockKindsKeepTheirContainers() throws {
        let gutter = DiffLineView.contentInset(for: .unified)
        let wrapping = DiffTextView.wrappingBlock()
        wrapping.gutterWidth = gutter
        wrapping.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
        #expect(try #require(wrapping.textContainer).size.width == 600 - gutter)

        let column = DiffTextView.pairColumn()
        column.gutterWidth = DiffLineView.contentInset(for: .split)
        column.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
        #expect(try #require(column.textContainer).size.width == CGFloat.greatestFiniteMagnitude)
    }
}
