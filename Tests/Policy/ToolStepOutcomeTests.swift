import Foundation
import Testing

@testable import PRism

/// Rozhodnutí o tom, jak dopadl pokus o nástroj (#326), a co se z něj kreslí.
///
/// Je to čistá funkce, takže výčtem: čtyři vstupní kombinace `is_error` × `non_execution_kind`
/// a čtyři podoby značky na konci řádku. Podstatná je jedna hranice — **odmítnutí od chyby
/// nástroje** —, protože `grep` bez shody vrací chybu při každém běhu, a odznak `ODMÍTNUTO`
/// nad ním by z read-only režimu udělal poplach.
@Suite("Jak dopadl pokus o nástroj")
struct ToolStepOutcomeTests {
    // MARK: - Rozbor odpovědi

    @Test("Odpověď bez chyby je prošlý krok")
    func anAnswerWithoutAnErrorPasses() {
        let outcome = Policy.toolOutcome(isError: false, nonExecutionKind: nil, text: "diff --git …")

        #expect(outcome.kind == .passed)
        // Text úspěšné odpovědi je celý soubor nebo celý diff — do osy na disku nepatří.
        #expect(outcome.reason == nil)
    }

    @Test("Chyba bez non_execution_kind je chyba nástroje, ne odmítnutí")
    func anErrorWithoutMetaIsAToolFailure() {
        let outcome = Policy.toolOutcome(isError: true, nonExecutionKind: nil, text: "Exit code 1")

        #expect(outcome.kind == .failed)
        #expect(outcome.reason == "Exit code 1")
    }

    @Test("non_execution_kind znamená odmítnutí")
    func aNonExecutionKindMeansDenied() {
        let outcome = Policy.toolOutcome(
            isError: true,
            nonExecutionKind: "user-rejected",
            text: "Claude requested permissions to use gh, but you haven't granted it yet."
        )

        #expect(outcome.kind == .denied)
        #expect(outcome.reason?.hasPrefix("Claude requested") == true)
    }

    /// Hodnota, kterou nikdo neviděl, je pořád „nástroj neběžel“ — a právě to ten odznak tvrdí.
    /// Vymýšlet pro ni čtvrtý stav by byl dohad.
    @Test("Neznámý non_execution_kind je taky odmítnutí")
    func anUnknownNonExecutionKindIsStillDenied() {
        let outcome = Policy.toolOutcome(isError: false, nonExecutionKind: "canceled", text: nil)

        #expect(outcome.kind == .denied)
    }

    @Test("Odpověď bez textu důvod nemá")
    func aReasonlessAnswerCarriesNoReason() {
        #expect(Policy.toolOutcome(isError: true, nonExecutionKind: nil, text: nil).reason == nil)
        #expect(Policy.toolOutcome(isError: true, nonExecutionKind: nil, text: "  \n ").reason == nil)
    }

    /// Odpovědí `Read`u je celý soubor, odpovědí `Bash`e celý výstup — a osa se ukládá na disk
    /// a čte při každém startu.
    @Test("Dlouhá hláška se ostříhá a srazí na řádek")
    func shortensALongReason() throws {
        let text = "chyba na prvním řádku\n" + String(repeating: "x", count: 5000)

        let reason = try #require(Policy.toolOutcome(isError: true, nonExecutionKind: nil, text: text).reason)

        #expect(reason.count == Policy.toolReasonLimit + 1)
        #expect(reason.hasSuffix("…"))
        #expect(!reason.contains("\n"))
    }

    // MARK: - Kdo koho smí přepsat

    /// Pravidlo pro tři místa (parser, záchrana z `permission_denials`, osa), takže výčtem —
    /// dvě kopie by se rozešly, a už se to stalo: osa nepřepisovala nic, takže záchrana
    /// `failed` → `denied` do kreslené osy nedoputovala (Copilot na #394).
    @Test("Nezavřený krok bere cokoli, failed přepíše jedině odmítnutí")
    func decidesWhoMayReplaceWhom() {
        let passed = ToolAttempt.Outcome(kind: .passed, after: .milliseconds(120))
        let failed = ToolAttempt.Outcome(kind: .failed, reason: "Exit code 1")
        let denied = ToolAttempt.Outcome(kind: .denied)

        for next in [passed, failed, denied] {
            #expect(Policy.replacesToolOutcome(nil, with: next))
        }
        #expect(Policy.replacesToolOutcome(failed, with: denied))

        // Co se **nikdy** nepřepíše: krok, který odpověděl (odmítnutý nebyl), a krok, u kterého je
        // o odmítnutí rozhodnuto — druhá odpověď by z něj sundala odznak.
        #expect(!Policy.replacesToolOutcome(passed, with: denied))
        #expect(!Policy.replacesToolOutcome(passed, with: failed))
        #expect(!Policy.replacesToolOutcome(denied, with: passed))
        #expect(!Policy.replacesToolOutcome(denied, with: failed))
        #expect(!Policy.replacesToolOutcome(denied, with: denied))
        // Chyba nástroje se druhou chybou nepřepisuje: platí ta, která přišla, když se to stalo.
        #expect(!Policy.replacesToolOutcome(failed, with: failed))
        #expect(!Policy.replacesToolOutcome(failed, with: passed))
    }

    // MARK: - Značka v ose

    @Test("Krok bez odpovědi běží")
    func anUnansweredStepIsPending() {
        let tool = ToolAttempt(name: "Read", detail: "a.php", id: "t1")

        #expect(Policy.toolStepMark(of: tool) == .pending)
    }

    /// **Krok bez `id` se nekreslí jako běžící.** Tak vypadají osy uložené před #326: odpověď
    /// se jim neměla s čím spárovat, takže o nich nevíme nic — a `běží…` u každého kroku
    /// doběhlého review z minulého týdne je text, který tvrdí víc, než data unesou.
    @Test("Krok bez id nemá značku žádnou")
    func aStepWithoutAnIdentifierHasNoMark() {
        let tool = ToolAttempt(name: "Read", detail: "a.php")

        #expect(Policy.toolStepMark(of: tool) == ToolStepMark.none)
    }

    @Test("Prošlý krok ukáže trvání")
    func aPassedStepShowsItsDuration() {
        let tool = ToolAttempt(
            name: "Read",
            detail: "a.php",
            id: "t1",
            outcome: ToolAttempt.Outcome(kind: .passed, after: .milliseconds(200))
        )

        #expect(Policy.toolStepMark(of: tool) == .duration(.milliseconds(200)))
    }

    /// Chyba nástroje ukazuje trvání jako úspěch — nástroj běžel a odpověděl. Že odpověď byla
    /// chybová, je v nápovědě řádku; červený odznak má jen odmítnutí.
    @Test("Chyba nástroje ukáže trvání, ne odznak")
    func aFailedStepShowsItsDurationToo() {
        let tool = ToolAttempt(
            name: "Bash",
            detail: "grep x",
            id: "t1",
            outcome: ToolAttempt.Outcome(kind: .failed, after: .milliseconds(90), reason: "Exit code 1")
        )

        #expect(Policy.toolStepMark(of: tool) == .duration(.milliseconds(90)))
    }

    @Test("Odmítnutý krok má odznak")
    func aDeniedStepIsBadged() {
        let tool = ToolAttempt(
            name: "Bash",
            detail: "gh pr view",
            id: "t1",
            outcome: ToolAttempt.Outcome(kind: .denied, reason: "no permission")
        )

        #expect(Policy.toolStepMark(of: tool) == .denied)
    }

    /// Zavřený krok bez změřeného trvání — tak vypadá pokus zavřený záchranou
    /// z `permission_denials`, když by z něj vyšel `passed` (nemůže) nebo `failed`.
    @Test("Zavřený krok bez trvání značku nedostane")
    func aClosedStepWithoutADurationHasNoMark() {
        let tool = ToolAttempt(
            name: "Bash",
            detail: "grep x",
            id: "t1",
            outcome: ToolAttempt.Outcome(kind: .failed, reason: "Exit code 1")
        )

        #expect(Policy.toolStepMark(of: tool) == ToolStepMark.none)
    }
}
