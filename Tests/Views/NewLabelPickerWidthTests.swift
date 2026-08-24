import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Nabídka se zakládáním labelu — **rozměr, ne pravidlo** (#413).
///
/// Pravidlo (kdy se akce nabídne) je v `NewLabelOfferTests`; tady se měří, že se to do popoveru
/// **vejde**. Zákres má naměřené rezervy na 300 bodech (`.pkr`) a nejdelší řádek potvrzení je podle
/// něj 265 b z 278, tedy 13 bodů — na takovou rezervu se odhadem spoléhat nedá.
///
/// **Měří se pixely za hranou, ne `fittingSize`** (`OverflowProbe`, viz jeho hlavička): popover má
/// pevný rámec 300 bodů, takže obsah, který se do něj nevejde, přeteče **vizuálně**, aniž by se
/// rámec změnil — a rodič, kterého by se šlo zeptat na velikost, o tom neví.
///
/// Dlouhé jméno je tady schválně na **39 znacích**: to je to, na čem se měřil zákres (dva řádky
/// a nic za okrajem). Akce jméno **zalomí, neořeže** — je to jediné místo před potvrzením, kde je
/// jméno vidět celé.
@MainActor
@Suite("Šířka nabídky se zakládáním labelu (#413)")
struct NewLabelPickerWidthTests {
    /// Šířka `.pkr` z návrhu. Nabídka ji má pevnou, aby obě obrazovky byly stejně široké.
    private let width = 300.0

    private static let known = [
        PullRequestLabel(name: "bug", color: "d73a4a"),
        PullRequestLabel(name: "bug-ui-legacy", color: "d73a4a"),
        PullRequestLabel(name: "dependencies", color: "0366d6"),
        PullRequestLabel(name: "enhancement", color: "a2eeef"),
        PullRequestLabel(name: "go", color: "16e2e2"),
        PullRequestLabel(name: "needs-design-review", color: "d4c5f9"),
        PullRequestLabel(name: "ready-for-review", color: "39d965"),
    ]

    /// Jména, kterými se to má prohnat: krátké, to ze zákresu a pak 39 znaků, na kterých se zákres
    /// měřil. Dvě z nich vyjdou na jeden řádek, poslední na dva.
    nonisolated static let names = [
        "x",
        "design-debt",
        "needs-design-review-and-product-signof",
    ]

    /// Akce `Založit „…“` **nesmí přetéct**, ani když se jméno zalomí na dva řádky. Leží mimo
    /// `ScrollView`, takže by přesah nikdo neukrojil — bylo by ho vidět přes hranu popoveru.
    @Test("Akce k založení se vejde do popoveru", arguments: names)
    func theCreateActionFits(name: String) throws {
        let probe = OverflowProbe(width: width, height: 400, name: "zalozit-\(name.count)")

        #expect(try probe.overflow(of: Self.picker(query: name)) == 0)
    }

    /// Potvrzení má nejdelší řádek v návrhu (barva s hexem) a k němu patku se dvěma tlačítky.
    @Test("Potvrzení se vejde do popoveru", arguments: names)
    func theConfirmationFits(name: String) throws {
        let probe = OverflowProbe(width: width, height: 400, name: "potvrzeni-\(name.count)")

        #expect(try probe.overflow(of: Self.confirmation(of: name)) == 0)
    }

    // Spočítané tvrzení o nejdelším řádku potvrzení (barva s hexem, v návrhu 265 b z 278) tady
    // **schválně není**. Měřilo by ho vlastním `NSFont`em opsaným z `LabelPickerView`, tedy druhou
    // pravdou o jedné velikosti — a po doladění písma v potvrzení by zůstalo zelené nad řádkem, který
    // se nevejde (pravidlo #236, tatáž past, kvůli které existuje `MiniButtonStyle.labelFont(of:)`).
    // Vytáhnout ta dvě písma na jedno místo kvůli jednomu tvrzení nemá cenu: pixelová sonda výš měří
    // tu samou věc **na tom, na čem se doopravdy kreslí**.

    // MARK: - Scéna

    @MainActor private static func picker(query: String) -> some View {
        LabelPickerView(
            repo: RepoID(owner: "ondrajodas", name: "PRism"),
            known: known,
            selected: [],
            isLoaded: true,
            toggle: { _ in },
            create: { _ in },
            load: {},
            query: query
        )
    }

    @MainActor private static func confirmation(of name: String) -> some View {
        LabelPickerView(
            repo: RepoID(owner: "ondrajodas", name: "PRism"),
            known: known,
            selected: [],
            isLoaded: true,
            toggle: { _ in },
            create: { _ in },
            load: {},
            query: name,
            // Label z `Policy`, ne vypsaný v testu: sonda pak měří tu barvu, která doopravdy odejde.
            confirming: Policy.newLabelOffer(
                query: name,
                known: known,
                isLoaded: true,
                editing: .allowed
            )
        )
    }
}
