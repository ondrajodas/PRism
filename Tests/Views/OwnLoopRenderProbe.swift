import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test: vyrenderuje dráhu smyčky vlastního PR (#508) do PNG, aby se dalo **koukat** na
/// to, co se za zastávkou nakreslí, a srovnat to s návrhem (sekce 52).
///
/// Vypnutá schválně (`.disabled`) — pouští se ručně, když se na dráhu sahá. Render nezastupuje
/// tvrzení: co má platit, tvrdí `OwnLoopTests`.
///
/// **Scéna `01` jsou skutečná data z `keboola/platform-libraries#566`** (`gh pr view 566`, 5. 9.
/// 2026): otevřený, `mergeable: MERGEABLE`, `mergeStateStatus: CLEAN`, `reviewDecision: APPROVED`,
/// `latestReviews` s jedním `APPROVED` od `odinuv`, `reviewRequests` s otevřenou žádostí na
/// `MiroCillik`, checky zeleně, jeden nález nepředaný.
///
/// Postup, proč zrovna takhle a co se z renderu nedozvíš, je v
/// [`docs/testovani.md`](../../docs/testovani.md), *Jak si zkontrolovat, jak view vypadá*.
@Suite("Sonda — dráha smyčky vlastního PR", .disabled("sonda, pouští se ručně"))
@MainActor
struct OwnLoopRenderProbe {
    private static let output = URL(filePath: NSTemporaryDirectory())
        .appending(path: "prism-own-loop")
    private static let width: Double = 900

    @Test("Vyrenderuj dráhu smyčky")
    func renderLane() throws {
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        for (name, loop) in Self.scenes {
            try render(try #require(loop), to: "\(name).png")
        }
        print("Dráha smyčky vyrenderovaná do \(Self.output.path)")
    }

    private static let scenes: [(String, OwnLoop?)] = [
        // Skutečná data #566: schváleno, CI zeleně, jeden nález k předání, jeden reviewer čeká.
        ("01-pl566", Policy.ownLoop(
            ownership: .mine,
            state: .open,
            review: .completed(findings: 6),
            handoff: HandoffReport(
                stage: .never,
                handoff: nil,
                pending: 1,
                freshDiscussion: [],
                staleFindings: 0,
                commits: nil
            ),
            status: .loaded(
                BranchStatus(mergeability: .mergeable, mergeState: .clean),
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            checks: [
                check("build"), check("phpstan"), check("tests"),
            ],
            reviewers: [
                RequestedReviewer(login: "odinuv", answer: .approved),
                RequestedReviewer(login: "MiroCillik", answer: .waiting),
            ],
            merge: .allowed
        )),
        // Totéž bez otevřené žádosti o review — takhle vypadá dráha, když je Review doopravdy hotové.
        ("02-pl566-bez-cekajiciho", Policy.ownLoop(
            ownership: .mine,
            state: .open,
            review: .completed(findings: 6),
            handoff: HandoffReport(
                stage: .never,
                handoff: nil,
                pending: 1,
                freshDiscussion: [],
                staleFindings: 0,
                commits: nil
            ),
            status: .loaded(
                BranchStatus(mergeability: .mergeable, mergeState: .clean),
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            checks: [check("build"), check("phpstan"), check("tests")],
            reviewers: [RequestedReviewer(login: "odinuv", answer: .approved)],
            merge: .allowed
        )),
        // Nepřetlačená práce v cache: CI ani Review nezezelenají, protože mluví o jiné hlavě.
        ("03-nepretlaceno", Policy.ownLoop(
            ownership: .mine,
            state: .open,
            review: .clean,
            handoff: .never,
            status: .loaded(
                BranchStatus(
                    mergeability: .mergeable,
                    mergeState: .clean,
                    divergence: BranchDivergence(ahead: 1, behind: 4)
                ),
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            checks: [check("build")],
            reviewers: [RequestedReviewer(login: "odinuv", answer: .approved)],
            merge: .allowed
        )),
    ]

    private static func check(_ name: String) -> PullRequestCheck {
        PullRequestCheck(name: name, outcome: .passed, link: nil, startedAt: nil, completedAt: nil)
    }

    private func render(_ loop: OwnLoop, to name: String) throws {
        let content = OwnLoopView(loop: loop, perform: { _ in })
            .availableWidth(Self.width)
            .frame(width: Self.width)
            .padding(12)
            .background(Palette.chrome)
            .environment(\.colorScheme, .dark)

        var image: NSImage?
        let appearance = try #require(NSAppearance(named: .darkAqua))
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            image = renderer.nsImage
        }

        let rendered = try #require(image)
        let bitmap = try #require(rendered.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: Self.output.appending(path: name))
    }
}
