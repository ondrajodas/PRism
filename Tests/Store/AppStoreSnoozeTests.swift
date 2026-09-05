import Foundation
import Testing

@testable import PRism

/// Odložení pull requestu ze strany store (#512).
///
/// **Cenná polovina jsou tvrzení o tom, co se nestane**, a u odložení to platí dvojnásob: odložený
/// PR není vidět, takže se každá z těchhle chyb rozbije potichu. Neobjeví se ve frontě, nepočítá
/// se do odznaku ani do souhrnu, nespustí se na něj automat a nezazvoní o něm notifikace — a
/// naopak se **nesmí ztratit**: leží v bloku `Odložené`, úklid po tiku mu nesmí zahodit nálezy
/// a odložení se nesmí zrušit dřív, než má.
@Suite("AppStore — odložení PR (#512)")
@MainActor
struct AppStoreSnoozeTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let pr = PRIdentifier("cli/cli#1")!
    private let other = PRIdentifier("cli/cli#2")!

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func configuration(automatic: Bool = false, notifications: Bool = true) -> Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = [Source(name: "Moje", query: "review-requested:@me is:open")]
        configuration.global.ownLogins = ["ondrajodas"]
        configuration.global.notifications.isEnabled = notifications
        if automatic { configuration.global.mode = .automatic }
        return configuration
    }

    private func summary(
        _ text: String,
        author: String = "odinuv",
        updatedAt: Date? = nil
    ) -> PullRequestSummary {
        let id = PRIdentifier(text)!
        return PullRequestSummary(
            id: id,
            title: "chore: modernize dependencies",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: updatedAt ?? start,
            state: .open
        )
    }

    private func store(
        _ gateway: FakeGitHubGateway,
        automatic: Bool = false,
        notifications enabled: Bool = true,
        center: FakeNotificationCenter? = nil,
        time: FakeTimeSource? = nil
    ) -> AppStore {
        let clock = time ?? FakeTimeSource(start: start)
        return AppStore(
            gateway: gateway,
            configuration: configuration(automatic: automatic, notifications: enabled),
            time: clock,
            // **Bez počitadla automat neplánuje vůbec** (`startAutomaticReviews` se vrací na
            // `guard let autoRuns`), takže by tvrzení „na odložený PR se nespustí review“ vyšlo
            // zeleně i nad úplně vypnutým automatem. Vlastní cache adresář, ne globální — #411.
            autoRuns: AutoRunLedger(layout: layout, time: clock),
            notifications: center,
            announced: AnnouncedPullRequests(layout: layout),
            snoozeStore: SnoozeStore(layout: layout, time: clock),
            activityLog: ActivityLog(layout: layout)
        )
    }
}

// MARK: - Co se nestane

extension AppStoreSnoozeTests {
    /// **Základní tvrzení celého issue.** Odložený PR z fronty zmizí — a zároveň se objeví
    /// v bloku pod ní, protože fronta, ze které práce potichu zmizí, je horší než fronta,
    /// ve které leží.
    @Test("Odložený PR zmizí z fronty a objeví se v bloku")
    func hidesTheSnoozedPullRequest() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1"), summary("cli/cli#2")]))
        let store = store(gateway)
        await store.refresh()

        await store.snooze(pr, .until(start.addingTimeInterval(3600)))

        #expect(store.queuePullRequests.map(\.id) == [other])
        #expect(store.visibleQueuePullRequests.map(\.id) == [other])
        #expect(store.snoozedQueuePullRequests.map(\.id) == [pr])
        // Plný seznam se tím **nemění** — na něm visí úklid, eviction a nabídka filtru.
        #expect(store.pullRequests.count == 2)
    }

    /// Odznak v railu i souhrn ve stavovém řádku mluví o frontě, takže odložený PR se do nich
    /// počítat nesmí — jinak by odznak sliboval práci, která na obrazovce není.
    @Test("Odložený PR se nepočítá do odznaku ani do souhrnu")
    func doesNotCountTowardsTheBadge() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1"), summary("cli/cli#2")]))
        let store = store(gateway)
        await store.refresh()
        #expect(store.railQueueCount == 2)

        await store.snooze(pr, .until(start.addingTimeInterval(3600)))

        #expect(store.railQueueCount == 1)
        #expect(store.queueSummary?.pullRequests == 1)
        // **Odznak v Docku je rail v Docku** (#529), takže musí počítat tutéž množinu — jinak by
        // v Docku svítilo číslo, které v okně nikde nestojí, a rozešly by se potichu (na obojí se
        // nekoukám naráz).
        #expect(store.dockBadgeLabel == "1")
    }

    /// Deska odpovídá na „co udělám teď“, a odložený PR je zrovna ten, o kterém jsem řekl, že teď
    /// ne. Že něco schované je, nese věta pod pozdravem — proto se tvrdí obojí naráz.
    @Test("Odložený PR není v žádném pruhu desky, ale je ve větě")
    func keepsTheBoardHonest() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1"), summary("cli/cli#2")]))
        let store = store(gateway)
        await store.refresh()

        await store.snooze(pr, .until(start.addingTimeInterval(3600)))

        let onBoard = store.board.lanes.flatMap { $0.rows.map(\.id) }
        #expect(!onBoard.contains(pr))
        #expect(onBoard.contains(other))
        #expect(Policy.boardSentence(store.board, snoozed: store.snoozedQueuePullRequests.count)
            .contains("1 odložený"))
    }

    /// **Nejcennější test téhle sady.** Odložení, po kterém se stejně utratí session, je odložení
    /// jen na obrazovce — a pozná se to až tím, že se na účtu objeví běh, o který nikdo nestál.
    /// Repo je v automatickém režimu, takže by to bez pravidla prošlo.
    @Test("Nad odloženým PR se automat nespustí")
    func neverRunsTheAutomaticReview() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        let store = store(gateway, automatic: true)
        // Odložení **před** tikem: přesně tak to vypadá po restartu aplikace, kdy se odložení čte
        // z disku dřív, než se poprvé tikne.
        await store.snooze(pr, .until(start.addingTimeInterval(3600)))

        await store.refresh()

        // **Ne `reviewTasks`**: běh, který se spustí, umí do konce `refresh()` doběhnout
        // i selhat, takže by prázdná mapa vyšla i tehdy, kdyby se review pustilo. Razítko
        // plánovače je naopak důkaz, že se PR **zvažoval** — a to je ta otázka.
        #expect(store.consideredForAutomation.isEmpty)
        #expect(store.automaticReviews.isEmpty)
    }

    /// Druhá polovina téhož: neodložený PR se spustit **musí**, jinak by test výš platil i tehdy,
    /// kdyby se automat vypnul celý.
    @Test("Neodložený PR automat spustí dál")
    func stillRunsForOthers() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1"), summary("cli/cli#2")]))
        let store = store(gateway, automatic: true)
        await store.snooze(pr, .until(start.addingTimeInterval(3600)))

        await store.refresh()

        #expect(store.consideredForAutomation.keys.contains(other))
        #expect(!store.consideredForAutomation.keys.contains(pr))
        for task in store.reviewTasks.values { task.task.cancel() }
    }

    /// Odložení, které přesto zazvoní, je odložení jen na obrazovce. Notifikace o novém PR se
    /// týká PR, které se odložilo, z fronty odešlo a vrátilo se — tehdy je v `newcomers` a
    /// odložené zároveň.
    @Test("O odloženém PR se nezvoní, ani když se vrátí do fronty")
    func neverNotifiesAboutASnoozedPullRequest() async {
        let center = FakeNotificationCenter()
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1")]),
            .success([]),
            .success([summary("cli/cli#1", updatedAt: start.addingTimeInterval(60))]),
        ])
        let store = store(gateway, center: center)
        await store.refresh()
        await store.snooze(pr, .until(start.addingTimeInterval(3600)))
        let beforeDeparture = center.delivered.count

        await store.refresh()
        await store.refresh()

        #expect(center.delivered.count == beforeDeparture, "návrat do fronty odložený PR neohlásí")
    }

    /// **Odložení se nesmí zrušit dřív, než má.** Ve chvíli odložení se hlava neví, takže by
    /// odložení bez pravidla o chybějícím základu skončilo hned první rozhlídkou — tedy do minuty.
    @Test("Odložení do pushe nevyprší první rozhlídkou")
    func doesNotExpireOnTheFirstProbe() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        gateway.snoozeSignals = [pr: SnoozeSignal(head: "4f2ac91", comments: 3)]
        let store = store(gateway)
        await store.refresh()
        await store.snooze(pr, .nextPush(head: nil))

        await store.refresh()

        #expect(store.isSnoozed(pr), "první rozhlídka jen doplní základ")
        #expect(store.snooze(of: pr)?.condition == .nextPush(head: "4f2ac91"))
        #expect(store.activityEvents.allSatisfy { $0.kind != .returnedFromSnooze })
    }

    /// **Nedostupný GitHub odložení neruší.** Kdyby chybějící odpověď vyšla jako „změnilo se to“,
    /// vysypal by výpadek sítě všechna odložení naráz.
    @Test("Selhaná rozhlídka odložení nezruší")
    func keepsTheSnoozeWhenTheProbeFails() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1", updatedAt: start)]))
        gateway.snoozeSignalsFailure = GitHubError.timedOut
        let store = store(gateway)
        await store.refresh()
        await store.snooze(pr, .nextPush(head: nil))

        await store.refresh()

        #expect(store.isSnoozed(pr))
    }

    /// **Na klidný den nula volání.** `updatedAt` se nepohnul a základ je doplněný, takže se
    /// rozhlídka nemá na co ptát — a tohle je jediné, co drží její cenu na nule.
    @Test("Odložení do času se rozhlídky neptá vůbec")
    func neverAsksAboutTimeSnoozes() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        let store = store(gateway)
        await store.refresh()
        await store.snooze(pr, .until(start.addingTimeInterval(3600)))

        await store.refresh()

        #expect(gateway.snoozeSignalRequests.isEmpty)
    }

    /// Blok `Odložené` mluví o tom, co se z **fronty** schovalo — takže se řídí filtrem stejně
    /// jako ona. Jinak by nad zafiltrovanou frontou ukazoval řádek, který by v ní nebyl vidět,
    /// ani kdyby odložený nebyl.
    @Test("Filtr schovává i blok Odložené")
    func theBlockFollowsTheFilter() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        let store = store(gateway)
        await store.refresh()
        await store.snooze(pr, .until(start.addingTimeInterval(3600)))
        #expect(store.snoozedQueuePullRequests.count == 1)

        var filter = PullRequestFilter()
        filter.repositories = [RepoID("vercel/next.js")!]
        store.setFilter(filter)

        #expect(store.snoozedQueuePullRequests.isEmpty)
    }
}

// MARK: - Návrat z odložení

extension AppStoreSnoozeTests {
    /// **PR se nesmí ve frontě objevit odnikud.** Řádek v `Dění` je jediné místo, kde se dá
    /// dohledat, že se vrátil a proč.
    @Test("Vypršelý čas vrátí PR a udělá řádek v Dění")
    func returnsWhenTheTimePasses() async {
        let time = FakeTimeSource(start: start)
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        let store = store(gateway, time: time)
        await store.refresh()
        await store.snooze(pr, .until(start.addingTimeInterval(3600)))
        #expect(store.queuePullRequests.isEmpty)

        time.advance(by: 3601)
        await store.refresh()

        #expect(!store.isSnoozed(pr))
        #expect(store.queuePullRequests.map(\.id) == [pr])
        #expect(store.activityEvents.first?.kind == .returnedFromSnooze)
        #expect(store.activityEvents.first?.detail == "došel čas")
    }

    @Test("Nová hlava vrátí PR a řekne, že přišel push")
    func returnsOnAPush() async {
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1")]),
            .success([summary("cli/cli#1", updatedAt: start.addingTimeInterval(60))]),
            .success([summary("cli/cli#1", updatedAt: start.addingTimeInterval(120))]),
        ])
        gateway.snoozeSignals = [pr: SnoozeSignal(head: "4f2ac91", comments: 3)]
        let store = store(gateway)
        await store.refresh()
        await store.snooze(pr, .nextPush(head: nil))
        // První rozhlídka doplní základ, druhá už měří proti nové hlavě.
        await store.refresh()
        gateway.snoozeSignals = [pr: SnoozeSignal(head: "9c1de02", comments: 3)]

        await store.refresh()

        #expect(!store.isSnoozed(pr))
        #expect(store.activityEvents.first?.detail == "přišel push")
    }

    @Test("Nový komentář vrátí PR a řekne, že přišel komentář")
    func returnsOnAComment() async {
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1")]),
            .success([summary("cli/cli#1", updatedAt: start.addingTimeInterval(60))]),
            .success([summary("cli/cli#1", updatedAt: start.addingTimeInterval(120))]),
        ])
        gateway.snoozeSignals = [pr: SnoozeSignal(head: "4f2ac91", comments: 3)]
        let store = store(gateway)
        await store.refresh()
        await store.snooze(pr, .nextComment(count: nil))
        await store.refresh()
        gateway.snoozeSignals = [pr: SnoozeSignal(head: "4f2ac91", comments: 4)]

        await store.refresh()

        #expect(!store.isSnoozed(pr))
        #expect(store.activityEvents.first?.detail == "přišel komentář")
    }

    @Test("Vrátit teď vrátí PR a řekne, že jsem to byl já")
    func returnsManually() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        let store = store(gateway)
        await store.refresh()
        await store.snooze(pr, .until(start.addingTimeInterval(3600)))

        await store.wake(pr)

        #expect(!store.isSnoozed(pr))
        #expect(store.queuePullRequests.map(\.id) == [pr])
        #expect(store.activityEvents.first?.kind == .returnedFromSnooze)
        #expect(store.activityEvents.first?.detail == "vrátil jsem ho ručně")
    }

    /// Za návrat banner nechodí — objednal jsem si ho sám. Chip `bez banneru` u řádku se přesto
    /// **nekreslí**: tvrdil by, že něco nedorazilo, přitom za tenhle druh notifikace nechodí nikdy.
    @Test("Návrat nezvoní a chip `bez banneru` nedostane")
    func theReturnIsSilent() async {
        let center = FakeNotificationCenter()
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        let store = store(gateway, center: center)
        await store.refresh()
        await store.snooze(pr, .until(start.addingTimeInterval(3600)))
        let before = center.delivered.count

        await store.wake(pr)

        #expect(center.delivered.count == before)
        #expect(!Policy.showsSilentChip(.returnedFromSnooze, announced: false))
    }
}

// MARK: - Co odložení nesmí zahodit

extension AppStoreSnoozeTests {
    /// **Odložený PR se nesmí ztratit z úklidu.** Úklid bere `summaries` z tiku, tedy plný seznam:
    /// odložený PR má na disku klon, nálezy i rozdělané review jako každý jiný, a uklidit mu je
    /// jen proto, že ho zrovna nechci vidět, by znamenalo začínat po návratu od nuly.
    @Test("Úklid po tiku odloženému PR nic nezahodí")
    func theSweepKeepsTheSnoozedPullRequest() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        let store = store(gateway)
        await store.refresh()
        store.readMarks[pr] = ReadMarks(pullRequest: pr)

        await store.snooze(pr, .until(start.addingTimeInterval(3600)))
        await store.refresh()

        #expect(store.readMarks[pr] != nil)
    }

    /// Odložení přežije restart — jinak by se PR po každém spuštění vrátil do fronty, aniž by se
    /// cokoli stalo. A **čte se před prvním tikem**, takže na něj automat nesáhne ani při startu.
    @Test("Odložení přežije restart a je v paměti před prvním tikem")
    func survivesARestart() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        let first = store(gateway)
        await first.refresh()
        await first.snooze(pr, .until(start.addingTimeInterval(3600)))

        let restarted = store(FakeGitHubGateway(always: .success([summary("cli/cli#1")])), automatic: true)
        await restarted.loadStoredSnoozes()
        await restarted.refresh()

        #expect(restarted.isSnoozed(pr))
        #expect(restarted.consideredForAutomation.isEmpty)
    }

    /// **Vlastní PR se odložit nedá** — blok `Odložené` visí pod frontou, takže odložené vlastní
    /// PR by ze sekce `Moje PR` zmizelo a nikde by se neobjevilo.
    @Test("Vlastní PR se odložit nedá")
    func refusesToSnoozeOwnPullRequests() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1", author: "ondrajodas")]))
        let store = store(gateway)
        await store.refresh()

        await store.snooze(pr, .until(start.addingTimeInterval(3600)))

        #expect(!store.isSnoozed(pr))
        #expect(!store.canSnooze(pr))
        #expect(store.visibleOwnPullRequests.map(\.id) == [pr])
    }
}
