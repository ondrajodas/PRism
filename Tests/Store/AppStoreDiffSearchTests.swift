import Foundation
import Testing

@testable import PRism

/// Hledání v diffu drží store (#152), ne view: pruh musí přežít přepnutí tabu i složení panelu,
/// po kterém se `DiffView` staví znovu.
///
/// Nejcennější tvrzení jsou tady negativní: že se **výskyty nepřepočítávají, když se nehledá**,
/// že se pruh **nevytvoří čtením** a že se stav dvou pull requestů (a dvou diffů téhož PR)
/// **nemíchá**.
@Suite("AppStore — hledání v diffu")
@MainActor
struct AppStoreDiffSearchTests {
    private let sources = [Source(name: "Moje", query: "review-requested:@me is:open")]

    private var configuration: Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = sources
        return configuration
    }

    private let pr = PRIdentifier("cli/cli#1")!
    private let other = PRIdentifier("cli/cli#2")!
    private let path = "src/Vault/SecretClient.php"

    private var diffText: String {
        [
            "diff --git a/\(path) b/\(path)",
            "--- a/\(path)",
            "+++ b/\(path)",
            "@@ -96,4 +96,5 @@",
            "     private const FLUSH_TIMEOUT = 5;",
            "-        $this->client->put($key, self::FLUSH_TIMEOUT);",
            "+        $this->client->putMultiple($chunk, self::FLUSH_TIMEOUT_MS);",
            " }",
        ].joined(separator: "\n")
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

    private func store(diffs: [Result<String, any Error>], files: [Result<String, any Error>] = []) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([]), diffs: diffs, files: files),
            configuration: configuration,
            time: FakeTimeSource()
        )
    }

    private func loaded() async -> AppStore {
        let store = store(diffs: [.success(diffText)])
        await store.loadDiff(for: summary(pr))
        return store
    }

    // MARK: - Otevření a zavření

    /// **Čtení pruh nevyrábí**: zápis do observable slovníku uprostřed skládání těla view by byl
    /// změna stavu při jeho čtení — a hlavně by pruh vznikl i tam, kde o něj nikdo neřekl.
    @Test("Bez ⌘F žádný pruh není")
    func readingDoesNotCreateTheBar() async {
        let store = await loaded()
        #expect(store.diffSearch(in: pr) == nil)
        #expect(store.diffSearches.isEmpty)
    }

    @Test("⌘F otevře pruh a řekne poli, ať se zaostří")
    func openFocusesTheField() async throws {
        let store = await loaded()
        store.openDiffSearch(in: pr)

        let state = try #require(store.diffSearch(in: pr))
        #expect(state.isOpen)
        #expect(state.focusRequests == 1)
    }

    /// Druhé ⌘F nad otevřeným pruhem má vrátit **fokus**, ne pruh zavřít. Zavírá se pojmenovanou
    /// akcí (`✕`, `⎋`).
    @Test("Druhé ⌘F pruh nezavře, jen znovu zaostří")
    func secondOpenOnlyRefocuses() async throws {
        let store = await loaded()
        store.openDiffSearch(in: pr)
        store.openDiffSearch(in: pr)

        let state = try #require(store.diffSearch(in: pr))
        #expect(state.isOpen)
        #expect(state.focusRequests == 2)
    }

    /// Zavření **nemaže dotaz** (druhé ⌘F pokračuje tam, kde první skončilo), ale zvýraznění
    /// zhasne — kreslí se z `drawnQuery`. A pozice se zapomíná: stát na výskytu má smysl jen
    /// s pruhem, ve kterém je vidět, kolikátý to je.
    @Test("Zavření zhasne zvýraznění, dotaz si nechá")
    func closeKeepsTheQuery() async throws {
        let store = await loaded()
        store.openDiffSearch(in: pr)
        store.setDiffSearchQuery("FLUSH_TIMEOUT", in: pr)
        _ = store.stepDiffSearch(.forward, in: pr)
        store.closeDiffSearch(in: pr)

        let state = try #require(store.diffSearch(in: pr))
        #expect(!state.isOpen)
        #expect(state.query == "FLUSH_TIMEOUT")
        #expect(state.current == nil)
        #expect(!state.drawnQuery.isActive)
        // Výskyty zůstávají spočítané — pruh se otevře do hotového stavu.
        #expect(state.hits.count == 3)
    }

    // MARK: - Dotaz a počty

    @Test("Dotaz spočítá výskyty i počty po souborech")
    func queryCountsHits() async throws {
        let store = await loaded()
        store.openDiffSearch(in: pr)
        store.setDiffSearchQuery("FLUSH_TIMEOUT", in: pr)

        let state = try #require(store.diffSearch(in: pr))
        #expect(state.hits.count == 3)
        #expect(state.counts == [path: 3])
        #expect(state.report == .hits(position: nil, total: 3))
    }

    /// **Psaní samo neskáče**: jinak by se diff hýbal pod rukama při každém písmenu. Pozice
    /// zůstává prázdná, dokud se nezmáčkne šipka nebo `⏎`.
    @Test("Psaní neskáče a přepsaný dotaz zapomene pozici")
    func typingDoesNotJump() async throws {
        let store = await loaded()
        store.openDiffSearch(in: pr)
        store.setDiffSearchQuery("FLUSH_TIMEOUT", in: pr)
        #expect(store.diffSearch(in: pr)?.current == nil)

        _ = store.stepDiffSearch(.forward, in: pr)
        #expect(store.diffSearch(in: pr)?.current == 0)

        store.setDiffSearchQuery("FLUSH", in: pr)
        #expect(store.diffSearch(in: pr)?.current == nil)
    }

    @Test("Vyprázdněné pole zahodí výskyty i počty")
    func clearingTheQueryClearsEverything() async throws {
        let store = await loaded()
        store.openDiffSearch(in: pr)
        store.setDiffSearchQuery("FLUSH_TIMEOUT", in: pr)
        store.setDiffSearchQuery("", in: pr)

        let state = try #require(store.diffSearch(in: pr))
        #expect(state.hits.isEmpty)
        #expect(state.counts.isEmpty)
        #expect(state.report == .idle)
    }

    @Test("Kapsle Aa přepočítá výskyty")
    func caseSensitivityRecounts() async throws {
        let store = await loaded()
        store.openDiffSearch(in: pr)
        store.setDiffSearchQuery("flush_timeout", in: pr)
        #expect(store.diffSearch(in: pr)?.hits.count == 3)

        store.setDiffSearchCaseSensitive(true, in: pr)
        #expect(store.diffSearch(in: pr)?.hits.isEmpty == true)
        #expect(store.diffSearch(in: pr)?.report == .empty)
    }

    // MARK: - Skok

    @Test("Šipka vrací výskyt a posouvá pozici")
    func stepReturnsTheHit() async throws {
        let store = await loaded()
        store.openDiffSearch(in: pr)
        store.setDiffSearchQuery("FLUSH_TIMEOUT", in: pr)

        let first = try #require(store.stepDiffSearch(.forward, in: pr))
        #expect(first.line.kind == .context)
        #expect(store.diffSearch(in: pr)?.current == 0)

        let second = try #require(store.stepDiffSearch(.forward, in: pr))
        #expect(second.line.kind == .removed)
        #expect(store.diffSearch(in: pr)?.current == 1)

        let back = try #require(store.stepDiffSearch(.backward, in: pr))
        #expect(back.line.kind == .context)
    }

    @Test("Bez výskytů šipka nic nevrátí")
    func stepWithoutHits() async {
        let store = await loaded()
        store.openDiffSearch(in: pr)
        store.setDiffSearchQuery("tady-nic-není", in: pr)
        #expect(store.stepDiffSearch(.forward, in: pr) == nil)
    }

    @Test("Bez pruhu se skákat nedá")
    func stepWithoutBar() async {
        let store = await loaded()
        #expect(store.stepDiffSearch(.forward, in: pr) == nil)
    }

    // MARK: - Přeskládání

    /// Rozbalený kontext se **do hledání započítá** — právě to říká věta v pruhu, takže se počet
    /// musí přeskládat hned, jak řádky přibudou.
    @Test("Rozbalení kontextu přidá výskyty")
    func revealingContextAddsHits() async throws {
        let content = (1...100).map { $0 == 10 ? "use FLUSH_TIMEOUT;" : "// řádek \($0)" }
        let store = store(diffs: [.success(diffText)], files: [.success(content.joined(separator: "\n"))])
        await store.loadDiff(for: summary(pr))
        store.openDiffSearch(in: pr)
        store.setDiffSearchQuery("FLUSH_TIMEOUT", in: pr)
        #expect(store.diffSearch(in: pr)?.hits.count == 3)

        store.reveal(1...95, of: path, in: pr)
        await waitUntil("obsah souboru dorazí") {
            !store.expansion(of: path, in: pr).content.isEmpty
        }
        await waitUntil("výskyt v rozbaleném kontextu se započítá") {
            store.diffSearch(in: pr)?.hits.count == 4
        }

        // A sbalení ho zase odebere: řádky v okně nejsou, takže by je počet tvrdil o kódu, na
        // který se nedá skočit.
        store.collapseRevealedLines(in: pr)
        #expect(store.diffSearch(in: pr)?.hits.count == 3)
    }

    /// **Nic se nepřepočítává, dokud se nehledá.** Tik pollingu nad diffem tak nestojí nic —
    /// a zavřený pruh s dotazem si počet nechá, protože se otevře do hotového stavu.
    @Test("Bez dotazu se přeskládání nekoná")
    func refreshDoesNothingWithoutAQuery() async throws {
        let store = await loaded()
        store.openDiffSearch(in: pr)
        store.refreshDiffSearch(in: pr)

        let state = try #require(store.diffSearch(in: pr))
        #expect(state.hits.isEmpty)
        #expect(state.report == .idle)
    }

    /// Nový diff = jiné řádky, takže se výskyty musí přeskládat. Bez toho by pruh ukazoval počet
    /// z minula a skok mířil do prázdna.
    @Test("Nový diff přeskládá výskyty")
    func newDiffRecounts() async throws {
        let second = [
            "diff --git a/\(path) b/\(path)",
            "--- a/\(path)",
            "+++ b/\(path)",
            "@@ -96,2 +96,2 @@",
            "-    private const FLUSH_TIMEOUT = 5;",
            "+    private const FLUSH_TIMEOUT_MS = 5000;",
        ].joined(separator: "\n")
        let store = store(diffs: [.success(diffText), .success(second)])
        await store.loadDiff(for: summary(pr))
        store.openDiffSearch(in: pr)
        store.setDiffSearchQuery("FLUSH_TIMEOUT", in: pr)
        #expect(store.diffSearch(in: pr)?.hits.count == 3)

        await store.loadDiff(for: summary(pr, updatedAt: 200))
        #expect(store.diffSearch(in: pr)?.hits.count == 2)
    }

    // MARK: - Co se nesmí míchat

    @Test("Dva pull requesty mají vlastní pruh")
    func eachPullRequestHasItsOwnBar() async throws {
        let store = store(diffs: [.success(diffText), .success(diffText)])
        await store.loadDiff(for: summary(pr))
        await store.loadDiff(for: summary(other))

        store.openDiffSearch(in: pr)
        store.setDiffSearchQuery("FLUSH_TIMEOUT", in: pr)

        #expect(store.diffSearch(in: other) == nil)
        #expect(store.diffSearch(in: pr)?.query == "FLUSH_TIMEOUT")
    }

    /// Diff commitu je jiný obsah na týchž souřadnicích, takže sdílený pruh by mluvil o jiném
    /// diffu — proto je `commit` součástí klíče (tentýž důvod jako u `FileExpansionKey`).
    @Test("Diff commitu má vlastní pruh, i když je otevřený i u PR")
    func commitDiffHasItsOwnBar() async throws {
        let store = await loaded()
        store.openDiffSearch(in: pr)
        store.setDiffSearchQuery("FLUSH_TIMEOUT", in: pr)

        store.openDiffSearch(in: pr, commit: "abc123")
        store.setDiffSearchQuery("putMultiple", in: pr, commit: "abc123")

        #expect(store.diffSearch(in: pr)?.query == "FLUSH_TIMEOUT")
        #expect(store.diffSearch(in: pr, commit: "abc123")?.query == "putMultiple")
        // Diff toho commitu se nikdy nenačetl, takže není v čem hledat — a pruh to nezastírá.
        #expect(store.diffSearch(in: pr, commit: "abc123")?.hits.isEmpty == true)
    }
}
