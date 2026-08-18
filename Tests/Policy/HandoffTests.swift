import Foundation
import Testing

@testable import PRism

/// Razítko předání a to, co po něm zbývá (#334) — `Policy.handoff`.
///
/// Čistá funkce, takže vyčerpávajícím výčtem a bez mockování. Čtyři věci se tu dají pokazit
/// **potichu**, a proto je na každou vlastní tvrzení „nestalo se“:
///
/// - odznak po předání **nezhasne** (pak razítko nedělá nic a #334 je k ničemu),
/// - odznak po předání **nezasvítí** ani na novou práci (pak razítko lže o tom, že je hotovo),
/// - po pushi zůstane `.delivered` (pak zadání mluví o kódu, který na PR není),
/// - zastaralý nález **zmizí** z počtu (pak by po pushi vypadalo, že není co dělat).
@Suite("Předání zadání (#334)")
struct HandoffTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let handedAt = Date(timeIntervalSince1970: 1_000_000)

    private func comment(
        id: String = "c1",
        author: String = "kolega",
        at offset: TimeInterval = -100
    ) -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: "text",
            createdAt: handedAt.addingTimeInterval(offset),
            url: URL(string: "https://github.com/cli/cli/pull/42#discussion_r\(id)")!
        )
    }

    private func thread(
        id: String = "t1",
        resolved: Bool = false,
        comments: [ThreadComment]
    ) -> ReviewThread {
        ReviewThread(
            id: id,
            path: "Cart.swift",
            line: 27,
            originalLine: 27,
            side: .right,
            isResolved: resolved,
            isOutdated: false,
            comments: ConversationPage(items: comments, total: comments.count, hasNextPage: false)
        )
    }

    private func conversation(
        threads: [ReviewThread] = [],
        comments: [ThreadComment] = [],
        reviews: [SubmittedReview] = []
    ) -> Conversation {
        Conversation(
            viewer: "ondrajodas",
            reviews: ConversationPage(items: reviews, total: reviews.count, hasNextPage: false),
            threads: ConversationPage(items: threads, total: threads.count, hasNextPage: false),
            comments: ConversationPage(items: comments, total: comments.count, hasNextPage: false)
        )
    }

    private func commits(_ shas: [String]) -> [PullRequestCommit] {
        // Od nejstaršího, jak je vydává gateway (`GhGateway.fetchCommits` neřadí).
        shas.map {
            PullRequestCommit(
                sha: $0,
                message: "commit \($0)",
                authorName: "Ondra",
                authorLogin: "ondrajodas",
                avatarURL: nil,
                committedAt: handedAt,
                isMerge: false
            )
        }
    }

    /// Razítko, které pokrývá **právě to, co je na PR** — skládá se z týchž položek, jaké by
    /// nesl prompt, ne z ručně napsaných identit. Kdyby se `id` skládalo v testu, ověřoval by
    /// test svoji kopii pravidla.
    private func handoff(
        of record: ReviewRecord?,
        conversation: Conversation?,
        headSha: String? = "9c1de02",
        at date: Date? = nil
    ) -> Handoff {
        let items = Policy.agentPromptItems(
            findings: record?.findings ?? [],
            dismissals: record?.dismissals ?? [:],
            conversation: conversation
        )
        .filter(\.choice.isPending)
        return Handoff(at: date ?? handedAt, headSha: headSha, handed: Set(items.map(\.id)))
    }

    // MARK: - Nepředáno

    /// Bez razítka je materiál k předání všechno, co jde do zadání — a odznak svítí.
    @Test("Bez razítka zbývá všechno")
    func countsEverythingWithoutAStamp() {
        let record = makeRecord(runs: [makeStoredRun(findings: [makeReported()])])
        let conversation = conversation(threads: [thread(comments: [comment()])])

        let report = Policy.handoff(nil, record: record, conversation: conversation, head: "9c1de02")

        #expect(report.stage == .never)
        #expect(report.pending == 2)
        #expect(report.awaitsMove)
        #expect(report.handoff == nil)
    }

    /// **Tvrzení, že se něco nestalo:** PR bez nálezů a bez diskuze odznak nerozsvítí.
    @Test("Prázdný PR na tah nečeká")
    func countsNothingOnAnEmptyPullRequest() {
        let report = Policy.handoff(nil, record: nil, conversation: nil, head: "9c1de02")

        #expect(report.stage == .never)
        #expect(report.pending == 0)
        #expect(!report.awaitsMove)
    }

    /// Odmítnutý nález (#113) a vyřešené vlákno do materiálu nepatří: jedno je moje rozhodnutí,
    /// druhé zavřená diskuze, a ani jedno po mně nic nechce.
    @Test("Odmítnuté nálezy a vyřešená vlákna se nepočítají")
    func ignoresDismissedFindingsAndResolvedThreads() {
        var record = makeRecord(runs: [makeStoredRun(findings: [makeReported()])])
        record.dismissals = makeDismissals(record.findings)
        let conversation = conversation(threads: [thread(resolved: true, comments: [comment()])])

        let report = Policy.handoff(nil, record: record, conversation: conversation, head: "9c1de02")

        #expect(report.pending == 0)
        #expect(!report.awaitsMove)
    }

    // MARK: - Předáno

    /// **Nejcennější tvrzení #334**: po předání odznak zhasne, i když nálezy dál existují.
    @Test("Po předání odznak zhasne")
    func goesDarkAfterTheHandoff() {
        let record = makeRecord(runs: [makeStoredRun(findings: [makeReported()])])
        let conversation = conversation(threads: [thread(comments: [comment()])])
        let stamp = handoff(of: record, conversation: conversation)

        let report = Policy.handoff(stamp, record: record, conversation: conversation, head: "9c1de02")

        #expect(report.stage == .delivered)
        #expect(report.pending == 0)
        #expect(!report.awaitsMove)
        // Nálezy nikam nezmizely — jen jsou předané.
        #expect(record.activeFindings.count == 1)
        #expect(report.handoff?.count == 2)
    }

    /// Vlákno, které v předaném zadání nebylo (vypnutá volba), drží odznak rozsvícený.
    /// Kdyby razítko nesl jen počet, „poslal jsem jednu položku“ by tuhle situaci odepsalo.
    @Test("Nepředané vlákno zbývá i po předání nálezů")
    func keepsUnhandedItemsPending() {
        let record = makeRecord(runs: [makeStoredRun(findings: [makeReported()])])
        let conversation = conversation(threads: [thread(comments: [comment()])])
        // Razítko jen na nálezy — vlákno se nepředalo.
        let onlyFindings = handoff(of: record, conversation: nil)

        let report = Policy.handoff(
            onlyFindings,
            record: record,
            conversation: conversation,
            head: "9c1de02"
        )

        #expect(report.stage == .changed)
        #expect(report.pending == 1)
        // Identita se skládá **produkční** funkcí, ne v testu: kdyby se `id` psalo ručně, test by
        // ověřoval svoji kopii pravidla.
        #expect(report.freshDiscussion == [AgentPromptItem.thread(thread(comments: [comment()])).id])
    }

    /// Nový komentář od kolegy je nové vlákno v materiálu, takže odznak zasvítí.
    @Test("Nové vlákno po předání odznak rozsvítí")
    func lightsUpOnANewThread() {
        let before = conversation(threads: [thread(comments: [comment()])])
        let stamp = handoff(of: nil, conversation: before)
        let fresh = thread(id: "t2", comments: [comment(id: "c2", at: 500)])
        let after = conversation(threads: [thread(comments: [comment()]), fresh])

        let report = Policy.handoff(stamp, record: nil, conversation: after, head: "9c1de02")

        #expect(report.stage == .changed)
        #expect(report.pending == 1)
        #expect(report.freshDiscussion == [AgentPromptItem.thread(fresh).id])
    }

    /// **Cizí odpověď v už předaném vlákně se počítá.** Identita vlákna se odpovědí nemění,
    /// takže samotné „už jsem ho poslal“ by novou větu od kolegy zahodilo.
    @Test("Cizí odpověď v předaném vlákně zbývá předat")
    func countsForeignRepliesInAHandedThread() {
        let before = conversation(threads: [thread(comments: [comment()])])
        let stamp = handoff(of: nil, conversation: before)
        let after = conversation(threads: [
            thread(comments: [comment(), comment(id: "c2", at: 500)]),
        ])

        let report = Policy.handoff(stamp, record: nil, conversation: after, head: "9c1de02")

        #expect(report.stage == .changed)
        #expect(report.pending == 1)
    }

    /// **Moje vlastní odpověď novinka není** — tatáž úvaha jako u „od tvé poslední návštěvy“.
    @Test("Moje odpověď v předaném vlákně odznak nerozsvítí")
    func ignoresMyOwnRepliesInAHandedThread() {
        let before = conversation(threads: [thread(comments: [comment()])])
        let stamp = handoff(of: nil, conversation: before)
        let after = conversation(threads: [
            thread(comments: [comment(), comment(id: "c2", author: "ondrajodas", at: 500)]),
        ])

        let report = Policy.handoff(stamp, record: nil, conversation: after, head: "9c1de02")

        #expect(report.stage == .delivered)
        #expect(!report.awaitsMove)
    }

    /// Opakované review, které našlo **týž** nález, odznak nerozsvítí: klíč nálezu se nemění,
    /// takže se pozná, že nic nového nepřišlo.
    @Test("Týž nález z dalšího běhu se za nový nepočítá")
    func ignoresRepeatedFindings() {
        let record = makeRecord(runs: [makeStoredRun(findings: [makeReported()])])
        let stamp = handoff(of: record, conversation: nil)
        // Druhý běh téhož skillu s týmž nálezem, jen o hodinu později.
        let again = makeRecord(runs: [
            makeStoredRun(findings: [makeReported()], finishedAt: handedAt.addingTimeInterval(3600)),
        ])

        let report = Policy.handoff(stamp, record: again, conversation: nil, head: "9c1de02")

        #expect(report.stage == .delivered)
        #expect(!report.awaitsMove)
    }

    /// Nový nález naopak zbývá předat — a je jediný, i když v záznamu jsou dva.
    @Test("Nový nález zbývá předat")
    func countsANewFinding() {
        let record = makeRecord(runs: [makeStoredRun(findings: [makeReported()])])
        let stamp = handoff(of: record, conversation: nil)
        let again = makeRecord(runs: [
            makeStoredRun(findings: [makeReported(), makeReported(summary: "další nález")]),
        ])

        let report = Policy.handoff(stamp, record: again, conversation: nil, head: "9c1de02")

        #expect(report.stage == .changed)
        #expect(report.pending == 1)
        // Nález se do „jen nové vlákno“ nedostane: po pushi platí pro starý kód a bez pushe je
        // celé zadání k sestavení znovu.
        #expect(report.freshDiscussion.isEmpty)
    }

    // MARK: - Po pushi

    /// **Druhá polovina #334**: posunutá hlava znamená, že zadání zastaralo — a všechno je
    /// k předání znovu, protože nálezy platí pro starý kód.
    @Test("Po pushi zadání zastará")
    func goesOutdatedAfterAPush() {
        let record = makeRecord(runs: [makeStoredRun(findings: [makeReported()])])
        let conversation = conversation(threads: [thread(comments: [comment()])])
        let stamp = handoff(of: record, conversation: conversation)

        let report = Policy.handoff(
            stamp,
            record: record,
            conversation: conversation,
            head: "ff11223",
            commits: commits(["aaa0001", "9c1de02", "bbb0003", "ff11223"])
        )

        #expect(report.stage == .outdated)
        #expect(report.awaitsMove)
        #expect(report.pending == 2)
        // **Zastaralé nálezy nezmizely** (#113): pořád je to jediné, co o tom kódu víme.
        #expect(report.staleFindings == 1)
        #expect(report.commits == 2)
    }

    /// Počet commitů je `nil`, když se předaná hlava v seznamu nenajde — typicky po force pushi.
    /// Dopočítat rozdíl z délky seznamu by dalo číslo, které s pushnutými commity nemá nic
    /// společného.
    @Test("Po force pushi se počet commitů netvrdí")
    func staysSilentAboutCommitsAfterAForcePush() {
        let stamp = handoff(of: nil, conversation: nil)

        let report = Policy.handoff(
            stamp,
            record: nil,
            conversation: nil,
            head: "ff11223",
            commits: commits(["xxx0001", "ff11223"])
        )

        #expect(report.stage == .outdated)
        #expect(report.commits == nil)
    }

    /// Bez načteného seznamu commitů se počet taky netvrdí — je to „nevím kolik“, ne nula.
    @Test("Bez commitů se počet netvrdí")
    func staysSilentAboutCommitsWithoutTheList() {
        let stamp = handoff(of: nil, conversation: nil)

        let report = Policy.handoff(stamp, record: nil, conversation: nil, head: "ff11223")

        #expect(report.stage == .outdated)
        #expect(report.commits == nil)
    }

    /// Po pushi se do `Sestavit i tak` dostane **jen diskuze**, která přibyla — nálezy ne.
    @Test("Po pushi jde do zúženého zadání jen nová diskuze")
    func narrowsTheFreshPromptToDiscussion() {
        let record = makeRecord(runs: [makeStoredRun(findings: [makeReported()])])
        let stamp = handoff(of: record, conversation: nil)
        let fresh = thread(id: "t9", comments: [comment(at: 500)])
        let after = conversation(threads: [fresh])

        let report = Policy.handoff(stamp, record: record, conversation: after, head: "ff11223")

        #expect(report.stage == .outdated)
        #expect(report.freshDiscussion == [AgentPromptItem.thread(fresh).id])
    }

    // MARK: - Neznámá hlava

    /// Předání proti neznámé hlavě se **nedá potvrdit ani vyvrátit**, takže odznak svítí dál.
    /// Vlastní stav, ne `outdated`: „zadání zastaralo“ je tvrzení o commitech, které tady chybí.
    @Test("Předání bez známé hlavy se nedá potvrdit")
    func cannotVerifyAHandoffWithoutAHead() {
        let record = makeRecord(runs: [makeStoredRun(findings: [makeReported()])])
        let stamp = handoff(of: record, conversation: nil, headSha: nil)

        let report = Policy.handoff(stamp, record: record, conversation: nil, head: "9c1de02")

        #expect(report.stage == .unverified)
        #expect(report.pending == 1)
        #expect(report.awaitsMove)
        #expect(report.commits == nil)
    }

    /// **Neznámá dnešní hlava se bere jako „neposunula se“** — a je to vědomá spodní hranice.
    ///
    /// Hlavu zná aplikace jedině z dotaženého detailu, a ten se tahá při zobrazení PR. Kdyby
    /// z toho vycházel `.outdated`, odznak by po předání nikdy nezhasl u žádného PR v seznamu,
    /// tedy přesně to, co #334 opravuje.
    @Test("Bez dnešní hlavy se předání bere jako platné")
    func assumesTheHandoffHoldsWithoutTodaysHead() {
        let record = makeRecord(runs: [makeStoredRun(findings: [makeReported()])])
        let stamp = handoff(of: record, conversation: nil)

        let report = Policy.handoff(stamp, record: record, conversation: nil, head: nil)

        #expect(report.stage == .delivered)
        #expect(!report.awaitsMove)
    }

    // MARK: - Volby panelu

    /// Volby a náhled se kreslí jen tam, kde je z čeho vybírat — po předání a po pushi ne.
    @Test("Které stavy kreslí zaškrtávací volby")
    func decidesWhereChoicesBelong() {
        let stamp = handoff(of: nil, conversation: nil)
        let record = makeRecord(runs: [makeStoredRun(findings: [makeReported()])])

        #expect(Policy.handoff(nil, record: record, conversation: nil, head: "9c1de02").showsChoices)
        #expect(!Policy.handoff(stamp, record: nil, conversation: nil, head: "9c1de02").showsChoices)
        #expect(!Policy.handoff(stamp, record: nil, conversation: nil, head: "ff11223").showsChoices)
        #expect(Policy.handoff(
            handoff(of: nil, conversation: nil, headSha: nil),
            record: record,
            conversation: nil,
            head: "9c1de02"
        ).showsChoices)
    }
}
