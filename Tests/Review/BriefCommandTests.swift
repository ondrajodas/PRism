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

    /// **Model se vynucuje, a je to výjimka z úmluvy u ostatních session** (#516, po změření
    /// ceny). Bez něj vybere `claude` ten uživatelův — u nás `opus-5` — a měřený studený běh stál
    /// **$0,46**, ačkoli je to přeformulování dvou a půl kilobajtu textu. Drží se to testem,
    /// protože právě tenhle argument je celý rozdíl mezi ~2,50 $ a ~14 $ měsíčně.
    @Test("Model je vynucený a je to ten levný")
    func pinsTheCheapModel() {
        let arguments = BriefCommand.arguments(prompt: "x")

        #expect(arguments.contains("--model"))
        #expect(arguments.contains(BriefCommand.model))
        #expect(BriefCommand.model == "haiku")
    }

    /// **MCP servery z uživatelova prostředí se nebootují.** Session má prázdnou sadu nástrojů,
    /// takže z nich nemůže použít ani jeden — ale jejich jména se bez tohohle argumentu stejně
    /// zapíšou do systémového promptu a zaplatí se. Měřeno: 47 676 → 42 555 tokenů bootu a o ~8 s
    /// kratší běh.
    @Test("MCP servery z prostředí se nebootují")
    func bootsWithoutForeignMCPServers() {
        #expect(BriefCommand.arguments(prompt: "x").contains("--strict-mcp-config"))
    }

    /// Vstup jde do promptu **celý a doslova** — brief se skládá z toho, co `Policy` rozhodla, ne
    /// z toho, co si model domyslí.
    @Test("Prompt nese vstup doslova")
    func carriesTheInputVerbatim() {
        let input = "Pruh Rozhodnout (1):\n- keboola/job-queue #727, review: 1 nález"

        #expect(BriefCommand.prompt(input: input).contains(input))
    }

    /// **Zadání jmenuje tři otázky a všechny tři klíče**, jinak by se odpověď nedala rozebrat —
    /// prompt a `parse` jsou dvě půlky jednoho protokolu a rozejít se nesmí.
    @Test("Prompt jmenuje všechny tři klíče")
    func namesEveryKey() {
        let prompt = BriefCommand.prompt(input: "x")

        for part in BriefPart.allCases {
            #expect(prompt.contains(part.key), "v zadání chybí klíč \(part.key)")
        }
    }

    /// **Vynechání řádku musí být v zadání dovolené.** Je to ta mez proti „tvrdí víc, než data
    /// unesou“: struktura, která si vynutí větu na každou otázku, si o vymyšlenou větu říká.
    @Test("Zadání dovoluje řádek vynechat a zakazuje seznamy")
    func allowsSilenceAndBansLists() {
        let prompt = BriefCommand.prompt(input: "x")

        #expect(prompt.contains("vynech celý"))
        #expect(prompt.contains("Seznamy čísel nevypisuj"))
        #expect(prompt.contains("\(BriefCommand.sentenceLimit) znaků"))
    }

    /// Odpověď se rozebere na **pojmenované řádky**, ne na odstavec (#516, po proklikání).
    @Test("Odpověď se rozebere na tři pojmenované řádky")
    func readsThreeLabelledLines() {
        let answer = """
            ADDED: Doběhlo ti čisté review na ondrajodas/PRism #584.
            BURNING: Hoří keboola/job-queue #727 se 4 nálezy.
            NEXT: Vezmi si ondrajodas/PRism #584.
            """

        #expect(BriefCommand.parse(answer) == [
            BriefLine(part: .added, text: "Doběhlo ti čisté review na ondrajodas/PRism #584."),
            BriefLine(part: .burning, text: "Hoří keboola/job-queue #727 se 4 nálezy."),
            BriefLine(part: .next, text: "Vezmi si ondrajodas/PRism #584."),
        ])
    }

    /// **Jeden řádek je legitimní odpověď, ne porucha.** Otázka, na kterou ve vstupu odpověď není,
    /// se má vynechat — je to celý smysl toho, že brief drží pole a ne trojici polí.
    @Test("Vynechaná otázka není porucha")
    func acceptsFewerLines() {
        #expect(BriefCommand.parse("BURNING: Hoří #727.") == [
            BriefLine(part: .burning, text: "Hoří #727.")
        ])
    }

    /// **Pořadí je naše, ne modelovo.** Návěští mají v okně stát pořád stejně, jinak se blok při
    /// každém shrnutí přeskládá a nedá se přelétnout okem.
    @Test("Pořadí řádků je naše, ne modelovo")
    func keepsOurOrder() {
        let parsed = BriefCommand.parse("NEXT: Třetí.\nADDED: První.\nBURNING: Druhá.")

        #expect(parsed?.map(\.part) == [.added, .burning, .next])
    }

    /// Markdownovou ozdobu okolo návěští model přidává, i když se zakáže — a řádek kvůli
    /// hvězdičce propadnout nesmí.
    @Test("Ozdoba kolem návěští se odečte")
    func stripsMarkdownAroundLabels() {
        #expect(BriefCommand.parse("**ADDED:** Věta.") == [BriefLine(part: .added, text: "Věta.")])
        #expect(BriefCommand.parse("- **ADDED**: Věta.") == [BriefLine(part: .added, text: "Věta.")])
        #expect(BriefCommand.parse("added: Věta.") == [BriefLine(part: .added, text: "Věta.")])
    }

    /// **Za klíčem musí stát dvojtečka.** Bez téhle podmínky by se návěštím stala každá věta, která
    /// tím slovem náhodou začíná — a její první slovo by z briefu zmizelo.
    @Test("Věta, která klíčem jen začíná, není návěští")
    func needsTheColon() {
        #expect(BriefCommand.parse("NEXT week bude klid.") == nil)
    }

    /// Próza kolem odpovědi je šum, ne věta briefu: pustit ji dál by znamenalo nakreslit ji pod
    /// cizí návěští.
    @Test("Řádky bez návěští se zahodí")
    func dropsUnlabelledProse() {
        let answer = """
            Jasně, tady je shrnutí:
            ADDED: Věta.
            Doufám, že pomůže.
            """

        #expect(BriefCommand.parse(answer) == [BriefLine(part: .added, text: "Věta.")])
    }

    /// **Týž klíč dvakrát: platí první.** Druhá odpověď na tutéž otázku je oprava, kterou nikdo
    /// nepotvrdil, a tiše vybrat tu pozdější je hádání.
    @Test("Při dvou stejných návěštích platí první")
    func keepsTheFirstOfADuplicate() {
        #expect(BriefCommand.parse("ADDED: První.\nADDED: Druhá.") == [
            BriefLine(part: .added, text: "První.")
        ])
    }

    /// Řádky se dělí `TextLines` (#295), takže `CRLF` od modelu **nesloučí dva řádky v jeden**.
    @Test("CRLF v odpovědi se přečte jako konec řádku")
    func splitsOnCRLF() {
        #expect(BriefCommand.parse("ADDED: První.\r\nBURNING: Druhá.") == [
            BriefLine(part: .added, text: "První."),
            BriefLine(part: .burning, text: "Druhá."),
        ])
    }

    /// Ohradníky kolem odpovědi se zahodí — model je přidává, i když se o ně neřekne.
    @Test("```-blok kolem odpovědi se zahodí")
    func stripsCodeFences() {
        #expect(BriefCommand.parse("```\nADDED: Věta.\n```") == [BriefLine(part: .added, text: "Věta.")])
        #expect(BriefCommand.parse("```markdown\nADDED: Věta.\n```") == [
            BriefLine(part: .added, text: "Věta.")
        ])
    }

    /// **Prázdná odpověď je porucha, ne prázdný brief.** Blok s prázdným místem je k nerozeznání
    /// od vypnutého, takže se musí dát poznat, že se to nepovedlo. Patří sem i odpověď, ve které
    /// **žádný řádek nenesl návěští** — próza bez klíčů se nedá nakreslit pod ta správná.
    @Test("Prázdná odpověď a próza bez návěští nejsou brief")
    func treatsEmptyAsMissing() {
        #expect(BriefCommand.parse(nil) == nil)
        #expect(BriefCommand.parse("") == nil)
        #expect(BriefCommand.parse("   \n\n  ") == nil)
        #expect(BriefCommand.parse("```\n```") == nil)
        #expect(BriefCommand.parse("Tři věty o stavu aplikace.") == nil)
        #expect(BriefCommand.parse("ADDED:") == nil)
    }

    /// **Limit je delší než dvě minuty, a je to změřené.** Haiku na tenhle prompt spotřebuje 3,5
    /// až 6 tisíc tokenů přemýšlení a doběhne za ~60 s; dvouminutový limit by nad tím měl jen
    /// dvojnásobnou rezervu a počet tokenů přemýšlení je napříč běhy rozkolísaný.
    @Test("Limit má nad změřeným během rezervu")
    func leavesRoomOverTheMeasuredRun() {
        #expect(BriefCommand.timeout == .seconds(180))
    }
}
