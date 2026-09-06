import Foundation
import Testing

@testable import PRism

/// Jak se o běhu agenta mluví (#511) — výčet výsledku, věta, ocas, pilulka.
///
/// **Nejcennější tvrzení téhle sady je negativní**: že se v žádné z těch vět nemluví o testech.
/// Session je pustit nemůže (`Bash` v její sadě není) a aplikace je nad jejím výsledkem nepouští,
/// takže „testy zelené“ by bylo tvrzení, které data neunesou — a rozbilo by se to **potichu**,
/// protože výsledkem není chyba, ale věta, které se dá uvěřit.
@Suite("Policy — jak dopadl agent (#511)")
struct AgentRunReportTests {
    private let worktree = URL(filePath: "/tmp/cache/worktrees/ondrajodas/PRism/499-sync")

    private func branch(files: Int, skipped: String? = nil) -> RebasedBranch {
        RebasedBranch(
            worktree: worktree,
            headSha: "cccc3333",
            rebasedFrom: "aaaa1111",
            arriving: [RebasedCommit(sha: "cccc3333", title: "fix: address review feedback (#511)")],
            replayed: 1,
            origin: .agent,
            fix: AgentFixAnswer(
                files: (0..<files).map { "App/Policy/Soubor\($0).swift" },
                summary: "opraveno",
                skipped: skipped
            )
        )
    }

    // MARK: - Výčet výsledku

    /// **Vyčerpávající výčet stavů.** Co o agentovi nemluví, musí vyjít `nil` — jinak by se věta
    /// o agentovi objevila nad prací, kterou udělal rebase.
    @Test("Výsledek se čte jen ze stavů, které o agentovi mluví")
    func outcomeComesOnlyFromAgentStates() {
        let agentless: [BranchSyncState] = [
            .rebasing,
            .resolving(round: 1, files: ["a.swift"]),
            .fixing(items: 2, since: .distantPast),
            .pushing,
            .discarding,
            .pushed(replayed: 1),
            .alreadyInSync,
            .conflicted(files: ["a.swift"]),
            .unfinished(files: []),
            .unresolved(files: ["a.swift"], detail: nil),
            .failed(.leaseRejected),
        ]
        for state in agentless {
            #expect(Policy.agentRun(of: state) == nil, "stav \(state) o agentovi mluvit nemá")
        }

        // `rebased` **po rebase** taky ne — rozhoduje `origin`, ne to, že něco leží v cache.
        var afterRebase = branch(files: 1)
        afterRebase.origin = .rebase
        #expect(Policy.agentRun(of: .rebased(afterRebase)) == nil)

        #expect(Policy.agentRun(of: .rebased(branch(files: 2))) == .done(files: 2))
        #expect(
            Policy.agentRun(of: .rebased(branch(files: 2, skipped: "README nechávám tobě.")))
                == .partial(files: 2, skipped: "README nechávám tobě.")
        )
        #expect(Policy.agentRun(of: .fixedNothing(detail: "nemám co")) == .nothing(detail: "nemám co"))
        #expect(Policy.agentRun(of: .fixRejected(detail: "psal mimo")) == .discarded(detail: "psal mimo"))
    }

    /// „Částečně“ rozhoduje **jediná věc** — přiznání agenta. Ne počet souborů, ne délka účtu.
    @Test("Částečně rozhoduje přiznání, ne počet souborů")
    func partialIsDecidedByTheAdmission() {
        #expect(Policy.agentRun(files: 0, skipped: nil) == .done(files: 0))
        #expect(Policy.agentRun(files: 9, skipped: nil) == .done(files: 9))
        // Prázdné přiznání je totéž co žádné — prázdná věta v panelu vypadá jako díra.
        #expect(Policy.agentRun(files: 1, skipped: "") == .done(files: 1))
        #expect(Policy.agentRun(files: 1, skipped: "a") == .partial(files: 1, skipped: "a"))
    }

    // MARK: - Věta

    /// Tvar ze zadání: **co udělal, kde to leží, co se nestalo**.
    @Test("Věta o hotovém běhu nese strom i to, že se nic neodeslalo")
    func doneSentenceNamesTheWorktreeAndTheSilence() {
        let sentence = Policy.agentRunSentence(.done(files: 2), worktree: "499-sync")

        #expect(sentence == "Agent upravil 2 soubory ve stromě 499-sync · nic se neodeslalo.")
    }

    /// **Nula souborů nesmí být `0 souborů`**: účet od modelu může být nečitelný, přitom commit
    /// vznikl — a `git` je ta strana, která má pravdu.
    @Test("Nečitelný účet nedá větu o nule souborů")
    func zeroFilesGetsItsOwnSentence() {
        let sentence = Policy.agentRunSentence(.done(files: 0), worktree: "499-sync")

        #expect(sentence == "Agent připravil commit ve stromě 499-sync · nic se neodeslalo.")
        #expect(!sentence.contains("0"))
    }

    /// Neznámý strom se **nevymýšlí** — věta o něm mlčí a mluví o kopii repa.
    @Test("Bez jména stromu se o něm mlčí")
    func unknownWorktreeIsNotInvented() {
        let sentence = Policy.agentRunSentence(.done(files: 1), worktree: nil)

        #expect(sentence == "Agent upravil 1 soubor v kopii repa · nic se neodeslalo.")
    }

    /// Věta od modelu stojí **až na konci**: je to cizí text neznámé délky a nesmí rozdělit to,
    /// co ví aplikace.
    @Test("Přiznání agenta stojí na konci věty")
    func skippedSentenceComesLast() {
        let sentence = Policy.agentRunSentence(
            .partial(files: 2, skipped: "README nechávám tobě: text mění význam."),
            worktree: "499-sync"
        )

        #expect(sentence.hasSuffix("README nechávám tobě: text mění význam."))
        #expect(sentence.contains("nic se neodeslalo."))
    }

    /// Selhání a nepřijatý výsledek už větou **jsou** — druhá kolem nich by z jedné příčiny
    /// udělala dvě tvrzení.
    @Test("Selhání a zahození nesou svou vlastní větu")
    func failureKeepsItsOwnSentence() {
        #expect(Policy.agentRunSentence(.failed(detail: "Agent nedoběhl."), worktree: "x") == "Agent nedoběhl.")
        #expect(Policy.agentRunSentence(.discarded(detail: "Psal mimo."), worktree: "x") == "Psal mimo.")
    }

    /// **To hlavní negativní tvrzení celé sady.** V žádné větě o výsledku se nesmí objevit nic
    /// o testech: nikdo je nepustil.
    @Test("O testech se nikde netvrdí nic")
    func nothingClaimsTestsWereRun() {
        let outcomes: [AgentRunOutcome] = [
            .done(files: 2),
            .partial(files: 2, skipped: "README nechávám tobě."),
            .nothing(detail: "nemám co opravit"),
            .failed(detail: "Agent nedoběhl v limitu 15 minut."),
            .discarded(detail: "Agenta jsi zrušil."),
        ]
        for outcome in outcomes {
            let texts = [
                Policy.agentRunSentence(outcome, worktree: "499-sync"),
                Policy.agentRunHeadline(outcome),
                Policy.agentRunNextStep(outcome),
            ]
            for text in texts {
                let lower = text.lowercased()
                #expect(!lower.contains("test"), "věta mluví o testech: \(text)")
                #expect(!lower.contains("zelen"), "věta tvrdí zeleno: \(text)")
            }
        }
    }

    // MARK: - Živý ocas

    /// Strop je **v `Policy`**, ne ve view: ocas je paměť, která roste s během.
    @Test("Ocas se usekne na čtyřech krocích")
    func tailStaysCapped() {
        var tail: [String] = []
        for index in 0..<12 { tail = Policy.agentTail(tail, appending: "krok \(index)") }

        #expect(tail.count == Policy.agentTailLength)
        #expect(tail == ["krok 8", "krok 9", "krok 10", "krok 11"])
    }

    /// **Bezprostřední opakování se nezdvojuje** — čtyři stejné řádky nejsou ocas.
    /// Opakování dál v ocase se ale nechává být: je to pravdivý postup.
    @Test("Opakovaný krok se nepřidá dvakrát za sebou")
    func repeatedStepIsNotDuplicated() {
        var tail = Policy.agentTail([], appending: "čte A")
        tail = Policy.agentTail(tail, appending: "čte A")

        #expect(tail == ["čte A"])

        tail = Policy.agentTail(tail, appending: "čte B")
        tail = Policy.agentTail(tail, appending: "čte A")
        #expect(tail == ["čte A", "čte B", "čte A"])
    }

    /// Prázdný krok se **nezapisuje**: prázdný řádek v panelu vypadá jako díra.
    @Test("Prázdný krok ocas nemění")
    func emptyStepChangesNothing() {
        #expect(Policy.agentTail(["čte A"], appending: "") == ["čte A"])
    }

    // MARK: - Pilulka v řádku

    /// **Na cizím PR nikdy** — agent se tam nespouští, takže by pilulka byla stav, který nemá jak
    /// vzniknout.
    @Test("Na cizím PR se pilulka nekreslí")
    func foreignRowHasNoPill() {
        let running = BranchSyncState.fixing(items: 2, since: Date(timeIntervalSince1970: 0))

        #expect(
            Policy.agentRowPill(
                sync: running,
                ownership: .theirs,
                now: Date(timeIntervalSince1970: 300)
            ) == nil
        )
    }

    @Test("Běžící agent i čekající push mají v řádku svou pilulku")
    func rowPillCoversBothStates() {
        let now = Date(timeIntervalSince1970: 300)

        #expect(
            Policy.agentRowPill(
                sync: .fixing(items: 2, since: Date(timeIntervalSince1970: 0)),
                ownership: .mine,
                now: now
            ) == .running(elapsed: "5 min")
        )
        #expect(
            Policy.agentRowPill(sync: .rebased(branch(files: 1)), ownership: .mine, now: now)
                == .awaitingPush
        )
        // Doběhlý rebase pilulku nedostane: `push čeká na tebe` nad ním by mluvilo o agentovi,
        // který tam nebyl.
        var afterRebase = branch(files: 1)
        afterRebase.origin = .rebase
        #expect(Policy.agentRowPill(sync: .rebased(afterRebase), ownership: .mine, now: now) == nil)
        #expect(Policy.agentRowPill(sync: nil, ownership: .mine, now: now) == nil)
    }

    /// **Pod minutu se nepíše `0 min`** — nula by tvrdila, že se nic neděje, zrovna když se
    /// začalo. Posunuté hodiny (záporný rozdíl) spadnou do téže odpovědi.
    @Test("Uplynulý čas se počítá v minutách a nulu nepíše")
    func elapsedNeverSaysZero() {
        let start = Date(timeIntervalSince1970: 1000)

        #expect(Policy.agentElapsed(since: start, now: start) == "<1 min")
        #expect(Policy.agentElapsed(since: start, now: start.addingTimeInterval(59)) == "<1 min")
        #expect(Policy.agentElapsed(since: start, now: start.addingTimeInterval(60)) == "1 min")
        #expect(Policy.agentElapsed(since: start, now: start.addingTimeInterval(899)) == "14 min")
        #expect(Policy.agentElapsed(since: start, now: start.addingTimeInterval(-60)) == "<1 min")
    }

    @Test("Text pilulky říká, co se děje")
    func pillTextIsReadable() {
        #expect(AgentRowPill.running(elapsed: "4 min").text == "agent běží · 4 min")
        #expect(AgentRowPill.awaitingPush.text == "push čeká na tebe")
    }

    // MARK: - Commit agenta jako řádek

    /// **Co v datech není, zůstává `nil`.** Ten commit na GitHubu není, takže účet ani obrázek
    /// autora nemá odkud vzít — a vymyšlený by v hlavičce vypadal jako přečtený.
    @Test("Commit agenta nepředstírá účet na GitHubu")
    func agentCommitRowInventsNothing() {
        let row = Policy.agentCommitRow(
            AgentFixCommit(
                sha: "cccc3333",
                message: "fix: address review feedback (#511)",
                authorName: "Ondřej Jodas",
                committedAt: Date(timeIntervalSince1970: 1000),
                diff: "diff --git a/A b/A\n"
            )
        )

        #expect(row.sha == "cccc3333")
        #expect(row.authorName == "Ondřej Jodas")
        #expect(row.authorLogin == nil)
        #expect(row.avatarURL == nil)
        #expect(!row.isMerge)
        #expect(row.subject == "fix: address review feedback (#511)")
    }
}
