import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// **Kolik si lišta nad diffem říká, kolik má a co z ní v tísni zbude** (#524, rozšířeno #593).
///
/// U #524 z toho vyšlo něco, co se nečekalo: **lišta v plné výbavě v podlahovém okně přetéká už
/// bez nové akce** — 819 bodů proti 572, které má. #593 z toho udělal rozhodnutí místo shody
/// okolností: každý prvek má svou sraženou podobu a své místo v pořadí (`Policy`), rozměr
/// **měří a předává** `DiffToolbarLayout`.
///
/// Dělba proti `DiffToolbarLadderTests` je podle toho, **co která sada umí dokázat**: tam se
/// vyčerpává rozhodnutí nad čísly, tady se ta čísla **měří na tom, co aplikace doopravdy kreslí**
/// (#236) — a **v pásmu šířek**, ne na jedné. Jak lišta vypadá, ukazuje `DiffToolbarRoomProbe`;
/// z `fittingSize` se to přečíst nedá.
@MainActor
@Suite("Místo v liště diffu (#524, #593)")
struct DiffToolbarRoomTests {
    /// **Podlaha okna, ne odhad**: `RootView` má `frame(minWidth: 700)`
    /// a `PRismApp` `windowResizability(.contentMinSize)`, takže užší okno v aplikaci nevznikne.
    private let windowFloor = 700.0
    /// Rail vlevo, který plochu tabu ukrajuje vždycky.
    private let rail = 52.0
    /// Oba boční sloupce složené na proužek — tedy stav, ve kterém je štěrbina diffu **nejširší,
    /// jaká v podlahovém okně být může**. Rozložené sloupce ji zúží, ale to už je volba člověka;
    /// sada se ptá na ten stav, ve kterém je místa nejvíc, a **přesto** ho nestačí.
    private let strips = 38.0 * 2

    /// Kolik místa lišta doopravdy má, když je okno na podlaze a oba sloupce složené.
    private var narrowToolbarWidth: Double { windowFloor - rail - strips }

    /// Pásmo šířek, na kterém se měří: podlaha, o kus víc, okno, ve kterém se zbytek vejde,
    /// a běžné okno na celou obrazovku.
    private let band = [572.0, 700.0, 900.0, 1_100.0, 1_400.0]

    /// Vodorovné odsazení lišty (14 na stranu) a mezery mezi prvky. Mezer je **9 uvnitř každé
    /// skupiny a 27 mezi skupinami**, takže plná výbava (2 prvky vlevo, 4 vpravo) má 63 —
    /// a že to číslo platí, hlídá `theToolbarAsksForTheSumOfItsItems` proti živé liště.
    private let padding = 28.0
    private func spacing(leading: Int, trailing: Int) -> Double {
        9 * Double(max(leading - 1, 0) + max(trailing - 1, 0)) + 27
    }

    // MARK: - Scéna

    private func diff(files: Int = 3, unreadable: Int = 0) -> Diff {
        Diff(
            files: (0..<files).map { index in
                FileDiff(
                    oldPath: "src/Soubor\(index).swift",
                    newPath: "src/Soubor\(index).swift",
                    change: .modified,
                    isBinary: false,
                    hunks: [
                        DiffHunk(oldStart: 1, oldCount: 3, newStart: 1, newCount: 5, heading: "", lines: [])
                    ]
                )
            },
            unrecognizedLines: unreadable
        )
    }

    /// Lišta s plnou výbavou: procházení nálezů, varování o šířce, hledání i sbalení.
    /// **Nejhorší běžný případ, ne typický** — všechno, co v liště může stát naráz, tam stojí.
    ///
    /// `unreadable` a `missing` jsou k tomu **vzácná** varování; s nimi se lišta nevejde ani po
    /// celém ustoupení, takže se na nich měří to ubírání.
    private func toolbar(
        annotation: DiffAnnotationActions?,
        contentWidth: Double,
        unreadable: Int = 0,
        missing: Int = 0
    ) -> DiffToolbar {
        DiffToolbar(
            diff: diff(unreadable: unreadable),
            layout: .constant(.split),
            navigation: FindingNavigation(
                position: 2,
                total: 7,
                hasPrevious: true,
                hasNext: true,
                isComplete: false,
                withoutPlace: 0
            ),
            onlyBlocking: .constant(false),
            stepFinding: { _ in },
            showBubbles: .constant(true),
            hasFindings: true,
            folding: DiffFoldingActions(
                isFolded: { _ in false },
                toggle: { _ in },
                foldAll: { _ in },
                unfoldAll: {}
            ),
            collapseExpansion: {},
            missingThreads: missing,
            contentWidth: contentWidth,
            openSearch: {},
            isSearching: false,
            annotation: annotation
        )
    }

    private func actions(_ state: Policy.AnnotationControl) -> DiffAnnotationActions {
        DiffAnnotationActions(state: state, start: {}, cancel: {})
    }

    /// **Bez vnějšího `frame(width:)`**, a je to celý rozdíl mezi měřením a tautologií: přibitá
    /// šířka se z `fittingSize` vrátí zpátky, ať je uvnitř cokoli — takže lišta s tlačítkem i bez
    /// něj vyjde stejně (změřeno: obojí 572). Bez ní se ptáme na to, oč si lišta **říká**.
    private func neededWidth(_ view: some View) -> Double {
        NSHostingView(rootView: view).fittingSize.width
    }

    /// Změřené prvky plné výbavy — tou cestou, kterou je měří `DiffToolbarLayout`.
    private func measuredItems(
        of bar: DiffToolbar,
        withWarnings: Bool = false
    ) -> [Policy.DiffToolbarMeasure] {
        let entries = DiffToolbarMeasuring.entries {
            bar.layoutPicker
            bar.findingNavigation
            if withWarnings { bar.warnings } else { bar.widthGauge }
            bar.annotateButton
            bar.searchButton
            bar.foldMenu
        }
        return entries.compactMap(\.measure)
    }

    private func room(_ bar: DiffToolbar, at width: Double, withWarnings: Bool = false) -> Policy.DiffToolbarRoom {
        let items = measuredItems(of: bar, withWarnings: withWarnings)
        let leading = items.count { Policy.diffToolbarSide($0.item) == .leading }
        return Policy.diffToolbarRoom(
            available: width - padding - spacing(leading: leading, trailing: items.count - leading),
            measures: items
        )
    }

    // MARK: - Co ta akce stojí (#524)

    /// **Celý popisek stojí ~95 bodů** — ikona, mezera a `Popsat změny` v 11,5 bodu. Strop je
    /// s rezervou, ne míra: hlídá, aby se popisek nerozrostl na větu.
    @Test("Popisek stojí kolem sta bodů, ne víc")
    func theLabelCostsAboutAHundredPoints() {
        let width = narrowToolbarWidth
        let without = neededWidth(toolbar(annotation: nil, contentWidth: width))
        let with = neededWidth(toolbar(annotation: actions(.idle), contentWidth: width))

        // Bez akce se **nekreslí nic**, ne zašedlá kapsle — proto se ty dvě šířky vůbec liší.
        #expect(with > without)
        #expect(with - without <= 110)
    }

    /// **Žádný ze tří stavů lištu nerozšíří.** Popisek se za běhu i po selhání mění, a kdyby byl
    /// některý z nich širší než `Popsat změny`, lámalo by se okno pod rukou — zrovna ve chvíli,
    /// kdy se na něj člověk dívá.
    @Test("Běh ani selhání lištu nerozšíří proti klidu", arguments: [
        Policy.AnnotationControl.running,
        .failed(detail: "Popis změn neproběhl. Session skončila s návratovým kódem 1."),
    ])
    func noStateIsWiderThanIdle(_ state: Policy.AnnotationControl) {
        let width = narrowToolbarWidth
        let idle = neededWidth(toolbar(annotation: actions(.idle), contentWidth: width))
        let other = neededWidth(toolbar(annotation: actions(state), contentWidth: width))

        #expect(other <= idle)
    }

    // MARK: - Přetečení, které tu bylo dřív (#524)

    /// **Lišta v plné výbavě přetéká v podlahovém okně už bez popisu změn** — 819 bodů proti 572,
    /// které má. Je to změřená vlastnost z #219 (*„v užším okně se lišta nevešla“*), ne něco, co
    /// přineslo #524; stojí tady proto, aby se tak nečetla.
    @Test("Lišta v plné výbavě přetéká v podlahovém okně i bez téhle akce")
    func theToolbarAlreadyOverflowsAtTheFloor() {
        let width = narrowToolbarWidth

        #expect(neededWidth(toolbar(annotation: nil, contentWidth: width)) > width)
    }

    // MARK: - Co si který prvek bere (#593)

    /// Součet prvků, mezery a odsazení dávají dohromady to, oč si lišta říká — jinak se v číslech
    /// níž měří něco jiného než ta lišta.
    @Test("Lišta si říká přesně o součet svých prvků, mezery a odsazení")
    func theToolbarAsksForTheSumOfItsItems() {
        let bar = toolbar(annotation: actions(.idle), contentWidth: narrowToolbarWidth)
        let items = measuredItems(of: bar)
        let leading = items.count { Policy.diffToolbarSide($0.item) == .leading }
        let expected = items.map(\.full).reduce(0, +)
            + spacing(leading: leading, trailing: items.count - leading) + padding

        #expect(neededWidth(bar) == expected)
        // Plná výbava je šest prvků: pohled, procházení, šířka, popis změn, hledání, sbalení.
        #expect(items.count == 6)
    }

    /// **Sražená podoba v kresbě musí odpovídat té vyhlášené v `Policy`.** Tohle je ta vada,
    /// kterou #593 opravuje: prvek, o kterém se tvrdí, že ustoupí, ale v kresbě druhou podobu
    /// nemá, se v tísni **nesrazí** a lišta přeteče. (Změřeno u nabídky `Sbalit vše`: `Menu`
    /// svému popisku šířku nepředává, takže `ViewThatFits` uvnitř popisku ustoupil o jediný bod.)
    @Test("Co má podle Policy ustoupit, to je i v kresbě užší")
    func drawnFloorsMatchThePolicy() {
        let bar = toolbar(annotation: actions(.idle), contentWidth: narrowToolbarWidth, unreadable: 3, missing: 2)
        let entries = DiffToolbarMeasuring.entries {
            bar.layoutPicker
            bar.findingNavigation
            bar.warnings
            bar.annotateButton
            bar.searchButton
            bar.foldMenu
        }

        #expect(entries.count == 8)
        for entry in entries {
            guard let item = entry.item else {
                Issue.record("prvek lišty bez identity — `Policy` o něm nemůže rozhodnout")
                continue
            }
            switch Policy.diffToolbarFloor(item) {
            case .full:
                #expect(entry.floor == entry.full)
            case .short, .icon:
                // Aspoň desetina, ne „o bod“: ustoupení, které nic neuspoří, je ustoupení jen
                // podle jména.
                #expect(entry.floor <= entry.full * 0.9)
            }
        }
    }

    /// Ikona je **ikona**, ne zkrácený popisek: `Popsat…` by neslo půl slova.
    @Test("Sražený popis změn je samotná ikona")
    func theAnnotateFloorIsAnIcon() {
        let bar = toolbar(annotation: actions(.idle), contentWidth: narrowToolbarWidth)
        let entry = DiffToolbarMeasuring.entry(.annotate) { bar.annotateButton }

        #expect(entry?.full ?? 0 > 80)
        #expect(entry?.floor ?? 0 < 20)
    }

    // MARK: - Pásmo šířek (#593, #236)

    /// **Po ustoupení se lišta v plné výbavě vejde na každé šířce z pásma** — a to je celý účel
    /// #593. Před ním se vejít nemohla: srazit se umělo jen `Popsat změny` (82 bodů) a chybělo
    /// jich 351.
    @Test("Plná výbava se po ustoupení vejde na celém pásmu šířek")
    func theFullKitFitsAcrossTheBand() {
        for width in band {
            let bar = toolbar(annotation: actions(.idle), contentWidth: width)
            let items = measuredItems(of: bar)
            let leading = items.count { Policy.diffToolbarSide($0.item) == .leading }
            let decided = room(bar, at: width)
            let taken = items.map { decided.width(of: $0.item) }.reduce(0, +)
                + spacing(leading: leading, trailing: items.count - leading) + padding

            #expect(taken <= width, "lišta se v \(width) nevejde: \(taken)")
            #expect(decided.truncated.isEmpty, "v \(width) se muselo ubírat")
        }
    }

    /// **Procházení nálezů zůstane celé na celém pásmu** — negativní tvrzení, které se rozbije
    /// potichu: kdyby se srazilo, nic nespadne, jen zmizí počitadlo nebo kapsle `jen blokující`.
    @Test("Procházení nálezů si na žádné šířce neubere")
    func navigationKeepsItsWidthAcrossTheBand() {
        for width in band {
            let bar = toolbar(annotation: actions(.idle), contentWidth: width, unreadable: 3, missing: 2)
            let items = measuredItems(of: bar, withWarnings: true)
            guard let navigation = items.first(where: { $0.item == .navigation }) else {
                Issue.record("procházení nálezů se v \(width) nekreslí vůbec")
                continue
            }
            let decided = room(bar, at: width, withWarnings: true)

            #expect(decided.width(of: .navigation) == navigation.full)
            #expect(!decided.conceded.contains(.navigation))
            #expect(!decided.truncated.contains(.navigation))
        }
    }

    /// **Čím širší okno, tím víc zůstane celé.** Kdyby pořadí ustupování na šířce nezáviselo,
    /// vyšla by tahle posloupnost naopak — a měřidlo by nerozeznalo „funguje“ od „nefunguje“
    /// (#478).
    @Test("S rostoucí šířkou ustupuje méně prvků")
    func fewerItemsConcedeAsTheWindowGrows() {
        let counts = band.map { width in
            room(toolbar(annotation: actions(.idle), contentWidth: width), at: width).conceded.count
        }

        #expect(counts == counts.sorted(by: >))
        #expect(counts.first ?? 0 > 0, "v podlahovém okně musí ustoupit aspoň jeden prvek")
        #expect(counts.last == 0, "v širokém okně nemá ustupovat nic")
    }

    /// V podlahovém okně ustoupí pět prvků a **přepínač pohledu jako poslední z nich** — na to,
    /// aby zůstal celý, chybí 102 bodů, které nemá odkud vzít nikdo jiný než on.
    @Test("V podlahovém okně zbude z akcí ikona a z přepínače ikony")
    func theFloorConcedesFiveItems() {
        let bar = toolbar(annotation: actions(.idle), contentWidth: narrowToolbarWidth)
        let decided = room(bar, at: narrowToolbarWidth)

        #expect(decided.conceded == [.annotate, .search, .fold, .width, .layout])
        #expect(decided.truncated.isEmpty)
    }

    /// **Obě vzácná varování naráz jsou ten jediný stav, kdy ustoupení nestačí** — a i tam
    /// zůstane každý prvek vidět. Je to zapsaná mez, ne přehlédnutí.
    @Test("I se vzácnými varováními zůstane každý prvek vidět")
    func everyItemSurvivesTheWorstCase() {
        let bar = toolbar(
            annotation: actions(.idle),
            contentWidth: narrowToolbarWidth,
            unreadable: 3,
            missing: 2
        )
        let items = measuredItems(of: bar, withWarnings: true)
        let decided = room(bar, at: narrowToolbarWidth, withWarnings: true)

        #expect(items.count == 8)
        #expect(!decided.truncated.isEmpty, "tohle je ten stav, ve kterém se ubírá")
        for item in items {
            // Mez platí na **ubírání**: prvek, jehož sražená podoba je užší (ikona má změřených
            // 13 bodů), zůstane na ní — ubírat se z něj už nesmí.
            #expect(decided.width(of: item.item) >= min(item.floor, Policy.diffToolbarItemFloor))
        }
    }

    // MARK: - Nic za hranou (#593)

    /// **Nic se nekreslí za hranou lišty**, a měří se to na kresbě: `fittingSize` o přetečení
    /// mlčí, `HStack` ho nehlásí — jen ho nakreslí.
    ///
    /// Postup: lišta se přibije na šířku štěrbiny a **hostitel je širší**, takže co přeteče,
    /// dopadne do té volné plochy vpravo a v bitmapě to je vidět. Kdyby se kreslilo do bitmapy
    /// široké jako lišta, přetečení by se **ořezalo** a měřidlo by vydalo tutéž hodnotu pro
    /// „funguje“ i „nefunguje“ (#478).
    ///
    /// Ověřeno vložením regrese: s prázdným `Policy.diffToolbarLadder` (tedy bez ustupování)
    /// tenhle test spadne na obou šířkách — inkoust dosáhne 63 bodů za hranu lišty.
    @Test("V úzkém okně nedopadne ani bod inkoustu za hranu lišty", arguments: [572.0, 700.0])
    func nothingIsDrawnPastTheEdge(_ width: Double) throws {
        let bar = toolbar(
            annotation: actions(.idle),
            contentWidth: width,
            unreadable: 3,
            missing: 2
        )
        let overhang = 200.0
        let host = NSHostingView(
            rootView: HStack(spacing: 0) {
                bar.frame(width: width)
                Spacer(minLength: 0)
            }
        )
        host.frame = NSRect(x: 0, y: 0, width: width + overhang, height: 34)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)

        // Dva body tolerance na stín aktivního segmentu a na zaoblení.
        let inked = Self.rightmostInk(in: bitmap, across: host.bounds.width)
        #expect(inked <= width + 2, "inkoust sahá do \(inked), lišta končí na \(width)")
    }

    /// Nejpravější **bod**, ve kterém se něco nakreslilo.
    ///
    /// Bitmapa je v **pixelech**, ne v bodech (na Retině dvojnásobek), takže se přepočítává
    /// změřeným poměrem — jinak by test tvrdil dvojnásobné přetečení a vypadal by zeleně
    /// jedině náhodou.
    private static func rightmostInk(in bitmap: NSBitmapImageRep, across width: Double) -> Double {
        var rightmost = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.01 else {
                    continue
                }
                rightmost = max(rightmost, x)
                break
            }
        }
        guard bitmap.pixelsWide > 0 else { return 0 }
        return Double(rightmost) * width / Double(bitmap.pixelsWide)
    }
}
