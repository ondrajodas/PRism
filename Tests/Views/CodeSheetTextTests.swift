import Foundation
import Testing

@testable import PRism

/// Texty hlavičky a patičky sheetu s kódem (#417).
///
/// Věty, které tvrdí něco o datech, se dají vyčerpat testem jen tehdy, když nejsou schované v těle
/// view — a tady jsou dvě, které se dají pokazit potichu: **doběhlému jobu se log nesmí říkat
/// snímek** (varovalo by to před něčím, co se nemůže stát, a takové věty se pak přehlíží i tam, kde
/// platí) a **věta o zalomených řádcích u textu, který se celý vejde**.
@Suite("Texty sheetu s kódem")
struct CodeSheetTextTests {
    /// 21:09:46, aby se dala porovnat celá věta včetně času.
    private let moment = Date(timeIntervalSince1970: 1_787_000_000)

    // MARK: - Hlavička hunku

    /// Text končí zlomem, takže se u něj zároveň ověřuje, že **poslední prázdný řádek není řádek**
    /// (`Policy.codeSheetLines`) — jinak by hlavička u textu z jiného zdroje než `Policy.code(of:)`
    /// tvrdila o řádek víc, než kolik je v sheetu vidět.
    @Test("Hlavička hunku říká, že je to nová verze bez znaků změny")
    func describesTheHunk() {
        let code = "    return $row['value'] ?? '';\n    }\n"

        #expect(CodeSheetText.hunkTitle(path: "src/Vault/SecretClient.php")
            == "Hunk — src/Vault/SecretClient.php")
        #expect(CodeSheetText.hunkNote(code: code)
            == "nová verze, 2 řádky — bez znaků změny a bez čísel řádků, přesně tak, jak se zkopíruje")
    }

    /// Skloňování, protože jazyk aplikace je čeština — `1 řádků` praští do očí hned.
    @Test("Počet řádků se skloňuje", arguments: [(1, "1 řádek"), (3, "3 řádky"), (12, "12 řádků")])
    func inflectsTheLineCount(lines: Int, expected: String) {
        let code = Array(repeating: "x", count: lines).joined(separator: "\n")

        #expect(CodeSheetText.hunkNote(code: code).hasPrefix("nová verze, \(expected) —"))
    }

    /// Krátká sha z návrhu je tady `subject`, tedy to, co se v diffu zrovna kreslí — a když chybí,
    /// zbyde hlavička hunku, ne prázdná odrážka.
    @Test("Slug hunku snese chybějící půlku")
    func composesTheHunkSlug() {
        #expect(CodeSheetText.hunkSlug(header: "@@ -78,9 +78,21 @@", subject: "keboola/vault#412")
            == "@@ -78,9 +78,21 @@ · keboola/vault#412")
        #expect(CodeSheetText.hunkSlug(header: "", subject: "9c1de02") == "9c1de02")
        #expect(CodeSheetText.hunkSlug(header: "@@ -1,2 +1,2 @@", subject: "") == "@@ -1,2 +1,2 @@")
    }

    // MARK: - Hlavička logu

    /// Na **konkrétní oddělovač tisíců se netestuje** (tatáž úmluva jako v `PluralTests`): čeština
    /// používá úzkou nedělitelnou mezeru a její přesná podoba je věc locale, ne tohohle typu.
    @Test("Slug logu nese počet řádků, velikost a PR")
    func composesTheLogSlug() {
        let log = JobLog(text: "", lineCount: 24_918, byteCount: 2_700_000, fetchedAt: moment)

        let slug = CodeSheetText.logSlug(log, subject: "keboola/vault#412")

        #expect(slug.hasPrefix("job.log · "))
        #expect(slug.hasSuffix(" řádků · 2,7 MB · keboola/vault#412"))
        #expect(!slug.contains("24918"), "počet řádků se neskupinuje: \(slug)")
    }

    /// **Doběhlému jobu se log neříká snímek** — a je to to jediné, co se mezi těmi dvěma stavy
    /// mění.
    @Test("Doběhlý job má log celý, běžící snímek")
    func tellsTheTwoStatesApart() {
        let finished = CodeSheetText.logNote(outcome: .failed, duration: 134, at: moment)
        let running = CodeSheetText.logNote(outcome: .running, duration: nil, at: moment)

        #expect(finished.contains("log je celý, nic už k němu nepřibude."))
        #expect(!finished.contains("Snímek"))
        #expect(running.contains("job pořád běží"))
        #expect(!running.contains("log je celý"))
    }

    /// Z čeho ten text je, platí v obou stavech — a je to jediné místo, kde se to říká: ANSI dole,
    /// timestampy nahoře, žádný ořez na 6 000 řádků jako v okýnku v tabu.
    @Test("Obě podoby říkají, z čeho ten text je")
    func alwaysSaysWhatTheTextIs() {
        for outcome in [PullRequestCheck.Outcome.failed, .passed, .running, .cancelled, .skipped] {
            let note = CodeSheetText.logNote(outcome: outcome, duration: 12, at: moment)
            #expect(note.hasSuffix(CodeSheetText.logMaterial), "\(outcome): \(note)")
            #expect(note.contains("bez ANSI: s timestampy a bez ořezu na"))
            #expect(!note.contains("6000"), "strop se neskupinuje: \(note)")
        }
    }

    /// Sloveso je z výčtu, ne z `ChecksText.detail` — tam je to výčet za jménem jobu, tady začátek
    /// věty o něm.
    @Test("Každý stav má vlastní sloveso")
    func hasAVerbForEveryOutcome() {
        #expect(CodeSheetText.logNote(outcome: .failed, duration: nil, at: nil).hasPrefix("Job selhal —"))
        #expect(CodeSheetText.logNote(outcome: .passed, duration: nil, at: nil).hasPrefix("Job prošel —"))
        #expect(CodeSheetText.logNote(outcome: .cancelled, duration: nil, at: nil).hasPrefix("Job byl zrušen —"))
    }

    /// **Nic se netvrdí, když se to neví** (`gh` časy nemusí dodat): bez okamžiku a bez délky běhu
    /// zbyde věta bez nich, ne s nulou nebo s pomlčkou na místě čísla.
    @Test("Bez času a bez délky běhu věta zůstane celá")
    func staysWholeWithoutTimes() {
        let note = CodeSheetText.logNote(outcome: .failed, duration: nil, at: nil)

        #expect(note.hasPrefix("Job selhal — log je celý"))
        #expect(!note.contains("po nil"))
        #expect(!note.contains("  "))
    }

    @Test("Doběhlý job s délkou běhu ji vypíše")
    func mentionsHowLongItRan() {
        let note = CodeSheetText.logNote(outcome: .failed, duration: 134, at: moment)

        // Délka běhu se sází `RunUsageText`em, tedy stejně jako v seznamu checků — a ten dává
        // nedělitelné mezery, takže se porovnává s ním, ne s opsaným literálem.
        #expect(note.contains("po \(RunUsageText.duration(.seconds(134)))"))
    }

    // MARK: - Patička

    /// **Bez téhle věty vypadá zalomený řádek jako dva.** `nil` u textu, který se celý vejde — věta
    /// o zalomení tam tvrdí něco, co se nestalo.
    @Test("Věta o zalomených řádcích se skloňuje a u nuly nevznikne")
    func describesTheOverflow() {
        #expect(CodeSheetText.overflow(nil) == nil)
        #expect(CodeSheetText.overflow(CodeSheetOverflow(wrapped: 1, total: 21))
            == "1 řádek z 21 se nevešel na šířku")
        #expect(CodeSheetText.overflow(CodeSheetOverflow(wrapped: 3, total: 21))
            == "3 řádky z 21 se nevešly na šířku")
        #expect(CodeSheetText.overflow(CodeSheetOverflow(wrapped: 7, total: 21))
            == "7 řádků z 21 se nevešlo na šířku")
    }
}
