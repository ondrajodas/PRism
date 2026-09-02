import Foundation
import Testing

@testable import PRism

/// Značky `Prošlo` v `AppStore` (#500).
///
/// Nejcennější tvrzení jsou tady dvě a obě říkají, že se něco **NEstalo**: commit, který soubor
/// nemění, značku nesundá — a `Rozbalit vše` ji nesmaže, jen soubor otevře.
@Suite("AppStore — značky Prošlo")
@MainActor
struct AppStoreReadMarkTests {
    private let pr = PRIdentifier("cli/cli#1")!
    private let other = PRIdentifier("cli/cli#2")!

    private var configuration: Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = [Source(name: "Moje", query: "review-requested:@me is:open")]
        return configuration
    }

    private func summary(_ id: PRIdentifier, updatedAt: TimeInterval = 100) -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/cli/cli/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: .open
        )
    }

    /// Dva soubory, každý s vlastním otiskem — tak, jak je posílá `gh pr diff`.
    private func diffText(cart: String, order: String) -> String {
        """
        diff --git a/src/Cart.swift b/src/Cart.swift
        index \(cart) 100644
        --- a/src/Cart.swift
        +++ b/src/Cart.swift
        @@ -1 +1 @@
        -a
        +b
        diff --git a/src/Order.swift b/src/Order.swift
        index \(order) 100644
        --- a/src/Order.swift
        +++ b/src/Order.swift
        @@ -1 +1 @@
        -c
        +d
        """
    }

    private func store(diffs: [Result<String, any Error>]) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([]), diffs: diffs),
            configuration: configuration,
            time: FakeTimeSource()
        )
    }

    private func loaded() async -> AppStore {
        let store = store(diffs: [.success(diffText(cart: "aaa..bbb", order: "ccc..ddd"))])
        await store.loadDiff(for: summary())
        return store
    }

    private func summary(updatedAt: TimeInterval = 100) -> PullRequestSummary {
        summary(pr, updatedAt: updatedAt)
    }

    private func fileDiff(_ path: String, in store: AppStore) -> FileDiff? {
        store.loadedDiff(for: pr)?.files.first { $0.displayPath == path }
    }

    // MARK: - Zaškrtnutí

    @Test("Zaškrtnutí uloží otisk a soubor se sbalí")
    func markingFoldsTheFile() async throws {
        let store = await loaded()
        let file = try #require(fileDiff("src/Cart.swift", in: store))

        store.toggleReadMark(file.displayPath, blobs: file.blobs, in: pr)

        #expect(store.readState(of: "src/Cart.swift", in: pr).isRead)
        #expect(store.isFolded("src/Cart.swift", in: pr))
        #expect(Policy.readFileCount(in: store.fileReviewStates(in: pr)) == 1)
    }

    @Test("Odškrtnutí značku sundá a soubor se rozbalí")
    func unmarkingUnfoldsTheFile() async throws {
        let store = await loaded()
        let file = try #require(fileDiff("src/Cart.swift", in: store))
        store.toggleReadMark(file.displayPath, blobs: file.blobs, in: pr)

        store.toggleReadMark(file.displayPath, blobs: file.blobs, in: pr)

        #expect(store.readState(of: "src/Cart.swift", in: pr) == .unread)
        #expect(!store.isFolded("src/Cart.swift", in: pr))
    }

    @Test("Zaškrtnutí jednoho souboru nesahá na ostatní")
    func marksOneFileOnly() async throws {
        let store = await loaded()
        let file = try #require(fileDiff("src/Cart.swift", in: store))

        store.toggleReadMark(file.displayPath, blobs: file.blobs, in: pr)

        #expect(store.readState(of: "src/Order.swift", in: pr) == .unread)
        #expect(!store.isFolded("src/Order.swift", in: pr))
    }

    /// Store je jeden na celé okno, takže bez klíčování PR by značka z jednoho pull requestu
    /// zaškrtla soubor v druhém — tatáž past jako u sbalení.
    @Test("Značka nepřeteče na jiný pull request")
    func doesNotLeakBetweenPullRequests() async throws {
        let store = await loaded()
        let file = try #require(fileDiff("src/Cart.swift", in: store))

        store.toggleReadMark(file.displayPath, blobs: file.blobs, in: pr)

        #expect(store.readState(of: "src/Cart.swift", in: other) == .unread)
    }

    // MARK: - Nový commit

    /// **Commit, který soubor nemění, značku nechá.** Kdyby ji shodil, byla by značka k ničemu
    /// právě u toho PR, kde se nejvíc hodí — u toho, do kterého se pushuje.
    @Test("Nový commit, který soubor nemění, značku nechá")
    func markSurvivesAnUnrelatedCommit() async throws {
        let store = store(diffs: [
            .success(diffText(cart: "aaa..bbb", order: "ccc..ddd")),
            .success(diffText(cart: "aaa..bbb", order: "ccc..eee")),
        ])
        await store.loadDiff(for: summary())
        let file = try #require(fileDiff("src/Cart.swift", in: store))
        store.toggleReadMark(file.displayPath, blobs: file.blobs, in: pr)

        await store.loadDiff(for: summary(updatedAt: 200))

        #expect(store.readState(of: "src/Cart.swift", in: pr).isRead)
        #expect(store.isFolded("src/Cart.swift", in: pr), "prošlý soubor se má držet sbalený")
    }

    /// **A commit, který ho mění, ji přepne na `změněno od prošlého`** — a soubor se sám rozbalí,
    /// protože přesně to je ta úspora: po druhém commitu zbude otevřené jen to, co se změnilo.
    @Test("Commit, který soubor mění, značku přepne na změněno a soubor rozbalí")
    func markGoesStaleAfterAChangingCommit() async throws {
        let store = store(diffs: [
            .success(diffText(cart: "aaa..bbb", order: "ccc..ddd")),
            .success(diffText(cart: "aaa..fff", order: "ccc..ddd")),
        ])
        await store.loadDiff(for: summary())
        let file = try #require(fileDiff("src/Cart.swift", in: store))
        store.toggleReadMark(file.displayPath, blobs: file.blobs, in: pr)

        await store.loadDiff(for: summary(updatedAt: 200))

        guard case .changed = store.readState(of: "src/Cart.swift", in: pr) else {
            Issue.record("Čekal jsem změněno, přišlo \(store.readState(of: "src/Cart.swift", in: pr))")
            return
        }
        #expect(!store.isFolded("src/Cart.swift", in: pr))
        #expect(Policy.readFileCount(in: store.fileReviewStates(in: pr)) == 0, "změněné se do počtu prošlých nepočítá")
    }

    /// `Prošlo znovu` je **nové razítko**, ne odškrtnutí: klik nad změněným souborem ho má vrátit
    /// mezi prošlé, ne značku sundat.
    @Test("Prošlo znovu zaškrtne s novým otiskem")
    func remarkingUsesTodaysBlobs() async throws {
        let store = store(diffs: [
            .success(diffText(cart: "aaa..bbb", order: "ccc..ddd")),
            .success(diffText(cart: "aaa..fff", order: "ccc..ddd")),
        ])
        await store.loadDiff(for: summary())
        let before = try #require(fileDiff("src/Cart.swift", in: store))
        store.toggleReadMark(before.displayPath, blobs: before.blobs, in: pr)
        await store.loadDiff(for: summary(updatedAt: 200))

        let after = try #require(fileDiff("src/Cart.swift", in: store))
        store.toggleReadMark(after.displayPath, blobs: after.blobs, in: pr)

        #expect(store.readState(of: "src/Cart.swift", in: pr).isRead)
        #expect(store.isFolded("src/Cart.swift", in: pr))
    }

    // MARK: - Sbalování

    /// **`Rozbalit vše` rozbalí i prošlé, ale značku nesmaže** — je to výslovný pokyn o tom, co je
    /// vidět, ne o tom, co je přečtené.
    @Test("Rozbalit vše otevře i prošlé soubory a značku nechá")
    func unfoldAllOpensReadFilesAndKeepsTheMark() async throws {
        let store = await loaded()
        let file = try #require(fileDiff("src/Cart.swift", in: store))
        store.toggleReadMark(file.displayPath, blobs: file.blobs, in: pr)

        store.unfoldAll(in: pr)

        #expect(!store.isFolded("src/Cart.swift", in: pr))
        #expect(store.readState(of: "src/Cart.swift", in: pr).isRead, "značka zmizela")
        #expect(Policy.readFileCount(in: store.fileReviewStates(in: pr)) == 1)
    }

    /// Ruční sbalení nepřečteného souboru se značkou nemá co dělat a musí přežít.
    @Test("Ruční sbalení nepřečteného souboru drží")
    func manualFoldStillWorks() async throws {
        let store = await loaded()

        store.toggleFolded("src/Order.swift", in: pr)

        #expect(store.isFolded("src/Order.swift", in: pr))
        #expect(store.readState(of: "src/Order.swift", in: pr) == .unread)
    }

    /// Skok na soubor ho musí otevřít i tehdy, když je prošlý — jinak by skončil na jeho hlavičce.
    @Test("Skok na prošlý soubor ho rozbalí")
    func jumpUnfoldsAReadFile() async throws {
        let store = await loaded()
        let file = try #require(fileDiff("src/Cart.swift", in: store))
        store.toggleReadMark(file.displayPath, blobs: file.blobs, in: pr)

        store.unfold("src/Cart.swift", in: pr)

        #expect(!store.isFolded("src/Cart.swift", in: pr))
    }

    /// Klik na hlavičku prošlého souboru ho **otevře**, ne zavře podruhé: odchylka se počítá proti
    /// odvozenému stavu, ne proti prázdné mapě.
    @Test("Klik na hlavičku prošlého souboru ho otevře")
    func togglingAReadFileOpensIt() async throws {
        let store = await loaded()
        let file = try #require(fileDiff("src/Cart.swift", in: store))
        store.toggleReadMark(file.displayPath, blobs: file.blobs, in: pr)

        store.toggleFolded("src/Cart.swift", in: pr)

        #expect(!store.isFolded("src/Cart.swift", in: pr))
        #expect(store.readState(of: "src/Cart.swift", in: pr).isRead)
    }

    // MARK: - Disk

    /// Bez načteného diffu se otisky nemají s čím porovnat, takže mapa stavů zůstane prázdná —
    /// a `unread` je pak správná odpověď, ne tvrzení.
    @Test("Značky bez načteného diffu nic netvrdí")
    func marksWithoutADiffSayNothing() async throws {
        let directory = try TemporaryDirectory()
        let layout = CacheLayout(root: directory.url)
        try await ReadMarkStore(layout: layout).save(ReadMarks(
            pullRequest: pr,
            marks: ["src/Cart.swift": ReadMark(blobs: "aaa..bbb", markedAt: Date())]
        ))
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            time: FakeTimeSource(),
            readMarkStore: ReadMarkStore(layout: layout)
        )

        await store.loadReadMarks(for: pr)

        #expect(store.readState(of: "src/Cart.swift", in: pr) == .unread)
        #expect(store.readMarks[pr]?.marks.count == 1, "značka se přečetla, jen se nemá s čím srovnat")
    }

    /// Po restartu je na disku značka a v okně žádné sbalení — a prošlý soubor má být přesto
    /// zavřený. Přesně proto se sbalení **odvozuje**, místo aby ho zaškrtnutí zapsalo.
    @Test("Značka z disku sbalí soubor i bez kliknutí")
    func marksFromDiskFoldTheFile() async throws {
        let directory = try TemporaryDirectory()
        let layout = CacheLayout(root: directory.url)
        try await ReadMarkStore(layout: layout).save(ReadMarks(
            pullRequest: pr,
            marks: ["src/Cart.swift": ReadMark(blobs: "aaa..bbb", markedAt: Date())]
        ))
        let store = AppStore(
            gateway: FakeGitHubGateway(
                always: .success([]),
                diffs: [.success(diffText(cart: "aaa..bbb", order: "ccc..ddd"))]
            ),
            configuration: configuration,
            time: FakeTimeSource(),
            readMarkStore: ReadMarkStore(layout: layout)
        )

        await store.loadReadMarks(for: pr)
        await store.loadDiff(for: summary())

        #expect(store.readState(of: "src/Cart.swift", in: pr).isRead)
        #expect(store.isFolded("src/Cart.swift", in: pr))
    }
}
