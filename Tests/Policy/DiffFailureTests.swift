import Foundation
import Testing

@testable import PRism

/// Proč diff není — a jestli se to v okně dá odlišit (#542).
///
/// Do #542 měly všechny příčiny jednu větu, takže z okna nešlo poznat, jestli je pull request nad
/// stropem GitHubu, jestli vypršel token, nebo jestli je repo nedostupné. Sada je proto z půlky
/// o tom, že se **strop pozná**, a z půlky o tom, že se **nepozná nikde jinde**: každá ostatní
/// chyba musí projít beze změny do věty, kterou nese `GitHubError`.
///
/// Odpověď je **skutečná** — `gh pr diff` nad `home-assistant/core#181088` (3 632 souborů),
/// fixture `gh/pr-diff-too-large.txt`. Vymyšlený literál by tady netvrdil nic: celé rozpoznání
/// stojí na znění, které píše GitHub, ne my.
@Suite("Policy — selhání diffu (#542)")
struct DiffFailureTests {
    private func response() throws -> String { try Fixture.text("gh/pr-diff-too-large.txt") }

    /// Chyba tak, jak vznikne na té cestě, kterou aplikace doopravdy jde: `gh` skončí nenulově
    /// a `GitHubError` si výstup zařadí sám.
    private func error(from stderr: String, exitCode: Int32 = 1) -> GitHubError {
        GitHubError(failure: ProcessResult(exitCode: exitCode, standardOutput: "", standardError: stderr))
    }

    // MARK: - Rozpoznání

    @Test("Strop se pozná ze skutečné odpovědi gh")
    func capIsRecognisedFromTheRealResponse() throws {
        let failure = Policy.diffFailure(error(from: try response()))

        guard case .tooManyFiles(let limit, let text) = failure else {
            Issue.record("Čekal jsem strop, přišlo \(failure)")
            return
        }
        #expect(limit == 300)
        // Syrová odpověď projde celá — je to jediné, z čeho se pozná, o který pull request šlo.
        #expect(text.contains("HTTP 406"))
        #expect(text.contains("home-assistant/core/pulls/181088"))
    }

    /// **Tohle je ten test, kvůli kterému číslo neleží v konstantě.** Tři sta je dnešní hodnota
    /// GitHubu, ne naše rozhodnutí; kdyby se pohnula, má se pohnout i věta v okně.
    @Test("Strop je číslo z odpovědi, ne konstanta v aplikaci")
    func capIsReadFromTheResponse() throws {
        let moved = try response().replacingOccurrences(of: "(300)", with: "(500)")

        #expect(Policy.diffFileCap(inResponse: moved) == 500)
    }

    /// Počet souborů aplikace v tu chvíli **nezná** — dozvěděla by se ho z toho diffu, který
    /// nedorazil. Odpověď bez čísla je proto pořád strop, jen bez čísla ve větě.
    @Test("Odpověď bez čísla je pořád strop, jen se v ní číslo netvrdí")
    func capWithoutANumberIsStillTheCap() throws {
        let vague = try response().replacingOccurrences(of: " (300)", with: "")
        let failure = Policy.diffFailure(error(from: vague))

        guard case .tooManyFiles(let limit, _) = failure else {
            Issue.record("Čekal jsem strop, přišlo \(failure)")
            return
        }
        #expect(limit == nil)
        // A věta o tom nesmí vymyslet číslo, které v odpovědi nebylo.
        let message = Policy.diffFailureNotice(failure).message ?? ""
        let claimsANumber = message.contains(where: \.isNumber)
        #expect(!claimsANumber)
    }

    /// V téže hlášce stojí i `(https://api.github.com/…)`. Kdyby o výsledku rozhodovalo pořadí
    /// závorek, vydala by tahle odpověď číslo z URL — nebo `nil` jen shodou okolností.
    @Test("Závorka s adresou se za strop nepovažuje")
    func theURLInParenthesesIsNotTheCap() throws {
        let vague = try response().replacingOccurrences(of: " (300)", with: "")

        #expect(vague.contains("(https://api.github.com"))
        #expect(Policy.diffFileCap(inResponse: vague) == nil)
    }

    /// Adresu by odmítl i `Int`, znaménko ne. Záporný strop by v okně dal větu „GitHub vydá diff
    /// nejvýš pro −5 souborů“ — tedy číslo, které se tváří jako přečtené, a přitom nedává smysl.
    @Test("Číslo se znaménkem se za strop nepovažuje")
    func aSignedNumberIsNotTheCap() throws {
        for odd in ["(-5)", "(+300)", "( 300)", "()"] {
            let broken = try response().replacingOccurrences(of: "(300)", with: odd)
            #expect(Policy.diffFileCap(inResponse: broken) == nil, "\(odd) nemá být strop")
        }
    }

    /// Rozpoznání se **nesmí vázat na třídu chyby**: `GitHubError` třídí podle znění a `gh` ho
    /// měnit může. Kdyby GitHub jednou napsal `not found` do téže věty, byl by z toho `notFound`
    /// — a strop by přestal být vidět, aniž by o tom kdokoli věděl.
    @Test("Strop se pozná i tehdy, když chyba spadne do jiné třídy")
    func capIsRecognisedRegardlessOfTheErrorClass() throws {
        let text = try response()

        for error in [GitHubError.notFound(text), .rateLimited(text), .malformedOutput(text)] {
            guard case .tooManyFiles = Policy.diffFailure(error) else {
                Issue.record("Čekal jsem strop u \(error)")
                continue
            }
        }
    }

    // MARK: - Co stropem není

    /// Vyčerpávající výčet: co strop není, musí projít beze změny do věty od `GitHubError`
    /// a nabídnout druhý pokus. Právě tohle se do #542 dělo **i** u stropu.
    @Test("Ostatní selhání zůstávají obecná a nabízejí druhý pokus")
    func otherFailuresKeepTheirSentence() {
        let others: [GitHubError] = [
            .notAuthenticated,
            .timedOut,
            .network("bez sítě"),
            .rateLimited("za hodinu"),
            .notFound("Could not resolve to a PullRequest"),
            .toolUnavailable("Permission denied"),
            .malformedOutput("nečekaný JSON"),
            .commandFailed(exitCode: 1, message: "něco jiného"),
        ]

        for error in others {
            let failure = Policy.diffFailure(error)
            #expect(failure == .other(error.userDescription))

            let notice = Policy.diffFailureNotice(failure)
            #expect(notice.title == "Diff se nepodařilo načíst")
            // Věta se nevymýšlí: co se stalo, ví jedině syrová odpověď pod ní.
            #expect(notice.message == nil)
            #expect(notice.detail == error.userDescription)
            #expect(notice.action == .retry)
        }
    }

    @Test("Prázdný text stropem není")
    func emptyResponseIsNotTheCap() {
        #expect(Policy.diffFileCap(inResponse: "") == nil)
        #expect(Policy.diffFailure(.network("")) == .other(GitHubError.network("").userDescription))
    }

    // MARK: - Co se o tom napíše

    @Test("U stropu se nenabízí druhý pokus, protože vrátí totéž")
    func theCapOffersGitHubInsteadOfARetry() throws {
        let notice = Policy.diffFailureNotice(Policy.diffFailure(error(from: try response())))

        #expect(notice.title == "Diff je nad stropem GitHubu")
        #expect(notice.action == .openOnGitHub)
        // Číslo z odpovědi patří do věty — bez něj by z ní nešlo poznat, kde ten strop je.
        #expect(notice.message?.contains("300") == true)
        // A druhá půlka té zprávy: **zbytek pull requestu se číst dá**. Bez ní vypadá prázdná
        // plocha jako „tenhle pull request se nedá otevřít“.
        #expect(notice.message?.contains("chybí jen ten") == true)
        #expect(notice.detail.contains("HTTP 406"))
    }
}
