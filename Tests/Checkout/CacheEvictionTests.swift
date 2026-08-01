import Foundation
import Testing

@testable import PRism

@Suite("CacheEviction")
struct CacheEvictionTests {
    private let workspace: TemporaryDirectory
    private let layout: CacheLayout
    private let vault = RepoID(owner: "keboola", name: "vault")
    private let stacks = RepoID(owner: "keboola", name: "kbc-stacks")

    init() throws {
        workspace = try TemporaryDirectory()
        layout = CacheLayout(root: workspace.url)
    }

    /// Klon o zadané velikosti, naposledy použitý v zadaný čas.
    @discardableResult
    private func makeClone(_ repo: RepoID, bytes: Int = 200_000, usedAt: Date = .now) throws -> URL {
        let clone = layout.bareClone(for: repo)
        try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)
        try Data(repeating: 0, count: bytes).write(to: clone.appending(path: "objects.pack"))
        try Data().write(to: layout.cloneMarker(for: repo))
        try CacheEviction.markUsed(repo, at: usedAt, in: layout)
        return clone
    }

    private func exists(_ repo: RepoID) -> Bool {
        FileManager.default.fileExists(atPath: layout.bareClone(for: repo).path(percentEncoded: false))
    }

    private func eviction(budget: Int) -> CacheEviction {
        CacheEviction(layout: layout, budget: budget)
    }

    @Test("Repo bez otevřeného PR se z cache smaže")
    func dropsRepositoriesWithoutOpenPullRequests() async throws {
        try makeClone(vault)
        try makeClone(stacks)

        try await eviction(budget: .max).run(
            openPullRequests: [PRIdentifier(repo: vault, number: 1)],
            busy: []
        )

        #expect(exists(vault))
        #expect(!exists(stacks))
    }

    @Test("Pod rozpočtem se nic dalšího nemaže")
    func keepsEverythingUnderBudget() async throws {
        // Rozpočet se počítá z **alokované** velikosti, takže i malý soubor zabere celý
        // blok — čísla v testech proto musí být řádově nad velikostí bloku.
        try makeClone(vault)
        try makeClone(stacks)

        try await eviction(budget: 1_000_000).run(
            openPullRequests: [
                PRIdentifier(repo: vault, number: 1),
                PRIdentifier(repo: stacks, number: 2),
            ],
            busy: []
        )

        #expect(exists(vault))
        #expect(exists(stacks))
    }

    @Test("Nad rozpočtem odchází nejdéle nepoužité")
    func evictsLeastRecentlyUsedOverBudget() async throws {
        try makeClone(vault, usedAt: Date(timeIntervalSince1970: 100))
        try makeClone(stacks, usedAt: Date(timeIntervalSince1970: 200))
        let open = [PRIdentifier(repo: vault, number: 1), PRIdentifier(repo: stacks, number: 2)]

        try await eviction(budget: 300_000).run(openPullRequests: open, busy: [])

        #expect(!exists(vault)) // starší
        #expect(exists(stacks))
    }

    @Test("Repo s běžícím review se nesmaže, ani když je na řadě")
    func neverEvictsARepositoryWithARunningReview() async throws {
        // Smazat klon pod běžícím review by mu vzalo pracovní strom pod rukama.
        try makeClone(vault, usedAt: Date(timeIntervalSince1970: 100))
        try makeClone(stacks, usedAt: Date(timeIntervalSince1970: 200))
        let open = [PRIdentifier(repo: vault, number: 1), PRIdentifier(repo: stacks, number: 2)]

        try await eviction(budget: 300_000).run(openPullRequests: open, busy: [vault])

        #expect(exists(vault))
        #expect(!exists(stacks))
    }

    @Test("Zavřené PR nesmaže repo, ve kterém běží review")
    func busyRepositorySurvivesEvenWithoutOpenPullRequests() async throws {
        try makeClone(vault)

        try await eviction(budget: .max).run(openPullRequests: [], busy: [vault])

        #expect(exists(vault))
    }

    @Test("Se smazaným repem jdou i jeho worktrees")
    func evictionTakesWorktreesWithIt() async throws {
        // Strom bez klonu je jen složka, ve které `git` neodpoví — držet ji nemá smysl.
        try makeClone(vault)
        let worktree = layout.worktree(for: PRIdentifier(repo: vault, number: 1), at: String(repeating: "a", count: 40))
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)

        try await eviction(budget: .max).run(openPullRequests: [], busy: [])

        #expect(!FileManager.default.fileExists(atPath: worktree.path(percentEncoded: false)))
    }

    @Test("Prázdná cache eviction nerozhodí")
    func emptyCacheIsFine() async throws {
        try await eviction(budget: 10).run(openPullRequests: [], busy: [])
    }

    @Test("Použití repa se zaznamená")
    func usageIsRecorded() throws {
        try makeClone(vault, usedAt: Date(timeIntervalSince1970: 100))

        try CacheEviction.markUsed(vault, at: Date(timeIntervalSince1970: 500), in: layout)

        #expect(try CacheEviction.lastUsed(vault, in: layout) == Date(timeIntervalSince1970: 500))
    }
}

extension CacheEvictionTests {
    @Test("Refy PR, které zmizely ze seznamu, se zahodí")
    func forgetsRefsOfPullRequestsThatLeftTheList() async throws {
        // Ref kotví objekty commitu — bez zahození by je `git gc` nesměl nikdy uklidit.
        try makeClone(vault)
        let checkout = FakeRepoCheckout(tracked: [vault: [1, 2, 3]])
        let eviction = CacheEviction(layout: layout, budget: .max, checkout: checkout)

        try await eviction.run(openPullRequests: [PRIdentifier(repo: vault, number: 2)], busy: [])

        #expect(checkout.forgottenPullRequests.map(\.number).sorted() == [1, 3])
    }

    @Test("Repo s běžícím review si refy nechá")
    func busyRepositoryKeepsItsRefs() async throws {
        try makeClone(vault)
        let checkout = FakeRepoCheckout(tracked: [vault: [1]])
        let eviction = CacheEviction(layout: layout, budget: .max, checkout: checkout)

        try await eviction.run(openPullRequests: [], busy: [vault])

        #expect(checkout.forgottenPullRequests.isEmpty)
    }

    @Test("Strom zavřeného PR odejde i z repa, které v cache zůstává")
    func discardsWorktreeOfAClosedPullRequestInALivingRepository() async throws {
        // Tenhle strom by jinak nesmazal nikdo: repo v cache zůstává kvůli jinému PR.
        try makeClone(vault)
        let closed = layout.worktree(for: PRIdentifier(repo: vault, number: 7), at: String(repeating: "a", count: 40))
        let open = layout.worktree(for: PRIdentifier(repo: vault, number: 8), at: String(repeating: "b", count: 40))
        for path in [closed, open] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }

        try await eviction(budget: .max).run(
            openPullRequests: [PRIdentifier(repo: vault, number: 8)],
            busy: []
        )

        #expect(!FileManager.default.fileExists(atPath: closed.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: open.path(percentEncoded: false)))
    }

    @Test("Úklid repa nesáhne na jiné, jehož jméno začíná stejně")
    func evictingARepositoryLeavesSimilarlyNamedOnesAlone() async throws {
        // `keboola-kbc-` je prefix i pro `keboola-kbc-stacks-…`; ploché názvy stromů by
        // tedy úklid jednoho repa pustily na stromy druhého.
        let kbc = RepoID(owner: "keboola", name: "kbc")
        try makeClone(kbc)
        try makeClone(stacks)
        let neighbour = layout.worktree(for: PRIdentifier(repo: stacks, number: 1), at: String(repeating: "c", count: 40))
        try FileManager.default.createDirectory(at: neighbour, withIntermediateDirectories: true)

        try await eviction(budget: .max).run(
            openPullRequests: [PRIdentifier(repo: stacks, number: 1)],
            busy: []
        )

        #expect(!exists(kbc))
        #expect(FileManager.default.fileExists(atPath: neighbour.path(percentEncoded: false)))
    }

    @Test("Mazání se nesmí dostat ven z cache")
    func neverDeletesOutsideTheCache() async throws {
        // Tvrdá podmínka: aplikace pracuje výhradně ve své cache. Symlink v cestě umí
        // `removeItem` poslat na cíl mimo ni.
        let outside = try TemporaryDirectory()
        let victim = outside.url.appending(path: "uzivateluv-klon.git")
        try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: layout.repositories, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: layout.repositories.appending(path: "keboola"),
            withDestinationURL: outside.url
        )

        _ = try? await eviction(budget: .max).run(openPullRequests: [], busy: [])

        #expect(FileManager.default.fileExists(atPath: victim.path(percentEncoded: false)))
    }
}

extension CacheEvictionTests {
    @Test("Stejné číslo PR v jiném repu strom neudrží")
    func worktreesAreKeptByRepositoryAndNumber() async throws {
        // Čísla PR se mezi repozitáři opakují — kdyby se filtrovalo jen podle čísla,
        // otevřené `kbc-stacks#1` by drželo při životě strom zavřeného `vault#1`.
        try makeClone(vault)
        try makeClone(stacks)
        let closed = layout.worktree(for: PRIdentifier(repo: vault, number: 1), at: String(repeating: "a", count: 40))
        let open = layout.worktree(for: PRIdentifier(repo: vault, number: 2), at: String(repeating: "b", count: 40))
        for path in [closed, open] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }

        try await eviction(budget: .max).run(
            openPullRequests: [
                PRIdentifier(repo: stacks, number: 1), // stejné číslo, jiné repo
                PRIdentifier(repo: vault, number: 2),
            ],
            busy: []
        )

        #expect(!FileManager.default.fileExists(atPath: closed.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: open.path(percentEncoded: false)))
    }
}

extension CacheEvictionTests {
    @Test("Po smazání stromu se v klonu zahodí i jeho záznam")
    func prunesTheCloneAfterRemovingAWorktree() async throws {
        // Samotné smazání složky nestačí — klon si o stromu drží záznam a příští
        // `worktree add` na stejnou cestu by skončil `missing but already registered`.
        try makeClone(vault)
        let stale = layout.worktree(for: PRIdentifier(repo: vault, number: 7), at: String(repeating: "a", count: 40))
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        let checkout = FakeRepoCheckout()

        try await CacheEviction(layout: layout, budget: .max, checkout: checkout).run(
            openPullRequests: [PRIdentifier(repo: vault, number: 8)],
            busy: []
        )

        #expect(checkout.prunedRepositories == [vault])
    }
}
