import Foundation
import Testing

@testable import PRism

/// Cizí aktivita na vlastních PR ze strany store (#335) — rozhlídka na pozadí a notifikace.
///
/// **Nejcennější tvrzení sady je, že notifikace o téže věci nedorazí dvakrát.** `VisitLedger` drží
/// poslední návštěvu, ne poslední oznámení, takže bez druhého razítka by „2 nové komentáře“ chodily
/// při každé rozhlídce, dokud PR neotevřu. Druhé v řadě je, že se **nic netahá** tam, kde není proč:
/// u cizích PR, beze změny `updatedAt` a dřív, než vyprší vlastní interval.
@Suite("AppStore — cizí aktivita na vlastních PR (#335)")
@MainActor
struct AppStoreActivityTests {
    private let pr = PRIdentifier("ondrajodas/PRism#324")!
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private var configuration: Configuration {
        var configuration = Configuration.standard
        // Jediný zdroj, ať je na tik jeden dotaz — a `ownLogins` místo dotaženého viewera, ať
        // rozřazení nezávisí na tom, kdy dojde `gh api user`.
        configuration.global.sources = [.mine]
        configuration.global.ownLogins = ["ondrajodas"]
        return configuration
    }

    private func summary(
        _ identifier: String? = nil,
        author: String = "ondrajodas",
        updated offset: TimeInterval
    ) -> PullRequestSummary {
        let id = identifier.flatMap { PRIdentifier($0) } ?? pr
        return PullRequestSummary(
            id: id,
            title: "feat: put the reviewer run timeout into settings",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: start.addingTimeInterval(offset),
            state: .open
        )
    }

    private func comment(
        id: String,
        by author: String = "odinuv",
        body: String = "opravdu to potřebuje ten mutex?",
        at offset: TimeInterval
    ) -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: body,
            createdAt: start.addingTimeInterval(offset),
            url: URL(string: "https://github.com/ondrajodas/PRism/pull/324#c-\(id)")!
        )
    }

    private func conversation(_ comments: [ThreadComment]) -> Conversation {
        Conversation(
            viewer: "ondrajodas",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(items: comments, total: comments.count, hasNextPage: false)
        )
    }

    private func store(
        _ gateway: FakeGitHubGateway,
        center: FakeNotificationCenter? = nil,
        time: FakeTimeSource,
        preferences: InMemoryPreferences = InMemoryPreferences()
    ) -> AppStore {
        AppStore(
            gateway: gateway,
            configuration: configuration,
            time: time,
            notifications: center,
            visits: VisitLedger(preferences: preferences),
            activityNotices: ActivityNoticeLedger(preferences: preferences)
        )
    }

    /// Notifikace o **téže věci** nesmí přijít dvakrát, ani když se rozhlídka na PR podívá znovu
    /// (protože se `updatedAt` mezitím pohnul něčím jiným). Drží to druhé razítko —
    /// `ActivityNoticeLedger` —, protože oznámením PR nenavštívím a značka návštěvy se nehne.
    @Test("O témže komentáři se nehlásí dvakrát")
    func announcesTheSameCommentOnlyOnce() async {
        let center = FakeNotificationCenter()
        let time = FakeTimeSource(start: start)
        let mention = comment(id: "c1", at: 300)
        let gateway = FakeGitHubGateway(
            [
                .success([summary(updated: -100)]),
                .success([summary(updated: 400)]),
                // Třetí tik: `updatedAt` se pohnul zas (třeba mým vlastním pushem), takže se
                // rozhlídka **zeptá znovu** — a právě tady by bez razítka přišla druhá hláška.
                .success([summary(updated: 900)]),
            ],
            conversations: [
                .success(conversation([])),
                .success(conversation([mention])),
                .success(conversation([mention])),
            ]
        )
        let store = store(gateway, center: center, time: time)

        await store.refresh()
        time.advance(by: Policy.activitySweepInterval)
        await store.refresh()
        time.advance(by: Policy.activitySweepInterval)
        await store.refresh()

        #expect(gateway.conversationRequests.count == 3)
        #expect(center.delivered.count == 1)
        #expect(center.delivered.first?.title == "1 nový komentář")
        #expect(center.delivered.first?.event == .activity)
    }

    @Test("Novější komentář se ohlásí znovu")
    func announcesANewerCommentAgain() async {
        // Razítko nesmí umlčet **novou** věc — jen tu, o které se hlásilo.
        let center = FakeNotificationCenter()
        let time = FakeTimeSource(start: start)
        let first = comment(id: "c1", at: 300)
        let second = comment(id: "c2", body: "a ještě jedna věc", at: 700)
        let gateway = FakeGitHubGateway(
            [
                .success([summary(updated: -100)]),
                .success([summary(updated: 400)]),
                .success([summary(updated: 800)]),
            ],
            conversations: [
                .success(conversation([])),
                .success(conversation([first])),
                .success(conversation([first, second])),
            ]
        )
        let store = store(gateway, center: center, time: time)

        await store.refresh()
        time.advance(by: Policy.activitySweepInterval)
        await store.refresh()
        time.advance(by: Policy.activitySweepInterval)
        await store.refresh()

        #expect(center.delivered.count == 2)
        #expect(center.delivered.last?.body.hasPrefix("odinuv: a ještě jedna věc") == true)
    }

    /// **Tvrzení, že se nic nestalo**: o vlastním komentáři se nehlásí. Bez `Conversation.isMine`
    /// by mi aplikace oznamovala, že jsem něco napsal.
    @Test("O vlastním komentáři se nehlásí")
    func staysQuietAboutMyOwnComment() async {
        let center = FakeNotificationCenter()
        let time = FakeTimeSource(start: start)
        let gateway = FakeGitHubGateway(
            [.success([summary(updated: -100)]), .success([summary(updated: 400)])],
            conversations: [
                .success(conversation([])),
                .success(conversation([comment(id: "c1", by: "ondrajodas", at: 300)])),
            ]
        )
        let store = store(gateway, center: center, time: time)

        await store.refresh()
        time.advance(by: Policy.activitySweepInterval)
        await store.refresh()

        #expect(gateway.conversationRequests.count == 2)
        #expect(center.delivered.isEmpty)
    }

    /// **Tvrzení, že se nic nestalo**, a je to ta cena, o kterou v issue šlo: cizí PR se na diskuzi
    /// neptá vůbec. Na cizím PR je moje práce spustit review, ne hlídat diskuzi.
    @Test("Cizí PR se na konverzaci neptá")
    func doesNotFetchTheConversationOfAForeignPullRequest() async {
        let center = FakeNotificationCenter()
        let time = FakeTimeSource(start: start)
        let gateway = FakeGitHubGateway(
            always: .success([summary("keboola/vault#85", author: "odinuv", updated: -100)]),
            conversations: [.success(conversation([comment(id: "c1", at: 300)]))]
        )
        let store = store(gateway, center: center, time: time)

        await store.refresh()
        time.advance(by: Policy.activitySweepInterval)
        await store.refresh()

        #expect(gateway.conversationRequests.isEmpty)
        #expect(center.delivered.isEmpty)
    }

    /// **Tvrzení, že se nic nestalo**: dva tiky za sebou znamenají jednu rozhlídku. Bez vlastního
    /// intervalu by to byl dotaz na konverzaci **každou minutu** za každé vlastní PR.
    @Test("Dva tiky v intervalu dají jednu rozhlídku")
    func sweepsOncePerInterval() async {
        let time = FakeTimeSource(start: start)
        let gateway = FakeGitHubGateway(
            [
                .success([summary(updated: -100)]),
                // `updatedAt` se pohnul, takže by se **jinak** ptalo znovu — brání tomu interval.
                .success([summary(updated: 400)]),
            ],
            conversations: [.success(conversation([]))]
        )
        let store = store(gateway, time: time)

        await store.refresh()
        time.advance(by: 60)
        await store.refresh()

        #expect(gateway.conversationRequests.count == 1)
    }

    /// **Tvrzení, že se nic nestalo**: dotažení konverzace na pozadí **není návštěva**. Kdyby se
    /// zapsala, značka „od minule“ by se posunula na teď a řádek by o komentáři kolegy mlčel.
    @Test("Rozhlídka nezapíše návštěvu")
    func aSweepIsNotAVisit() async {
        let preferences = InMemoryPreferences()
        let time = FakeTimeSource(start: start)
        let gateway = FakeGitHubGateway(
            always: .success([summary(updated: -100)]),
            conversations: [.success(conversation([]))]
        )
        let store = store(gateway, time: time, preferences: preferences)

        await store.refresh()

        #expect(gateway.conversationRequests == [pr])
        #expect(VisitLedger(preferences: preferences).lastVisit(to: pr) == nil)
        // Značka v paměti ale vzniknout musí — bez ní by „od minule“ nemělo proti čemu počítat.
        #expect(store.visitSnapshots[pr] == start)
    }

    /// Co z toho vidí řádek seznamu: **tentýž report** jako pilulka `N k předání`, takže se nemají
    /// jak rozejít.
    @Test("Řádek dostane cizí aktivitu z téhož reportu")
    func theRowReadsTheActivityFromTheSameReport() async {
        let time = FakeTimeSource(start: start)
        let gateway = FakeGitHubGateway(
            [.success([summary(updated: -100)]), .success([summary(updated: 400)])],
            conversations: [
                .success(conversation([])),
                .success(conversation([comment(id: "c1", at: 300), comment(id: "c2", at: 350)])),
            ]
        )
        let store = store(gateway, time: time)

        await store.refresh()
        time.advance(by: Policy.activitySweepInterval)
        await store.refresh()

        #expect(store.foreignActivity(for: pr).count == 2)
        #expect(store.handoffReport(for: pr).activity == store.foreignActivity(for: pr))
        #expect(PullRequestRow(
            pullRequest: summary(updated: 400),
            reviewState: .notStarted,
            ownership: .mine,
            activity: store.foreignActivity(for: pr)
        ).activityLine == "2 nové komentáře od minule")
    }

    /// Vypnutý přepínač znamená **ticho**, ne jen jiný text — brána je v `AppStore.notify` (#86),
    /// takže se u nové události nedá zapomenout.
    @Test("Vypnutý přepínač hlášku nepustí")
    func theSwitchStopsIt() async {
        let center = FakeNotificationCenter()
        let time = FakeTimeSource(start: start)
        var configuration = configuration
        configuration.global.notifications.activity = false
        let gateway = FakeGitHubGateway(
            [.success([summary(updated: -100)]), .success([summary(updated: 400)])],
            conversations: [
                .success(conversation([])),
                .success(conversation([comment(id: "c1", at: 300)])),
            ]
        )
        let store = AppStore(
            gateway: gateway,
            configuration: configuration,
            time: time,
            notifications: center,
            visits: VisitLedger(preferences: InMemoryPreferences()),
            activityNotices: ActivityNoticeLedger(preferences: InMemoryPreferences())
        )

        await store.refresh()
        time.advance(by: Policy.activitySweepInterval)
        await store.refresh()

        #expect(center.delivered.isEmpty)
        // Konverzace se přesto načetla: text v řádku na ní stojí a ten se nevypíná.
        #expect(store.foreignActivity(for: pr).count == 1)
    }

    /// Přechodné selhání razítko **nehne**, takže se hláška neztratí — tatáž nesymetrie jako
    /// u nových PR (#85): zapsat před doručením znamená notifikaci, která už nikdy nepřijde.
    @Test("Po selhaném doručení se to zkusí znovu")
    func retriesAfterAFailedDelivery() async {
        let center = FakeNotificationCenter(outcome: .failed("centrum neodpovědělo"))
        let time = FakeTimeSource(start: start)
        let mention = comment(id: "c1", at: 300)
        let gateway = FakeGitHubGateway(
            [
                .success([summary(updated: -100)]),
                .success([summary(updated: 400)]),
                .success([summary(updated: 900)]),
            ],
            conversations: [
                .success(conversation([])),
                .success(conversation([mention])),
                .success(conversation([mention])),
            ]
        )
        let store = store(gateway, center: center, time: time)

        await store.refresh()
        time.advance(by: Policy.activitySweepInterval)
        await store.refresh()
        #expect(center.delivered.count == 1)

        center.answer(with: .delivered)
        time.advance(by: Policy.activitySweepInterval)
        await store.refresh()

        #expect(center.delivered.count == 2)
        #expect(center.delivered.allSatisfy { $0.title == "1 nový komentář" })
    }

    /// Selhaný tik rozhlídku **nespustí**, takže se při rate limitu ani nekouká: běží uvnitř
    /// `afterSuccessfulTick`, tedy v backoffu pollingu, ne vedle něj.
    @Test("Rate limit rozhlídku nepustí")
    func aRateLimitedTickDoesNotSweep() async {
        let time = FakeTimeSource(start: start)
        let gateway = FakeGitHubGateway(
            [.failure(GitHubError.rateLimited("API rate limit exceeded"))],
            conversations: [.success(conversation([comment(id: "c1", at: 300)]))]
        )
        let store = store(gateway, time: time)

        await store.refresh()

        #expect(gateway.conversationRequests.isEmpty)
    }
}
