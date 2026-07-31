import Foundation
import Testing

@testable import PRism

/// `gh` popisuje stav dvěma poli a v každém příkazu jinou velikostí písmen — mapování na
/// jeden plochý výčet je proto vlastní krok a testuje se vyčerpávajícím způsobem.
@Suite("PullRequestState z výstupu gh")
struct GhPullRequestStateTests {
    @Test("Otevřený PR", arguments: ["open", "OPEN"])
    func openMapsToOpen(raw: String) {
        #expect(PullRequestState(ghState: raw, isDraft: false) == .open)
    }

    @Test("Otevřený rozpracovaný PR je draft", arguments: ["open", "OPEN"])
    func draftMapsToDraft(raw: String) {
        #expect(PullRequestState(ghState: raw, isDraft: true) == .draft)
    }

    @Test("Mergnutý PR", arguments: ["merged", "MERGED"])
    func mergedMapsToMerged(raw: String) {
        #expect(PullRequestState(ghState: raw, isDraft: false) == .merged)
    }

    @Test("Zavřený PR", arguments: ["closed", "CLOSED"])
    func closedMapsToClosed(raw: String) {
        #expect(PullRequestState(ghState: raw, isDraft: false) == .closed)
    }

    @Test("Zavřený draft je zavřený, ne draft")
    func closedDraftIsClosed() {
        #expect(PullRequestState(ghState: "closed", isDraft: true) == .closed)
    }

    @Test("Neznámý stav se nehádá")
    func unknownStateIsRejected() {
        #expect(PullRequestState(ghState: "locked", isDraft: false) == nil)
    }
}
