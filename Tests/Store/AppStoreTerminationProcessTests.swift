import Foundation
import Testing

@testable import PRism

/// Zavření aplikace proti **skutečnému procesu**, ne proti fake reviewerovi (#264).
///
/// Fake runner ověří, že se běh zruší; jestli tím opravdu umře podproces, se dá zjistit jedině
/// spuštěním — a přesně na tom to selhávalo. Zrušení jde přes `WorkCoordinator`, který práci drží
/// ve vlastním tasku, takže mezi `cancel()` a odeslaným signálem je několik hopů mezi aktory.
/// S fake reviewerem není ta cesta vidět vůbec.
///
/// Celý řetěz je proto **produkční**: `AppStore` → `ClaudeReviewRunner` → `SubprocessStreamer` →
/// `Process`. Za `claude` stojí skript, který ignoruje argumenty, vypíše svoje PID a čeká —
/// `exec` schválně, aby to PID patřilo tomu procesu, který má umřít, a nezůstal pod ním potomek,
/// který by výsledek rozmazal.
@Suite("AppStore — zavření aplikace nad skutečným procesem")
@MainActor
struct AppStoreTerminationProcessTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    @Test("Zavření aplikace zabije session, která běží")
    func closingTheAppKillsTheSession() async throws {
        let pidFile = directory.url.appending(path: "session.pid")
        let store = try store(claude: script(writingPidTo: pidFile))

        store.startReview(for: pr)
        // Zabíjet se má proces, který **doopravdy běží** — jinak by test prošel i tehdy, kdyby
        // se žádná session nespustila.
        let pid = try await processID(writtenTo: pidFile)

        await store.stopReviewsBeforeTermination()

        // **Tohle tvrzení musí být první a bez jediného `await`.** V provozu po téhle metodě
        // následuje zavření aplikace, takže víc času než „nic“ běh nedostane — a doběhlý běh
        // znamená, že jeho proud skončil, tedy že `SIGKILL` odešel. Čekání kdekoli výš by tuhle
        // podmínku samo splnilo a test by prošel i nad verzí, která se nedočká.
        #expect(store.runningReviews == 0)
        // Až potom se kouká na proces. Tady se čekat smí: mezi doručeným `SIGKILL`em a tím, že
        // proces zmizí z tabulky, je ještě sklizení, které nemá s aplikací co dělat.
        #expect(await processHasGone(pid), "session \(pid) po zavření aplikace pořád běží")
    }

    // MARK: - Řetěz

    private func store(claude: URL) throws -> AppStore {
        let detail = PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
        let worktree = directory.url.appending(path: "worktree")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)

        return AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail)),
            time: FakeTimeSource(),
            checkout: FakeRepoCheckout(worktree: worktree),
            reviewer: ClaudeReviewRunner(
                claude: claude,
                // Session se nespustí, takže na `gh` nikdo nesáhne — cesta je tu jen do
                // prostředí, které si `ClaudeCommand` skládá.
                gh: URL(filePath: "/usr/bin/true"),
                runner: SubprocessStreamer()
            ),
            reviews: ReviewStore(layout: layout, time: FakeTimeSource())
        )
    }

    /// Skript za `claude`: vypíše svoje PID a čeká, dokud ho někdo nezabije.
    private func script(writingPidTo pidFile: URL) throws -> URL {
        let path = pidFile.path(percentEncoded: false)
        let script = directory.url.appending(path: "claude")
        try """
        #!/bin/sh
        echo $$ > '\(path)'
        exec sleep 30
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path(percentEncoded: false)
        )
        return script
    }

    // MARK: - Sledování procesu

    // Sonda na PID i její důvod jsou v `Tests/Support/ProcessProbing.swift` — tentýž postup
    // potřebují tři suity, takže tři kopie by znamenaly, že se příští oprava udělá v jedné (#296).
}
