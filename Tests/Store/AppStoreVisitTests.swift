import Foundation
import Testing

@testable import PRism

/// Návštěvy PR (#173) — dvě značky, každá kvůli něčemu jinému: jedna přežije restart,
/// druhá říká, proti čemu se počítá v tomhle běhu.
@Suite("AppStore — návštěvy")
@MainActor
struct AppStoreVisitTests {
    private let pr = PRIdentifier("cli/cli#1")!
    private let other = PRIdentifier("cli/cli#2")!
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func store(
        preferences: InMemoryPreferences = InMemoryPreferences(),
        time: FakeTimeSource? = nil,
        conversations: [Result<Conversation, any Error>] = []
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway([.success([])], conversations: conversations),
            time: time ?? FakeTimeSource(start: start),
            visits: VisitLedger(preferences: preferences)
        )
    }

    private func summary(_ id: PRIdentifier) -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private var emptyConversation: Conversation {
        Conversation(
            viewer: "ja",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(items: [], total: 0, hasNextPage: false),
            events: ConversationPage(items: [], hasNextPage: false)
        )
    }

    @Test("První návštěva se zapíše a nic neukáže")
    func theFirstVisitIsRecordedAndShowsNothing() {
        let preferences = InMemoryPreferences()
        let store = store(preferences: preferences)

        store.noteVisit(to: pr)

        // Zapsaná je — jinak by o ní příští spuštění nevědělo.
        #expect(VisitLedger(preferences: preferences).lastVisit(to: pr)?.at == start)
        // Ale snapshot je „teď", takže se nemá co ukázat: u PR viděného poprvé není „od minule".
        #expect(store.visitSnapshots[pr] == start)
    }

    @Test("Uvnitř jednoho PR se snapshot nemění")
    func theSnapshotSurvivesWithinOnePullRequest() {
        // Odskok do `Změněných souborů` a zpátky přegeneruje pohled, ale je to pořád tatáž
        // návštěva — banner o ni nesmí přijít dřív, než ho stihnu přečíst. Značka
        // v předvolbách se přitom posouvá dál.
        let preferences = InMemoryPreferences()
        let time = FakeTimeSource(start: start)
        let store = store(preferences: preferences, time: time)

        store.noteVisit(to: pr)
        let first = store.visitSnapshots[pr]
        time.advance(by: 3600)
        store.noteVisit(to: pr)

        #expect(store.visitSnapshots[pr] == first)
        #expect(VisitLedger(preferences: preferences).lastVisit(to: pr)?.at == start.addingTimeInterval(3600))
    }

    @Test("Odchod na jiný PR a návrat je nová návštěva")
    func leavingAndComingBackIsANewVisit() async {
        // Během té první návštěvy jsem banner na obrazovce měl, takže se podruhé neukazuje.
        let time = FakeTimeSource(start: start)
        let store = store(time: time, conversations: [.success(emptyConversation)])
        await store.loadConversation(for: summary(pr))

        store.noteVisit(to: pr)
        time.advance(by: 60)
        store.noteVisit(to: other)
        time.advance(by: 60)
        store.noteVisit(to: pr)

        #expect(store.visitSnapshots[pr] == start.addingTimeInterval(60))
    }

    @Test("Proletění seznamu bez načtené konverzace banner nespotřebuje")
    func skimmingTheListDoesNotConsumeTheBanner() {
        // Nejcennější test v souboru: bez načtené konverzace se banner nemá z čeho vykreslit,
        // takže na obrazovce nebyl — a „viděl jsem to" by byla lež. Bez téhle podmínky by
        // projetí seznamu šipkami zahodilo novinky u všech PR, přes které jsem přejel.
        let time = FakeTimeSource(start: start)
        let store = store(time: time)

        store.noteVisit(to: pr)
        let first = store.visitSnapshots[pr]
        time.advance(by: 60)
        store.noteVisit(to: other)
        time.advance(by: 60)
        store.noteVisit(to: pr)

        #expect(store.visitSnapshots[pr] == first)
    }

    @Test("Druhé spuštění počítá proti minulé návštěvě")
    func asecondLaunchMeasuresAgainstTheLastVisit() {
        // Předvolby přežijí, store ne — tohle je to, co se děje po restartu aplikace.
        let preferences = InMemoryPreferences()
        store(preferences: preferences).noteVisit(to: pr)

        let time = FakeTimeSource(start: start.addingTimeInterval(86_400))
        let next = store(preferences: preferences, time: time)
        next.noteVisit(to: pr)

        #expect(next.visitSnapshots[pr] == start)
    }

    @Test("Přečteno posune značku na teď")
    func markingAsSeenMovesTheMark() {
        let preferences = InMemoryPreferences()
        let time = FakeTimeSource(start: start)
        let store = store(preferences: preferences, time: time)
        store.noteVisit(to: pr)
        time.advance(by: 3600)

        store.markChangesAsSeen(for: pr)

        #expect(store.visitSnapshots[pr] == start.addingTimeInterval(3600))
        // A zapíše se i do předvoleb, jinak by se banner po restartu vrátil.
        #expect(VisitLedger(preferences: preferences).lastVisit(to: pr)?.at == start.addingTimeInterval(3600))
    }

    @Test("Přečtené se dalším otevřením nevrátí")
    func whatWasSeenDoesNotComeBack() {
        // Nejcennější test v souboru: „přečteno" má vydržet. Kdyby `noteVisit` snapshot
        // přepsal zpátky, pruh by naskočil při prvním přepnutí na jiný PR a zpátky.
        let time = FakeTimeSource(start: start)
        let store = store(time: time)
        store.noteVisit(to: pr)
        time.advance(by: 3600)
        store.markChangesAsSeen(for: pr)

        time.advance(by: 60)
        store.noteVisit(to: pr)

        #expect(store.visitSnapshots[pr] == start.addingTimeInterval(3600))
    }

    private func detail(_ head: String) -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: head,
            baseSha: "base",
            url: URL(string: "https://github.com/cli/cli/pull/1")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(
        preferences: InMemoryPreferences,
        time: FakeTimeSource,
        head: String
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway([.success([])], detail: .success(detail(head))),
            time: time,
            visits: VisitLedger(preferences: preferences)
        )
    }

    @Test("Posunutá hlava se pozná i bez commitu na časové ose")
    func aMovedHeadIsDetectedWithoutTimelineEvents() async {
        // Tohle je ten případ, kvůli kterému se hlava vůbec ukládá: `TimelineEvent.at` je
        // u commitu `committedDate`, ne čas pushnutí, takže po rebase je starší než moje
        // návštěva a commit z „od minule" vypadne. Porovnání sha na to nesáhne.
        let preferences = InMemoryPreferences()
        let first = store(preferences: preferences, time: FakeTimeSource(start: start), head: "aaa1111")
        first.noteVisit(to: pr)
        await first.loadDetail(for: summary(pr))

        let second = store(
            preferences: preferences,
            time: FakeTimeSource(start: start.addingTimeInterval(86_400)),
            head: "bbb2222"
        )
        second.noteVisit(to: pr)
        await second.loadDetail(for: summary(pr))

        #expect(second.movedHead(for: pr) == "bbb2222")
    }

    @Test("Nezměněná hlava se za posun nevydává")
    func anUnchangedHeadIsNotAMove() async {
        let preferences = InMemoryPreferences()
        let first = store(preferences: preferences, time: FakeTimeSource(start: start), head: "aaa1111")
        first.noteVisit(to: pr)
        await first.loadDetail(for: summary(pr))

        let second = store(
            preferences: preferences,
            time: FakeTimeSource(start: start.addingTimeInterval(86_400)),
            head: "aaa1111"
        )
        second.noteVisit(to: pr)
        await second.loadDetail(for: summary(pr))

        #expect(second.movedHead(for: pr) == nil)
    }

    @Test("Bez znalosti minulé hlavy se posun netvrdí")
    func withoutAKnownHeadNothingIsClaimed() async {
        // První otevření PR: starou hlavu neznáme, takže „posunulo se" by byla výmluva.
        let store = store(preferences: InMemoryPreferences(), time: FakeTimeSource(start: start), head: "aaa1111")
        store.noteVisit(to: pr)
        await store.loadDetail(for: summary(pr))

        #expect(store.movedHead(for: pr) == nil)
    }

    @Test("Přečteno skryje i banner, který visel kvůli posunuté hlavě")
    func markingAsSeenAlsoMovesTheHead() async {
        // Křížek musí fungovat i v tom případě, kvůli kterému sha vůbec existuje: po rebase
        // časová osa mlčí a banner drží jen posunutá hlava. Kdyby se posunul jen čas, pruh by
        // po kliknutí zůstal viset.
        let preferences = InMemoryPreferences()
        let first = store(preferences: preferences, time: FakeTimeSource(start: start), head: "aaa1111")
        first.noteVisit(to: pr)
        await first.loadDetail(for: summary(pr))

        let second = store(
            preferences: preferences,
            time: FakeTimeSource(start: start.addingTimeInterval(86_400)),
            head: "bbb2222"
        )
        second.noteVisit(to: pr)
        await second.loadDetail(for: summary(pr))
        #expect(second.movedHead(for: pr) == "bbb2222")

        second.markChangesAsSeen(for: pr)

        #expect(second.movedHead(for: pr) == nil)
        // A přežije to restart — jinak by se pruh vrátil při dalším spuštění.
        #expect(VisitLedger(preferences: preferences).lastVisit(to: pr)?.head == "bbb2222")
    }

    @Test("Odchod na jiný PR posune i hlavu")
    func leavingAlsoMovesTheHead() async {
        // Totéž pravidlo jako u „přečteno": návrat je nová návštěva, takže po něm nesmí banner
        // viset ani kvůli sha.
        let preferences = InMemoryPreferences()
        let first = store(preferences: preferences, time: FakeTimeSource(start: start), head: "aaa1111")
        first.noteVisit(to: pr)
        await first.loadDetail(for: summary(pr))

        let time = FakeTimeSource(start: start.addingTimeInterval(86_400))
        let second = AppStore(
            gateway: FakeGitHubGateway(
                [.success([])],
                detail: .success(detail("bbb2222")),
                conversations: [.success(emptyConversation)]
            ),
            time: time,
            visits: VisitLedger(preferences: preferences)
        )
        second.noteVisit(to: pr)
        await second.loadDetail(for: summary(pr))
        await second.loadConversation(for: summary(pr))
        #expect(second.movedHead(for: pr) == "bbb2222")

        second.noteVisit(to: other)
        second.noteVisit(to: pr)

        #expect(second.movedHead(for: pr) == nil)
    }

    @Test("Bez načtené konverzace se nic neukazuje")
    func withoutAConversationThereIsNothingToShow() {
        // „Nic nového" nad nenačtenými daty je tvrzení, které data neunesou.
        let store = store()
        store.noteVisit(to: pr)

        #expect(store.changesSinceLastVisit(for: pr).isEmpty)
    }
}
