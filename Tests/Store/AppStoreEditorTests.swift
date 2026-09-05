import Foundation
import Testing

@testable import PRism

/// Otevření souboru v editoru (#530).
///
/// **Nejcennější jsou tady tvrzení o tom, co se neotevře.** Tlačítko posílá cestu cizí aplikaci,
/// takže jediná chyba, na které záleží, je cesta ven z cache — tvrdá podmínka č. 3. Fake editor
/// existuje právě proto, aby šlo tvrdit, že se `NSWorkspace` **nepředalo nic**.
@Suite("AppStore — otevření souboru v editoru (#530)")
@MainActor
struct AppStoreEditorTests {
    private let pullRequest = PRIdentifier("cli/cli#42")!

    private func store(
        cache: TemporaryDirectory,
        editor: ExternalEditor? = .cursor,
        opener: FakeEditorOpener
    ) -> AppStore {
        var configuration = Configuration.standard
        configuration.global.externalEditor = editor
        return AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            time: FakeTimeSource(),
            cacheLayout: CacheLayout(root: cache.url),
            editorOpener: opener
        )
    }

    /// Strom pro srovnání větve i se souborem, tedy stav po `Srovnat větev` na vlastním PR.
    @discardableResult
    private func makeSyncWorktree(in cache: TemporaryDirectory, file: String = "src/App.swift") throws -> URL {
        let tree = CacheLayout(root: cache.url).syncWorktree(for: pullRequest)
        let target = tree.appending(path: file)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "let x = 1\n".write(to: target, atomically: true, encoding: .utf8)
        return target
    }

    // MARK: - Co se otevře

    @Test("Soubor ze stromu -sync se otevře na řádku nálezu")
    func opensTheFileAtTheLine() async throws {
        let cache = try TemporaryDirectory()
        let file = try makeSyncWorktree(in: cache)
        let opener = FakeEditorOpener()
        let store = store(cache: cache, opener: opener)

        await store.openInEditor(file: "src/App.swift", line: 81, of: pullRequest)

        #expect(store.editorFailure == nil)
        #expect(opener.openedURLs == [Policy.editorURL(.cursor, file: file.standardizedFileURL, line: 81)!])
    }

    /// Strom `-sync` na cizím PR nevzniká, takže rozhoduje strom posledního review — a je to
    /// jediná cesta, kterou se u cizího PR soubor otevře.
    @Test("Bez stromu -sync se sáhne po stromu posledního review")
    func fallsBackToTheReviewWorktree() async throws {
        let cache = try TemporaryDirectory()
        let tree = CacheLayout(root: cache.url).worktree(for: pullRequest, at: "abc1234")
        let file = tree.appending(path: "src/App.swift")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "let x = 1\n".write(to: file, atomically: true, encoding: .utf8)
        let opener = FakeEditorOpener()
        let store = store(cache: cache, opener: opener)
        store.reviewTimelines[pullRequest] = [ReviewerTimeline(skill: "code-review", worktree: tree)]

        await store.openInEditor(file: "src/App.swift", line: nil, of: pullRequest)

        #expect(store.editorFailure == nil)
        #expect(opener.openedURLs.count == 1)
        #expect(opener.openedURLs.first?.absoluteString.hasSuffix("/42-abc1234/src/App.swift") == true)
    }

    // MARK: - Co se neotevře

    /// **Tohle je to tvrzení, kvůli kterému celý suite existuje.** Cesta, která z cache vede pryč,
    /// se nesmí dostat do `NSWorkspace` — jinak by aplikace otevřela uživatelův klon, tedy přesně
    /// to, co tvrdá podmínka č. 3 zakazuje.
    @Test("Cesta mimo cache se do editoru nedostane")
    func neverLeavesTheCache() async throws {
        let cache = try TemporaryDirectory()
        try makeSyncWorktree(in: cache)
        let opener = FakeEditorOpener()
        let store = store(cache: cache, opener: opener)

        await store.openInEditor(file: "../../../../../../etc/hosts", line: 1, of: pullRequest)

        #expect(opener.openedURLs.isEmpty)
        #expect(store.editorFailure?.contains("mimo cache") == true)
    }

    /// Odkaz **na samotném souboru** je ta tišší půlka téže vady: cesta leží v cache, jenže editor
    /// by otevřel jeho cíl — a ten smí být kdekoli. Proto se ověřuje `CacheFile.refusal`, ne
    /// `isInsideCache`.
    @Test("Symbolický odkaz v cache se do editoru nedostane")
    func refusesASymbolicLink() async throws {
        let cache = try TemporaryDirectory()
        try makeSyncWorktree(in: cache)
        let outside = try TemporaryDirectory()
        let secret = outside.url.appending(path: "clone.swift")
        try "tajné\n".write(to: secret, atomically: true, encoding: .utf8)
        let link = CacheLayout(root: cache.url)
            .syncWorktree(for: pullRequest)
            .appending(path: "src/Link.swift")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)
        let opener = FakeEditorOpener()
        let store = store(cache: cache, opener: opener)

        await store.openInEditor(file: "src/Link.swift", line: nil, of: pullRequest)

        #expect(opener.openedURLs.isEmpty)
        #expect(store.editorFailure?.contains("symbolický odkaz") == true)
    }

    /// Bez zvoleného editoru se tlačítko nekreslí, takže sem se nedojde — a kdyby přece, nesmí se
    /// otevřít „něco“.
    @Test("Bez zvoleného editoru se neotevře nic a nic se nehlásí")
    func doesNothingWithoutAnEditor() async throws {
        let cache = try TemporaryDirectory()
        try makeSyncWorktree(in: cache)
        let opener = FakeEditorOpener()
        let store = store(cache: cache, editor: nil, opener: opener)

        await store.openInEditor(file: "src/App.swift", line: 81, of: pullRequest)

        #expect(opener.openedURLs.isEmpty)
        #expect(store.editorFailure == nil)
    }

    /// Smazaný soubor je v diffu vidět, na disku po něm nezůstalo nic — bez téhle zastávky by
    /// editor otevřel prázdné okno a vypadalo by to jako prázdný soubor.
    @Test("Soubor, který v kopii není, se nahlásí a neotevře")
    func reportsAMissingFile() async throws {
        let cache = try TemporaryDirectory()
        try makeSyncWorktree(in: cache)
        let opener = FakeEditorOpener()
        let store = store(cache: cache, opener: opener)

        await store.openInEditor(file: "src/Deleted.swift", line: 3, of: pullRequest)

        #expect(opener.openedURLs.isEmpty)
        #expect(store.editorFailure == Policy.editorMissingFileNote("src/Deleted.swift"))
    }

    @Test("Bez pracovní kopie v cache se to řekne")
    func reportsAMissingWorktree() async throws {
        let cache = try TemporaryDirectory()
        let opener = FakeEditorOpener()
        let store = store(cache: cache, opener: opener)

        await store.openInEditor(file: "src/App.swift", line: 3, of: pullRequest)

        #expect(opener.openedURLs.isEmpty)
        #expect(store.editorFailure == Policy.editorNoWorktreeNote)
    }

    /// Systém adresu nepřevzal — nejčastěji proto, že editor není nainstalovaný. Spolknout to
    /// nejde: editor se otevírá **mimo okno**, takže neúspěch vypadá jako by se nekliklo.
    @Test("Odmítnutá adresa se nahlásí, ne spolkne")
    func reportsARefusalFromTheSystem() async throws {
        let cache = try TemporaryDirectory()
        try makeSyncWorktree(in: cache)
        let opener = FakeEditorOpener(accepting: false)
        let store = store(cache: cache, opener: opener)

        await store.openInEditor(file: "src/App.swift", line: 81, of: pullRequest)

        #expect(opener.openedURLs.count == 1)
        #expect(store.editorFailure == Policy.editorRefusedBySystemNote(.cursor))
    }

    /// Hláška mluví o **posledním** pokusu: viset po povedeném otevření by znamenalo věta o chybě,
    /// která už neplatí.
    @Test("Povedené otevření zahodí hlášku z minula")
    func clearsTheFailureOnTheNextTry() async throws {
        let cache = try TemporaryDirectory()
        try makeSyncWorktree(in: cache)
        let opener = FakeEditorOpener()
        let store = store(cache: cache, opener: opener)

        await store.openInEditor(file: "src/Deleted.swift", line: 3, of: pullRequest)
        #expect(store.editorFailure != nil)

        await store.openInEditor(file: "src/App.swift", line: 3, of: pullRequest)
        #expect(store.editorFailure == nil)
    }
}
