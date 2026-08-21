import Foundation
import Testing

@testable import PRism

/// Otevřel reviewer kód? (#383)
///
/// Sada je postavená tak, aby padla na **obojí**: na falešné čisto (běh, který kód neotevřel,
/// vyjde jako průkazný) i na falešný poplach (běh, který ho otevřel, nebo o kterém záznam nic
/// neříká, vyjde jako nepřečtený). Druhá polovina je ta cennější — falešné poplachy se přestanou
/// čítat stejně jako falešné čisto, jen se to pozná později.
///
/// **Osy jsou opsané ze skutečných uložených běhů** z cache hlavní instance (`security-review`
/// z 18.–20. 8.), jen s cestami převedenými na veřejné repo: záznamy z firemních PR do repa
/// nepatří, takže se z nich bere **tvar**, ne obsah. Co v nich stálo doopravdy: `Read` zadání
/// (`<strom>.md`), `Read` v `~/.claude/projects/…/tool-results/*.txt` a sedm `Bash` s `git diff`
/// uvnitř stromu — dohromady jedenáct pokusů a ani jeden otevřený soubor z kódu.
@Suite("Policy.codeReading")
struct CodeReadingTests {
    private let worktree = URL(fileURLWithPath: "/cache/worktrees/cli/cli/42-aaaa1111")

    /// Osa z pokusů o nástroje. `started` na začátku je tam schválně — v uložených osách je taky
    /// a nesmí se počítat jako pokus.
    private func timeline(
        _ attempts: [ToolAttempt],
        worktree: URL?,
        dropped: Int = 0
    ) -> StoredTimeline {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var entries = [ReviewerTimeline.Entry(id: 0, at: start, kind: .started)]
        for (index, attempt) in attempts.enumerated() {
            entries.append(
                ReviewerTimeline.Entry(
                    id: index + 1,
                    at: start.addingTimeInterval(Double(index + 1)),
                    kind: .tool(attempt)
                )
            )
        }
        return StoredTimeline(worktree: worktree, entries: entries, dropped: dropped)
    }

    private func run(_ attempts: [ToolAttempt], dropped: Int = 0) -> StoredReviewRun {
        runIn(worktree, attempts, dropped: dropped)
    }

    /// Běh nad **jiným** stromem, než je ten výchozí — `nil` znamená osu, která strom nezná.
    private func runIn(_ worktree: URL?, _ attempts: [ToolAttempt], dropped: Int = 0) -> StoredReviewRun {
        makeStoredRun(timeline: timeline(attempts, worktree: worktree, dropped: dropped))
    }

    private func read(_ path: String, outcome: ToolAttempt.Outcome? = nil) -> ToolAttempt {
        ToolAttempt(name: "Read", detail: path, id: "toolu_\(path.hashValue)", outcome: outcome)
    }

    private func bash(_ command: String) -> ToolAttempt {
        ToolAttempt(name: "Bash", detail: command)
    }

    // MARK: - Přečtený kód

    @Test("Otevřený soubor z pracovní kopie je doklad čtení")
    func readingAFileInsideTheWorktreeCounts() {
        let run = run([read("/cache/worktrees/cli/cli/42-aaaa1111/src/Job/Runner.php")])

        #expect(Policy.codeReading(of: run) == .read)
    }

    @Test("Doklad přebíjí nejistotu")
    func evidenceOutweighsUncertainty() {
        // Kdo otevřel soubor, ten kód čeká — `Grep` vedle toho už nic nezpochybňuje.
        let run = run([
            ToolAttempt(name: "Grep", detail: "StateTerminalException"),
            read("/cache/worktrees/cli/cli/42-aaaa1111/src/Job/Runner.php"),
        ])

        #expect(Policy.codeReading(of: run) == .read)
    }

    @Test("Starší osa bez odpovědí na nástroje se bere jako přečtená")
    func anOlderTimelineWithoutOutcomesStillCounts() {
        // Odpovědi na `tool_use` se ze streamu čtou teprve od #326, takže `outcome == nil` je
        // v uložených osách běžný stav — kdyby znamenal „nepřečteno“, vyšly by všechny starší
        // záznamy jako nepřečtené naráz.
        let run = run([read("/cache/worktrees/cli/cli/42-aaaa1111/src/Job/Runner.php", outcome: nil)])

        #expect(Policy.codeReading(of: run) == .read)
    }

    @Test("Lomítko v cestě se dopočítá, i když strom končí na lomítku")
    func toleratesATrailingSlashOnTheWorktree() {
        let run = runIn(
            URL(fileURLWithPath: "/cache/worktrees/cli/cli/42-aaaa1111", isDirectory: true),
            [read("/cache/worktrees/cli/cli/42-aaaa1111/src/Job/Runner.php")]
        )

        #expect(Policy.codeReading(of: run) == .read)
    }

    // MARK: - Nepřečtený kód

    /// **Nejcennější test téhle sady** — je to doslova ten běh, kvůli kterému #383 vzniklo.
    @Test("Běh, který si přečetl jen zadání a diff, kód neotevřel")
    func aRunThatOnlyReadTheIntentAndTheDiffIsUnread() {
        let run = run([
            ToolAttempt(name: "Skill", detail: "security-review"),
            read("/cache/worktrees/cli/cli/42-aaaa1111.md"),
            read("/Users/x/.claude/projects/-cache-worktrees-cli-cli-42/tool-results/bhesufeti.txt"),
            bash("cd \"/cache/worktrees/cli/cli/42-aaaa1111\" && git diff bbbb2222...HEAD --stat"),
            bash("cd \"/cache/worktrees/cli/cli/42-aaaa1111\" && git diff bbbb2222...HEAD -- composer.json"),
            ToolAttempt(name: "ReportFindings", detail: nil),
        ])

        #expect(Policy.codeReading(of: run) == .unread)
    }

    /// Zadání pro reviewera (#120) leží jako `<strom>.md`, tedy **soubor vedle** pracovní kopie
    /// se stejnou předponou. Bez oddělovače v předponě by ho `hasPrefix` spolkl jako soubor v ní —
    /// a přečte si ho i ten běh, který se do kódu vůbec nepodíval.
    @Test("Soubor se zadáním vedle stromu se za kód nepočítá")
    func theIntentFileNextToTheWorktreeIsNotCode() {
        let run = run([read("/cache/worktrees/cli/cli/42-aaaa1111.md")])

        #expect(Policy.codeReading(of: run) == .unread)
    }

    @Test("Čtení mimo pracovní kopii se za kód nepočítá")
    func readingOutsideTheWorktreeIsNotCode() {
        let run = run([
            read("/Users/x/.claude/projects/-cache-worktrees-cli-cli-42/session.jsonl"),
            read("/Users/x/.claude/skills/security-review/SKILL.md"),
        ])

        #expect(Policy.codeReading(of: run) == .unread)
    }

    @Test("Odmítnutý ani chybou skončený pokus není čtení")
    func aDeniedOrFailedAttemptIsNotReading() {
        let path = "/cache/worktrees/cli/cli/42-aaaa1111/src/Job/Runner.php"
        let denied = run([read(path, outcome: .init(kind: .denied, reason: "permission denied"))])
        let failed = run([read(path, outcome: .init(kind: .failed, reason: "File does not exist"))])

        #expect(Policy.codeReading(of: denied) == .unread)
        #expect(Policy.codeReading(of: failed) == .unread)
    }

    @Test("Glob sám kód nečte — hledá jména")
    func globAloneIsNotReading() {
        // Vzor je navíc relativní (`src/**/*.php`), takže by se z něj tvrzení o čtení nedalo
        // postavit ani při dobré vůli.
        let run = run([ToolAttempt(name: "Glob", detail: "src/**/*.php")])

        #expect(Policy.codeReading(of: run) == .unread)
    }

    // MARK: - Nedá se soudit

    @Test("Grep zpochybní tvrzení o nečtení, protože nese vzor, ne cestu")
    func grepMakesTheAnswerUnknown() {
        // `ToolAttempt.detailKeys` má `pattern` před `path`, takže ze `StateTerminalException`
        // nejde poznat, jestli se hledalo ve stromě, nebo v cizím transkriptu. Ověřeno na
        // uložených bězích — `Grep` v nich nese pokaždé vzor.
        let run = run([bash("git diff"), ToolAttempt(name: "Grep", detail: "StateTerminalException")])

        #expect(Policy.codeReading(of: run) == .unknown)
    }

    @Test("Podagent zpochybní tvrzení o nečtení")
    func anAgentMakesTheAnswerUnknown() {
        // `Agent` nemá detail vůbec a jestli se jeho pokusy objeví v proudu rodiče, se
        // z uložených běhů dokázat nedá.
        #expect(Policy.codeReading(of: run([ToolAttempt(name: "Agent", detail: nil)])) == .unknown)
        #expect(Policy.codeReading(of: run([ToolAttempt(name: "Task", detail: nil)])) == .unknown)
    }

    @Test("Bez osy se netvrdí nic")
    func withoutATimelineNothingIsClaimed() {
        // Osa se ukládá od #203, takže starších záznamů je na disku plno — 15 ze 40 měřených.
        #expect(Policy.codeReading(of: makeStoredRun(timeline: nil)) == .unknown)
    }

    @Test("Bez pracovního stromu se netvrdí nic")
    func withoutAWorktreeNothingIsClaimed() {
        let run = runIn(nil, [read("/cache/worktrees/cli/cli/42-aaaa1111/src/Job/Runner.php")])

        #expect(Policy.codeReading(of: run) == .unknown)
    }

    @Test("Zkrácená osa netvrdí nic — ořezal se právě začátek")
    func aTruncatedTimelineClaimsNothing() {
        // Ořezává se začátek, tedy zrovna ta část, ve které se čte nejvíc. A takový běh má za
        // sebou 300+ událostí, což je spíš doklad práce než jejího chybění.
        let run = run([bash("git diff")], dropped: 12)

        #expect(Policy.codeReading(of: run) == .unknown)
    }

    @Test("Osa bez jediného pokusu netvrdí nic")
    func aTimelineWithoutToolsClaimsNothing() {
        #expect(Policy.codeReading(of: run([])) == .unknown)
    }
}
