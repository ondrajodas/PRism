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
/// **Scéna `01` jsou skutečná data z `keboola/platform-libraries#566`** (`gh pr view 566` a `gh api
/// compare`, 5. 9. 2026): otevřený, `mergeable: MERGEABLE`, `mergeStateStatus: CLEAN`,
/// `reviewDecision: APPROVED`, `latestReviews` s jedním `APPROVED` od `odinuv`, `reviewRequests`
/// s otevřenou žádostí na `MiroCillik`, checky zeleně, jeden nález nepředaný — a větev **o 21
/// commitů pozadu** za `main`em.
///
/// **Ta poslední hodnota tady do třetího kola #508 chyběla, a je to poučení o téhle sondě.** Scéna
/// bez ní vyšla podle tehdejšího pravidla „správně“, zatímco okno nad týmž PR kreslilo něco jiného
/// — sonda totiž tvrdí něco o **kresbě z připravených dat**, ne o tom, jaká data aplikace
/// doopravdy má. Je to pravidlo z #478: měřidlo, které vydá tutéž hodnotu pro „funguje“
/// i „nefunguje“, netvrdí nic. **Doklad o tom, že dráha na skutečném PR sedí, je snímek běžící
/// aplikace**, ne tenhle render.
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
        // Skutečná data #566: schváleno, CI zeleně, jeden nález k předání, jeden reviewer čeká
        // a větev o 21 commitů pozadu. `CI` a `Review` zelené, `Push` mlčí — poloha větve hlavou
        // na GitHubu nehýbe.
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
                BranchStatus(
                    mergeability: .mergeable,
                    mergeState: .clean,
                    divergence: BranchDivergence(ahead: 1, behind: 21)
                ),
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
        // Totéž po rebase: srovnaná větev, takže zezelená i `Push` a zastávka se posune na `Merge`.
        ("02-pl566-po-rebase", Policy.ownLoop(
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
        // Nepřetlačená práce v cache: `CI` ani `Review` nezezelenají, protože na GitHubu leží
        // **předchozí** hlava. Tohle je ta jediná podoba „rozešlé hlavy“, která je zhasíná —
        // scéna `01` vedle toho ukazuje, že poloha proti základu je něco jiného.
        ("03-nepretlaceno", Policy.ownLoop(
            ownership: .mine,
            state: .open,
            review: .clean,
            handoff: .never,
            sync: .rebased(
                RebasedBranch(
                    worktree: URL(filePath: "/tmp/566-sync"),
                    headSha: "abc1234",
                    rebasedFrom: "9c1de02",
                    arriving: [],
                    replayed: 2
                )
            ),
            status: .loaded(
                BranchStatus(mergeability: .mergeable, mergeState: .clean),
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
