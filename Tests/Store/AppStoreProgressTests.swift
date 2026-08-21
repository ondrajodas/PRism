import Foundation
import Testing

@testable import PRism

/// Časová osa toho, co reviewer dělal. Drží ji store, aby zůstala i po doběhnutí běhu —
/// právě tehdy se k ní člověk vrací.
@Suite("AppStore — průběh review")
@MainActor
struct AppStoreProgressTests {
    private let sources = [Source(name: "Moje", query: "review-requested:@me is:open")]

    /// Zdroje i sada skillů se berou z konfigurace, takže si ji test postaví.
    private var configuration: Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = sources
        return configuration
    }
    private let pr = PRIdentifier("cli/cli#1")!

    private func detail() -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: "head123",
            baseSha: "base456",
            url: URL(string: "https://github.com/cli/cli/pull/1")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(_ reviewer: FakeReviewRunner, reviews: ReviewStore) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail())),
            configuration: configuration,
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(outcome: .success(URL(filePath: "/tmp/clone.git"))),
            reviewer: reviewer,
            reviews: reviews,
        )
    }

    private func runReview(_ store: AppStore) async {
        store.startReview(for: pr)
        await waitUntil("review doběhne") { !store.isReviewing(pr) }
    }

    /// Nastavené id, které na nic nemapuje, si model nahradí nejbližším — a hlavička osy
    /// by pak tvrdila, že běžel nastavený skill. Ověřeno u #78 na skutečném běhu.
    @Test("Načtený jiný skill se pozná")
    func spotsADifferentSkill() {
        var timeline = ReviewerTimeline(skill: "code-review")
        timeline.record(
            .attemptedTool(ToolAttempt(name: "Skill", detail: "code-review:code-review")),
            at: Date(timeIntervalSince1970: 0)
        )

        #expect(timeline.loadedSkill == "code-review:code-review")
        #expect(timeline.loadedADifferentSkill)
    }

    @Test("Načtený správný skill se za záměnu nepovažuje")
    func acceptsTheRequestedSkill() {
        var timeline = ReviewerTimeline(skill: "code-review:code-review")
        timeline.record(
            .attemptedTool(ToolAttempt(name: "Skill", detail: "code-review:code-review")),
            at: Date(timeIntervalSince1970: 0)
        )

        #expect(!timeline.loadedADifferentSkill)
    }

    /// Běh, který si skill nevzal vůbec, udělal obecné review — jiná situace než záměna,
    /// a hlásit u něj „běžel jiný“ by bylo matoucí.
    @Test("Běh bez skillu není záměna")
    func aRunWithoutASkillIsNotAMismatch() {
        var timeline = ReviewerTimeline(skill: "code-review")
        timeline.record(
            .attemptedTool(ToolAttempt(name: "Read", detail: "App/Main.swift")),
            at: Date(timeIntervalSince1970: 0)
        )

        #expect(timeline.loadedSkill == nil)
        #expect(!timeline.loadedADifferentSkill)
    }

    @Test("Průběh běhu se zaznamená v pořadí")
    func recordsProgressInOrder() async throws {
        let workspace = try TemporaryDirectory()
        // `.queued` hlásí runner sám, tady se dopisuje zbytek.
        let reviewer = FakeReviewRunner(
            progress: [
                .started(sessionID: "session-abc"),
                .attemptedTool(ToolAttempt(name: "Read", detail: "App/Main.swift")),
                .findings(count: 2),
            ]
        )
        let store = store(reviewer, reviews: ReviewStore(layout: CacheLayout(root: workspace.url)))

        await runReview(store)

        let timeline = try #require(store.timelines(for: pr).first)
        #expect(timeline.skill == Configuration.standard.global.skills.first)
        #expect(timeline.sessionID == "session-abc")
        // Pořadí je to hlavní, co časová osa říká.
        #expect(timeline.entries.map(\.kind) == [
            .queued,
            .started,
            .tool(ToolAttempt(name: "Read", detail: "App/Main.swift")),
            .findings(count: 2),
            .finished(.finished),
        ])
        // A na disk jde **tatáž osa** (#308), ne to, co z ní bylo hotové ve chvíli zápisu.
        // Do #308 se snímek pro uložení bral mimo proud událostí, takže o obsahu souboru
        // rozhodoval závod na `MainActoru`: celá osa, samotné `[ve frontě]`, nebo žádná —
        // a `dropped` u toho zůstalo nulové, tedy o zkrácení mlčelo.
        let stored = try #require(store.reviewRecord(for: pr)?.runs.first?.timeline)
        #expect(stored.entries == timeline.entries)
        #expect(stored.dropped == 0)
    }

    /// K průběhu se člověk vrací **po** doběhnutí — „co to vlastně četlo?“.
    @Test("Časová osa zůstane i po doběhnutí")
    func keepsTheTimelineAfterTheRun() async throws {
        let workspace = try TemporaryDirectory()
        let store = store(
            FakeReviewRunner(progress: [.started(sessionID: "s")]),
            reviews: ReviewStore(layout: CacheLayout(root: workspace.url))
        )

        await runReview(store)

        #expect(!store.isReviewing(pr))
        #expect(store.timelines(for: pr).first?.entries.isEmpty == false)
    }

    @Test("Nový běh začíná s čistou osou")
    func startsAFreshTimelineForEveryRun() async throws {
        let workspace = try TemporaryDirectory()
        let store = store(
            FakeReviewRunner(progress: [.started(sessionID: "s")]),
            reviews: ReviewStore(layout: CacheLayout(root: workspace.url))
        )

        await runReview(store)
        let first = store.timelines(for: pr).first?.entries.count
        await runReview(store)

        #expect(store.timelines(for: pr).first?.entries.count == first)
    }

    /// Store, který si tik pollingu odbude jednou a skončí — PR v něm není, takže se na něm dá
    /// vyzkoušet úklid.
    private func store(_ reviewer: FakeReviewRunner, tickingOnceIn workspace: TemporaryDirectory) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail())),
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1),
            checkout: FakeRepoCheckout(outcome: .success(URL(filePath: "/tmp/clone.git"))),
            reviewer: reviewer,
            reviews: ReviewStore(layout: CacheLayout(root: workspace.url)),
        )
    }

    /// **Tik uklidí živou kopii osy, ne osu** (#308; do té doby se tenhle test jmenoval
    /// „…se zahodí“ a tvrdil, že po tiku není osa žádná).
    ///
    /// Uložený záznam se totiž schválně neuklízí (#137 na něm pozná re-review od novinky), takže
    /// `timelines(for:)` po tiku odpovídá z disku — přesně jako po restartu (#203). Jediné, co se
    /// pustilo, je kopie v paměti; a co okno ukáže, musí být **tatáž osa**, ne její zkrácený opis.
    @Test("Průběh PR, které zmizelo ze seznamu, se pustí z paměti, ale zůstane v záznamu")
    func releasesTheLiveTimelineOfAPullRequestThatLeftTheList() async throws {
        let workspace = try TemporaryDirectory()
        let store = store(
            FakeReviewRunner(progress: [.started(sessionID: "s")]),
            tickingOnceIn: workspace
        )

        await runReview(store)
        let live = try #require(store.timelines(for: pr).first)

        await store.keepFresh()   // tik, ve kterém to PR není

        // Živá kopie se pustí — to je celý úklid, který tik nad osou dělá.
        #expect(store.reviewTimelines[pr] == nil)
        // A osa, kterou okno ukáže potom, je ta samá. Tohle tvrzení chytá závod z #308: tehdy
        // v ní chybělo `započalo` a razítka byla ze dvou různých hodin, protože konec osy
        // dopočítala `completeTail` z `finishedAt` uloženého běhu.
        let stored = try #require(store.timelines(for: pr).first)
        #expect(stored.entries == live.entries)
        #expect(stored.entries.map(\.kind) == [.queued, .started, .finished(.finished)])
        // `sessionID` se **neporovnává**: fake ho hlásí v události průběhu (`s`) jinak než
        // v souhrnu session (`session-<skill>`), takže by se tady porovnávala vlastnost fake,
        // ne aplikace. Ve skutečném běhu je to jedna a tatáž hodnota z jedné session.
    }

    /// **Nejcennější tvrzení téhle sady**: běžícímu review tik osu nesebere a událost, která
    /// dorazí po tiku, do ní **pokračuje** — nezakládá druhou ani novou.
    ///
    /// Je to druhá polovina odpovědi z #308. Pozdní událost zahozeného běhu nastat nemůže (proud
    /// se dojíždí uvnitř `review()`, takže po jeho konci už žádná nepřijde), ale událost běhu,
    /// který **pořád běží**, přijít musí — a `forget` proto osu běžícího review vyjímá z úklidu.
    /// Kdyby to přestalo platit, dostal by tab `Průběh` osu začínající uprostřed, tedy zrovna to
    /// tiché zkrácení, které #203 zakazuje.
    @Test("Běžícímu review tik osu nesebere a další událost do ní pokračuje")
    func keepsTheTimelineOfARunningReviewAcrossATick() async throws {
        let workspace = try TemporaryDirectory()
        let reviewer = FakeReviewRunner(
            holdsUntilRelease: true,
            progress: [.started(sessionID: "s")],
            // Krok nad kódem dorazí **až po tiku** — tedy to, čemu se v #308 říkalo „pozdní
            // událost“. Do osy má pokračovat, ne si založit novou začínající uprostřed běhu.
            progressAfterRelease: [.attemptedTool(ToolAttempt(name: "Read", detail: "App/Main.swift"))]
        )
        let store = store(reviewer, tickingOnceIn: workspace)

        store.startReview(for: pr)
        await waitUntil("osa má rozjezd") { store.timelines(for: pr).first?.entries.count == 2 }

        await store.keepFresh()   // tik, ve kterém to PR není

        // Osa běžícího review zůstala v paměti celá — a samo review běží dál, protože si ho
        // vyžádal člověk.
        #expect(store.isReviewing(pr))
        #expect(store.reviewTimelines[pr]?.count == 1)
        #expect(store.timelines(for: pr).first?.entries.map(\.kind) == [.queued, .started])

        reviewer.releaseAll()
        await waitUntil("review doběhne") { !store.isReviewing(pr) }

        // Krok i konec dorazily **po** tiku a připsaly se do téže osy, ne do nové: kdyby ji tik
        // sebral, začínala by osa `Read`em, tedy uprostřed běhu — a nic by neřeklo, že rozjezd
        // chybí (`droppedEntries` by zůstalo nulové).
        #expect(store.timelines(for: pr).count == 1)
        #expect(store.timelines(for: pr).first?.entries.map(\.kind) == [
            .queued,
            .started,
            .tool(ToolAttempt(name: "Read", detail: "App/Main.swift")),
            .finished(.finished),
        ])
        #expect(store.timelines(for: pr).first?.droppedEntries == 0)
    }
}
