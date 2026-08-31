import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test: vyrenderuje sekci `Větev` (#465, #466) do PNG, aby se dalo **koukat** na to, co
/// se u srovnání větve nakreslí, a srovnat to s návrhem (sekce 36).
///
/// Vypnutá schválně (`.disabled`) — pouští se ručně, když se na tu sekci sahá. Render nezastupuje
/// tvrzení: co má platit, tvrdí `BranchSyncOfferTests` a `AppStoreBranchSyncTests`.
///
/// Postup, proč zrovna takhle a co se z renderu nedozvíš, je v
/// [`docs/testovani.md`](../../docs/testovani.md), *Jak si zkontrolovat, jak view vypadá*.
@Suite("Sonda — sekce Větev", .disabled("sonda, pouští se ručně"))
@MainActor
struct BranchSyncRenderProbe {
    private static let output = URL(filePath: NSTemporaryDirectory())
        .appending(path: "prism-branch-sync")

    @Test("Vyrenderuj stavy sekce Větev")
    func renderStates() throws {
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            for (name, state) in Self.scenes {
                try render(state, to: "\(name)-\(suffix).png", dark: dark)
            }
        }
        print("Sekce Větev vyrenderovaná do \(Self.output.path)")
    }

    /// Scény, na které se u #466 kouká. **Vyjmenované**, aby se render dal srovnat s návrhem po
    /// řádcích, ne po dojmu.
    private static let scenes: [(String, Scene)] = [
        ("01-zeleno", Scene(behind: 0, checkFailed: false, sync: nil)),
        ("02-pozadu", Scene(behind: 4, checkFailed: true, sync: nil)),
        ("03-brana-vypnuta", Scene(behind: 4, checkFailed: false, sync: nil, editing: .blocked("Odesílání na GitHub je vypnuté."))),
        ("04-prehravam", Scene(behind: 4, checkFailed: false, sync: .rebasing)),
        ("04b-mezistav", Scene(behind: 4, checkFailed: false, sync: .rebased(Self.rebased(replayed: 4)))),
        ("04c-mezistav-jeden", Scene(behind: 1, checkFailed: false, sync: .rebased(Self.rebased(replayed: 1)))),
        // **`behind: 0` schválně**: po úspěšném force pushi je větev nad základem, takže scéna
        // s „o 4 commity vzadu“ vedle „force push poslal 4 commity“ by si protiřečila. Od #466 je
        // to i pravda v aplikaci — hlava se dotáhne, takže se divergence přepočítá.
        ("05-pretlaceno", Scene(behind: 0, checkFailed: false, sync: .pushed(replayed: 4))),
        ("06-uz-bylo", Scene(behind: 4, checkFailed: false, sync: .alreadyInSync)),
        ("07-konflikt", Scene(behind: 4, checkFailed: false, sync: .conflicted(files: ["composer.lock", "src/Vault/SecretClient.php", "tests/VaultTest.php", "README.md"]))),
        ("08-rozdelany-rebase", Scene(behind: 4, checkFailed: false, sync: .unfinished(files: ["composer.lock"]))),
        ("09-rozdelany-po-restartu", Scene(behind: 4, checkFailed: false, sync: .unfinished(files: []))),
        ("10-lease-odmitnut", Scene(behind: 4, checkFailed: false, sync: .failed(.leaseRejected))),
        ("11-cizi-vetev", Scene(behind: 4, checkFailed: false, sync: .failed(.notMine(author: "odinuv")))),
        ("12-fork", Scene(behind: 4, checkFailed: false, sync: nil, crossRepository: true)),
    ]

    private struct Scene {
        let behind: Int
        let checkFailed: Bool
        let sync: BranchSyncState?
        var editing: Policy.MetadataEditing = .allowed
        var crossRepository: Bool? = false
    }

    /// Šířka panelu je ta skutečná (300 bodů minus rail), aby se poznalo, co se do ní **nevejde** —
    /// zúžená komponenta je jiný design (pravidlo z `CLAUDE.md`).
    private static let contentWidth = 278.0

    private func render(_ scene: Scene, to name: String, dark: Bool) throws {
        let section = try #require(
            Policy.branchSection(
                editing: scene.editing,
                detail: Self.detail(crossRepository: scene.crossRepository),
                commits: Self.commits(),
                status: Self.status(behind: scene.behind),
                checks: Self.checks(failed: scene.checkFailed),
                blockingFindings: 0,
                sync: scene.sync
            )
        )

        let content = PanelBranchView(
            section: section,
            contentWidth: Self.contentWidth,
            syncState: scene.sync
        )
        .availableWidth(Self.contentWidth)
        .background(Palette.chrome)
        .environment(\.colorScheme, dark ? .dark : .light)

        var image: NSImage?
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
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

    // MARK: - Data scény

    private static let pr = PRIdentifier(repo: RepoID(owner: "ondrajodas", name: "PRism"), number: 466)

    /// Přerovnaná větev, která čeká na přetlačení — mezistav z rozdělení akce na dva kroky (#466).
    private static func rebased(replayed: Int) -> RebasedBranch {
        RebasedBranch(
            worktree: URL(filePath: "/tmp/prism-sync"),
            headSha: "1111222233334444555566667777888899990000",
            rebasedFrom: "9c1de02aa1b2c3d4e5f60718293a4b5c6d7e8f90",
            replayed: replayed
        )
    }

    private static func detail(crossRepository: Bool? = false) -> PullRequest {
        PullRequest(
            id: pr,
            title: "feat: sync own branch with main",
            author: "ondrajodas",
            headSha: "9c1de02aa1b2c3d4e5f60718293a4b5c6d7e8f90",
            baseSha: "7b3f740e",
            headRef: "issue-466-branch-sync",
            baseRef: "main",
            url: URL(string: "https://github.com/ondrajodas/PRism/pull/466")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open,
            isCrossRepository: crossRepository
        )
    }

    private static func commits() -> [PullRequestCommit] {
        (0..<3).map { index in
            PullRequestCommit(
                sha: "aaaa\(index)",
                message: "feat: krok \(index)",
                authorName: "Ondřej Jodas",
                authorLogin: "ondrajodas",
                avatarURL: nil,
                committedAt: Date(timeIntervalSince1970: 100),
                isMerge: false
            )
        }
    }

    private static func status(behind: Int) -> BranchStatusState {
        .loaded(
            BranchStatus(
                mergeability: .mergeable,
                mergeState: .clean,
                divergence: BranchDivergence(ahead: 3, behind: behind)
            ),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private static func checks(failed: Bool) -> [PullRequestCheck] {
        var checks = (0..<5).map { index in
            PullRequestCheck(
                name: "test-\(index)",
                outcome: .passed,
                link: nil,
                startedAt: nil,
                completedAt: nil
            )
        }
        checks.append(
            PullRequestCheck(
                name: failed ? "test-php 8.3" : "test-php 8.4",
                outcome: failed ? .failed : .passed,
                link: nil,
                startedAt: nil,
                completedAt: nil
            )
        )
        return checks
    }
}
