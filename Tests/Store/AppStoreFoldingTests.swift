import Foundation
import Testing

@testable import PRism

/// Sbalení souboru v diffu. Stav drží store, ne view — jinak by přetekl mezi pull requesty.
@Suite("AppStore — sbalení souborů")
@MainActor
struct AppStoreFoldingTests {
    private let first = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 1)
    private let second = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 2)

    private func store() -> AppStore {
        AppStore(gateway: FakeGitHubGateway(always: .success([])), time: FakeTimeSource())
    }

    /// U PR o padesáti souborech je rozbaleno výchozí stav a sbalení je gesto.
    @Test("Soubor je ve výchozím stavu rozbalený")
    func filesStartUnfolded() {
        #expect(!store().isFolded("src/Cart.swift", in: first))
    }

    @Test("Klik sbalí a druhý rozbalí")
    func togglesBackAndForth() {
        let store = store()

        store.toggleFolded("src/Cart.swift", in: first)
        #expect(store.isFolded("src/Cart.swift", in: first))

        store.toggleFolded("src/Cart.swift", in: first)
        #expect(!store.isFolded("src/Cart.swift", in: first))
    }

    @Test("Sbalení jednoho souboru nesahá na ostatní")
    func foldsOneFileOnly() {
        let store = store()

        store.toggleFolded("src/Cart.swift", in: first)

        #expect(!store.isFolded("src/Order.swift", in: first))
    }

    /// `PullRequestDetailView` si SwiftUI mezi PR ponechá, takže stav ve view by přetekl.
    @Test("Sbalení nepřeteče na jiný pull request")
    func doesNotLeakBetweenPullRequests() {
        let store = store()

        store.toggleFolded("src/Cart.swift", in: first)

        #expect(!store.isFolded("src/Cart.swift", in: second))
    }

    @Test("Sbalit vše sbalí vyjmenované soubory")
    func foldsEverythingListed() {
        let store = store()

        store.foldAll(["src/Cart.swift", "src/Order.swift"], in: first)

        #expect(store.isFolded("src/Cart.swift", in: first))
        #expect(store.isFolded("src/Order.swift", in: first))
    }

    @Test("Rozbalit vše rozbalí i to, co bylo sbalené po jednom")
    func unfoldsEverything() {
        let store = store()
        store.toggleFolded("src/Cart.swift", in: first)
        store.foldAll(["src/Order.swift"], in: first)

        store.unfoldAll(in: first)

        #expect(!store.isFolded("src/Cart.swift", in: first))
        #expect(!store.isFolded("src/Order.swift", in: first))
    }

    /// Sbalení v jiném PR je cizí stav — tlačítko v jednom okně se nesmí projevit jinde.
    @Test("Rozbalit vše nesahá na jiný pull request")
    func unfoldAllLeavesOtherPullRequestsAlone() {
        let store = store()
        store.foldAll(["src/Cart.swift"], in: first)
        store.foldAll(["src/Cart.swift"], in: second)

        store.unfoldAll(in: first)

        #expect(!store.isFolded("src/Cart.swift", in: first))
        #expect(store.isFolded("src/Cart.swift", in: second))
    }

    /// Skok na sbalený soubor by skončil nikde — jeho řádky v líném seznamu nejsou.
    @Test("Rozbalení je idempotentní")
    func unfoldIsIdempotent() {
        let store = store()
        store.toggleFolded("src/Cart.swift", in: first)

        store.unfold("src/Cart.swift", in: first)
        store.unfold("src/Cart.swift", in: first)

        #expect(!store.isFolded("src/Cart.swift", in: first))
    }
}
