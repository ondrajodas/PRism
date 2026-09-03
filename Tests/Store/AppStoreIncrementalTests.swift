import Foundation
import Testing

@testable import PRism

/// Přírůstkové review po pushi (#517) — od rozhodnutí po to, co se uloží.
///
/// **Nejcennější tvrzení jsou tady negativní**: že se přírůstek **nepustí** tam, kde není společná
/// historie, a že se `git` **neptá**, když není proti čemu. Obojí se rozbije potichu — přírůstek
/// nad přepsanou historií otevře víc než celý diff PR (změřeno u #284) a nikdo to nepozná, protože
/// běh doběhne a nálezy nahlásí.
@Suite("AppStore — review jen přírůstku")
@MainActor
struct AppStoreIncrementalTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let time = FakeTimeSource()

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private var summary: PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func detail(headSha: String) -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: headSha,
            baseSha: "base0000",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    /// Konfigurace se sadou jednoho skillu. Přepínač přírůstku je **vyjmenovaný**, ne výchozí:
    /// test, který se na něj ptá, nemá stát na tom, co je zrovna v `Configuration.standard`.
    private func configuration(incremental: Bool = true) -> Configuration {
        var configuration = Configuration.standard
        configuration.global.skills = ["code-review"]
        configuration.global.incrementalAfterPush = incremental
        return configuration
    }

    private func store(
        reviewer: FakeReviewRunner,
        checkout: FakeRepoCheckout,
        reviews: ReviewStore,
        incremental: Bool = true,
        headSha: String = "new2222"
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(
                always: .success([summary]),
                detail: .success(detail(headSha: headSha))
            ),
            configuration: configuration(incremental: incremental),
            time: time,
            checkout: checkout,
            reviewer: reviewer,
            reviews: reviews,
            cacheLayout: layout
        )
    }

    /// Uložené první kolo: doběhlý běh nad starší hlavou s jedním nálezem a se známou cenou.
    private func firstRound(in reviews: ReviewStore) async throws -> Finding {
        var stream = StreamSummary()
        stream.calledReportFindings = true
        stream.findings = [makeReported(file: "Cart.swift", line: 13, summary: "chybí kontrola")]
        stream.usage = RunUsage(cost: 0.82)
        try await reviews.save(ReviewRun(
            key: ReviewRunKey(pullRequest: pr, headSha: "old1111", skillID: "code-review"),
            summary: stream,
            outcome: .finished
        ))
        return try #require(await reviews.record(for: pr, at: "old1111")?.findings.first)
    }

    private func prepared(_ store: AppStore) async {
        await store.loadStoredReviews()
        await store.loadDetail(for: summary)
    }

    // MARK: - Kdy se přírůstek pustí

    /// Společná historie: reviewer dostane rozsah a soubor s nálezy z minula, a v požadavku je
    /// **obojí** — bez souboru by se na verdikty nezeptal.
    @Test("Po pushi dostane reviewer rozsah a nálezy z minula")
    func aPushGetsTheIncrementAndThePreviousFindings() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        _ = try await firstRound(in: reviews)
        let reviewer = FakeReviewRunner(resultText: #"[{"id":0,"status":"still-applies"}]"#)
        let store = store(
            reviewer: reviewer,
            checkout: FakeRepoCheckout(ancestry: .ancestor),
            reviews: reviews
        )
        await prepared(store)

        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }

        let request = try #require(reviewer.requests.first)
        #expect(request.increment?.range == IncrementalDiffRange(seen: "old1111", head: "new2222"))
        let file = try #require(request.increment?.previousFindings)
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(try String(contentsOf: file, encoding: .utf8).contains("chybí kontrola"))
    }

    /// **Force push bez společné historie: přírůstek se nepustí.** Kdyby se pustil, `git diff
    /// <stará>...HEAD` by vydal víc než celý diff PR — a nikdo by to nepoznal.
    @Test("Bez společné historie se přírůstek nepustí")
    func noIncrementWithoutSharedHistory() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        _ = try await firstRound(in: reviews)
        let reviewer = FakeReviewRunner()
        let store = store(
            reviewer: reviewer,
            checkout: FakeRepoCheckout(ancestry: .rewritten),
            reviews: reviews
        )
        await prepared(store)

        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }

        #expect(reviewer.requests.first?.increment == nil)
    }

    /// **Nález Copilota na #517**: rozhodnutí se musí donést do osy i tehdy, když nad přírůstkem
    /// neběží **nikdo** — a to je zrovna případ force pushe u repa s jedním reviewerem. Bez toho
    /// by věta `celý diff — historie se přepsala` nikdy nevyšla a rozhodnutí `Policy.reviewScope`
    /// by zůstalo držené, ale nikde nečtené.
    @Test("Důvod celého diffu se donese do Průběhu, i když přírůstek neběží nikde")
    func theWholeDiffReasonReachesTheLane() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        _ = try await firstRound(in: reviews)
        let store = store(
            reviewer: FakeReviewRunner(),
            checkout: FakeRepoCheckout(ancestry: .rewritten),
            reviews: reviews
        )
        await prepared(store)

        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }

        let lanes = Policy.lanes(
            of: store.timelines(for: pr),
            skills: ["code-review"],
            record: store.reviewRecord(for: pr)
        )
        #expect(lanes.first?.wholeReason == .rewroteHistory)
        #expect(lanes.first?.increment == nil)
    }

    /// První kolo naopak **nic nevysvětluje**: „celý diff, protože je to první kolo“ je stav,
    /// ve kterém aplikace běžela do #517, a řádek o něm by přidal šum do každé osy.
    @Test("První kolo do osy žádné vysvětlení neposílá")
    func theFirstRoundExplainsNothing() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        let store = store(
            reviewer: FakeReviewRunner(),
            checkout: FakeRepoCheckout(ancestry: .ancestor),
            reviews: reviews
        )
        await prepared(store)

        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }

        let lanes = Policy.lanes(
            of: store.timelines(for: pr),
            skills: ["code-review"],
            record: store.reviewRecord(for: pr)
        )
        #expect(lanes.first?.wholeReason == nil)
        #expect(lanes.first?.increment == nil)
    }

    /// Nezjištěná příbuznost je tatáž bezpečná strana: co se nedá ohraničit, se čte celé.
    @Test("Nezjištěná příbuznost znamená celý diff")
    func anUnknownAncestryMeansTheWholeDiff() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        _ = try await firstRound(in: reviews)
        let reviewer = FakeReviewRunner()
        let store = store(
            reviewer: reviewer,
            checkout: FakeRepoCheckout(ancestry: .unknown),
            reviews: reviews
        )
        await prepared(store)

        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }

        #expect(reviewer.requests.first?.increment == nil)
    }

    /// **Bez záznamu z minula se `git` neptá vůbec.** Je to jedno volání na review, ale odpověď
    /// by se neměla k čemu vztáhnout — a `Policy` v tom případě příbuznost nečte.
    @Test("V prvním kole se na společnou historii neptáme")
    func theFirstRoundDoesNotAskGit() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        let checkout = FakeRepoCheckout(ancestry: .ancestor)
        let reviewer = FakeReviewRunner()
        let store = store(reviewer: reviewer, checkout: checkout, reviews: reviews)
        await prepared(store)

        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }

        #expect(checkout.askedAncestryOf.isEmpty)
        #expect(reviewer.requests.first?.increment == nil)
    }

    /// Vypnuté nastavení: `git` se neptá a rozsah se neposílá — i když by společná historie byla.
    @Test("S vypnutým nastavením se přírůstek neskládá")
    func theSettingOffSkipsEverything() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        _ = try await firstRound(in: reviews)
        let checkout = FakeRepoCheckout(ancestry: .ancestor)
        let reviewer = FakeReviewRunner()
        let store = store(
            reviewer: reviewer,
            checkout: checkout,
            reviews: reviews,
            incremental: false
        )
        await prepared(store)

        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }

        #expect(checkout.askedAncestryOf.isEmpty)
        #expect(reviewer.requests.first?.increment == nil)
    }

    // MARK: - Co se uloží

    /// Staré nálezy se přenesou na novou hlavu s odkazem na původ (tvrdá podmínka č. 5) a nový
    /// nález přijde vedle nich. **Ani jeden z nich nezmizí.**
    @Test("Uloží se nový nález i ten přenesený, s odznakem")
    func bothTheNewAndTheCarriedFindingAreStored() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        _ = try await firstRound(in: reviews)
        let reviewer = FakeReviewRunner(
            findings: [makeReported(file: "Cart.swift", line: 122, summary: "nový nález")],
            resultText: #"[{"id":0,"status":"still-applies","note":"pořád tam je"}]"#
        )
        let store = store(
            reviewer: reviewer,
            checkout: FakeRepoCheckout(ancestry: .ancestor),
            reviews: reviews
        )
        await prepared(store)

        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }

        let record = try #require(store.reviewRecord(for: pr))
        #expect(record.headSha == "new2222")
        #expect(record.findings.count == 2)
        let carried = try #require(record.findings.first { $0.carriedFrom != nil })
        #expect(carried.headSha == "new2222")
        #expect(carried.carriedFrom == "old1111")
        #expect(carried.reported.summary == "chybí kontrola")
        // A verdikt u něj — odznak, ne ubraný nález.
        let statuses = Policy.findingStatuses(of: record, head: "new2222")
        #expect(statuses[Policy.key(of: carried)]?.verdict == .stillApplies)
        #expect(statuses[Policy.key(of: carried)]?.note == "pořád tam je")
    }

    /// **Vyřešený pushem nezmizí.** Sundat nález smí jedině odmítnutí člověkem (#113), takže
    /// „vyřešeno“ je odznak — a tenhle test je ten, který to hlídá na celé cestě, ne jen v `Policy`.
    @Test("Vyřešený pushem zůstane v záznamu")
    func aResolvedFindingSurvives() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        _ = try await firstRound(in: reviews)
        let reviewer = FakeReviewRunner(resultText: #"[{"id":0,"status":"resolved"}]"#)
        let store = store(
            reviewer: reviewer,
            checkout: FakeRepoCheckout(ancestry: .ancestor),
            reviews: reviews
        )
        await prepared(store)

        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }

        let record = try #require(store.reviewRecord(for: pr))
        let carried = try #require(record.findings.first)
        #expect(record.activeFindings.count == 1)
        #expect(Policy.findingStatuses(of: record, head: "new2222")[Policy.key(of: carried)]?
            .verdict == .resolved)
    }

    /// Odpověď, kterou se nepodařilo přečíst, **nálezy nezahodí**: skončí jako `bez odpovědi`,
    /// což je v okně vidět. Tiché nule by se dalo věřit.
    @Test("Nepřečtená odpověď nechá staré nálezy bez odznaku")
    func anUnreadableAnswerLeavesTheFindingsUnanswered() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        _ = try await firstRound(in: reviews)
        let reviewer = FakeReviewRunner(resultText: "tohle není JSON")
        let store = store(
            reviewer: reviewer,
            checkout: FakeRepoCheckout(ancestry: .ancestor),
            reviews: reviews
        )
        await prepared(store)

        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }

        let record = try #require(store.reviewRecord(for: pr))
        let tally = try #require(Policy.incrementalTally(of: record.runs[0], in: record))
        #expect(tally.carried == 1)
        #expect(tally.unanswered == 1)
        #expect(Policy.findingStatuses(of: record, head: "new2222").isEmpty)
    }

    /// Dráha v `Průběhu` nese rozsah — i **po restartu**, protože jde do osy jako událost.
    @Test("Dráha v Průběhu nese rozsah a souhrn")
    func theLaneCarriesTheRangeAndTheTally() async throws {
        let reviews = ReviewStore(layout: layout, time: time)
        _ = try await firstRound(in: reviews)
        let reviewer = FakeReviewRunner(
            findings: [makeReported(summary: "nový")],
            usage: RunUsage(cost: 0.12),
            resultText: #"[{"id":0,"status":"resolved"}]"#
        )
        let store = store(
            reviewer: reviewer,
            checkout: FakeRepoCheckout(ancestry: .ancestor),
            reviews: reviews
        )
        await prepared(store)

        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(self.pr) }

        let lanes = Policy.lanes(
            of: store.timelines(for: pr),
            skills: ["code-review"],
            record: store.reviewRecord(for: pr)
        )
        let increment = try #require(lanes.first?.increment)
        #expect(increment.range == IncrementalDiffRange(seen: "old1111", head: "new2222"))
        #expect(increment.tally?.new == 1)
        #expect(increment.tally?.resolved == 1)
        // Cena celého běhu z prvního kola stojí vedle ceny přírůstku.
        #expect(increment.tally?.wholeUsage?.cost == 0.82)
        #expect(lanes.first?.usage?.cost == 0.12)
    }
}
