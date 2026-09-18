import Foundation
import Testing

@testable import PRism

/// Osmá session ze strany příkazu (#521) — co odejde do CLI a jak se čte, co přijde zpátky.
///
/// Sadu povolení tvrdí `SessionToolSetsTests` (na jednom místě pro všech osm session), tady zbývá
/// **prompt** a **parser**: tedy to, čím se tahle session od briefu a od anotací doopravdy liší.
@Suite("Tělo návrhu review — příkaz (#521)")
struct ReviewBodyCommandTests {
    // MARK: - Argumenty

    /// **Model se nevynucuje**, na rozdíl od briefu — a je to zapsané rozhodnutí, ne opomenutí
    /// (`ReviewBodyCommand.arguments`). Bez tohohle tvrzení by se `--model haiku` dalo přidat
    /// „pro konzistenci s briefem“ a nikdo by si nevšiml, že tím zlevnil zrovna to napodobování
    /// hlasu, kvůli kterému session je.
    @Test("Argumenty model nevybírají")
    func doesNotPickAModel() {
        #expect(!ReviewBodyCommand.arguments(prompt: "x").contains("--model"))
    }

    /// Streamem, protože **cena** je v `result` eventu. Bufferovaná session by stála peníze
    /// a neukázala kolik — a tahle je v `Průběhu` vedle reviewerů právě proto, aby to bylo vidět.
    @Test("Argumenty jdou streamem, aby byla vidět cena")
    func streamsForTheCost() {
        let arguments = ReviewBodyCommand.arguments(prompt: "x")

        #expect(arguments.contains("--output-format"))
        #expect(arguments.contains("stream-json"))
        // `--verbose` je u `stream-json` v `claude -p` **povinné**, jinak CLI skončí chybou.
        #expect(arguments.contains("--verbose"))
        #expect(arguments.contains("--strict-mcp-config"))
    }

    // MARK: - Prompt

    /// **Materiál je v promptu doslova.** Kdyby se cestou osekával nebo přeskládával, byl by
    /// v aplikaci druhý zdroj pravdy o tom, co session ví — a `Policy.reviewBodyInput` by tvrdila
    /// něco jiného než to, co doopravdy odešlo.
    @Test("Prompt nese materiál doslova")
    func carriesTheMaterial() {
        let prompt = ReviewBodyCommand.prompt(input: "Převzaté nálezy (1):\n- php-review: nález")

        #expect(prompt.contains("Převzaté nálezy (1):\n- php-review: nález"))
    }

    /// **Čtyři pravidla a každé zavírá jednu cestu, jak by tělo mohlo tvrdit víc, než co je
    /// v panelu.** Tvrdí se tady, protože prompt je u session bez nástrojů **jediná** věc, která
    /// tvar odpovědi ovlivňuje — smazat z něj větu o sporných nálezech je změna chování, která
    /// v žádném jiném testu nespadne.
    @Test("Prompt zakazuje verdikt, nové nálezy i zamluvení sporných")
    func forbidsTheFourThings() {
        let prompt = ReviewBodyCommand.prompt(input: "cokoli")

        #expect(prompt.contains("Sporné nálezy nevydávej za vyřízené"))
        #expect(prompt.contains("Nepiš verdikt"))
        #expect(prompt.contains("Nic si nedomýšlej"))
        #expect(prompt.contains("vzor **stylu**"))
        // Strop jde do promptu **jako číslo**, ne jako slovo: bez něj by se o délce nerozhodovalo
        // nikde (`bodyLimit` se schválně nikde nevynucuje).
        #expect(prompt.contains("\(ReviewBodyCommand.bodyLimit) znaků"))
    }

    // MARK: - Parser

    @Test("Obyčejný odstavec projde, jen bez okrajových prázdných řádků")
    func readsAParagraph() {
        #expect(ReviewBodyCommand.parse("\n  Díky, tři věci k opravě.  \n") == "Díky, tři věci k opravě.")
    }

    /// Model přidává ```-blok, i když se zakáže — u briefu změřeno, tady platí totéž.
    @Test("```-blok kolem odpovědi se zahodí")
    func stripsFences() {
        let text = """
        ```
        Díky za PR.
        ```
        """

        #expect(ReviewBodyCommand.parse(text) == "Díky za PR.")
    }

    /// **Tři zpětné apostrofy uvnitř věty jsou text, ne ohrada** — a v těle review stojí
    /// legitimně. Hledají se proto celé řádky.
    @Test("Ohradníky uprostřed řádku se neberou jako ohrada")
    func keepsInlineBackticks() {
        let text = "Pozor na ``` v komentáři, rozbíjí to výpis."

        #expect(ReviewBodyCommand.parse(text) == text)
    }

    /// **Vnitřní prázdné řádky se zachovají**, na rozdíl od briefu, který si řádky filtruje ze
    /// seznamu vět. Tady je výsledkem odstavec (klidně dva) a odsazení je součást textu, který
    /// odejde na GitHub.
    @Test("Prázdný řádek uvnitř odstavce zůstane")
    func keepsInnerBlankLines() {
        #expect(ReviewBodyCommand.parse("První.\n\nDruhý.") == "První.\n\nDruhý.")
    }

    /// **Nezkracuje se.** Strop je v promptu a uříznutý konec by u textu odesílaného na GitHub
    /// uměl obrátit, co odstavec tvrdí — je to tatáž úvaha jako u délky věty briefu.
    @Test("Delší odpověď se nezkracuje")
    func doesNotTruncate() {
        let long = String(repeating: "á", count: ReviewBodyCommand.bodyLimit * 2)

        #expect(ReviewBodyCommand.parse(long)?.count == ReviewBodyCommand.bodyLimit * 2)
    }

    /// **Prázdno je porucha, ne prázdné tělo.** Doběhlá session bez textu končí jako selhání
    /// (`ClaudeReviewBodyWriter`), aby pruh nad panelem nemlčel nad prázdným composerem.
    @Test("Prázdná a chybějící odpověď je nil")
    func emptyIsNil() {
        #expect(ReviewBodyCommand.parse(nil) == nil)
        #expect(ReviewBodyCommand.parse("") == nil)
        #expect(ReviewBodyCommand.parse("   \n\n ") == nil)
        #expect(ReviewBodyCommand.parse("```\n```") == nil)
    }
}
