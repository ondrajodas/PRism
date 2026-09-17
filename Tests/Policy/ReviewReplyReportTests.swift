import Foundation
import Testing

@testable import PRism

/// Druhé kolo nad mými odeslanými komentáři (#522).
///
/// Tři věci se tady rozbijí potichu a každá má vlastní test:
///
/// - **hranice mezi daty a modelem** — `odpovězeno` musí vyjít z konverzace (#72) i tehdy, když
///   model tvrdí něco jiného; opačně by aplikace tvrdila víc, než data unesou;
/// - **platnost** — verdikt nad posunutou hlavou se nesmí ukázat (tvrdá podmínka č. 5), zatímco
///   fakt z konverzace posunem hlavy nezastarává;
/// - **párování** — verdikt musí sednout na vlákno podle indexu, ne podle textu.
@Suite("Policy — druhé kolo nad komentáři")
struct ReviewReplyReportTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    private func comment(_ id: String, line: Int? = 13) -> SentComment {
        SentComment(threadID: id, path: "Cart.swift", line: line, body: "co se stane u nuly?")
    }

    private func thread(
        _ id: String,
        mine: Bool = true,
        replies: [String] = [],
        line: Int? = 13
    ) -> ReviewThread {
        let authors = [mine ? "ondrajodas" : "babakks"] + replies
        let comments = authors.enumerated().map { index, author in
            ThreadComment(
                id: "\(id)-\(index)",
                author: author,
                body: "co se stane u nuly?",
                createdAt: Date(timeIntervalSince1970: 1_000_000 + Double(index)),
                url: URL(string: "https://github.com/cli/cli/pull/42#discussion_r\(index)")!
            )
        }
        return ReviewThread(
            id: id,
            path: "Cart.swift",
            line: line,
            originalLine: line,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(
                items: comments,
                total: comments.count,
                hasNextPage: false
            )
        )
    }

    private func conversation(_ threads: [ReviewThread]) -> Conversation {
        Conversation(
            viewer: "ondrajodas",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: threads, total: threads.count, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }

    private func record(
        _ replyStatuses: [String: RecheckStatus],
        against headSha: String = "new2222",
        outcome: ReviewRunOutcome = .finished
    ) -> ReviewRecord {
        ReviewRecord(
            pullRequest: pr,
            headSha: "old1111",
            runs: [makeStoredRun(findings: [makeReported()], headSha: "old1111")],
            isStale: true,
            recheck: StoredRecheck(
                againstHeadSha: headSha,
                outcome: outcome,
                sessionID: "session",
                statuses: [:],
                replyStatuses: replyStatuses,
                finishedAt: Date(timeIntervalSince1970: 2_000_000)
            )
        )
    }

    // MARK: - Stav jednoho komentáře — vyčerpávající výčet

    /// `Policy.replyState` je **jediné místo, kde se ty dvě osy skládají**, takže se vyčerpává
    /// celý součin: odpověď (ano/ne) × verdikt (`nil` a tři hodnoty `RecheckStatus.Verdict`).
    /// Osm případů, každý s vypsaným očekáváním — tabulka je tady kvůli tomu, aby při změně
    /// pravidla bylo vidět, které buňky se hnuly.
    @Test(
        "Výčet stavů: odpověď × verdikt",
        arguments: [
            (true, RecheckStatus.Verdict?.none, Policy.ReviewReplyState.answered),
            (true, .some(.resolved), .answered),
            (true, .some(.stillApplies), .answered),
            (true, .some(.unclear), .answered),
            (false, RecheckStatus.Verdict?.none, .unanswered(.unknown)),
            (false, .some(.resolved), .fixed(in: "new2222")),
            (false, .some(.stillApplies), .unanswered(.unchanged)),
            (false, .some(.unclear), .unanswered(.unclear)),
        ]
    )
    func everyCombinationOfDataAndVerdict(
        answered: Bool,
        verdict: RecheckStatus.Verdict?,
        expected: Policy.ReviewReplyState
    ) {
        #expect(
            Policy.replyState(answered: answered, verdict: verdict, against: "new2222") == expected
        )
    }

    /// Bez platné hlavy se osa modelu nečte vůbec — `opraveno` z ní nesmí vyjít ani tehdy, když
    /// verdikt uložený je (tvrdá podmínka č. 5).
    @Test(
        "Bez platné hlavy nevydá model žádný stav",
        arguments: [RecheckStatus.Verdict?.none, .some(.resolved), .some(.stillApplies), .some(.unclear)]
    )
    func withoutAValidHeadTheModelSaysNothing(verdict: RecheckStatus.Verdict?) {
        #expect(
            Policy.replyState(answered: false, verdict: verdict, against: nil)
                == .unanswered(.unknown)
        )
    }

    // MARK: - Hranice mezi daty a modelem

    /// **Nejcennější tvrzení celého issue.** Model řekl „opraveno“, ale ve vlákně je odpověď —
    /// a odpověď je fakt, kdežto verdikt je tvrzení. Kdyby vyhrálo `opraveno`, schovala by
    /// aplikace větu kolegy, kterou si mám přečíst, kvůli tomu, že se modelu něco zdálo.
    @Test("Odpověď z dat přebije verdikt modelu")
    func dataBeatsTheModel() {
        let report = Policy.replies(
            of: record(["t1": RecheckStatus(verdict: .resolved, note: "opraveno v commitu")]),
            head: "new2222",
            in: conversation([thread("t1", replies: ["autor"])])
        )

        guard case .current(let tally) = report else {
            Issue.record("report má být current")
            return
        }
        #expect(tally.entries.map(\.state) == [.answered])
        #expect(tally.fixed == 0)
        #expect(tally.answered == 1)
        // Věta modelu se u stavu z dat **neveze**: pod `odpovězeno` by vypadala jako jeho zdroj.
        #expect(tally.entries.first?.note == nil)
    }

    /// A naopak: bez odpovědi verdikt platí a nese hlavu, proti které se vyslovil.
    @Test("Bez odpovědi rozhoduje verdikt a nese sha")
    func withoutAReplyTheVerdictDecides() {
        let report = Policy.replies(
            of: record(["t1": RecheckStatus(verdict: .resolved, note: "opraveno v commitu")]),
            head: "new2222",
            in: conversation([thread("t1")])
        )

        guard case .current(let tally) = report else {
            Issue.record("report má být current")
            return
        }
        #expect(tally.entries.map(\.state) == [.fixed(in: "new2222")])
        #expect(tally.entries.first?.note == "opraveno v commitu")
        #expect(tally.fixed == 1)
    }

    /// `odpovězeno` nepotřebuje kontrolu vůbec — je to fakt z konverzace, takže platí i na PR,
    /// nad kterým kontrola nikdy neběžela.
    @Test("Odpovězeno platí i bez kontroly")
    func answeredHoldsWithoutAnyRecheck() {
        let report = Policy.replies(
            of: nil,
            head: "new2222",
            in: conversation([thread("t1", replies: ["autor"]), thread("t2")])
        )

        guard case .current(let tally) = report else {
            Issue.record("report má být current")
            return
        }
        #expect(tally.entries.map(\.state) == [.answered, .unanswered(.unknown)])
        #expect(tally.verdicts == nil)
    }

    // MARK: - Platnost (tvrdá podmínka č. 5)

    /// Kontrola běžela proti jiné hlavě, než na které PR stojí: verdikty zhasnou, **fakta ne**.
    /// Slít obojí do jednoho `outdated` by znamenalo schovat odpověď kolegy kvůli tomu, že
    /// přišel commit.
    @Test("Posunutá hlava zhasne verdikty, odpovědi zůstanou")
    func aMovedHeadDropsVerdictsButNotFacts() {
        let statuses = [
            "t1": RecheckStatus(verdict: .resolved),
            "t2": RecheckStatus(verdict: .stillApplies),
        ]

        let report = Policy.replies(
            of: record(statuses, against: "new2222"),
            head: "newer3333",
            in: conversation([thread("t1"), thread("t2", replies: ["autor"])])
        )

        guard case .current(let tally) = report else {
            Issue.record("report má být current")
            return
        }
        #expect(tally.entries.map(\.state) == [.unanswered(.unknown), .answered])
        #expect(tally.verdicts == nil)
        #expect(tally.fixed == 0)
    }

    /// Neznámá hlava (detail se nenačetl) je totéž co posunutá: platnost, kterou nemáme čím
    /// potvrdit, se nepředpokládá — tatáž úmluva jako u `Policy.recheck(of:head:)`.
    @Test("Neznámá hlava verdikty nevydá")
    func anUnknownHeadYieldsNoVerdicts() {
        let report = Policy.replies(
            of: record(["t1": RecheckStatus(verdict: .resolved)]),
            head: nil,
            in: conversation([thread("t1")])
        )

        #expect(report.states["t1"] == .unanswered(.unknown))
    }

    /// Nenačtená konverzace je `unknown`, ne prázdný seznam: „o svých komentářích nevím nic“
    /// a „žádné tam nemám“ jsou dvě různé věty a v okně z nich vyjde jiný text.
    @Test("Bez konverzace je report unknown, ne prázdný")
    func withoutAConversationTheReportIsUnknown() {
        #expect(Policy.replies(of: record([:]), head: "new2222", in: nil) == .unknown)

        let empty = Policy.replies(of: record([:]), head: "new2222", in: conversation([]))
        #expect(empty != .unknown)
        guard case .current(let tally) = empty else {
            Issue.record("report má být current")
            return
        }
        #expect(tally.entries.isEmpty)
    }

    /// Cizí vlákno v reportu nefiguruje, ani když se o něm kontrola omylem vyjádřila.
    @Test("Cizí vlákno se do reportu nedostane")
    func someoneElsesThreadIsNotInTheReport() {
        let report = Policy.replies(
            of: record(["t2": RecheckStatus(verdict: .resolved)]),
            head: "new2222",
            in: conversation([thread("t1"), thread("t2", mine: false)])
        )

        #expect(report.states.keys.sorted() == ["t1"])
    }

    /// Jak běh skončil, se **musí** vézt s sebou: kontrola, která spadla po dvou odpovědích,
    /// za zbytek nemluví — a `bez odpovědi` u zbytku pak neznamená „nic se nezměnilo“.
    @Test("Report nese, jak kontrola skončila")
    func theReportCarriesTheOutcome() {
        let report = Policy.replies(
            of: record(["t1": RecheckStatus(verdict: .resolved)], outcome: .timedOut),
            head: "new2222",
            in: conversation([thread("t1"), thread("t2")])
        )

        guard case .current(let tally) = report else {
            Issue.record("report má být current")
            return
        }
        #expect(tally.verdicts?.outcome == .timedOut)
        #expect(tally.verdicts?.againstHeadSha == "new2222")
        #expect(tally.unanswered == 1)
    }

    // MARK: - Párování přes index

    /// Odpovědi leží v **jednom** poli s nálezy, takže komentáře začínají za nimi. Verdikt
    /// s indexem nálezu se ke komentáři přiřadit nesmí.
    @Test("Komentáře se párují indexem posunutým za nálezy")
    func commentsArePairedByAnOffsetIndex() {
        let comments = [comment("t1"), comment("t2")]

        let statuses = Policy.replyStatuses(
            [
                0: RecheckStatus(verdict: .resolved),
                2: RecheckStatus(verdict: .stillApplies),
                3: RecheckStatus(verdict: .unclear),
            ],
            of: comments,
            startingAt: 2
        )

        // `0` patří nálezu, ne komentáři.
        #expect(statuses.count == 2)
        #expect(statuses["t1"]?.verdict == .stillApplies)
        #expect(statuses["t2"]?.verdict == .unclear)
    }

    /// **Párování přes index, ne přes text** (#150): odpověď, ve které model komentář
    /// přeformuloval, musí sednout na totéž vlákno. Text se v odpovědi nevyskytuje vůbec, takže
    /// jediné, co se dá splést, je číslo.
    @Test("Přeformulovaný text párování nerozhodí")
    func rewordedTextDoesNotBreakThePairing() {
        let comments = [comment("t1"), comment("t2")]
        let answers = RecheckCommand.parse(
            """
            [{"id": 2, "status": "resolved", "note": "the zero-quantity guard is there now"},
             {"id": 3, "status": "still-applies", "note": "nothing changed around the secret"}]
            """,
            count: 4
        )

        let statuses = Policy.replyStatuses(answers, of: comments, startingAt: 2)

        #expect(statuses["t1"]?.verdict == .resolved)
        #expect(statuses["t1"]?.note == "the zero-quantity guard is there now")
        #expect(statuses["t2"]?.verdict == .stillApplies)
    }

    /// Vymyšlené `id` se zahazuje — v jednom poli s nálezy to znamená i **záporný** posun.
    @Test("Index mimo rozsah se zahodí")
    func anIndexOutsideTheRangeIsDropped() {
        let statuses = Policy.replyStatuses(
            [
                1: RecheckStatus(verdict: .resolved),
                9: RecheckStatus(verdict: .resolved),
            ],
            of: [comment("t1")],
            startingAt: 2
        )

        #expect(statuses.isEmpty)
    }

    // MARK: - Useknutá odpověď

    /// Useknutá stránka vláken musí být **vidět**: jinak by `2 opravené ze 3` platilo o třech,
    /// která dorazila, a mlčelo o těch, která ne. Počet je přes **všechna** vlákna PR — kolik
    /// z chybějících je mých, se z odpovědi zjistit nedá a dopočítat to odhadem je zrovna to
    /// tvrzení navíc, kterému se celé #522 vyhýbá.
    @Test("Useknutá stránka vláken je v reportu vidět")
    func aTruncatedThreadPageIsVisible() throws {
        let conversation = try load("conversation-truncated.json", number: 13084, viewer: "babakks")

        guard case .current(let tally) = Policy.replies(
            of: nil,
            head: "new2222",
            in: conversation
        ) else {
            Issue.record("report má být current")
            return
        }
        #expect(conversation.threads.isTruncated)
        #expect(tally.isTruncated)
        #expect(tally.missingThreads == conversation.threads.missing)
        #expect(tally.missingThreads > 0)
    }

    /// A na úplné odpovědi se to **nerozsvítí**: hláška o zkrácení, která svítí vždycky,
    /// přestane něco znamenat.
    @Test("Úplná odpověď zkrácení nehlásí")
    func aCompleteResponseReportsNoTruncation() throws {
        let conversation = try load("conversation-small.json", number: 11451, viewer: "babakks")

        guard case .current(let tally) = Policy.replies(
            of: nil,
            head: "new2222",
            in: conversation
        ) else {
            Issue.record("report má být current")
            return
        }
        #expect(!tally.isTruncated)
        #expect(tally.missingThreads == 0)
    }

    private func load(_ fixture: String, number: Int, viewer: String) throws -> Conversation {
        let text = try Fixture.text("gh/\(fixture)")
        let response = try GhOutput.decoder.decode(
            GhConversationResponse.self,
            from: Data(text.utf8)
        )
        let conversation = try response.conversation(
            id: PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: number)
        )
        return Conversation(
            viewer: viewer,
            reviews: conversation.reviews,
            threads: conversation.threads,
            comments: conversation.comments,
            events: conversation.events
        )
    }
}
