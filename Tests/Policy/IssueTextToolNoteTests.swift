import Foundation
import Testing

@testable import PRism

/// Co stojí pod polem `Jméno MCP nástroje` v nastavení (#389) a co se z něj uloží.
///
/// Čistá funkce, takže výčtem: tři stavy, a **dva z nich nejsou porucha**. Nejcennější tvrzení
/// v téhle sadě je to o **stejném měřítku** — věta pod polem se rozhoduje tou samou funkcí, kterou
/// se hodnota vyhodnocuje na cestě do běhu, takže nemůže nastat pole, pod kterým stojí „tahá se“,
/// a review, ve kterém se netahá.
@Suite("Policy — text issue z trackeru v nastavení (#389)")
struct IssueTextToolNoteTests {

    // MARK: - Tři stavy pole

    @Test("Prázdná hodnota znamená netahat, ne nedodělek")
    func blankMeansNotFetching() {
        for configured in [nil, "", " ", "\t", "\n", "   \n "] as [String?] {
            #expect(Policy.issueTextToolNote(for: configured) == .notFetching)
        }
        #expect(IssueTextTool.Note.notFetching.text == "Nevyplněno — text issue se netahá.")
        // Prázdno **není** varování: je to odpověď, a pole, u kterého vždycky něco svítí, se
        // přestane čítat.
        #expect(IssueTextTool.Note.notFetching.isWarning == false)
    }

    @Test("Jméno s prefixem mcp__ znamená, že se tahá")
    func aPrefixedNameFetches() {
        for configured in [
            "mcp__claude_ai_Linear__get_issue",
            "  mcp__jira__issue  ",
            "mcp__",
        ] {
            #expect(Policy.issueTextToolNote(for: configured) == .fetching, "\(configured)")
        }
        #expect(
            IssueTextTool.Note.fetching.text
                == "Tahá se — u PR s odkazem na issue běží session navíc."
        )
        #expect(IssueTextTool.Note.fetching.isWarning == false)
    }

    /// **Varování, ne zákaz.** Jméno je fakt o cizím stroji a aplikace ho neumí ověřit, dokud
    /// session neběží — uložit ho tedy jde a věta pod polem je jediné, co na to upozorní.
    @Test("Jméno bez prefixu je varování")
    func anUnprefixedNameWarns() {
        for configured in ["get_issue", "Linear__get_issue", "MCP__linear__get_issue", "mcp_x"] {
            #expect(Policy.issueTextToolNote(for: configured) == .unlikelyName, "\(configured)")
        }
        #expect(IssueTextTool.Note.unlikelyName.isWarning)
        #expect(IssueTextTool.Note.unlikelyName.text.contains("mcp__"))
    }

    /// Tři stavy jsou tři různé věty. Jedna věta se závorkou by znamenala, že se z okna nedá
    /// poznat, který z nich zrovna platí.
    @Test("Každý stav má vlastní větu")
    func everyStateHasItsOwnSentence() {
        let notes: [IssueTextTool.Note] = [.notFetching, .fetching, .unlikelyName]
        #expect(Set(notes.map(\.text)).count == notes.count)
        #expect(notes.allSatisfy { !$0.text.isEmpty })
    }

    // MARK: - Stejné měřítko jako na cestě do běhu

    /// Věta pod polem a rozhodnutí „pustit session“ musí vyjít z téže hodnoty. Kdyby se rozešly,
    /// okno by tvrdilo něco jiného, než co pak review udělá — a to je přesně ten druh rozdílu,
    /// který se pozná až po zaplacené session.
    @Test("Věta pod polem se řídí týmž měřítkem jako cesta do běhu")
    func theNoteAgreesWithTheRunPath() {
        for configured in [
            nil, "", "   ", "mcp__claude_ai_Linear__get_issue", " mcp__jira__issue ", "get_issue",
        ] as [String?] {
            let fetches = Policy.issueTextTool(from: configured) != nil
            #expect((Policy.issueTextToolNote(for: configured) == .notFetching) == !fetches)
        }
    }

    // MARK: - Co se z pole uloží

    @Test("Vymazané pole se uloží jako chybějící klíč")
    func anEmptyFieldStoresNothing() {
        #expect(Policy.issueTextToolEdit(typed: "") == nil)
    }

    /// Mezera napsaná do prázdného pole nesmí zmizet pod rukou — pole se překresluje z uložené
    /// hodnoty, takže zahozený bílý znak by se projevil jako nefunkční klávesa.
    @Test("Bílé znaky se ukládají tak, jak jsou napsané")
    func keepsWhitespaceAsTyped() {
        #expect(Policy.issueTextToolEdit(typed: " ") == " ")
        #expect(Policy.issueTextToolEdit(typed: "  mcp__x__y ") == "  mcp__x__y ")
        // A přitom se s takovou hodnotou netahá, protože měřítko je pořád jedno.
        #expect(Policy.issueTextToolNote(for: Policy.issueTextToolEdit(typed: " ")) == .notFetching)
    }

    @Test("Napsané jméno se uloží nedotčené")
    func storesTheTypedName() {
        #expect(Policy.issueTextToolEdit(typed: "mcp__jira__issue") == "mcp__jira__issue")
    }

    /// Vzor v prázdném poli je **vzor**, ne příklad z tohohle stroje: konkrétní jméno by vypadalo
    /// jako výchozí hodnota, kterou stačí potvrdit — a ta by byla tvrzením o cizím prostředí.
    @Test("Nápověda v prázdném poli je vzor, ne hodnota")
    func thePlaceholderIsAPattern() {
        #expect(IssueTextTool.namePattern.hasPrefix(IssueTextTool.prefix))
        #expect(IssueTextTool.namePattern.contains("<server>"))
        // Vzor sám by nastavením být nemohl: kdo ho opíše, dostane varování, ne tichý pokus.
        #expect(Policy.issueTextToolNote(for: IssueTextTool.namePattern) == .fetching)
    }
}
