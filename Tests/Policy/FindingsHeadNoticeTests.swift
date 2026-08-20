import Foundation
import Testing

@testable import PRism

/// Proti kterému kódu nálezy v panelu platí (#392).
///
/// **Tohle je tvrdá podmínka č. 5 přepsaná do věty**, takže se testuje vyčerpávajícím výčtem po
/// tabech: panel je od #392 i v `Commitech`, a tam může vedle nálezů stát jiný commit, než na
/// kterém vznikly.
@Suite("Proti čemu nálezy platí")
struct FindingsHeadNoticeTests {
    private static let head = "e8d4a60f1c2d3e4f5061728394a5b6c7d8e9f012"
    private static let older = "5e2b1aa31f6c0a2a7f2f0a1b3c4d5e6f70819293"

    /// **Ve třech tabech s panelem se věta nekreslí** — vedle panelu tam stojí hlava PR, takže není
    /// co vysvětlovat a věta by byla šum na každé obrazovce.
    @Test(
        "Mimo Commity se věta nekreslí",
        arguments: [PullRequestTab.overview, .filesChanged, .conversation]
    )
    func silentOutsideCommits(tab: PullRequestTab) {
        #expect(Policy.findingsHeadNotice(
            tab: tab,
            findingsHead: Self.head,
            openCommit: Self.older,
            hasFindings: true
        ) == .none)
    }

    /// Nad seznamem commitů (žádný rozkliknutý) nálezy platí — stačí klidná věta.
    @Test("Nad seznamem commitů je klidná věta")
    func calmSentenceAboveTheList() {
        #expect(Policy.findingsHeadNotice(
            tab: .commits,
            findingsHead: Self.head,
            openCommit: nil,
            hasFindings: true
        ) == .head(Self.head))
    }

    /// **Ten nejcennější případ**: u rozkliknutého staršího commitu nálezy o kódu na obrazovce
    /// nemluví, takže je z věty výstraha a karty se ztlumí.
    @Test("U staršího commitu je výstraha a karty se ztlumí")
    func warnsAtAnOlderCommit() {
        let notice = Policy.findingsHeadNotice(
            tab: .commits,
            findingsHead: Self.head,
            openCommit: Self.older,
            hasFindings: true
        )

        #expect(notice == .mismatch(head: Self.head, commit: Self.older))
        #expect(notice.dimsFindings)
    }

    /// U rozkliknuté **hlavy** nálezy platí, takže výstraha ne — a hlavně **se karty nesmí ztlumit**:
    /// ztlumení by tvrdilo, že s nálezy něco není v pořádku.
    @Test("U rozkliknuté hlavy je věta, ne výstraha")
    func calmAtTheHeadCommit() {
        let notice = Policy.findingsHeadNotice(
            tab: .commits,
            findingsHead: Self.head,
            openCommit: Self.head,
            hasFindings: true
        )

        #expect(notice == .head(Self.head))
        #expect(!notice.dimsFindings)
    }

    /// **Bez nálezů není co kvalifikovat.** Proč je prázdno, vysvětluje `FindingsEmptyReason` — věta
    /// o hlavě by nad prázdným seznamem tvrdila, že tam nějaké nálezy jsou.
    @Test("Bez nálezů se nekreslí nic, ani u staršího commitu")
    func silentWithoutFindings() {
        #expect(Policy.findingsHeadNotice(
            tab: .commits,
            findingsHead: Self.head,
            openCommit: Self.older,
            hasFindings: false
        ) == .none)
    }

    /// Bez uloženého záznamu není hlava, proti které by nálezy platily — a bez ní se nic tvrdit nedá.
    @Test("Bez záznamu se nekreslí nic")
    func silentWithoutARecord() {
        #expect(Policy.findingsHeadNotice(
            tab: .commits,
            findingsHead: nil,
            openCommit: Self.older,
            hasFindings: true
        ) == .none)
    }

    /// Ztlumení je **jen u neshody**, u ostatních dvou případů nikdy — vyčerpávající výčet, protože
    /// na tom stojí, jestli nálezy vypadají jako platné.
    @Test("Ztlumení je výhradně u neshody")
    func onlyMismatchDims() {
        #expect(!Policy.FindingsHeadNotice.none.dimsFindings)
        #expect(!Policy.FindingsHeadNotice.head(Self.head).dimsFindings)
        #expect(Policy.FindingsHeadNotice.mismatch(head: Self.head, commit: Self.older).dimsFindings)
    }

    /// **V `Kontrolách`, `Nálezech` a `Průběhu` panel není** (`showsReviewPanel == false`), takže se
    /// tam věta nemá kde nakreslit — ale funkce o tom stejně nic tvrdit nesmí: rozhoduje tab, ve
    /// kterém panel **je**.
    @Test(
        "V tabech bez panelu se věta nekreslí",
        arguments: [PullRequestTab.checks, .findings, .progress]
    )
    func silentInPanelFreeTabs(tab: PullRequestTab) {
        #expect(!tab.showsReviewPanel)
        #expect(Policy.findingsHeadNotice(
            tab: tab,
            findingsHead: Self.head,
            openCommit: Self.older,
            hasFindings: true
        ) == .none)
    }
}
