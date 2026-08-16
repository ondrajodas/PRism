import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Pořadí v `Přehledu` (#280): **řada faktů stojí nad kartou s popisem.**
///
/// Je to jediné, co #280 mění, a rozbije se to potichu — přehozený `VStack` build nepoloží,
/// testy na šířku (`OverviewWidthTests`) projdou v obou pořadích a na renderu si toho všimne jen
/// ten, kdo ví, že se to změnilo. Proto se to měří.
///
/// **Jak se to pozná z pixelů.** Řada faktů je mřížka čtyř dlaždic s mezerami 9 bodů mezi nimi
/// (`grid-template-columns: repeat(4, 1fr); gap: 9px`), takže ve svislém pruhu **mezi** dlaždicemi
/// se nekreslí nic. Karta s popisem je proti tomu jedna plocha přes celou šířku, takže v tomtéž
/// pruhu nakreslená **je**. Stačí tedy porovnat, kde v tom pruhu obsah začíná, s tím, kde začíná
/// uprostřed první dlaždice:
///
/// - uprostřed dlaždice → vrchol **řady faktů**,
/// - v mezeře mezi dlaždicemi → vrchol **karty s popisem**.
///
/// Fakta jsou nad popisem právě tehdy, když je první číslo menší než druhé. Ověřeno vloženou
/// regresí: po prohození obou prvků ve `VStacku` vyjdou obě čísla na 16 (plná plocha karty kreslí
/// v obou sloupcích) a suita spadne ve všech osmi šířkách.
///
/// **Měří se `OverflowProbe`m**, ne vlastní scénou — plátno, podklad i tolerance toho, co se počítá
/// za nakreslené, patří na jedno místo. Rozdíl proti `OverviewWidthTests` je jen v otázce: tam
/// „přeteklo něco vpravo“, tady „co je výš“. Oba sloupce se ptají **jedním** dotazem, protože
/// každý dotaz stojí dva rendery.
///
/// **Banner „od minule“ se schválně nekreslí** (`changes: .none`, `movedHead: nil`) — je to další
/// plocha přes celou šířku, takže by v pruhu mezi dlaždicemi začínal dřív než popis a měřilo by se
/// místo popisu on.
@MainActor
@Suite("Pořadí v Přehledu (#280)")
struct OverviewOrderTests {
    /// Tytéž šířky jako u měření přesahu — sazba se v každé zalomí jinak a pořadí má platit ve
    /// všech. Spodní kraj 128 je tab v okně na minimu s panelem vytaženým na maximum.
    private let widths: [CGFloat] = [128, 200, 320, 420, 560, 720, 900, 1180]

    @Test("Řada faktů začíná výš než karta s popisem")
    func factsSitAboveDescription() throws {
        for width in widths {
            let layout = try measure(width: width)
            #expect(
                layout.factsTop < layout.descriptionTop,
                """
                šířka \(Int(width)): fakta začínají na \(layout.factsTop), \
                popis na \(layout.descriptionTop) — řada faktů musí být nad popisem
                """
            )
        }
    }

    /// Pojistka proti tomu, že by měření vracelo nesmysl a test byl zelený omylem: obě hodnoty
    /// musí být **nalezené**, ne „nic se nenakreslilo“ (`nil`), a musí se lišit.
    @Test("Obě části se v renderu doopravdy najdou")
    func bothPartsArePainted() throws {
        for width in widths {
            let layout = try measure(width: width)
            #expect(layout.factsTop >= 0, "šířka \(Int(width)): řada faktů se nenašla")
            #expect(layout.descriptionTop >= 0, "šířka \(Int(width)): karta s popisem se nenašla")
        }
    }

    // MARK: - Měření

    private struct Layout {
        /// První nakreslený řádek uprostřed první dlaždice.
        var factsTop: Int
        /// První nakreslený řádek v mezeře mezi první a druhou dlaždicí.
        var descriptionTop: Int
    }

    private func measure(width: CGFloat) throws -> Layout {
        // Obsah je odsazený o 16 bodů (`.padding(16)`), takže mřížka začíná až za nimi.
        let inset: CGFloat = 16
        let tileWidth = (width - 2 * inset - 3 * Self.tileSpacing) / 4

        // Oba sloupce jedním dotazem — jinak by se totéž plátno vykreslilo dvakrát.
        let rows = try OverflowProbe(width: width).firstPaintedRows(
            of: Self.overview.content,
            atColumns: [
                inset + tileWidth / 2,
                inset + tileWidth + Self.tileSpacing / 2,
            ]
        )
        return Layout(factsTop: rows[0], descriptionTop: rows[1])
    }

    /// Mezera mezi dlaždicemi z návrhu (`gap: 9px`) i z `PullRequestFactsView`.
    private static let tileSpacing: CGFloat = 9

    // MARK: - Scéna

    private static let overview = OverviewView(
        description: description,
        facts: facts,
        lastVisit: Date(timeIntervalSince1970: 1_754_000_000),
        pullRequest: pullRequest
    )

    private static let pullRequest = PullRequestSummary(
        id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 14013),
        title: "Route autolink requests through api.Client",
        author: "williammartin",
        url: URL(string: "https://github.com/cli/cli/pull/14013")!,
        updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
        state: .open
    )

    private static let description = """
        ## Popis

        Odstavec s **tučným**, `inline kódem` a [odkazem](https://github.com), dost dlouhý na to,
        aby se v úzkém tabu zalomil na několik řádků.

        - první odrážka
        - [x] hotová položka
        """

    private static let facts = PullRequestFacts(
        tiles: [
            .init(caption: "Commity", value: "12", note: "3 nové"),
            .init(caption: "Soubory", value: "8", note: "2 s nálezem"),
            .init(caption: "Hlava", value: "abc1234", isMonospaced: true),
            .init(caption: "Nálezy proti", value: "def5678", isMonospaced: true, isStale: true),
        ]
    )
}
