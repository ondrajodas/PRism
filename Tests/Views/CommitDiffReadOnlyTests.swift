import Foundation
import SwiftUI
import Testing

@testable import PRism

/// **Že se v diffu commitu nedá nic napsat** (#317) — test, který tvrdí, že se něco *ne*stalo.
///
/// Tab `Commity` je prohlížeč, ne review, a stojí to na dvou tvrdých podmínkách: komentář k řádku
/// commitu by potřeboval jiný klíč draftu a **pátou metodu v `ReviewPublishing`** (č. 1), a nálezy
/// jsou klíčované `headSha` (č. 5), takže by u staršího commitu ukazovaly na jiný kód. Zrušit to
/// jde jedním přidaným parametrem u `DiffView` — a na obrazovce by se to poznalo až tehdy, když by
/// někdo bublinu uviděl.
///
/// Testuje se ve **dvou vrstvách**, protože jedna sama by prošla naprázdno:
///
/// 1. **Co tab `DiffView`u předá** — všechny kanály, kterými se do diffu dostane psaní, musí být
///    prázdné.
/// 2. **Co z toho vyjde v řádcích** — z týchž hodnot se poskládají řádky diffu a nesmí mezi nimi
///    být bublina nálezu ani rozdělaný komentář. Ke každému tvrzení stojí **protipól se stejnými
///    daty v režimu review**, který bublinu vyrobit **musí**; bez něj by test procházel i tehdy,
///    kdyby se bubliny přestaly kreslit úplně.
@MainActor
@Suite("Diff commitu je jen ke čtení (#317)")
struct CommitDiffReadOnlyTests {
    // MARK: - Co tab předá

    @Test("Diff commitu nedostane nic, čím se dá psát")
    func handsNoWritingChannelsToTheDiff() throws {
        let view = try commitDiffView()
        let reading = view.reading(try Self.diff())

        #expect(reading.findings.isEmpty, "bubliny nálezů v tomhle tabu nejsou")
        #expect(reading.findingActions == nil, "nález se tu nedá odmítnout ani vrátit")
        #expect(reading.comments.isEmpty, "rozdělané komentáře patří do Změněných souborů")
        #expect(reading.threads.isEmpty, "vlákna konverzace se kotví na hlavu PR, ne na commit")
        #expect(reading.draft.canCompose == false, "do draftu se odsud psát nedá")
        #expect(reading.stepFinding == nil, "po nálezech se tu nechodí")
        #expect(reading.panelExpanded == nil, "panel s mým review se v tabu nekreslí")
        #expect(reading.missingThreads == 0)
        #expect(reading.highlighted == nil)
    }

    /// Panel se v tabu nekreslí, a **je to vlastnost tabu**, ne rozhodnutí view. Kdyby se
    /// `showsReviewPanel` u `Commitů` obrátilo, stál by vedle diffu staršího commitu panel
    /// s nálezy k jinému kódu.
    @Test("Tab Commity panel s nálezy nemá")
    func theCommitsTabHasNoPanel() {
        #expect(PullRequestTab.commits.showsReviewPanel == false)
    }

    // MARK: - Co z toho vyjde v řádcích

    /// Nález **na tomtéž souboru a řádku**, jaký diff commitu obsahuje. V review z něj bublina
    /// vznikne; tady nesmí.
    @Test("V řádcích diffu commitu není bublina nálezu")
    func buildsNoFindingBubbles() throws {
        let file = try Self.file()
        let reading = try commitDiffView().reading(try Self.diff())

        let readingRows = DiffRow.rows(
            of: file,
            findings: reading.findings,
            threads: reading.threads,
            comments: reading.comments
        )
        #expect(Self.findingBubbles(in: readingRows) == 0)

        // Protipól: tytéž řádky s nálezem bublinu **vyrobí**, takže tvrzení výš není o prázdnu.
        let reviewRows = DiffRow.rows(of: file, findings: Policy.groups(of: [Self.finding]))
        #expect(Self.findingBubbles(in: reviewRows) > 0, "bez nálezů by test výš prošel naprázdno")
    }

    @Test("V řádcích diffu commitu není rozdělaný komentář")
    func buildsNoDraftComments() throws {
        let file = try Self.file()
        let reading = try commitDiffView().reading(try Self.diff())

        let readingRows = DiffRow.rows(
            of: file,
            findings: reading.findings,
            threads: reading.threads,
            comments: reading.comments
        )
        #expect(Self.draftComments(in: readingRows) == 0)

        let reviewRows = DiffRow.rows(of: file, comments: [Self.comment])
        #expect(Self.draftComments(in: reviewRows) > 0, "bez komentáře by test výš prošel naprázdno")
    }

    /// A z třetí strany: **na žádném řádku se nenabídne akce, kterou by komentář vznikl.**
    /// Bubliny se dají odebrat i tak, že by tlačítko u řádku zůstalo — a tichý komentář založený
    /// omylem je horší než bublina, protože se odesílá.
    @Test("Žádný řádek diffu commitu nenabízí komentář ani poznámku")
    func offersNoCommentActionOnAnyLine() throws {
        let file = try Self.file()
        let anchors = Policy.commentAnchors(in: file)
        let lines = file.hunks.flatMap(\.lines)
        #expect(!lines.isEmpty)

        let reading = try commitDiffView().reading(try Self.diff())
        let readOnly = reading.draft.bound(to: file, anchors: anchors)
        for line in lines {
            #expect(readOnly.action(for: line) == nil, "řádek \(line.newNumber.map(String.init) ?? "?")")
        }

        // Protipól: tytéž řádky s draftem, do kterého se psát dá, akci nabídnou.
        let composing = DraftActions(canCompose: true).bound(to: file, anchors: anchors)
        #expect(lines.contains { composing.action(for: $0) != nil }, "jinak test výš nic nedokazuje")
    }

    // MARK: - Scéna

    private func commitDiffView() throws -> CommitDiffView {
        CommitDiffView(
            commit: Self.commit,
            state: .diff(try Self.diff()),
            position: "2 ze 7",
            url: Policy.commitURL(of: Self.commit.sha, in: Self.repo),
            expansion: DiffExpansionActions(state: { _ in FileExpansion() }, reveal: { _, _ in }, collapse: nil),
            folding: DiffFoldingActions(isFolded: { _ in false }, toggle: { _ in }, foldAll: { _ in }, unfoldAll: {}),
            layout: .constant(.unified),
            back: {},
            showFiles: {},
            retry: {}
        )
    }

    private static func findingBubbles(in rows: [DiffRow]) -> Int {
        rows.count { if case .finding = $0 { true } else { false } }
    }

    private static func draftComments(in rows: [DiffRow]) -> Int {
        rows.count { if case .draftComments = $0 { true } else { false } }
    }

    private static let repo = RepoID(owner: "cli", name: "cli")

    private static let commit = PullRequestCommit(
        sha: "5e2b1aa31f6c0a2a7f2f0a1b3c4d5e6f70819293",
        message: "feat: cache secrets for the lifetime of the request",
        authorName: "Odin Uv",
        authorLogin: "odinuv",
        avatarURL: nil,
        committedAt: Date(timeIntervalSince1970: 1_754_000_000),
        isMerge: false
    )

    /// Skutečný diff z fixture, ne vymyšlený: bubliny se kotví na čísla řádků z hunků, takže na
    /// upraveném textu by protipól nemusel vzniknout ze správného důvodu.
    private static func diff() throws -> Diff {
        DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))
    }

    private static func file() throws -> FileDiff {
        try #require(diff().files.first { $0.displayPath == "CLAUDE.md" })
    }

    private static let finding = makeFinding(file: "CLAUDE.md", line: 174, summary: "nález u řádku")

    private static let comment = ReviewDraftComment(
        path: "CLAUDE.md",
        anchor: DraftAnchor(line: 174, side: .right),
        body: "můj komentář",
        origin: .own
    )
}
