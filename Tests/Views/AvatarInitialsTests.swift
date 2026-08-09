import Foundation
import Testing

@testable import PRism

/// Iniciály v kolečku u autora (#198).
///
/// Co se dá pokazit potichu: **vzít jen první dvě písmena**. Z `ErikZigo` pak vyjde `ER` — druhé
/// jméno se ztratí a dva lidé se stejným začátkem přezdívky mají v okně totéž kolečko.
@Suite("Iniciály autora")
struct AvatarInitialsTests {
    @Test("Velké písmeno uvnitř začíná nové slovo")
    func splitsOnCamelCase() {
        #expect(AvatarView.words(in: "ErikZigo") == ["Erik", "Zigo"])
    }

    @Test("Dělí se i na oddělovačích")
    func splitsOnSeparators() {
        #expect(AvatarView.words(in: "github-actions[bot]") == ["github", "actions", "bot"])
    }

    /// Zkratka na začátku se nesmí rozpadnout po písmenech — velké písmeno začíná slovo jedině
    /// po malém.
    @Test("Zkratka zůstane jedním slovem")
    func keepsAnAcronymTogether() {
        #expect(AvatarView.words(in: "GHActions") == ["GHActions"])
    }

    @Test("Jednoslovná přezdívka zůstane celá")
    func keepsASingleWord() {
        #expect(AvatarView.words(in: "odinuv") == ["odinuv"])
    }

    @Test("Prázdné jméno nedá žádné slovo")
    func handlesAnEmptyLogin() {
        #expect(AvatarView.words(in: "").isEmpty)
    }
}
