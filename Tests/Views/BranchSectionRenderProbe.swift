import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#465): vyrendruje **sekci `Větev`** ve všech podobách, které má zákres
/// (sekce 36), a k tomu potvrzení merge.
///
/// Proč sonda: „sedí to se sekcí 36?“ je otázka na obrázek. Co se **dá** tvrdit číslem, je
/// v `BranchMergeTests` (výčet důvodů a texty řádků) a v `MergePublishingTests` (co odejde).
///
/// `NSHostingView`, ne `ImageRenderer` — tatáž cesta jako u ostatních sond, viz
/// `docs/testovani.md`.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda sekce Větev (#465)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct BranchSectionRenderProbe {
    /// Podoby sekce — přesně ty dvě, které kreslí zákres, a k nim ty, které v něm nejsou,
    /// ale v aplikaci nastanou (načítá se, vypnutá brána, blokující nález).
    @Test("Vyrendrovat sekci Větev")
    func rendersTheBranchSection() throws {
        let scenes: [(String, Policy.BranchSection?)] = [
            ("vetev-zeleno", section()),
            ("vetev-za-zakladem", section(
                status: status(.mergeable, .behind),
                checks: [check("test-php 8.3", .failed), check("lint", .passed)]
            )),
            ("vetev-zjistuje", section(status: nil)),
            ("vetev-brana-vypnuta", section(
                editing: .blocked(PublishError.publishingNotAllowed(Self.repo).userDescription)
            )),
            ("vetev-blokujici-nalez", section(blocking: 2)),
            ("vetev-konflikt", section(status: status(.conflicting, .dirty))),
        ]

        for (name, section) in scenes {
            guard let section else { continue }
            let url = Self.outputDirectory.appending(path: "\(name).png")
            try Self.render(
                AnyView(
                    PanelBranchView(
                        section: section,
                        contentWidth: PanelMetadataView.contentWidth(inPanelOf: 300)
                    )
                    .frame(width: 300, alignment: .topLeading)
                    .background(Palette.chrome)
                ),
                width: 340,
                height: 200,
                to: url
            )
            print("SONDA \(url.path)")
        }
    }

    /// Potvrzení merge — jedna obrazovka, ale ve třech stavech, protože patička je to, co se v ní
    /// mění.
    @Test("Vyrendrovat potvrzení merge")
    func rendersTheMergeSheet() async throws {
        let scenes: [(String, MergeSubmission.State?)] = [
            ("merge-potvrzeni", nil),
            ("merge-potvrzeni-hotovo", .merged(
                MergedPullRequest(sha: "d5e454dd4838a98ce88339531517411941233813")
            )),
            ("merge-potvrzeni-selhalo", .failed(.branchMoved("Head branch was modified."))),
        ]

        for (name, state) in scenes {
            let url = Self.outputDirectory.appending(path: "\(name).png")
            // Podklad se nasazuje **tady, ne v sheetu**: v aplikaci ho kreslí okno sheetu, takže
            // by zadrátovaný v `MergeSheet` byl barva navíc, kterou tam nikdo nechce.
            try Self.render(
                AnyView(
                    MergeSheet(submission: await Self.submission(state: state), close: {})
                        .background(Palette.surface)
                ),
                width: 520,
                height: 380,
                to: url
            )
            print("SONDA \(url.path)")
        }
    }

    // MARK: - Scéna

    private static let repo = RepoID(owner: "keboola", name: "vault")
    private static let pr = PRIdentifier(repo: repo, number: 85)

    private func check(_ name: String, _ outcome: PullRequestCheck.Outcome) -> PullRequestCheck {
        PullRequestCheck(name: name, outcome: outcome, link: nil, startedAt: nil, completedAt: nil)
    }

    private func status(
        _ mergeability: BranchStatus.Mergeability,
        _ state: BranchStatus.MergeState
    ) -> BranchStatusState {
        .loaded(
            BranchStatus(mergeability: mergeability, mergeState: state),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    /// Scéna ze zákresu: `odinuv:chore/deps → main`, tři commity, šest checků.
    private func section(
        editing: Policy.MetadataEditing = .allowed,
        status: BranchStatusState? = .loaded(
            BranchStatus(mergeability: .mergeable, mergeState: .clean),
            updatedAt: Date(timeIntervalSince1970: 100)
        ),
        checks: [PullRequestCheck]? = nil,
        blocking: Int = 0
    ) -> Policy.BranchSection? {
        let detail = PullRequest(
            id: Self.pr,
            title: "chore: modernize dependencies",
            author: "odinuv",
            headSha: "9c1de02aa1b2c3d4e5f60718293a4b5c6d7e8f90",
            baseSha: "7b3f740e",
            headRef: "odinuv:chore/deps",
            baseRef: "main",
            url: URL(string: "https://github.com/\(Self.repo)/pull/85")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
        let green = (0..<6).map { check("check-\($0)", .passed) }
        return Policy.branchSection(
            editing: editing,
            detail: detail,
            commits: (0..<3).map { index in
                PullRequestCommit(
                    sha: String(format: "%040d", index),
                    message: "chore: krok \(index)",
                    authorName: "odinuv",
                    authorLogin: "odinuv",
                    avatarURL: nil,
                    committedAt: Date(timeIntervalSince1970: 100),
                    isMerge: false
                )
            },
            status: status,
            checks: checks ?? green,
            blockingFindings: blocking
        )
    }

    /// Odeslání ve **výchozím** stavu, nebo v tom, který si sonda vyžádá.
    ///
    /// Stav se nastavuje **voláním `merge()` s fake publisherem**, ne přepsáním pole: `state` je
    /// `private(set)` schválně, a sonda, která by ho obcházela, by fotila stav, do kterého se
    /// aplikace nedostane.
    @MainActor private static func submission(state: MergeSubmission.State?) async -> MergeSubmission {
        let plan = MergePlan(
            pullRequest: pr,
            headSha: "9c1de02aa1b2c3d4e5f60718293a4b5c6d7e8f90",
            head: "odinuv:chore/deps",
            base: "main",
            commits: 3,
            commitTitle: "chore: modernize dependencies (#85)"
        )
        let outcome: Result<MergedPullRequest, any Error> = switch state {
        case .merged(let merged): .success(merged)
        case .failed(let error): .failure(error)
        default: .failure(PublishError.unknown("sonda nemergovala"))
        }
        let submission = MergeSubmission(
            pullRequest: PullRequestSummary(
                id: pr,
                title: "chore: modernize dependencies",
                author: "odinuv",
                url: URL(string: "https://github.com/\(repo)/pull/85")!,
                updatedAt: Date(timeIntervalSince1970: 100),
                state: .open
            ),
            plan: plan,
            publisher: { FakeReviewPublisher(merge: outcome) },
            afterSuccess: {}
        )
        // Do stavu se sonda dostane **tou samou cestou jako aplikace** — zavoláním `merge()`
        // s fake publisherem. `state` je `private(set)` schválně a sonda, která by to obcházela,
        // by fotila stav, do kterého se aplikace nedostane.
        if state != nil { await submission.merge() }
        return submission
    }

    private static var outputDirectory: URL {
        URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako u ostatních
    /// sond.
    private static func render(_ scene: AnyView, width: CGFloat, height: CGFloat, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene.frame(width: width, height: height))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }
}
