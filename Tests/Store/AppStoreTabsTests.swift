import Foundation
import Testing

@testable import PRism

/// Záložky okna (#180). Nejcennější tvrzení je, že zavření záložky **nic nezahodí** — všechno
/// ve store visí na `PRIdentifier`, ne na záložce.
@Suite("AppStore — záložky")
@MainActor
struct AppStoreTabsTests {
    private let first = PRIdentifier("cli/cli#1")!
    private let second = PRIdentifier("cli/cli#2")!
    private let third = PRIdentifier("cli/cli#3")!

    private func store() -> AppStore {
        AppStore(gateway: FakeGitHubGateway([.success([])]), time: FakeTimeSource())
    }

    /// Store, který umí dotáhnout detail — bez známé hlavy PR draft **nevznikne**, protože se
    /// píše proti konkrétnímu commitu.
    private func storeWithDetail(of id: PRIdentifier) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway([.success([])], detail: .success(detail(of: id))),
            time: FakeTimeSource()
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

    private func detail(of id: PRIdentifier) -> PullRequest {
        PullRequest(
            id: id,
            title: "titulek",
            author: "autor",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    @Test("Otevření PR založí záložku a přepne se na ni")
    func openingAPullRequestAddsATab() {
        let store = store()

        store.openTab(first)

        #expect(store.openTabs == [first])
        #expect(store.activeTab == .pullRequest(first))
        #expect(store.selection == first)
    }

    @Test("Otevřený PR se neotevře podruhé")
    func openingTwiceDoesNotDuplicate() {
        // Kliknutí na už otevřený PR ho má vytáhnout dopředu, ne založit druhou záložku —
        // jako v prohlížeči.
        let store = store()
        store.openTab(first)
        store.openTab(second)

        store.openTab(first)

        #expect(store.openTabs == [first, second])
        #expect(store.activeTab == .pullRequest(first))
    }

    @Test("Zavření aktivní záložky přejde na sousední")
    func closingTheActiveTabMovesToTheNeighbour() {
        // Zavírá se typicky doprojité review a další v řadě je to, co člověk chce vidět.
        let store = store()
        store.openTab(first)
        store.openTab(second)
        store.openTab(third)
        store.activeTab = .pullRequest(second)

        store.closeTab(second)

        #expect(store.openTabs == [first, third])
        #expect(store.activeTab == .pullRequest(third))
        #expect(store.selection == third)
    }

    @Test("Zavření poslední záložky propadne domů")
    func closingTheLastTabFallsHome() {
        let store = store()
        store.openTab(first)

        store.closeTab(first)

        #expect(store.openTabs.isEmpty)
        #expect(store.activeTab == .home)
        #expect(store.selection == nil)
    }

    @Test("Zavření neaktivní záložky nepřepne obsah")
    func closingAnInactiveTabKeepsTheContent() {
        // Zavřít vedlejší záložku nesmí odnést člověka od toho, co zrovna čte.
        let store = store()
        store.openTab(first)
        store.openTab(second)

        store.closeTab(first)

        #expect(store.openTabs == [second])
        #expect(store.activeTab == .pullRequest(second))
    }

    @Test("Zavření záložky nezahodí rozdělané review")
    func closingATabKeepsTheDraft() async throws {
        // Nejdůležitější tvrzení v souboru: záložka nic nevlastní. Draft leží na disku a visí
        // na `PRIdentifier`, takže se zavřením nesmí ztratit — jinak by okno umělo zahodit
        // rozepsanou práci jedním kliknutím na křížek.
        let store = storeWithDetail(of: first)
        store.openTab(first)
        await store.loadDetail(for: summary(first))
        store.setDraftBody("rozepsané", for: first)
        #expect(store.hasDraft(first))

        store.closeTab(first)

        #expect(store.hasDraft(first))
        #expect(store.draft(for: first)?.body == "rozepsané")
    }

    @Test("Odznak fronty mlčí, dokud se seznam nenačte")
    func theQueueBadgeStaysQuietUntilLoaded() {
        // Nula nad nenačtenými daty vypadá jako „hotovo“ — tatáž úvaha jako u souhrnu fronty.
        let store = store()

        #expect(store.railQueueCount == nil)
    }
}
