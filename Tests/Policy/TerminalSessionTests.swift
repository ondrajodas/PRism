import Foundation
import Testing

@testable import PRism

/// Živá session v Terminálu (#453) — co se pustí, kde a kdy se to vůbec nabídne.
///
/// Je to `Policy`, takže výčtem a bez mockování: rozhodnutí „tlačítko se nekreslí“ se za běhu
/// nedá zjistit jinak než tím, že se na obrazovku někdo podívá.
@Suite("Terminál — živá session (#453)")
struct TerminalSessionTests {
    // MARK: - Kdy se tlačítko vůbec nabídne

    /// **Nejcennější tvrzení téhle suity**: dráha bez session tlačítko nedostane. Zašedlé by
    /// u dráhy, která teprve čeká na slot, slibovalo něco, co přijde samo.
    @Test("Bez session_id se tlačítko nekreslí")
    func withoutASessionThereIsNoButton() {
        #expect(Policy.terminalSession(of: lane(session: nil, worktree: nil)) == nil)
        #expect(Policy.terminalSession(of: lane(session: nil, worktree: URL(filePath: "/tmp/w"))) == nil)
    }

    /// Pracovní strom je podmínka **stejně jako `session_id`**: bez adresáře se nedá poskládat
    /// příkaz, který by session doopravdy navázal — `claude --resume` hledá vlákno podle adresáře,
    /// ve kterém se spustí. Otevřelo by se okno, ve kterém `claude` řekne, že takové vlákno nezná.
    @Test("Bez pracovního stromu se tlačítko taky nekreslí")
    func withoutAWorktreeThereIsNoButtonEither() {
        #expect(Policy.terminalSession(of: lane(session: "abc-123", worktree: nil)) == nil)
    }

    /// Stavy, ve kterých dráha vzniká **bez osy** (`queued`, `notStarted`, `missingProgress`),
    /// session ani strom nemají — je to tatáž množina, ve které se nekreslí `Ukázat session`.
    @Test("Dráhy bez osy tlačítko nedostanou v žádném ze svých stavů")
    func lanesWithoutATimelineNeverOfferIt() {
        let lanes = Policy.lanes(
            of: [],
            skills: ["security-review"],
            record: nil,
            running: ["php-review"]
        )
        #expect(lanes.count == 2)
        for lane in lanes {
            #expect(Policy.terminalSession(of: lane) == nil)
        }
    }

    @Test("S obojím se session složí")
    func withBothTheSessionIsBuilt() throws {
        let session = try #require(
            Policy.terminalSession(of: lane(session: "abc-123", worktree: URL(filePath: "/tmp/w")))
        )

        #expect(session.directory == URL(filePath: "/tmp/w"))
        #expect(session.command == "claude --resume abc-123")
    }

    // MARK: - Týž příkaz, jaký se kopíruje

    /// Celý slib #453 je „**tentýž** příkaz, jen rovnou puštěný“. Kdyby se ty dva texty rozešly,
    /// pozná se to jedině tím, že jeden z nich nefunguje — proto je skládá jedna funkce a proto
    /// se to tvrdí tady.
    @Test("Terminál pouští týž příkaz, jaký kopíruje ⧉")
    func theTerminalRunsWhatTheCopyButtonCopies() throws {
        let session = try #require(
            Policy.terminalSession(of: lane(session: "8c1f-42", worktree: URL(filePath: "/tmp/w")))
        )

        #expect(session.command == Policy.resumeCommand(sessionID: "8c1f-42"))
    }

    @Test("Příkaz je claude --resume s identifikátorem")
    func theResumeCommandIsSpelledOut() {
        #expect(Policy.resumeCommand(sessionID: "8c1f-42") == "claude --resume 8c1f-42")
    }

    // MARK: - Řádka pro shell

    /// **`&&`, ne `;`**: strom umí zmizet (úklid cache), a `claude --resume` spuštěný místo něj
    /// v domovském adresáři by odpověděl větou o session, ne o adresáři.
    @Test("Řádka nejdřív přejde do stromu, a jen když se to povede")
    func theShellLineEntersTheWorktreeFirst() {
        let session = TerminalSession(
            directory: URL(filePath: "/Users/o/Library/Application Support/PRism/worktrees/o/r/6-abc"),
            command: "claude --resume abc-123"
        )

        #expect(
            session.shellLine
                == "cd '/Users/o/Library/Application Support/PRism/worktrees/o/r/6-abc' "
                + "&& claude --resume abc-123"
        )
    }

    /// Cesta s apostrofem uzávorkování rozbije **potichu** — příkaz se pustí rozstřelený a pozná
    /// se to teprve v okně terminálu. Ověřeno i spuštěním (`cd` do složky `it's here` projde).
    @Test("Apostrof v cestě uzávorkování nerozbije")
    func anApostropheInThePathSurvives() {
        let session = TerminalSession(
            directory: URL(filePath: "/tmp/it's here"),
            command: "claude --resume abc"
        )

        #expect(session.shellLine == "cd '/tmp/it'\\''s here' && claude --resume abc")
    }

    /// Mezera v cestě je běžná (`Application Support`), takže neuzávorkovaná cesta by z jednoho
    /// argumentu udělala dva a `cd` by spadlo na „too many arguments“.
    @Test("Cesta jde do shellu vždycky uzávorkovaná")
    func thePathIsAlwaysQuoted() {
        #expect(ShellQuoting.quoted("/tmp/a b") == "'/tmp/a b'")
        #expect(ShellQuoting.quoted(URL(filePath: "/tmp/a b")) == "'/tmp/a b'")
    }

    private func lane(session: String?, worktree: URL?) -> ReviewerLane {
        ReviewerLane(
            skill: "security-review",
            state: .finished,
            phases: [],
            lastTool: nil,
            finishedAt: nil,
            reportedFindings: nil,
            usage: nil,
            sessionID: session,
            worktree: worktree,
            droppedEntries: 0,
            loadedSkill: nil,
            intentGap: nil,
            entries: [],
            isConfigured: true
        )
    }
}
