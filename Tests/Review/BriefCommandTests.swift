import Foundation
import Testing

@testable import PRism

/// Jak se volá šestá session a jak se čte její odpověď (#516).
///
/// Sada povolení se tvrdí **na jednom místě** (`SessionToolSetsTests`) jako u ostatních pěti
/// session; tady je zbytek kontraktu s CLI a čtení volného textu od modelu.
@Suite("Brief — příkaz a čtení odpovědi (#516)")
struct BriefCommandTests {
    /// Streamem kvůli **ceně**: účet nese `result` event a session, která stojí peníze a neukáže
    /// kolik, je vada. `--verbose` k tomu být **musí** — bez něj `claude` v print režimu
    /// `stream-json` odmítne.
    @Test("Běh jde streamem, aby se dala přečíst cena")
    func streamsForTheCost() {
        let arguments = BriefCommand.arguments(prompt: "x")

        #expect(arguments.contains("--output-format"))
        #expect(arguments.contains("stream-json"))
        #expect(arguments.contains("--verbose"))
    }

    /// **Model se nevolí**, jako u překladu nálezů: je to mechanické přeformulování hotového
    /// textu, ne úvaha nad cizím kódem. Kdyby se volil, byl by to čtvrtý knoflík o tom, kterým
    /// modelem aplikace mluví.
    @Test("Model se nevolí")
    func picksNoModel() {
        #expect(!BriefCommand.arguments(prompt: "x").contains("--model"))
    }

    /// Vstup jde do promptu **celý a doslova** — brief se skládá z toho, co `Policy` rozhodla, ne
    /// z toho, co si model domyslí.
    @Test("Prompt nese vstup doslova")
    func carriesTheInputVerbatim() {
        let input = "Pruh Rozhodnout (1):\n- keboola/job-queue #727, review: 1 nález"

        #expect(BriefCommand.prompt(input: input).contains(input))
    }

    /// Odpověď se slévá do **jednoho odstavce**: blok kreslí odstavec, takže odřádkování od modelu
    /// by v něm bylo bílé místo, které návrh nemá.
    @Test("Odpověď se slévá do jednoho odstavce")
    func joinsLinesIntoOneParagraph() {
        #expect(BriefCommand.parse("První věta.\n\nDruhá věta.\nTřetí.") == "První věta. Druhá věta. Třetí.")
    }

    /// Řádky se dělí `TextLines` (#295), takže `CRLF` od modelu **nezůstane v textu** — a taky se
    /// mezi věty nevloží prázdný řádek navíc.
    @Test("CRLF v odpovědi se přečte jako konec řádku")
    func splitsOnCRLF() {
        #expect(BriefCommand.parse("První.\r\nDruhá.") == "První. Druhá.")
    }

    /// Ohradníky kolem odpovědi se zahodí — model je přidává, i když se o ně neřekne.
    @Test("```-blok kolem odpovědi se zahodí")
    func stripsCodeFences() {
        #expect(BriefCommand.parse("```\nTři věty.\n```") == "Tři věty.")
        #expect(BriefCommand.parse("```markdown\nTři věty.\n```") == "Tři věty.")
    }

    /// **Prázdná odpověď je porucha, ne prázdný brief.** Blok s prázdným místem je k nerozeznání
    /// od vypnutého, takže se musí dát poznat, že se to nepovedlo.
    @Test("Prázdná odpověď není brief")
    func treatsEmptyAsMissing() {
        #expect(BriefCommand.parse(nil) == nil)
        #expect(BriefCommand.parse("") == nil)
        #expect(BriefCommand.parse("   \n\n  ") == nil)
        #expect(BriefCommand.parse("```\n```") == nil)
    }
}
