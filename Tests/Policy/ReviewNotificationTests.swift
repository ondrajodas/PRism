import Foundation
import Testing

@testable import PRism

/// Text notifikace o doběhlém review (#82, rozvržení #200).
///
/// Čistá funkce nad `ReviewState`, takže se nic nemockuje. To hlavní tady není, jak přesně
/// je věta formulovaná, ale že se **nesmí slít stavy, které znamenají opak** — „nic jsem
/// nenašel“ a „nemám co říct“ vypadají v datech podobně a v notifikaci by z druhého vyšel
/// schválený PR s neohlášenou chybou.
///
/// Od #200 se ověřují **dvě místa**: titulek (první řádek banneru, podle kterého se člověk
/// rozhoduje, jestli jde k počítači hned) a tělo (nález a pod ním PR).
@Suite("Policy — notifikace o doběhlém review")
struct ReviewNotificationTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    private func title(_ state: ReviewState, blocking: Int = 0) -> String? {
        Policy.reviewNotification(for: pr, state: state, blocking: blocking)?.title
    }

    private func body(
        _ state: ReviewState,
        blocking: Int = 0,
        topFinding: Finding? = nil
    ) -> String? {
        Policy.reviewNotification(
            for: pr,
            state: state,
            blocking: blocking,
            topFinding: topFinding
        )?.body
    }

    @Test("Titulek nese počet i to, kolik z nich blokuje")
    func reportsFindingsAndBlockingCount() {
        // Návrh (sekce 10) to má přesně takhle a je to celý smysl #200: podle titulku se
        // pozná, jestli jít k počítači hned.
        #expect(title(.completed(findings: 3), blocking: 1) == "3 nálezy · 1 blokuje")
    }

    @Test("Když nic neblokuje, řekne se i to")
    func saysWhenNothingBlocks() {
        // Bez druhé půlky by „3 nálezy“ vypadaly stejně vážně jako tři blokující —
        // a jestli je mezi nimi blokující, je zadání #82.
        #expect(title(.completed(findings: 3)) == "3 nálezy · nic neblokuje")
    }

    @Test("Počet nálezů se skloňuje", arguments: [
        (1, "1 nález · nic neblokuje"),
        (2, "2 nálezy · nic neblokuje"),
        (4, "4 nálezy · nic neblokuje"),
        (5, "5 nálezů · nic neblokuje"),
        (11, "11 nálezů · nic neblokuje"),
    ])
    func inflectsTheFindingCount(count: Int, expected: String) {
        // Notifikace je krátký text, kde je špatné skloňování to jediné, co v ní je vidět.
        #expect(title(.completed(findings: count)) == expected)
    }

    @Test("Skloňuje se i sloveso u blokujících", arguments: [
        (1, "1 blokuje"),
        (2, "2 blokují"),
        (4, "4 blokují"),
        (5, "5 blokuje"),
        (12, "12 blokuje"),
    ])
    func inflectsTheBlockingVerb(blocking: Int, expected: String) {
        // Sloveso je past, na kterou tenhle soubor už jednou došel — jen z druhé strany:
        // do #200 tu bylo přídavné jméno („3 blokujících“, nález Copilota na #131), kde se
        // shodovalo `one` a `few`. U slovesa se shoduje `one` a **`many`**: „1 blokuje“,
        // „3 blokují“, ale od pěti zase „5 blokuje“. Proto tabulka, ne jeden případ.
        #expect(title(.completed(findings: 20), blocking: blocking) == "20 nálezů · \(expected)")
    }

    @Test("Tělo nese nejzávažnější nález a pod ním PR")
    func carriesTheTopFindingAndThePullRequest() {
        // Návrh chce v těle konkrétní nález, ne jen jméno PR — to jde na třetí řádek.
        let finding = makeFinding(category: "correctness", shortSummary: "?? '' schová chybějící secret")

        #expect(
            body(.completed(findings: 3), blocking: 1, topFinding: finding)
                == "correctness: ?? '' schová chybějící secret\ncli/cli#42"
        )
    }

    @Test("Bez zkráceného souhrnu se vezme celý")
    func fallsBackToTheFullSummary() {
        // `shortSummary` reviewer vyplnit nemusí a nález kvůli tomu nemá z notifikace zmizet.
        let finding = makeFinding(category: "security", summary: "Token se loguje do stdout")

        #expect(body(.completed(findings: 1), topFinding: finding)?.hasPrefix("security: Token se loguje") == true)
    }

    @Test("Dlouhý souhrn se zkrátí, ať v banneru zbude i PR")
    func shortensALongSummary() {
        // Změřeno v běžící aplikaci: 140znakový souhrn zabral všechny čtyři řádky těla
        // a macOS uřízl i řádek s identifikací PR. Vlastní řez ho tam nechá.
        let finding = makeFinding(
            category: "correctness",
            summary: """
            Prázdný fallback udělá z chybějícího tokenu prázdný string a request odejde bez \
            autorizace, takže se to pozná až podle 401 v logu.
            """
        )

        let lines = body(.completed(findings: 1), topFinding: finding)?.split(separator: "\n")

        #expect(lines?.count == 2)
        #expect(lines?.last == "cli/cli#42")
        #expect(lines?.first?.count ?? 0 <= Policy.notificationFindingLimit + 1)
        #expect(lines?.first?.hasSuffix("…") == true)
        // Řeže se na hranici slova, ne uprostřed.
        #expect(lines?.first?.contains("autoriz…") == false)
    }

    @Test("Slovo, které se do limitu vešlo celé, se nezahodí")
    func keepsAWordThatFits() {
        // `dropLast()` na slepo bral poslední slovo i tehdy, když řez padl přesně na mezeru —
        // z banneru pak zmizel kus textu, na který bylo místo (nález Copilota na #248).
        // Sto znaků tady končí za dvacátým `abcd`, takže se má vejít celé.
        let finding = makeFinding(category: nil, summary: String(repeating: "abcd ", count: 30))

        let first = body(.completed(findings: 1), topFinding: finding)?.split(separator: "\n").first

        #expect(first?.hasSuffix("abcd…") == true)
        // 99 znaků textu (20 × `abcd` a 19 mezer) plus tři tečky; se starým chováním o pět míň.
        #expect(first?.count == Policy.notificationFindingLimit)
    }

    @Test("Jediné dlouhé slovo se ořízne natvrdo, ne na nic")
    func cutsASingleLongWord() {
        // Cesta nebo hash hranici slova nemá — kdyby se řezalo jen po slovech, nezbylo by nic.
        let finding = makeFinding(category: nil, summary: String(repeating: "a", count: 200))

        let first = body(.completed(findings: 1), topFinding: finding)?.split(separator: "\n").first

        #expect(first?.count == Policy.notificationFindingLimit + 1)
        #expect(first?.hasSuffix("…") == true)
    }

    @Test("Nález bez kategorie nenechá v textu visící dvojtečku")
    func omitsTheCategoryWhenThereIsNone() {
        let finding = makeFinding(category: nil, summary: "Chybí test")

        #expect(body(.completed(findings: 1), topFinding: finding) == "Chybí test\ncli/cli#42")
    }

    @Test("Zalomení v nálezu neodsune PR z dohledu")
    func keepsThePullRequestOnTheThirdLine() {
        // Tělo má **dva** řádky (detail a PR) a banner ukáže jen část — jeden `\n` navíc
        // v souhrnu od reviewera by identifikaci odsunul mimo to, co je vidět.
        let finding = makeFinding(summary: "první řádek\ndruhý řádek")

        let lines = body(.completed(findings: 1), topFinding: finding)?.split(separator: "\n")

        #expect(lines?.count == 2)
        #expect(lines?.last == "cli/cli#42")
    }

    @Test("Nedodaný nález nechá v těle aspoň PR")
    func keepsThePullRequestWithoutAFinding() {
        // Nastat by to nemělo (store bere počet i nález z téhož záznamu), ale prázdný řádek
        // pod titulkem by byl horší než kratší tělo.
        #expect(body(.completed(findings: 2), blocking: 1) == "cli/cli#42")
    }

    @Test("Čisté review je kratší, ale poznat se musí")
    func saysCleanExplicitly() {
        #expect(title(.clean) == "Čisté review")
        #expect(body(.clean) == "Reviewer nenašel žádný nález.\ncli/cli#42")
    }

    @Test("Selhání nese důvod, se kterým se dá něco dělat")
    func carriesTheFailureReason() {
        #expect(title(.failed(detail: "Session spadla na chybějícím skillu.")) == "Review se nepovedlo")
        #expect(
            body(.failed(detail: "Session spadla na chybějícím skillu."))
                == "Session spadla na chybějícím skillu.\ncli/cli#42"
        )
    }

    @Test("Víceřádkový důvod selhání PR z těla nevytlačí")
    func keepsAMultilineFailureOnOneLine() {
        // `CheckoutError.userDescription` lepí výstup `gitu` za prázdný řádek, takže bez
        // slití by tělo mělo čtyři řádky a identifikace by se propadla mimo banner.
        let state = ReviewState.checkoutFailed(detail: "Přihlášení odmítnuto.\n\nfatal: could not read")

        #expect(body(state) == "Přihlášení odmítnuto. fatal: could not read\ncli/cli#42")
    }

    @Test("Čisté review a selhání zůstávají dvě různé věty")
    func neverMergesCleanWithFailure() {
        // Tvrdá podmínka z `CLAUDE.md`: „nic jsem nenašel“ a „session spadla“ říkají opak
        // jedno o druhém a slití by z druhého udělalo schválený PR.
        #expect(title(.clean) != title(.failed(detail: "spadlo to")))
        #expect(body(.clean) != body(.failed(detail: "spadlo to")))
    }

    @Test("Nejistý výsledek se nesmí tvářit jako čistý")
    func doesNotPassOffAnInconclusiveRunAsClean() {
        // `Policy.reviewState` posílá nereportující běh do `inconclusive` s vysvětlením — kdyby
        // notifikace řekla „nenašel žádný nález“, bylo by to schválené PR s neohlášenou
        // chybou. Tady se ověřuje, že se ta věta z Policy doopravdy propíše.
        //
        // **Titulek není „Review se nepovedlo“** (změna u #383): session doběhla `success`,
        // takže hláška o poruše by nad ní lhala. Musí se ale pořád lišit od čistoty — a to je
        // to jediné, na čem tady záleží.
        let record = makeRecord(runs: [makeStoredRun(calledReportFindings: false)])
        let state = Policy.reviewState(for: record)

        #expect(title(state) == "Z review se čisto tvrdit nedá")
        #expect(title(state) != title(.clean))
        #expect(body(state)?.contains("nenahlásil") == true)
    }

    @Test("Ztracený nález se hlásí, ne schová")
    func reportsDroppedFindings() {
        let record = makeRecord(runs: [makeStoredRun(droppedFindings: 2)])

        #expect(body(Policy.reviewState(for: record))?.contains("nepodařilo přečíst") == true)
    }

    @Test("Timeout s nálezy řekne obojí")
    func saysBothOnTimeout() {
        // Zabitý běh mohl mít nálezy rozepsané, takže samotné „2 nálezy“ v titulku by tvrdilo
        // víc, než se stalo — proto to detail hned pod ním doplní.
        let finding = makeFinding(category: "correctness", summary: "total() ignoruje množství")

        #expect(title(.timedOut(findings: 2), blocking: 1) == "2 nálezy · 1 blokuje")
        #expect(
            body(.timedOut(findings: 2), blocking: 1, topFinding: finding)
                == "Nedoběhlo do limitu. correctness: total() ignoruje množství\ncli/cli#42"
        )
    }

    @Test("Timeout bez nálezů to řekne bez počtu")
    func saysTimeoutWithoutFindings() {
        #expect(title(.timedOut(findings: 0)) == "Review nedoběhlo do limitu")
        #expect(body(.timedOut(findings: 0)) == "Reviewer nic nenahlásil.\ncli/cli#42")
    }

    /// Přerušený běh musí říct **proč** to nedoběhlo: s timeoutem se dělá něco jiného (dá se
    /// zvednout limit) než se spadlou aplikací. A že jsou nálezy z transcriptu, taky — samotný
    /// titulek „3 nálezy“ by tvrdil, že běh doběhl.
    @Test("Přerušený běh se pozná od timeoutu i od doběhlého")
    func tellsAnInterruptedRunApart() {
        let text = body(.interrupted(findings: 3), blocking: 1, topFinding: makeFinding())

        #expect(title(.interrupted(findings: 3), blocking: 1) == "3 nálezy · 1 blokuje")
        #expect(text?.contains("Přerušila to aplikace") == true)
        #expect(text?.contains("transcriptu") == true)
        #expect(text != body(.timedOut(findings: 3), blocking: 1, topFinding: makeFinding()))
        #expect(title(.interrupted(findings: 0)) == "Review přerušila aplikace")
    }

    @Test("Odmítnuté nálezy nejsou totéž jako čisto")
    func distinguishesDismissedFromClean() {
        // „Našel a já to zamítl“ je jiné tvrzení než „nic nenašel“ (#113) a v notifikaci se
        // to nesmí slít — ani v titulku, ani v těle.
        #expect(title(.dismissed(findings: 2)) == "Zbyly jen odmítnuté nálezy")
        #expect(body(.dismissed(findings: 2)) == "Odmítl jsi 2 nálezy a nic jiného nezbylo.\ncli/cli#42")
        #expect(title(.dismissed(findings: 2)) != title(.clean))
        #expect(body(.dismissed(findings: 2)) != body(.clean))
    }

    @Test("Věta o odmítnutých unese i jediný nález")
    func inflectsTheDismissedCount() {
        // Původní formulace („Zbyly jen nálezy, které jsi odmítl (1)“) mluvila o jednom
        // nálezu v množném čísle — tatáž třída chyby jako u blokujících, jen ji tady neřeší
        // skloňování slova, ale to, jak je věta postavená.
        #expect(body(.dismissed(findings: 1))?.hasPrefix("Odmítl jsi 1 nález a") == true)
        #expect(body(.dismissed(findings: 8))?.hasPrefix("Odmítl jsi 8 nálezů a") == true)
    }

    @Test("Selhaný checkout se pozná od selhané session")
    func distinguishesCheckoutFailure() {
        #expect(title(.checkoutFailed(detail: "Nejsi přihlášený v gh.")) == "Nepovedlo se připravit pracovní kopii")
        #expect(
            title(.checkoutFailed(detail: "Nejsi přihlášený v gh."))
                != title(.failed(detail: "Nejsi přihlášený v gh."))
        )
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

    @Test("Notifikace nese PR, kterého se týká — v datech i na třetím řádku")
    func carriesThePullRequest() {
        let notification = Policy.reviewNotification(for: pr, state: .clean)

        // Klik na notifikaci se řídí typem, ne textem; do #200 bylo PR i v titulku.
        #expect(notification?.pullRequest == pr)
        #expect(notification?.body.hasSuffix("\ncli/cli#42") == true)
        #expect(notification?.title == "Čisté review")
    }

    @Test("Číslo PR se neformátuje přes locale")
    func doesNotGroupTheNumber() {
        // `Text("#\(number)")` by z #21663 udělalo „#21 663“ — číslo PR není množství.
        // Jméno jde přes `description` identifikátoru, takže se to stát nemůže; je na to
        // test, aby to tak zůstalo.
        let big = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 21663)

        #expect(Policy.reviewNotification(for: big, state: .clean)?.body.hasSuffix("cli/cli#21663") == true)
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

    // MARK: - Vlastní PR (#332)

    /// **Tvrzení, že se něco nestalo**: o vlastním PR se touhle cestou nehlásí **nic** — ani
    /// nálezy, ani čisto, ani selhání. Všechny tři události jsou odpověď na review request, takže
    /// by hlásily práci, o kterou nikdo nepožádal. Vlastní notifikace o vlastních PR je #335.
    @Test("O vlastním PR se touhle cestou nehlásí nic", arguments: [
        ReviewState.completed(findings: 3),
        .clean,
        .dismissed(findings: 2),
        .failed(detail: "spadlo"),
        .checkoutFailed(detail: "nešlo naklonovat"),
        .timedOut(findings: 2),
        .interrupted(findings: 1),
    ])
    func staysQuietOnOwnPullRequests(state: ReviewState) {
        #expect(Policy.reviewNotification(for: pr, ownership: .mine, state: state, blocking: 1) == nil)
        // A cizí PR v témže stavu hlásit **musí** — jinak by test výš platil i nad vypnutými
        // notifikacemi.
        #expect(Policy.reviewNotification(for: pr, ownership: .theirs, state: state, blocking: 1) != nil)
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
        // Přerušený běh se dělí stejně a ze stejného důvodu: nálezy jsou k přečtení, kdežto
        // přerušený běh bez nich je selhání.
        #expect(event(.interrupted(findings: 2)) == .findings)
        #expect(event(.interrupted(findings: 0)) == .failure)
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

    private func notification(
        _ ids: [String],
        titles: [String: String] = [:],
        reviewed: [String] = []
    ) -> PullRequestNotification? {
        Policy.newPullRequestsNotification(
            for: ids.map(pr),
            titles: Dictionary(uniqueKeysWithValues: titles.map { (pr($0.key), $0.value) }),
            reviewed: Set(reviewed.map(pr))
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

    // MARK: - Re-review (#137)

    /// Tohle je celé zadání #137: u PR, který jsem reviewoval minulý týden, není „Nový PR
    /// k review“ pravda — a je to zrovna ten případ, kdy má člověk jiné očekávání.
    @Test("Známé PR se ohlásí jako re-review, ne jako novinka")
    func announcesAKnownPullRequestAsARereview() {
        let result = notification(
            ["cli/cli#1"],
            titles: ["cli/cli#1": "Opravit součet"],
            reviewed: ["cli/cli#1"]
        )

        #expect(result?.title == "Znovu požádáno o review — cli/cli#1")
        // Tělo je pořád titulek PR: co se změnilo, se stejně pozná až v okně.
        #expect(result?.body == "Opravit součet")
    }

    @Test("PR, u kterého review nikdy neběželo, zůstává novinkou")
    func keepsAnUnknownPullRequestNew() {
        let result = notification(["cli/cli#1"], reviewed: ["cli/cli#9"])

        #expect(result?.title == "Nový PR k review — cli/cli#1")
    }

    @Test("Souhrn bez re-review se textem nemění")
    func summaryWithoutRereviewsIsUnchanged() {
        #expect(notification(["cli/cli#1", "cli/cli#2"])?.title == "2 nové PR k review")
    }

    @Test("Souhrn řekne, kolik z nich je znovu")
    func summaryCountsRereviews() {
        let result = notification(
            ["cli/cli#1", "cli/cli#2", "cli/cli#3"],
            reviewed: ["cli/cli#2"]
        )

        #expect(result?.title == "3 PR k review (1 znovu)")
    }

    @Test("Když jsou znovu všechna, řekne to taky")
    func summaryWhenEverythingIsARereview() {
        // Vlastní tvar („3 PR znovu k review“) tady schválně není: dvě větve se udrží
        // v souladu snáz než tři a tenhle případ je vzácný.
        let result = notification(["cli/cli#1", "cli/cli#2"], reviewed: ["cli/cli#1", "cli/cli#2"])

        #expect(result?.title == "2 PR k review (2 znovu)")
    }

    @Test("Re-review nemění událost, takže se dá vypnout jedním přepínačem")
    func rereviewKeepsTheEvent() {
        // Vlastní `NotificationEvent` by šel vypnout zvlášť (#86), ale je to pátý přepínač
        // za rozdíl, který zatím nikdo vypínat nechtěl.
        #expect(notification(["cli/cli#1"], reviewed: ["cli/cli#1"])?.event == .newPullRequest)
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
