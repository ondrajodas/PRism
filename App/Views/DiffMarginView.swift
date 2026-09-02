import SwiftUI

/// Okraj vpravo od diffu (#503): karta nálezu stojí **na výšce svého řádku**, ne pod ním.
///
/// Do #503 visel blokující nález pod svým řádkem jako karta o sto bodech (#185) a tentýž nález
/// stál podruhé jako řádek v panelu vpravo (#182) — kód se tím čte přes díry a jedno tvrzení je na
/// obrazovce dvakrát. Okraj je odpověď z Google Docs a z Figmy: kód zůstane souvislý, karta stojí
/// vedle svého řádku, spojnice říká vedle kterého a řádek nese na pravé hraně 3bodový pruh
/// závažnosti (`DiffBlockRowView`).
///
/// **Tři věci, na kterých to stojí, a všechny tři jsou geometrie, ne data:**
///
/// 1. **Kde řádek leží** hlásí blok kódu do `DiffMarginAnchors` — v souřadnicích **obsahu**,
///    takže se to scrollováním nemění.
/// 2. **Kde stojí karta** počítá `Policy.marginTops(desired:heights:gap:)` ze změřených výšek
///    karet. Odstrčení je tím čistá funkce, kterou jde vyčerpat výčtem.
/// 3. **Posun s výřezem** dělá jediný modifikátor (`DiffMarginScroll`), který čte `DiffViewport.top`.
///    Vlastní modifikátor, ne kus tohohle těla, a je to výkonová podmínka: `top` se mění při
///    **každém** otočení kolečka, kdežto `content` uvnitř modifikátoru je zástupný uzel, takže se
///    karty samy nepřekládají. Kdyby se `top` četl tady, přeložilo by se při každém snímku tělo
///    okraje i všech jeho karet — je to tentýž vzorec jako `DiffPinnedHeader` (#469).
///
/// **Karty se kreslí `FindingBubbleView`em, ne vlastní kartou.** Nález je tentýž nález, jen o kus
/// vedle: odznaky, shoda dvou reviewerů, stav z kontroly (#150), odmítnutí (#113) i řada akcí
/// `Převzít · Neplatí · Nepatří sem` (#283) se v okraji nesmí chovat jinak než v bublině. Druhá
/// kresba téhož by se rozešla — a rozejít se v tomhle znamená, že jedna obrazovka nabízí akci,
/// kterou druhá nemá.
struct DiffMarginView: View {
    /// Karty v pořadí obsahu. Skládá je `Policy.marginCards` z **dat**, ne z hlášení bloků.
    let cards: [DiffMarginCard]
    let anchors: DiffMarginAnchors
    let viewport: DiffViewport
    /// Výška, kterou okraj dostane. **Změřená, ne vyjednaná** (#220) — `DiffView` ji má
    /// z `onGeometryChange` nad plochou diffu, takže se o ni okraj nepře se sousedy.
    let height: Double
    var blockingCategories: Set<String> = Policy.defaultBlockingCategories
    var findingActions: FindingActions?
    /// Akce rozdělaného review svázané se souborem karty, klíčované cestou. Skládá je `DiffView`
    /// jednou za soubor — kotvy se hledají v hunkách, takže na kartu by to byl průchod navíc.
    var drafts: [String: FileDraftActions] = [:]
    /// Místo, na které se právě skočilo z tabulky nálezů.
    var highlighted: FindingHighlight?
    /// Kde stojí kurzor procházení (#187). Karta na tom místě dostane rámeček — bez něj by po
    /// skoku `⌥↓` nebylo v okraji poznat, o které kartě lišta mluví.
    var current: FindingPlace?

    /// Změřené výšky karet, klíčované `id`. **Měří se na tom, na čem se kreslí** (#236): výška
    /// karty je funkce jejího obsahu a šířky okraje, tedy ničeho, co by záviselo na její poloze —
    /// zpětná vazba z toho proto být nemůže.
    ///
    /// Do prvního změření platí odhad (`Self.estimate`) a odstrčení je o něj vedle; usadí se
    /// o průchod později. **Je to jediné místo v diffu, kde se výška odhaduje**, a smí to tu být
    /// právě proto, že odhad nehýbe kódem: v okraji se pohne karta, ne obsah pod prstem (na rozdíl
    /// od bloků, kde je odhad zamítnutý — viz `DiffBlockSlot`).
    @State private var heights: [String: Double] = [:]

    /// Šířka z návrhu (`grid-template-columns: 210px 1fr 300px`) — tatáž jako panel, který okraj
    /// v tomhle tabu zastupuje, takže se počet znaků na stranu nemění.
    static let width = 300.0
    /// Mezera mezi odstrčenými kartami (návrh: `margin-top: 8px`).
    private static let gap = 8.0
    /// Odsazení karty od hran okraje (návrh: `.mgn { padding: 0 10px }`).
    private static let inset = 10.0
    /// Kde na kartě spojnice končí — 11 bodů dlouhá, 13 pod horní hranou karty, jak ji má návrh
    /// (`.mgn-card::before { left: -11px; top: 13px }`). Vodorovný pahýl začíná na hraně okraje,
    /// takže je z něj vidět 10 bodů; jedenáctý padne na dělicí linku.
    private static let connectorY = 13.0
    /// Odhad výšky karty do prvního změření. Číslo je z návrhu: kapsle, řádek shrnutí a řada akcí.
    private static let estimate = 96.0

    var body: some View {
        // **Kreslí se jen karty v pásu kolem výřezu** (#469), ne všechny. Pás se čte **tady**,
        // a je to schválně on a ne `top`: je kvantovaný na násobky výřezu, takže se mění jednou
        // za projetý výřez, kdežto `top` při každém snímku. Změřeno (`DiffMarginWheelProbe`,
        // 2000 řádků, 11 karet, projetí 150 × 40 pt): bez pásu **1,65 / 1,67 s** CPU, s pásem
        // **1,56 / 1,53 s** — proti **1,47 / 1,47 s** nad tímtéž diffem bez nálezů. Pás tedy
        // sundal dvě třetiny toho, co si okraj bral.
        let band = viewport.band
        let placed = placements
        ZStack(alignment: .topLeading) {
            // Prázdná plocha drží šířku i výšku i tehdy, když všechny karty odscrollovaly pryč.
            // Bez ní by okraj splaskl na nejvyšší kartu a linka na hraně by končila v prázdnu.
            Color.clear
            ForEach(placed) { spot in
                if Policy.isBlockMounted(spot.span, band: band) {
                    connector(of: spot)
                    card(of: spot)
                }
            }
        }
        .modifier(DiffMarginScroll(viewport: viewport))
        .frame(width: Self.width, height: height, alignment: .topLeading)
        // Bez ořezu by karta u prvního nebo posledního řádku přetekla nad lištu, respektive pod
        // spodní hranu okna.
        .clipped()
        .background(Palette.chrome)
        .overlay(alignment: .leading) { Rectangle().fill(Palette.lineSoft).frame(width: 1) }
        // **Popisek okraje jako celku tady schválně není.** `accessibilityLabel` na kontejneru
        // s dětmi je odpověď za ně, takže by se řada `Převzít · Neplatí · Nepatří sem` dala
        // z VoiceOveru ztratit. Přístupnost si nese karta sama (`FindingBubbleView`), a je to
        // tatáž karta jako v panelu.
    }

    // MARK: - Rozvržení

    /// Karta i s tím, kde nakonec stojí.
    private struct Placed: Identifiable {
        let card: DiffMarginCard
        /// Horní hrana karty v souřadnicích obsahu — po odstrčení.
        let top: Double
        /// Kam míří spojnice v kódu. `nil` = polohu řádku ještě nikdo neohlásil, takže se
        /// spojnice nekreslí: čárka do prázdna tvrdí polohu, kterou neznáme.
        let row: Double?
        /// Svislý rozsah karty — z něj se pozná, jestli je v pásu kolem výřezu.
        let span: ClosedRange<Double>

        var id: String { card.id }
    }

    private var placements: [Placed] {
        let spots = anchors.spots
        // Výšky se do odstrkování berou **pro všechny karty**, i pro ty mimo pás: kdo se
        // odstrkuje, závisí na tom, co je nad ním, takže z útržku by vyšly jiné polohy podle
        // toho, kde je zrovna výřez.
        let heights = cards.map { self.heights[$0.id] ?? Self.estimate }
        let tops = Policy.marginTops(
            desired: cards.map { spots[$0.id]?.top },
            heights: heights,
            gap: Self.gap
        )
        return cards.enumerated().map { index, card in
            Placed(
                card: card,
                top: tops[index],
                row: spots[card.id]?.middle,
                span: tops[index]...(tops[index] + heights[index])
            )
        }
    }

    // MARK: - Kresba

    /// Spojnice ke kartě: vodorovný pahýl na její hraně, a když je karta odstrčená, svislé
    /// zalomení do `L` od řádku k ní.
    ///
    /// Kreslí se **dvěma obdélníky, ne cestou**: jsou to dvě pravoúhlé čárky a `Path` by si vzal
    /// vlastní vrstvu kreslení, přitom by řekl totéž.
    @ViewBuilder private func connector(of spot: Placed) -> some View {
        if let row = spot.row {
            let cardY = spot.top + Self.connectorY
            Rectangle()
                .fill(Palette.ink3)
                .frame(width: Self.inset, height: 1)
                .offset(y: cardY)
            // Zalomení jedině tehdy, když karta doopravdy neleží u svého řádku. U nulové výšky
            // by z obdélníku byl neviditelný prvek k umístění navíc (#252).
            if abs(row - cardY) > 0.5 {
                Rectangle()
                    .fill(Palette.ink3)
                    .frame(width: 1, height: abs(row - cardY))
                    .offset(y: min(row, cardY))
            }
        }
    }

    private func card(of spot: Placed) -> some View {
        FindingBubbleView(
            group: spot.card.group,
            blockingCategories: blockingCategories,
            isHighlighted: isCurrent(spot.card) || highlighted?.matches(spot.card.group) == true,
            draft: drafts[spot.card.path] ?? FileDraftActions(),
            actions: findingActions,
            // Rozbalená a **bez pruhu na sbalení**: v okraji nestojí karta v cestě kódu, takže
            // sbalit ji není proč (#185 to řešilo právě tím, že bublina kód rozráží). Bez pruhu
            // se hlavičky nálezů kreslí uvnitř karty, jako v tabulce nálezů.
            disclosure: .expanded,
            toggle: nil,
            placement: .margin
        )
        .frame(width: Self.width)
        // Výška se měří na kartě samotné (#236). `onGeometryChange` se při nezměněné hodnotě
        // nespustí (#361), takže scrollováním se do stavu nezapisuje.
        .onGeometryChange(for: Double.self) { $0.size.height } action: { heights[spot.id] = $0 }
        .offset(y: spot.top)
    }

    private func isCurrent(_ card: DiffMarginCard) -> Bool {
        guard let current else { return false }
        return FindingPlace(card.group) == current
    }
}

/// Posun okraje s výřezem (#503).
///
/// **Vlastní modifikátor, ne `offset` v těle okraje**, a je to výkonová podmínka: `DiffViewport.top`
/// se mění při **každém** otočení kolečka. Uvnitř `body(content:)` je `content` zástupný uzel, takže
/// se přeloží jedině tenhle modifikátor — karty ani jejich obsah ne. Kdyby se `top` čtlo v těle
/// okraje, platilo by se při každém snímku za překlad všech karet.
///
/// `offset` je navíc geometrická transformace, ne rozvržení: děti se kvůli němu nepřeměřují.
private struct DiffMarginScroll: ViewModifier {
    let viewport: DiffViewport

    func body(content: Content) -> some View {
        content.offset(y: -viewport.top)
    }
}

extension DiffMarginSeverity {
    /// Barva pruhu na hraně řádku a hrany karty. **Tatáž škála jako u bubliny a u karty v panelu**
    /// (`FindingBubbleView.accent`, `FindingCardView.accent`) — a je to jediné místo, kde se z
    /// hodnoty stává barva, takže se ty tři kresby nemohou rozejít.
    var stripe: Color {
        switch self {
        case .blocking: Palette.crit
        case .finding: Palette.find
        case .dismissed: Palette.ink3
        }
    }
}
