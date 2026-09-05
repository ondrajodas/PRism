import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Dráha smyčky se do hlavičky doopravdy nakreslí (#508).
///
/// `Policy.ownLoop` se dá otestovat výčtem, jenže z toho neplyne, že se sedm kapslí do hlavičky
/// **vejde na jeden řádek** — a kdyby se zalomily, vyroste hlavička PR přes půl okna. Měří se
/// rozvržením mimo obrazovku (`fittingSize`), jako u `PullRequestRowPromptTests`: accessibility
/// tree se v okně mimo obrazovku nenaplní (změřeno u #269).
@Suite("Dráha smyčky v hlavičce (#508)")
@MainActor
struct OwnLoopRenderTests {
    private func loop(move: OwnLoop.Move?) -> OwnLoop {
        OwnLoop(
            stations: OwnLoop.Station.allCases.enumerated().map { index, station in
                OwnLoop.Stop(
                    station: station,
                    state: index == 1 ? .running : (index < 1 ? .done : .idle),
                    detail: index == 1 ? "2 k předání" : nil
                )
            },
            active: .handoff,
            last: "Od předání přibyly 2 položky.",
            move: move,
            stamp: "předáno 6 položek · proti 9c1de02"
        )
    }

    private func hosting(_ view: OwnLoopView, width: Double = 900) -> NSHostingView<some View> {
        NSHostingView(rootView: view.frame(width: width))
    }

    /// **Kreslí se akce, a jen když je co volat.**
    ///
    /// **Že je tlačítko doopravdy na obrazovce, se v harnessu tvrdit nedá, a je to změřené**:
    /// SwiftUI `Button` v hostované hierarchii `NSButton` **není** (`firstDescendant(ofType:)`
    /// vrací `nil` i nad dráhou, která tlačítko kreslí) a `fittingSize.width` vyjde **stejná**
    /// s ním i bez něj — 435 bodů v obou případech, protože přirozenou šířku dráhy drží věta pod
    /// fázemi. Měřidlo, které vydá tutéž hodnotu pro „funguje“ i „nefunguje“, netvrdí nic (#478),
    /// takže se sem nepíše. Zbývá **pojmenované rozhodnutí** (`showsAction`, tentýž vzor jako
    /// `PullRequestRow.showsPromptAction`, #333) — a že se tlačítko kreslí, **ověřil člověk
    /// screenshotem** (patří to do popisu PR, jako u fokusu a kláves, #184).
    @Test("Akce aktivní stanice se kreslí, a jen když je co volat")
    func drawsTheActionOfTheActiveStation() {
        #expect(OwnLoopView(loop: loop(move: .openHandoff), perform: { _ in }).showsAction)
        // Bez uzávěru se nekreslí: tlačítko, které nic nedělá, je zrovna ten stav, ve kterém
        // člověk hledá, co je rozbité (tatáž úvaha jako u `Prompt →`, #333).
        #expect(!OwnLoopView(loop: loop(move: .openHandoff)).showsAction)
        // A stanice bez tahu (`Nálezy`, `Agent`, čekání na reviewera) nenabídne prázdné tlačítko.
        #expect(!OwnLoopView(loop: loop(move: nil), perform: { _ in }).showsAction)
    }

    /// Sedm kapslí vedle sebe se v hlavičce **nezalomí**: `ProportionalColumns` jim navrhuje
    /// konkrétní šířku, takže dráha zůstává tři řádky vysoká (hlavička, fáze, věta) i v úzkém okně.
    @Test("Sedm stanic se do hlavičky vejde na jeden řádek")
    func sevenStationsFitOnOneRow() {
        let wide = hosting(OwnLoopView(loop: loop(move: nil)), width: 1200).fittingSize.height
        let narrow = hosting(OwnLoopView(loop: loop(move: nil)), width: 620).fittingSize.height
        #expect(wide == narrow, "kapsle se v užším okně zalomily")
        #expect(narrow < 120, "dráha přerostla hlavičku: \(narrow)")
    }
}
