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

        #expect(text == "Odmítl jsi 2 nálezy a nic jiného nezbylo.")
        #expect(text != body(.clean))
    }

    @Test("Věta o odmítnutých unese i jediný nález")
    func inflectsTheDismissedCount() {
        // Původní formulace („Zbyly jen nálezy, které jsi odmítl (1)“) mluvila o jednom
        // nálezu v množném čísle — tatáž třída chyby jako u blokujících, jen ji tady neřeší
        // skloňování slova, ale to, jak je věta postavená.
        #expect(body(.dismissed(findings: 1)) == "Odmítl jsi 1 nález a nic jiného nezbylo.")
        #expect(body(.dismissed(findings: 8)) == "Odmítl jsi 8 nálezů a nic jiného nezbylo.")
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

extension ReviewNotificationTests {
    private func event(_ state: ReviewState) -> NotificationEvent? {
        Policy.reviewNotification(for: pr, state: state)?.event
    }

    @Test("Timeout s nálezy je o nálezech, bez nich je to selhání")
    func splitsTimeoutByWhetherItDelivered() {
        // Do #133 padal celý `timedOut` do `findings`, takže kdo si vypnul `Review se nepovedlo`,
        // dostával notifikaci o běhu, který nedoběhl a **nic nenahlásil** — a to je selhání,
        // ne nález. Chytil to Copilot na rozporu mezi textem v nastavení a mapováním.
        #expect(event(.timedOut(findings: 2)) == .findings)
        #expect(event(.timedOut(findings: 0)) == .failure)
    }

    @Test("Události odpovídají tomu, co notifikace říká", arguments: [
        (ReviewState.completed(findings: 1), NotificationEvent.findings),
        (.clean, .clean),
        (.dismissed(findings: 2), .clean),
        (.failed(detail: "spadlo to"), .failure),
        (.checkoutFailed(detail: "clone selhal"), .failure),
    ])
    func mapsStatesToEvents(state: ReviewState, expected: NotificationEvent) {
        // Odmítnuté nálezy jsou z pohledu vyrušení totéž jako čisto: nezbylo nic k řešení.
        #expect(event(state) == expected)
    }

    @Test("Co se neohlašuje, nemá ani událost")
    func hasNoEventWhenThereIsNothingToSay() {
        // Text a událost si musí odpovídat — obojí vychází z téhož `ReviewState`, takže kdyby se
        // množiny rozešly, vznikla by notifikace bez události nebo naopak.
        for state in [ReviewState.notStarted, .queued, .cloning, .running(finished: 1, total: 2), .stale] {
            #expect(Policy.reviewNotification(for: pr, state: state) == nil)
        }
    }
}

/// Seskupování notifikací (#87).
///
/// Čistá funkce, takže **bez čekání v reálném čase** — a to je i důvod, proč se slévá nad
/// seznamem z jednoho tiku a ne přes vlastní okno: zadání chce test bez zdržení.
@Suite("Policy — seskupování notifikací")
struct NotificationGroupingTests {
    private func pr(_ text: String) -> PRIdentifier { PRIdentifier(text)! }

    private func notification(_ ids: [String], titles: [String: String] = [:]) -> PullRequestNotification? {
        Policy.newPullRequestsNotification(
            for: ids.map(pr),
            titles: Dictionary(uniqueKeysWithValues: titles.map { (pr($0.key), $0.value) })
        )
    }

    @Test("Jedno PR dá plnou hlášku s titulkem, ne souhrn")
    func aSinglePullRequestKeepsItsTitle() {
        // „1 nový PR k review“ říká **méně** než jeho název.
        let result = notification(["cli/cli#1"], titles: ["cli/cli#1": "Opravit součet"])

        #expect(result?.title == "Nový PR k review — cli/cli#1")
        #expect(result?.body == "Opravit součet")
    }

    @Test("Tři PR dají jednu notifikaci, ne tři")
    func threePullRequestsBecomeOne() {
        let result = notification(["cli/cli#1", "cli/cli#2", "b/b#7"])

        #expect(result?.title == "3 nové PR k review")
        #expect(result?.body == "cli/cli#1, cli/cli#2, b/b#7")
    }

    @Test("Souhrn skloňuje počet", arguments: [
        (2, "2 nové PR k review"),
        (4, "4 nové PR k review"),
        (5, "5 nových PR k review"),
        (12, "12 nových PR k review"),
    ])
    func inflectsTheSummaryCount(count: Int, expected: String) {
        let ids = (1 ... count).map { "cli/cli#\($0)" }

        #expect(notification(ids)?.title == expected)
    }

    @Test("Dlouhý seznam se zkrátí a řekne kolik zbývá")
    func shortensALongList() {
        // Notifikace má dva řádky, takže se vypíšou tři jménem a zbytek spočítá. Počet je ta
        // informace, podle které se pozná, jestli se do fronty jít podívat hned.
        let ids = (1 ... 7).map { "cli/cli#\($0)" }

        let result = notification(ids)

        #expect(result?.body == "cli/cli#1, cli/cli#2, cli/cli#3 a 4 další")
    }

    @Test("Zbytek se skloňuje taky")
    func inflectsTheRemainder() {
        let ids = (1 ... 9).map { "cli/cli#\($0)" }

        #expect(notification(ids)?.body.hasSuffix("a 6 dalších") == true)
    }

    @Test("Klik na souhrn vybere první PR")
    func clickingASummarySelectsTheFirst() {
        // Nevybrat nic by znamenalo kliknutí, po kterém se nestane nic; seznam je řazený od
        // naposledy změněného, takže první je ten, u kterého má smysl začít.
        let result = notification(["cli/cli#9", "cli/cli#1"])

        #expect(result?.pullRequest == pr("cli/cli#9"))
    }

    @Test("Prázdný seznam nedá nic")
    func nothingForAnEmptyList() {
        #expect(notification([]) == nil)
    }

    @Test("Nový výsledek review přepíše ten starý, hlášku o novém PR ne")
    func replacesOnlyWithinTheSameGroup() {
        // Výsledek review nad PR je **jeden** a nový ho přepíše, ať byl předchozí jakýkoli —
        // jinak by po opakovaném běhu zůstala vedle „3 nálezy“ viset stará hláška „nenašel
        // žádný nález“, tedy tvrzení, které už neplatí. Tenhle test původně tvrdil opak
        // a chytil vadu v návrhu identity.
        let clean = Policy.reviewNotification(for: pr("cli/cli#1"), state: .clean)!
        let findings = Policy.reviewNotification(for: pr("cli/cli#1"), state: .completed(findings: 2))!
        let failure = Policy.reviewNotification(for: pr("cli/cli#1"), state: .failed(detail: "spadlo"))!
        let newcomer = notification(["cli/cli#1"])!

        #expect(clean.identifier == findings.identifier)
        #expect(findings.identifier == failure.identifier)
        // Že PR přišel a jak dopadlo jeho review, jsou dvě různé informace.
        #expect(newcomer.identifier != clean.identifier)
        // A hláška o jiném PR nesmí přepsat nic z toho.
        #expect(Policy.reviewNotification(for: pr("cli/cli#2"), state: .clean)!.identifier != clean.identifier)
    }

    @Test("Vlákno je podle PR, ať systém řadí jeho hlášky k sobě")
    func threadsByPullRequest() {
        // Podle PR, ne podle repa: u firemního monorepa by seskupení po repu slilo věci, které
        // spolu nemají nic společného.
        let review = Policy.reviewNotification(for: pr("cli/cli#1"), state: .clean)!
        let newcomer = notification(["cli/cli#1"])!
        let elsewhere = Policy.reviewNotification(for: pr("cli/cli#2"), state: .clean)!

        #expect(review.threadIdentifier == newcomer.threadIdentifier)
        #expect(review.threadIdentifier != elsewhere.threadIdentifier)
    }
}
