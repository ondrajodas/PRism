import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#465): vyrendruje **sekci `Větev`** ve všech podobách, které má zákres
/// (sekce 36 a od #482 i sekce 37), a k tomu potvrzení merge.
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
    /// ale v aplikaci nastanou (načítá se, vypnutá brána, konflikt).
    ///
    /// **Scéna `vetev-blokujici-nalez` odešla s #563**: blokující nález přestal být překážkou
    /// merge, takže by se nakreslila jako `vetev-zeleno` — a druhá kopie téhož snímku by tvrdila,
    /// že je co srovnávat.
    ///
    /// **Co z téhle sondy vyčíst nejde: barvu `Připravit k review`** (#482). Plná plocha
    /// `borderedProminent` se v **neaktivním** okně kreslí systémově šedá, ať je `tint` jakýkoli —
    /// vyzkoušeno, `.tint(Palette.accent)` na scéně na tom nezmění nic, takže tady nestojí (byl by
    /// to modifikátor, který nic nedělá). Odstín nasazuje `ContentView` celému oknu a ověřuje se
    /// **na běžící aplikaci**; sonda tvrdí rozvržení, ne barvu plochy.
    @Test("Vyrendrovat sekci Větev")
    func rendersTheBranchSection() throws {
        let scenes: [(String, Policy.BranchSection?, MetadataActionState?)] = [
            ("vetev-zeleno", section(), nil),
            ("vetev-za-zakladem", section(
                status: status(.mergeable, .behind),
                checks: [check("test-php 8.3", .failed), check("lint", .passed)]
            ), nil),
            ("vetev-zjistuje", section(status: nil), nil),
            ("vetev-brana-vypnuta", section(
                editing: .blocked(PublishError.publishingNotAllowed(Self.repo).userDescription)
            ), nil),
            ("vetev-konflikt", section(status: status(.conflicting, .dirty)), nil),
            // Sekce 37 (#482) — tři podoby, které zákres kreslí: draft s tlačítkem, draft
            // s chybou pod ním a **draft s vypnutou branou**, kde je tlačítko zašedlé a důvod
            // stojí ve výstraze nad ním.
            ("vetev-draft", section(state: .draft, status: status(.mergeable, .draft)), nil),
            (
                "vetev-draft-chyba",
                section(state: .draft, status: status(.mergeable, .draft)),
                .readyFailed(.unknown("HTTP 403: Resource not accessible by integration"))
            ),
            (
                "vetev-draft-brana-vypnuta",
                section(
                    editing: .blocked(PublishError.publishingNotAllowed(Self.repo).userDescription),
                    state: .draft,
                    status: status(.mergeable, .draft)
                ),
                nil
            ),
        ]

        for (name, section, action) in scenes {
            guard let section else { continue }
            let url = Self.outputDirectory.appending(path: "\(name).png")
            try Self.render(
                AnyView(
                    PanelBranchView(
                        section: section,
                        contentWidth: PanelMetadataView.contentWidth(inPanelOf: 300),
                        actionState: action
                    )
                    .frame(width: 300, alignment: .topLeading)
                    .background(Palette.chrome)
                ),
                width: 340,
                // Draftové scény mají o tlačítko a o věty víc, takže 200 bodů by je uřízlo —
                // a uříznutá sonda je zrovna to, kvůli čemu se na ni nedá spolehnout.
                height: section.ready.isVisible ? 300 : 200,
                to: url
            )
            print("SONDA \(url.path)")
        }
    }

    /// Potvrzení merge — jedna obrazovka, ale v šesti stavech: patička je to, co se v ní mění,
    /// a od #556 k tomu **metoda**.
    ///
    /// Tři nové scény jsou přesně sekce 48 zákresu: výchozí metoda z nastavení, přebitá pro tenhle
    /// jeden merge, a **repo, které výchozí metodu nepovoluje**. Do té třetí se v aplikaci
    /// klikáním nedostaneš — je to stav, který nastane jedině nad konkrétním repem —, takže je to
    /// jediné místo, kde se dá zkontrolovat, jak vypadá.
    @Test("Vyrendrovat potvrzení merge")
    func rendersTheMergeSheet() async throws {
        // Repo z měření: `keboola/job-queue-daemon` nemá `allow_rebase_merge`.
        let withoutRebase = RepositoryMergeSettings(
            allowsMergeCommit: true,
            allowsSquash: true,
            allowsRebase: false,
            squashBody: .commitMessages,
            mergeCommitBody: .pullRequestTitle
        )
        let scenes: [(String, () async -> MergeSubmission)] = [
            ("merge-potvrzeni", { await Self.submission(state: nil) }),
            ("merge-potvrzeni-hotovo", {
                await Self.submission(state: .merged(
                    MergedPullRequest(sha: "d5e454dd4838a98ce88339531517411941233813")
                ))
            }),
            ("merge-potvrzeni-selhalo", {
                await Self.submission(state: .failed(.branchMoved("Head branch was modified.")))
            }),
            // #556 — přebito pro tenhle jeden merge: s metodou se přepíšou i ostatní řádky.
            ("merge-metoda-prebita", {
                await Self.submission(state: nil, override: .mergeCommit)
            }),
            ("merge-metoda-rebase", { await Self.submission(state: nil, override: .rebase) }),
            // #556 — výchozí metoda, kterou repo nepovoluje: nic není vybráno, `Mergnout` je
            // zakázané a pod výpisem stojí výstraha.
            ("merge-metoda-nejde", {
                await Self.submission(
                    state: nil,
                    defaultMethod: .rebase,
                    repository: withoutRebase
                )
            }),
        ]

        for (name, make) in scenes {
            let url = Self.outputDirectory.appending(path: "\(name).png")
            // Podklad se nasazuje **tady, ne v sheetu**: v aplikaci ho kreslí okno sheetu, takže
            // by zadrátovaný v `MergeSheet` byl barva navíc, kterou tam nikdo nechce.
            try Self.render(
                AnyView(
                    MergeSheet(submission: await make(), close: {})
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
        state: PullRequestState = .open,
        status: BranchStatusState? = .loaded(
            BranchStatus(mergeability: .mergeable, mergeState: .clean),
            updatedAt: Date(timeIntervalSince1970: 100)
        ),
        checks: [PullRequestCheck]? = nil
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
            state: state,
            // **Vyplněné schválně**: `nil` je „nevím, kde větev leží“, a `Policy.syncWarnings` na to
            // přidá do výstrahy vlastní větu — sonda by pak fotila stav, do kterého se okno
            // s načteným detailem nedostane.
            isCrossRepository: false
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
            checks: checks ?? green
        )
    }

    /// Odeslání ve **výchozím** stavu, nebo v tom, který si sonda vyžádá.
    ///
    /// Stav se nastavuje **voláním `merge()` s fake publisherem**, ne přepsáním pole: `state` je
    /// `private(set)` schválně, a sonda, která by ho obcházela, by fotila stav, do kterého se
    /// aplikace nedostane.
    @MainActor private static func submission(
        state: MergeSubmission.State?,
        // Metoda merge (#556). `defaultMethod` je to, co stojí v nastavení; `repository` to, co
        // repo pustí. Výchozí hodnoty jsou stav z návrhu: squash a repo se všemi třemi metodami.
        defaultMethod: MergeMethod = .squash,
        repository: RepositoryMergeSettings = RepositoryMergeSettings(
            allowsMergeCommit: true,
            allowsSquash: true,
            allowsRebase: true,
            squashBody: .commitMessages,
            mergeCommitBody: .pullRequestTitle
        ),
        // Přebití metody pro tenhle jeden merge — tou samou cestou jako klik na pilulku.
        override: MergeMethod? = nil
    ) async -> MergeSubmission {
        // Návrh, ne payload (#556): metoda se vybírá až v potvrzení, takže titulek commitu
        // skládá `Policy` z titulku pull requestu podle vybrané metody.
        let proposal = MergeProposal(
            pullRequest: pr,
            headSha: "9c1de02aa1b2c3d4e5f60718293a4b5c6d7e8f90",
            head: "odinuv:chore/deps",
            base: "main",
            commits: 3,
            title: "chore: modernize dependencies",
            defaultMethod: defaultMethod,
            repository: repository
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
            proposal: proposal,
            publisher: { FakeReviewPublisher(merge: outcome) },
            afterSuccess: {}
        )
        // Do stavu se sonda dostane **tou samou cestou jako aplikace** — zavoláním `merge()`
        // s fake publisherem. `state` je `private(set)` schválně a sonda, která by to obcházela,
        // by fotila stav, do kterého se aplikace nedostane.
        if let override { submission.method = override }
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
