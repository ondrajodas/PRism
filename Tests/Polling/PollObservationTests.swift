import Foundation
import Testing

@testable import PRism

/// Co tik pollingu **nesmí** zneplatnit (#472).
///
/// Tohle je ta nejcennější třída tvrzení v tomhle repu — tvrdí, že se něco **nestalo**, a rozbije
/// se potichu. Do #472 držel `PollingService` celý `PollState` jako **jednu** vlastnost, takže
/// `@Observable` hlásil jednu změnu za všech pět polí naráz: `isRefreshing = true` na začátku tiku
/// zneplatnil i každého, kdo četl jen seznam PR. A ten čte `AppStore.author(of:)`, na kterém visí
/// `ownership(of:)` — tedy i celý detail PR, jehož jedno přerovnání stojí **33–43 ms** rozvržení
/// okna (`DetailRelayoutMeasurement`).
///
/// Druhá polovina je, že `@Observable` hlásí **zápis, ne změnu**: tik, po kterém je fronta stejná
/// jako před minutou (tedy skoro každý), zapisoval tentýž seznam a okno se překreslilo celé.
@MainActor
@Suite("Co tik pollingu nezneplatní (#472)")
struct PollObservationTests {
    /// Čtenář seznamu PR, který si pamatuje, jestli ho někdo probudil.
    ///
    /// `withObservationTracking` je **jednorázové**: `onChange` se zavolá při první změně
    /// sledované vlastnosti a odběr tím končí. Sondě to stačí — ptá se, jestli přišla **vůbec
    /// nějaká**.
    private final class Watcher: @unchecked Sendable {
        private(set) var woken = false

        func watch(_ read: @escaping @MainActor () -> Void) {
            MainActor.assumeIsolated {
                withObservationTracking { read() } onChange: { [self] in woken = true }
            }
        }
    }

    private func summary(
        _ id: String,
        title: String = "titulek",
        updatedAt: TimeInterval = 1_000_000
    ) -> PullRequestSummary {
        PullRequestSummary(
            id: PRIdentifier(id)!,
            title: title,
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/1")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: .open
        )
    }

    private func service(_ gateway: FakeGitHubGateway) -> PollingService {
        PollingService(gateway: gateway, sources: [.reviewRequested], time: FakeTimeSource())
    }

    /// Tik, po kterém je fronta stejná, **nesmí probudit čtenáře seznamu**.
    ///
    /// Pokrývá obojí naráz: příznak `isRefreshing` (dvakrát za tik) i zápis téhož seznamu.
    @Test("Tik beze změny fronty nezneplatní čtenáře seznamu")
    func quietTickDoesNotWakeTheListReader() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        let polling = service(gateway)
        await polling.refresh()

        let watcher = Watcher()
        watcher.watch { _ = polling.pullRequests }
        await polling.refresh()

        #expect(!watcher.woken)
    }

    /// A tik, po kterém se fronta **změnila**, ho probudit musí — jinak by z toho byla oprava,
    /// která zároveň přestala kreslit nové PR.
    @Test("Tik se změněnou frontou čtenáře seznamu probudí")
    func changedTickWakesTheListReader() async {
        let gateway = FakeGitHubGateway([
            .success([summary("cli/cli#1")]),
            .success([summary("cli/cli#1"), summary("cli/cli#2")]),
        ])
        let polling = service(gateway)
        await polling.refresh()

        let watcher = Watcher()
        watcher.watch { _ = polling.pullRequests }
        await polling.refresh()

        #expect(watcher.woken)
    }

    /// Změna **uvnitř** shrnutí je taky změna: nový commit posune `updatedAt` a na tom stojí
    /// dotažení diffu i konverzace (`task(id: pullRequest)` v detailu). Porovnává se proto celé
    /// shrnutí, ne jen identifikátory.
    @Test("Nové razítko v tomtéž PR čtenáře seznamu probudí")
    func newTimestampWakesTheListReader() async {
        let first = summary("cli/cli#1")
        let pushed = summary("cli/cli#1", updatedAt: 1_000_060)
        let gateway = FakeGitHubGateway([.success([first]), .success([pushed])])
        let polling = service(gateway)
        await polling.refresh()

        let watcher = Watcher()
        watcher.watch { _ = polling.pullRequests }
        await polling.refresh()

        #expect(watcher.woken)
    }

    /// Příznak „ptáme se“ se **mění pořád** a čte ho tlačítko `⟳` a odpočet na dashboardu.
    /// Nesmí ale probudit nikoho dalšího — právě tím se do #472 překresloval detail PR dvakrát
    /// za tik.
    @Test("Příznak `ptáme se` nezneplatní čtenáře seznamu")
    func refreshFlagDoesNotWakeTheListReader() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        let polling = service(gateway)
        await polling.refresh()

        let watcher = Watcher()
        watcher.watch { _ = polling.pullRequests }
        // Nezpůsobuje to tenhle test, ale samotný `refresh()`: příznak zapíná i vypíná on.
        await polling.refresh()

        #expect(!watcher.woken)
        // A že se ten příznak doopravdy hýbal, tvrdí `PollingServiceTests`; kdyby ne, byl by
        // tenhle test zelený nad ničím.
        #expect(polling.isRefreshing == false)
    }

    /// **`@Observable` hlásí změnu, ne zápis** — a je to změřené, ne převzaté.
    ///
    /// Stojí na tom, že `refresh()` píše seznam i stav **bez `if` na rovnost**: kdyby toolchain
    /// hlásil každý zápis, bylo by tohle tvrzení červené a ten `if` by se musel vrátit. Proto
    /// tenhle test existuje — je to jediné místo, kde se ta domněnka dá chytit, až se změní.
    @Test("Zápis téže hodnoty nikoho nebudí")
    func writingTheSameValueDoesNotWake() {
        let polling = service(FakeGitHubGateway(always: .success([])))
        polling.interval = .seconds(60)

        let watcher = Watcher()
        watcher.watch { _ = polling.interval }
        polling.interval = .seconds(60)

        #expect(!watcher.woken)
    }

    /// **A úklid po tiku taky nikoho nebudí** — což je tvrzení o `forget(whatIsNotIn:)`, který
    /// po každém úspěšném tiku přepíše přes třicet map výsledkem `filter`u.
    ///
    /// Vypadá to jako druhá polovina #472 a **není**: nabízelo se zapisovat jen tehdy, když
    /// z mapy opravdu ubylo, jenže s takovou úpravou i bez ní je tenhle test zelený — zápis téže
    /// hodnoty toolchain nehlásí (viz test o řádek výš). Zůstává proto jen tvrzení, aby se ta
    /// cesta hlídala; kdyby se chování `@Observable` změnilo, spadne tohle **i** ten test výš
    /// a bude z toho jasné, co dělat.
    @Test("Tichý tik nezneplatní ani rozbalení kontextu v diffu")
    func quietTickDoesNotWakeTheDiffReader() async throws {
        let pr = PRIdentifier("cli/cli#1")!
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        let directory = try TemporaryDirectory()
        defer { _ = directory }
        let store = AppStore(
            gateway: gateway,
            time: FakeTimeSource(),
            drafts: ReviewDraftStore(layout: CacheLayout(root: directory.url))
        )
        await store.refresh()
        // Mapa musí být **neprázdná**, jinak by test procházel nad ničím: `filter` nad prázdnou
        // mapou nic neubere ani před opravou.
        store.expansions[FileExpansionKey(pullRequest: pr, path: "a.swift", commit: nil)] = FileExpansion()

        let watcher = Watcher()
        watcher.watch { _ = store.expansion(of: "a.swift", in: pr) }
        await store.refresh()

        #expect(!watcher.woken)

        // **Ověřeno i obráceně**, jinak by tohle tvrzení mohlo být zelené nad nesledovanou
        // vlastností: skutečná změna téže mapy toho čtenáře probudit **musí**.
        let second = Watcher()
        second.watch { _ = store.expansion(of: "a.swift", in: pr) }
        store.expansions[FileExpansionKey(pullRequest: pr, path: "b.swift", commit: nil)] = FileExpansion()

        #expect(second.woken)
    }

    /// **Totéž o okně, ne jen o pollingu.** `ownership(of:)` je to, na čem detail PR pozná, čí
    /// PR kreslí — a jde přes `author(of:)`, tedy přes seznam z pollingu. Bez tohohle tvrzení by
    /// se oprava dala rozbít kdekoli mezi `PollingService` a `AppStore`.
    @Test("Tichý tik nezneplatní ani otázku, čí je PR")
    func quietTickDoesNotWakeTheOwnershipReader() async throws {
        let pr = PRIdentifier("cli/cli#1")!
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        let directory = try TemporaryDirectory()
        defer { _ = directory }
        let store = AppStore(
            gateway: gateway,
            time: FakeTimeSource(),
            drafts: ReviewDraftStore(layout: CacheLayout(root: directory.url))
        )
        await store.refresh()

        let watcher = Watcher()
        watcher.watch { _ = store.ownership(of: pr) }
        await store.refresh()

        #expect(!watcher.woken)
    }
}
