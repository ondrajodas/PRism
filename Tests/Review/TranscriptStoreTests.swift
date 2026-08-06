import Foundation
import Testing

@testable import PRism

/// Čtení transcriptu zabité session (#97).
///
/// Proti **skutečnému** transcriptu z veřejného `ondrajodas/prism-review-sandbox`, jen
/// zkráceném na pět řádků: dva `queue-operation`, `user`, `assistant` s `ReportFindings`
/// a `last-prompt`. Ty typy eventů ve `stream-json` **nejsou** — a právě proto je fixture
/// skutečná, ne vyrobená: kdyby je parser neuměl přejít, dotažení by na nich spadlo.
///
/// Chybí v ní `result` event, přesně jako u každé zabité session. Z toho plyne, že se
/// z transcriptu nikdy nedá vyčíst „doběhlo“.
@Suite("Transcript zabité session")
struct TranscriptStoreTests {
    private let directory: TemporaryDirectory
    private let worktree = URL(filePath: "/Users/ondra/cache/worktrees/o/r/3-abc")

    init() throws {
        directory = try TemporaryDirectory()
    }

    private var store: TranscriptStore { TranscriptStore(projects: directory.url) }

    /// Uloží fixture tam, kde ji `claude` má.
    private func place(_ fixture: String, as sessionID: String) throws {
        let url = TranscriptLocation.transcript(
            ofSession: sessionID,
            in: worktree,
            projects: directory.url
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Fixture.text(fixture).write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("Ze skutečného transcriptu se vytáhnou nálezy")
    func readsFindingsFromARealTranscript() async throws {
        try place("transcript/interrupted-session.jsonl", as: "session-1")

        let summary = try #require(await store.summary(ofSession: "session-1", in: worktree))

        #expect(summary.calledReportFindings)
        #expect(summary.findings.count == 7)
        #expect(summary.findings.first?.file == "src/OrderRepository.php")
        #expect(summary.findings.first?.line == 14)
        #expect(summary.findings.first?.category == "security")
        // Neznámé typy eventů (`queue-operation`, `last-prompt`) parser přejde, ne spočítá
        // jako rozbité řádky.
        #expect(summary.malformedLines == 0)
    }

    /// Chybějící `result` event je to, co odlišuje zabitou session od doběhlé — a je to
    /// důvod, proč se výsledek ukládá jako `interrupted`, ne jako `finished`.
    @Test("Transcript neříká, že běh doběhl")
    func neverClaimsTheRunFinished() async throws {
        try place("transcript/interrupted-session.jsonl", as: "session-1")

        let summary = try #require(await store.summary(ofSession: "session-1", in: worktree))

        #expect(summary.outcome == nil)
    }

    @Test("Chybějící transcript není chyba, jen nic")
    func missingTranscriptGivesNothing() async throws {
        #expect(try await store.summary(ofSession: "nikdy-nebyla", in: worktree) == nil)
    }

    /// Session, která nálezy nikdy nenahlásila, se nesmí uložit jako výsledek — v řádku by
    /// vypadala jako „reviewer nic nenašel“.
    @Test("Transcript bez ReportFindings nedá nic")
    func aTranscriptWithoutFindingsGivesNothing() async throws {
        let url = TranscriptLocation.transcript(
            ofSession: "session-2",
            in: worktree,
            projects: directory.url
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"type":"assistant","message":{"content":[{"type":"text","text":"koukám"}]}}"#
            .write(to: url, atomically: true, encoding: .utf8)

        #expect(try await store.summary(ofSession: "session-2", in: worktree) == nil)
    }
}
