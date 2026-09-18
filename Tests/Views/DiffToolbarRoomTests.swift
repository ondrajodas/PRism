import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// **Kolik místa v liště stojí `Popsat změny`** (#524) — a co se stane, když ho není dost.
///
/// Akce se do lišty stěhovala z nabídky pod šipkou a odůvodnění té nabídky byla zrovna šířka:
/// *„v liště se soutěží o místo s věcmi, které se používají při každém review“*. Tvrzení o šířce
/// se dá **změřit**, takže se tady měří místo toho, aby se o něm dohadovalo — a měření vydalo
/// i něco, co se nečekalo: **lišta v plné výbavě v podlahovém okně přetéká už bez téhle akce**.
/// Proto tu ta hodnota stojí taky: aby se přetečení nečetlo jako něco, co přineslo #524.
///
/// Rozvrhuje se **mimo obrazovku** (`fittingSize`), protože otázka je o šířce, kterou si lišta
/// **vyžádá**, ne o tom, co je vidět: accessibility tree se v okně mimo obrazovku nenaplní (#269),
/// zato `fittingSize` odpoví. Jak vypadá lišta, které se místa nedostává, ukazuje
/// `DiffToolbarRoomProbe` — z `fittingSize` se to přečíst nedá.
@MainActor
@Suite("Místo pro `Popsat změny` v liště diffu (#524)")
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

    // MARK: - Scéna

    private func diff(files: Int = 3) -> Diff {
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
            unrecognizedLines: 0
        )
    }

    /// Lišta s plnou výbavou: procházení nálezů, varování o šířce, hledání i sbalení.
    /// **Nejhorší případ, ne typický** — akce se musí snést vedle všeho, co v liště může stát naráz.
    private func toolbar(annotation: DiffAnnotationActions?, contentWidth: Double) -> some View {
        DiffToolbar(
            diff: diff(),
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
            missingThreads: 0,
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

    // MARK: - Co ta akce stojí

    /// **Celý popisek stojí ~104 bodů** — ikona, mezera a `Popsat změny` v 11,5 bodu. Strop je
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

    // MARK: - Přetečení, které tu bylo dřív

    /// **Lišta v plné výbavě přetéká v podlahovém okně už bez popisu změn** — 819 bodů proti 572,
    /// které má. Je to změřená vlastnost z #219 (*„v užším okně se lišta nevešla“*), ne něco, co
    /// přineslo #524; stojí tady proto, aby se tak nečetla.
    ///
    /// Proto je `Popsat změny` **jediný prvek v liště bez `fixedSize()` a se zápornou prioritou
    /// rozvržení**: když se místa nedostává, srazí se na samotnou ikonu (`ViewThatFits`) a to,
    /// co v liště bylo dřív, zůstane, kde bylo. Kresbu ukazuje `DiffToolbarRoomProbe`.
    @Test("Lišta v plné výbavě přetéká v podlahovém okně i bez téhle akce")
    func theToolbarAlreadyOverflowsAtTheFloor() {
        let width = narrowToolbarWidth

        #expect(neededWidth(toolbar(annotation: nil, contentWidth: width)) > width)
    }
}
