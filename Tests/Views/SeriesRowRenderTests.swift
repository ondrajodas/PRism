import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Série v řádku seznamu (#513) — **co se dá tvrdit měřením**.
///
/// Řádek fronty je úzký a od #509 se v něm o místo dělí mapa PR, tečky dráhy, pilulka a `Prompt →`.
/// Pilulka série je do toho **další** prvek, takže se musí změřit, že se pořád vejde: kdyby ne,
/// ustoupil by titulek, tedy to jediné, podle čeho se PR v seznamu pozná. Měří se `fittingSize`
/// mimo obrazovku, jako u `OwnLoopRowRenderTests`.
@Suite("Série v řádku seznamu (#513)")
@MainActor
struct SeriesRowRenderTests {
    /// Pilulka řádek **nezvýší**: je to tatáž kapsle jako odznak vedle ní.
    @Test("Pilulka série výšku řádku nezvedne")
    func doesNotGrowTheRow() {
        #expect(height(of: row(series: placement())) == height(of: row(series: nil)))
    }

    /// 636 bodů je obsah nejužšího okna bez railu — tam se pilulka tluče o místo s titulkem
    /// a mapou PR.
    @Test("V nejužším okně zůstává řádek se sérií na jedné řádce")
    func fitsTheNarrowestWindow() {
        let narrow = height(of: row(series: placement()), width: 636)
        let wide = height(of: row(series: placement()), width: 900)

        #expect(narrow == wide, "v 636 b vyšlo \(narrow), v 900 b \(wide)")
        #expect(narrow == height(of: row(series: nil), width: 636))
    }

    /// **Nejtěsnější kombinace v celém okně**: vlastní PR v sérii, tedy pilulka série, tečky dráhy
    /// (#509), slovo k aktivní stanici a `Prompt →` v jedné řádce. Tohle je ten případ, který
    /// vznikl slitím dvou větví a který by se od oka neodhalil.
    @Test("Vlastní řádek unese sérii i dráhu naráz")
    func fitsAlongsideTheLoop() {
        let loop = OwnLoopRow(
            dots: OwnLoop.Station.allCases.map { .init(station: $0, state: .idle) },
            word: "Push o 4 vzadu",
            tone: .running
        )

        let both = height(of: row(series: placement(), loop: loop), width: 636)

        // **Proti téže řádce bez série**, ne proti cizímu řádku: ten je nižší, protože nemá ani
        // tečky, ani `Prompt →`. Tvrdí se tu jedna věc — pilulka série do toho nejtěsnějšího
        // uspořádání **nic nepřidá**.
        #expect(both == height(of: row(series: nil, loop: loop), width: 636))
    }

    /// Popisek je **jedna řádka navíc nad řádkem**, ne roztažený řádek: řádek pod ním musí zůstat
    /// stejně vysoký jako kterýkoli jiný.
    @Test("Popisek přidá jednu řádku a řádek nechá být")
    func addsOneLineAbove() {
        let plain = height(of: row(series: placement()), width: 636)
        let captioned = height(
            of: row(series: placement(), caption: "série · AJDA-563 · 2 PR · review v pořadí ↓"),
            width: 636
        )

        #expect(captioned > plain)
        // Jedna řádka mono 10 s odsazením 6 + 2, změřeno **21 bodů**. Strop je nad tím jen
        // s rezervou na metriku písma: dvě řádky by znamenaly, že se popisek zalomil.
        #expect(captioned - plain <= 26, "popisek přidal \(captioned - plain) b")
    }

    /// Řádek **bez série** se nesmí pohnout ani o bod: odsazení pro přerušovanou čáru se přidává
    /// jedině členovi skupiny, jinak by se celá fronta posunula doprava.
    @Test("Řádek mimo sérii se neposune")
    func leavesOtherRowsAlone() {
        let hosting = NSHostingView(rootView: row(series: nil).frame(width: 636))
        let withSeries = NSHostingView(rootView: row(series: placement()).frame(width: 636))

        #expect(hosting.fittingSize.height == withSeries.fittingSize.height)
    }
}

// MARK: - Pomocné

extension SeriesRowRenderTests {
    private func placement(
        position: Int = 2,
        standsOn: String? = "cli/cli#14451"
    ) -> SeriesPlacement {
        SeriesPlacement(
            position: position,
            count: 2,
            standsOn: standsOn.map { PRIdentifier($0)! },
            standsOnBase: "trunk"
        )
    }

    private func row(
        series: SeriesPlacement?,
        caption: String? = nil,
        loop: OwnLoopRow? = nil
    ) -> PullRequestRow {
        PullRequestRow(
            pullRequest: PullRequestSummary(
                id: PRIdentifier("cli/cli#14452")!,
                title: "Refreshable tokens (3/7): short-lived login, refresh, and git credential path",
                author: "babakks",
                url: URL(string: "https://github.com/cli/cli/pull/14452")!,
                updatedAt: Date(timeIntervalSince1970: 1_000_000),
                state: .open
            ),
            reviewState: .completed(findings: 1),
            row: QueueRow(blocking: 0),
            ownership: loop == nil ? .theirs : .mine,
            openPrompt: loop == nil ? nil : {},
            pending: 6,
            loop: loop,
            series: series,
            seriesCaption: caption
        )
    }

    private func height(of row: PullRequestRow, width: Double = 900) -> Double {
        NSHostingView(rootView: row.frame(width: width)).fittingSize.height
    }
}
