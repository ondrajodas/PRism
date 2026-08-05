import Foundation
import Testing

@testable import PRism

/// Text notifikace o doběhlém review (#82).
///
/// Čistá funkce nad `ReviewState`, takže se nic nemockuje. To hlavní tady není, jak přesně
/// je věta formulovaná, ale že se **nesmí slít stavy, které znamenají opak** — „nic jsem
/// nenašel“ a „nemám co říct“ vypadají v datech podobně a v notifikaci by z druhého vyšel
/// schválený PR s neohlášenou chybou.
@Suite("Policy — notifikace o doběhlém review")
struct ReviewNotificationTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    private func body(_ state: ReviewState, blocking: Int = 0) -> String? {
        Policy.reviewNotification(for: pr, state: state, blocking: blocking)?.body
    }

    @Test("Nálezy nesou počet i to, kolik z nich blokuje")
    func reportsFindingsAndBlockingCount() {
        let text = body(.completed(findings: 3), blocking: 1)

        #expect(text == "3 nálezy, z toho 1 blokující.")
    }

    @Test("Nálezy bez blokujícího to řeknou taky")
    func saysWhenNothingBlocks() {
        // Bez té půlky věty by „3 nálezy“ vypadalo stejně vážně jako tři blokující —
        // a jestli je mezi nimi blokující, je zadání #82.
        #expect(body(.completed(findings: 3)) == "3 nálezy, nic blokujícího.")
    }

    @Test("Počet nálezů se skloňuje", arguments: [
        (1, "1 nález, nic blokujícího."),
        (2, "2 nálezy, nic blokujícího."),
        (4, "4 nálezy, nic blokujícího."),
        (5, "5 nálezů, nic blokujícího."),
        (11, "11 nálezů, nic blokujícího."),
    ])
    func inflectsTheFindingCount(count: Int, expected: String) {
        // Notifikace je krátký text, kde je špatné skloňování to jediné, co v ní je vidět.
        #expect(body(.completed(findings: count)) == expected)
    }

    @Test("Skloňuje se i blokující počet", arguments: [
        (1, "1 blokující"),
        (2, "2 blokující"),
        (4, "4 blokující"),
        (5, "5 blokujících"),
        (12, "12 blokujících"),
    ])
    func inflectsTheBlockingCount(blocking: Int, expected: String) {
        // U „blokující“ jsou tvary **dva**, ne tři: 1 i 2–4 vyjdou stejně a teprve od pěti se
        // mění. Původně se to skloňovalo jako „jednička proti ostatním“, z čehož vycházelo
        // „3 blokujících“ — chytil to Copilot na #131, takže je na to tabulka.
        #expect(body(.completed(findings: 20), blocking: blocking) == "20 nálezů, z toho \(expected).")
    }

    @Test("Čisté review je kratší, ale poznat se musí")
    func saysCleanExplicitly() {
        let text = body(.clean)

        #expect(text == "Reviewer nenašel žádný nález.")
    }

    @Test("Selhání nese důvod, se kterým se dá něco dělat")
    func carriesTheFailureReason() {
        let text = body(.failed(detail: "Session spadla na chybějícím skillu."))

        #expect(text == "Review se nepovedlo. Session spadla na chybějícím skillu.")
    }

    @Test("Nejistý výsledek se nesmí tvářit jako čistý")
    func doesNotPassOffAnInconclusiveRunAsClean() {
        // `Policy.reviewState` posílá nereportující běh do `failed` s vysvětlením — kdyby
        // notifikace řekla „nenašel žádný nález“, bylo by to schválené PR s neohlášenou
        // chybou. Tady se ověřuje, že se ta věta z Policy doopravdy propíše.
        let record = makeRecord(runs: [makeStoredRun(calledReportFindings: false)])
        let text = body(Policy.reviewState(for: record))

        #expect(text?.hasPrefix("Review se nepovedlo.") == true)
        #expect(text?.contains("nenahlásil") == true)
    }

    @Test("Ztracený nález se hlásí, ne schová")
    func reportsDroppedFindings() {
        let record = makeRecord(runs: [makeStoredRun(droppedFindings: 2)])
        let text = body(Policy.reviewState(for: record))

        #expect(text?.contains("nepodařilo přečíst") == true)
    }

    @Test("Timeout s nálezy řekne obojí")
    func saysBothOnTimeout() {
        // Zabitý běh mohl mít nálezy rozepsané, takže samotné „2 nálezy“ by tvrdilo víc,
        // než se stalo.
        let text = body(.timedOut(findings: 2), blocking: 1)

        #expect(text == "Review nedoběhlo do limitu. 2 nálezy, z toho 1 blokující.")
    }

    @Test("Timeout bez nálezů to řekne bez počtu")
    func saysTimeoutWithoutFindings() {
        #expect(body(.timedOut(findings: 0)) == "Review nedoběhlo do limitu a nic nenahlásilo.")
    }

    @Test("Odmítnuté nálezy nejsou totéž jako čisto")
    func distinguishesDismissedFromClean() {
        // „Našel a já to zamítl“ je jiné tvrzení než „nic nenašel“ (#113) a v notifikaci se
        // to nesmí slít.
        let text = body(.dismissed(findings: 2))

        #expect(text == "Zbyly jen nálezy, které jsi odmítl (2).")
        #expect(text != body(.clean))
    }

    @Test("Selhaný checkout se pozná od selhané session")
    func distinguishesCheckoutFailure() {
        let text = body(.checkoutFailed(detail: "Nejsi přihlášený v gh."))

        #expect(text == "Nepovedlo se připravit pracovní kopii. Nejsi přihlášený v gh.")
        #expect(text != body(.failed(detail: "Nejsi přihlášený v gh.")))
    }

    @Test("Stavy, které nejsou konec běhu, se neoznamují", arguments: [
        ReviewState.notStarted,
        .queued,
        .cloning,
        .running(finished: 1, total: 3),
        .stale,
    ])
    func staysQuietOnNonTerminalStates(state: ReviewState) {
        // `stale` je mezi nimi schválně: zastaralý záznam znamená, že během běhu přišel nový
        // commit, takže by notifikace posílala číst nálezy, které se vzápětí zneplatní.
        #expect(Policy.reviewNotification(for: pr, state: state) == nil)
    }

    @Test("Notifikace nese PR, kterého se týká, i v titulku")
    func carriesThePullRequest() {
        let notification = Policy.reviewNotification(for: pr, state: .clean)

        #expect(notification?.pullRequest == pr)
        #expect(notification?.title == "cli/cli#42")
    }

    @Test("Číslo PR se neformátuje přes locale")
    func doesNotGroupTheNumber() {
        // `Text("#\(number)")` by z #21663 udělalo „#21 663“ — číslo PR není množství.
        // Titulek jde přes `description` identifikátoru, takže se to stát nemůže; je na to
        // test, aby to tak zůstalo.
        let big = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 21663)

        #expect(Policy.reviewNotification(for: big, state: .clean)?.title == "cli/cli#21663")
    }

    @Test("Blokující se počítají jen z platných nálezů")
    func countsOnlyActiveFindings() {
        // Blokující nález, kterému nevěřím (#113), není důvod k vyrušení.
        let blocking = makeFinding(category: "correctness")
        var record = makeRecord(runs: [makeStoredRun(findings: [blocking.reported])])
        #expect(Policy.blockingCount(in: record) == 1)

        record.dismissals = makeDismissals(record.activeFindings)

        #expect(Policy.blockingCount(in: record) == 0)
    }

    @Test("Nálezy mimo blokující sadu se nepočítají")
    func ignoresNonBlockingCategories() {
        let record = makeRecord(runs: [
            makeStoredRun(findings: [makeReported(category: "style")]),
        ])

        #expect(Policy.blockingCount(in: record) == 0)
    }
}
