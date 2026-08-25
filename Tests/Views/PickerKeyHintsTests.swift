import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Patka s nápovědou kláves — **rozměr, ne pravidlo** (#434).
///
/// Pravidlo (kdy se patka vůbec kreslí) je čistá funkce a testuje ho `PickerSearchTests`; tady se
/// měří, že se **nejdelší kombinace vejde do 300 bodů**, což je šířka `.pkr` z návrhu. Odhad by na
/// to nestačil: u #413 vyšla rezerva u patky potvrzení na 39 bodů proti 41 nakresleným, tedy
/// v řádu jednoho slova.
///
/// Měří se **dvěma měřidly a každé odpovídá na jinou otázku**. `fittingSize` řekne, **kolik místa
/// si patka řekne** — z toho je vidět rezerva, tedy o kolik se smí písmo nebo sloveso protáhnout.
/// `OverflowProbe` řekne, jestli něco **přeteklo za hranu** popoveru, a to je jediná otázka, na
/// kterou `fittingSize` u nabídky labelů odpovědět neumí: ta má pevný rámec 300 bodů, takže obsah
/// za ním přeteče **vizuálně**, aniž by se velikost změnila.
@MainActor
@Suite("Nápověda kláves v nabídce (#434)")
struct PickerKeyHintsTests {
    /// Šířka `.pkr` z návrhu.
    private let width = 300.0

    /// Obě slovesa, která se do patky dosazují — nejdelší kombinace je jedno z nich.
    /// `nonisolated`, protože `arguments:` se vyhodnocuje mimo actor.
    nonisolated static let verbs = ["přepne", "vyžádá"]

    /// **Rezerva se vypíše, ne jen „vešlo se“** — z čísla je vidět, o kolik se smí sloveso nebo
    /// písmo protáhnout, a při spadnutí je z hlášky poznat, o kolik to přeteklo. Mez je jediná
    /// a je to ta z návrhu: víc než 300 bodů nabídka nemá.
    @Test("Patka se vejde do šířky popoveru", arguments: verbs)
    func theHintsFitTheWidth(verb: String) {
        let measured = NSHostingView(rootView: PickerKeyHints(confirm: verb)).fittingSize.width

        print("MĚŘENÍ patka „\(verb)“: \(measured) b, rezerva \(width - measured) b")
        #expect(measured <= width, "patka „\(verb)“ potřebuje \(measured) z \(width)")
    }

    /// Nabídka labelů má **pevný rámec 300 bodů**, takže se na přesah musí koukat pixely.
    /// Prohání se i stavem, ve kterém je pod seznamem akce `Založit „…“` — tam je patka poslední
    /// prvek a nemá pod sebou nic, co by přesah ukrojilo.
    @Test("Nabídka labelů s patkou nepřeteče popover", arguments: ["", "design-debt"])
    func theLabelPickerDoesNotOverflow(query: String) throws {
        let probe = OverflowProbe(width: width, height: 500, name: "patka-labely-\(query.count)")

        #expect(try probe.overflow(of: Self.labelPicker(query: query)) == 0)
    }

    /// Nabídka reviewerů si šířku **neurčuje rámcem** (na rozdíl od nabídky labelů, která má
    /// pevných 300) — sází se podle nejširšího prvku. **Patka jím od #434 je**, a je to změřené,
    /// ne odhadnuté: nadpis `VYŽÁDAT REVIEW OD` chce 145 b, patka 195 b, takže se přirozená šířka
    /// nabídky posunula ze 145 na 195.
    ///
    /// **Není to regrese, je to podlaha** — návrh kreslí `.pkr` na 300 bodech, takže užší nabídka
    /// je odchylka od zákresu na tu druhou stranu a 195 je jí blíž. Tvrdí se proto to, co skutečně
    /// platit musí: patka nesmí nabídku přetáhnout **za** těch 300.
    @Test("Patka nepřetáhne nabídku reviewerů za šířku ze zákresu")
    func theHintsKeepTheReviewerPickerWithinTheDesign() {
        let picker = NSHostingView(rootView: Self.reviewerPicker).fittingSize.width
        let hints = NSHostingView(rootView: PickerKeyHints(confirm: "vyžádá")).fittingSize.width

        print("MĚŘENÍ nabídka reviewerů: \(picker) b, patka \(hints) b")
        #expect(picker <= width, "nabídka má \(picker) z \(width)")
        #expect(hints <= picker, "patka (\(hints)) je širší než nabídka (\(picker))")
    }

    // MARK: - Scéna

    /// Skutečné labely z `cli/cli`, jako v ostatních sondách nad nabídkou.
    private static let known = [
        PullRequestLabel(name: "bug", color: "d73a4a"),
        PullRequestLabel(name: "bug-ui-legacy", color: "d73a4a"),
        PullRequestLabel(name: "dependencies", color: "0366d6"),
        PullRequestLabel(name: "enhancement", color: "a2eeef"),
        PullRequestLabel(name: "go", color: "16e2e2"),
        PullRequestLabel(name: "needs-design-review", color: "d4c5f9"),
        PullRequestLabel(name: "ready-for-review", color: "39d965"),
    ]

    @MainActor private static func labelPicker(query: String) -> some View {
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

    /// Skutečné loginy a slugy z `orgs/keboola` — čtrnáct řádků je ten stav, kvůli kterému
    /// v nabídce je hledání i nápověda kláves.
    @MainActor private static var reviewerPicker: some View {
        let people = [
            "adamvoves", "BagToad", "dasa-novakova", "ErikZigo", "halinapetrikova",
            "jirkanovak", "odinuv", "petramala", "sergiou87", "tomaskraus",
        ]
        return ReviewerPickerView(
            candidates: people.map { .person($0) } + ["ajda-swimlane", "platform"].map { .team($0) },
            isLoaded: true,
            request: { _ in },
            load: {}
        )
    }
}
