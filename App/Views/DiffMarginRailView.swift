import SwiftUI

/// Složený okraj — **hrana 28 bodů se značkami** (#505).
///
/// Do #505 měl okraj dva stavy: kolonu o 300 bodech, nebo nic. „Nic“ přitom znamenalo, že nález
/// přebírá panel vpravo, tedy **další** třistabodová kolona — v úzkém okně se tedy za nález
/// platilo vždycky stejně, ať se rozhodlo jakkoli. Hrana je to mezi: kód dostane zpátky 272 bodů
/// a na obrazovce zůstane vidět, **kde** nálezy jsou.
///
/// **Rozložená kolona a složená hrana jsou dva typy, ne jedno tělo s `if`em** — tentýž vzorec
/// jako `ItineraryColumnView` a `ItineraryRailView` (#506) a ze stejného důvodu: každý vstup má
/// v obou typech význam. Hrana nepotřebuje změřené výšky karet ani spojnice, kolona nepotřebuje
/// patku s počtem.
///
/// **Značky se vezou s řádky, počet se neveze.** Puntík stojí na výšce svého řádku, takže po
/// odscrollování zmizí z obrazovky stejně jako řádek sám; kolik nálezů PR má celkem, se proto
/// píše do patky, která drží spodní hranu.
struct DiffMarginRailView: View {
    /// Karty v pořadí obsahu — tytéž, jaké by kreslila rozložená kolona. Skládá je
    /// `Policy.marginCards` z **dat**, ne z hlášení bloků, takže se značka neztratí ani u řádku,
    /// jehož blok je zrovna mimo nasazený pás (#469).
    let cards: [DiffMarginCard]
    let anchors: DiffMarginAnchors
    let viewport: DiffViewport
    /// Výška, kterou hrana dostane. **Změřená, ne vyjednaná** (#220) — jako u kolony.
    let height: Double
    var blockingCategories: Set<String> = Policy.defaultBlockingCategories
    var findingActions: FindingActions?
    /// Akce rozdělaného review klíčované cestou souboru — viz `DiffMarginView.drafts`.
    var drafts: [String: FileDraftActions] = [:]
    /// Kde stojí kurzor procházení (#187). Značka na tom místě dostane rámeček.
    var current: FindingPlace?
    /// Místo, na které se právě skočilo z tabulky nálezů. Rámeček dostane **taky** — je to tatáž
    /// otázka *o které značce je řeč*, jen položená z druhé strany okna, a v rozložené koloně na ni
    /// odpovídá tentýž rámeček (`DiffMarginView.card`).
    var highlighted: FindingHighlight?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Prázdná plocha drží šířku i výšku i tehdy, když všechny značky odscrollovaly pryč —
            // jinak by hrana splaskla na nejvyšší značku a dělicí linka by končila v prázdnu.
            Color.clear
            ForEach(dots) { dot in
                DiffMarginDotView(
                    card: dot.card,
                    isCurrent: isCurrent(dot.card),
                    blockingCategories: blockingCategories,
                    findingActions: findingActions,
                    draft: drafts[dot.card.path] ?? FileDraftActions()
                )
                .offset(y: dot.top)
            }
        }
        // **Posun s výřezem dělá tentýž modifikátor jako u kolony** (#503): `DiffViewport.top` se
        // mění při každém otočení kolečka, takže se uvnitř `body(content:)` přeloží jedině on.
        // Pás (`band`) hrana nečte schválně — značka je puntík bez textu a bez měření, tedy nic
        // z toho, kvůli čemu se bloky kódu nasazují po pásech.
        .modifier(DiffMarginScroll(viewport: viewport))
        .frame(width: Self.width, height: height, alignment: .topLeading)
        // Bez ořezu by značka u prvního nebo posledního řádku přetekla nad lištu, respektive pod
        // spodní hranu okna.
        .clipped()
        // Patka **mimo ořez a mimo posun**: je to jediné místo, ze kterého se dá přečíst, kolik
        // nálezů PR má celkem, takže se s obsahem vézt nesmí.
        .overlay(alignment: .bottom) { total }
        .background(Palette.chrome)
        .overlay(alignment: .leading) { Rectangle().fill(Palette.lineSoft).frame(width: 1) }
        // Popisek celé hrany tady schválně není: `accessibilityLabel` na kontejneru s dětmi je
        // odpověď za ně, takže by se značky z VoiceOveru ztratily. Každá si nese svůj popisek
        // sama (`DiffMarginDotView`) a patka ten svůj.
    }

    /// Patka s počtem nálezů.
    private var total: some View {
        Text(verbatim: Policy.marginRailCount(of: cards))
            .font(.system(size: 10, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(Palette.chrome)
            .overlay(alignment: .top) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
            .help(Policy.marginRailHint(of: cards))
            .accessibilityLabel(Policy.marginRailHint(of: cards))
    }

    // MARK: - Rozvržení

    /// Značka i s tím, kde stojí.
    private struct Dot: Identifiable {
        let card: DiffMarginCard
        let top: Double

        var id: String { card.id }
    }

    /// Kde značky stojí — **toutéž funkcí, jakou se odstrkují karty** (`Policy.marginTops`), jen
    /// s výškou značky místo změřené výšky karty.
    ///
    /// Dvě věci z toho plynou a obě jsou žádoucí: značka, jejíž řádek ještě žádný blok neohlásil,
    /// jde **za předchozí** místo na nulu (zmizet nesmí), a dvě značky na sobě se rozestoupí.
    /// U běžné rozteče řádků se nestane ani jedno — `marginTops` odstrkuje teprve tehdy, když by
    /// se značky potkaly.
    private var dots: [Dot] {
        let spots = anchors.spots
        let size = DiffMarginDotView.size
        let tops = Policy.marginTops(
            // Puntík stojí **na středu** svého řádku, ne na jeho horní hraně: u zalomeného řádku
            // by jinak mířil nad text, ke kterému patří — tatáž úvaha jako u spojnice ke kartě.
            desired: cards.map { spots[$0.id].map { $0.middle - size / 2 } },
            heights: Array(repeating: size, count: cards.count),
            gap: Self.gap
        )
        return cards.enumerated().map { index, card in Dot(card: card, top: tops[index]) }
    }

    private func isCurrent(_ card: DiffMarginCard) -> Bool {
        if highlighted?.matches(card.group) == true { return true }
        guard let current else { return false }
        return FindingPlace(card.group) == current
    }

    /// **Čte se z `Policy`**, protože podle téhož čísla se rozhoduje, jestli se hrana do okna
    /// vejde (`Policy.diffSideColumns`) — dvě pravdy o jedné šířce se rozejdou při první úpravě.
    static let width = Policy.marginColumnWidth(form: .rail)
    /// Mezera mezi odstrčenými značkami. Menší než u karet: značka je puntík, ne karta s textem.
    private static let gap = 2.0
}
