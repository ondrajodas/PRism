import Foundation
import Testing

@testable import PRism

/// Předfiltr dotazu na slévatelnost vlastních PR (#572) — kdo se do dotazu dostane a kdo ne.
///
/// **Rozhodování o mergi se tím nemění**: `Policy.mergeOffer` ani `isMergeReady` se nedotýkají.
/// Tahle funkce odpovídá na jinou otázku — **kdy** mají ta rozhodnutí data.
@Suite("Policy — koho se ptát na slévatelnost (#572)")
struct MergeReadinessProbeTests {
    private let mine: Set<String> = ["ondrajodas"]

    private func summary(
        _ text: String,
        author: String = "ondrajodas",
        state: PullRequestState = .open,
        updatedAt: TimeInterval = 100
    ) -> PullRequestSummary {
        let id = PRIdentifier(text)!
        return PullRequestSummary(
            id: id,
            title: "feat: něco",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: state
        )
    }

    /// Vlastní otevřený PR bez načtených dat — přesně ten případ, kvůli kterému #572 vzniklo.
    @Test("Vlastní otevřený PR bez dat se zeptá")
    func asksAboutAnOwnOpenPullRequest() {
        let pull = summary("ondrajodas/PRism#569")

        let probe = Policy.mergeReadinessProbe(of: [pull], mine: mine, isFresh: { _ in false })

        #expect(probe == [pull.id])
    }

    /// **Rozpracovaný taky.** Merge se na něm nenabízí (`mergeOffer` má `draftPullRequest` mezi
    /// překážkami), ale sekce `Větev` se kreslí a hranice je tady tatáž jako v `loadBranchStatus`
    /// — jedno pravidlo, ne dvě.
    @Test("Rozpracovaný PR se zeptá taky")
    func asksAboutADraft() {
        let draft = summary("ondrajodas/PRism#569", state: .draft)

        #expect(Policy.mergeReadinessProbe(of: [draft], mine: mine, isFresh: { _ in false }) == [draft.id])
    }

    /// **Mergnutý ani zavřený PR se neptá.** GitHub u něj vrací `mergeable: UNKNOWN` navždycky
    /// (změřeno na `PRism#470`), takže by se odpověď tik co tik zahazovala a ptalo by se donekonečna.
    @Test("Mergnutý ani zavřený PR se neptá")
    func skipsFinishedPullRequests() {
        let finished = [
            summary("ondrajodas/PRism#568", state: .merged),
            summary("ondrajodas/PRism#567", state: .closed),
        ]

        #expect(Policy.mergeReadinessProbe(of: finished, mine: mine, isFresh: { _ in false }).isEmpty)
    }

    /// **Cizí PR se neptá vůbec** — sekce `Větev` se na něm nekreslí a mergnout ho odsud nejde.
    @Test("Cizí PR se neptá")
    func skipsSomeoneElsesPullRequest() {
        let theirs = summary("cli/cli#14360", author: "odinuv")

        #expect(Policy.mergeReadinessProbe(of: [theirs], mine: mine, isFresh: { _ in false }).isEmpty)
    }

    /// **Prázdná množina loginů znamená nula dotazů**, ne dotaz na všechno: „nikdo nejsem“ je
    /// odpověď, ne povolení. Bez toho by zapomenutý parametr znamenal dotazy na cizí frontu.
    @Test("Bez loginu se neptá nikoho")
    func asksNobodyWithoutALogin() {
        let pull = summary("ondrajodas/PRism#569")

        #expect(Policy.mergeReadinessProbe(of: [pull], mine: [], isFresh: { _ in false }).isEmpty)
    }

    /// **Klidný tik je prázdno**, a na tom stojí „nula volání, dokud se nic nepohne“.
    @Test("Načtený PR se znovu neptá")
    func staysSilentWhenEverythingIsFresh() {
        let pull = summary("ondrajodas/PRism#569")

        #expect(Policy.mergeReadinessProbe(of: [pull], mine: mine, isFresh: { _ in true }).isEmpty)
    }

    /// Razítko je `updatedAt`, ne příznak „už jsme se ptali“ — a rozhoduje se **po jednom PR**.
    @Test("Ptá se jen na to, co zestaralo")
    func asksOnlyAboutWhatMoved() {
        let fresh = summary("ondrajodas/PRism#569", updatedAt: 100)
        let moved = summary("ondrajodas/PRism#568", updatedAt: 200)

        let probe = Policy.mergeReadinessProbe(
            of: [fresh, moved],
            mine: mine,
            isFresh: { $0.updatedAt == Date(timeIntervalSince1970: 100) }
        )

        #expect(probe == [moved.id])
    }

    /// **Strop je na velikost dokumentu, ne na počet volání**: co se nevejde, se zeptá příští tik,
    /// protože do map se zapíše jedině to, na co se ptalo. Uřízne se konec, tedy to nejstarší —
    /// seznam chodí seřazený od naposledy změněného.
    @Test("Strop uřízne konec seznamu")
    func stopsAtTheLimit() {
        let many = (1...40).map { summary("ondrajodas/PRism#\($0)") }

        let probe = Policy.mergeReadinessProbe(of: many, mine: mine, isFresh: { _ in false })

        #expect(probe.count == Policy.mergeReadinessProbeLimit)
        #expect(probe.first == many.first?.id)
        #expect(probe.last == many[Policy.mergeReadinessProbeLimit - 1].id)
    }

    /// Prázdný vstup je prázdný výstup — a prázdný seznam se **nespouští** (`query() { }` není
    /// platný dokument).
    @Test("Prázdný seznam nedá dotaz")
    func returnsNothingForAnEmptyList() {
        #expect(Policy.mergeReadinessProbe(of: [], mine: mine, isFresh: { _ in false }).isEmpty)
    }
}
