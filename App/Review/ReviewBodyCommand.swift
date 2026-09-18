import Foundation

/// Jak se `claude` volá kvůli **tělu** návrhu review (#521). Čisté funkce, žádné I/O.
///
/// **Osmá vyjmenovaná session** vedle revieweera, dotažení textu issue (#345), rozhovoru (#452),
/// slévání konfliktů (#467), agenta na vlastním PR (#510), briefu (#516) a anotací hunků (#524) —
/// a **třetí s prázdnou sadou**, po překladu nálezů a briefu.
enum ReviewBodyCommand {
    /// Sada nástrojů — **prázdná** (tvrdá podmínka č. 2).
    ///
    /// Je to tatáž hranice jako u briefu, jen nad jiným materiálem: session dostane **hotové
    /// nálezy** a **moje starší těla review** a napíše z nich odstavec. Kód nečte a číst ho nemá
    /// čím — a to je celý rozdíl mezi *formulováním* a *review logikou*. Kdyby si měla něco
    /// dohledat v kódu, patřila by ta úvaha do skillu, ne do aplikace.
    ///
    /// **Je to zároveň ta nejsilnější mez u session, která píše text odesílaný na GitHub.** Tělo
    /// review odchází pod mým jménem; session bez jediného nástroje se o repozitáři nemá jak
    /// dozvědět nic, takže v tom odstavci nemůže stát nic, co jí zadání neřeklo.
    ///
    /// **Konstanta, ne prázdný literál u volajícího** — jako u briefu: pojmenovaná konstanta je to,
    /// na co se dá ukázat testem (`SessionToolSetsTests`).
    static let allowedTools = ""

    /// Kolik má tělo času, než se session zabije.
    ///
    /// **Tři minuty, jako brief** (#516), a ze stejného důvodu: je to jeden odstavec, ale počet
    /// tokenů přemýšlení je napříč běhy rozkolísaný a spoluurčuje ho `effortLevel` z uživatelova
    /// nastavení, do kterého aplikace nevidí. Dvouminutový limit by nad tím nejdelším měřeným
    /// během briefu měl rezervu už jen dvojnásobnou.
    ///
    /// Nekonfiguruje se, jako u briefu, rozhovoru a konfliktů: knoflík, který si nikdo nenastaví,
    /// je jen řádek v nastavení.
    static let timeout: Duration = .seconds(180)

    /// Kolik znaků smí mít tělo. **Do promptu, ne do `Policy`** — tatáž úvaha jako u délky věty
    /// briefu (`BriefCommand.sentenceLimit`): uříznutý konec umí obrátit, co odstavec tvrdí,
    /// a u textu, který odchází na GitHub, by to byla ta nejdražší možná tichá vada. Délka je tedy
    /// **tvar odpovědi**, a ten umí ovlivnit jedině model; nikde se proto **nevynucuje**.
    static let bodyLimit = 700

    /// Argumenty jednoho běhu.
    ///
    /// `--output-format stream-json` (a s ním povinné `--verbose`) kvůli **ceně**: účet nese
    /// `result` event, a cena běhu je vidět v `Průběhu` vedle reviewerů i v `Dneska stálo`.
    ///
    /// **`--disallowedTools` je `ClaudeCommand.disallowedTools`**, tedy tatáž konstanta jako
    /// u ostatních sedmi session. Nad prázdnou sadou nezavírá nic, co by nebylo zavřené — a právě
    /// proto tady je: tvrdá podmínka „na GitHub se nic neposílá“ nemá stát na tom, že je povolený
    /// seznam zrovna prázdný.
    ///
    /// **`--strict-mcp-config`** ze stejného, změřeného důvodu jako u briefu: bez něj `claude`
    /// nabootuje MCP servery z uživatelova prostředí, ze kterých session s prázdnou sadou nemůže
    /// použít ani jeden, a jejich jména se stejně zapíšou do systémového promptu (~5 100 tokenů
    /// a ~8 s, změřeno u #516).
    ///
    /// **Model se nevynucuje, a je to opačné rozhodnutí než u briefu** (`BriefCommand.model`).
    /// Stojí na dvou věcech, ne na opatrnosti:
    ///
    /// 1. **Tohle se pouští jedině za doběhlým review**, tedy za během, který právě stál dolary —
    ///    ne podle kalendáře a bez kliknutí. Session, u které nepovšimnutá cena bolí nejvíc, je
    ///    brief; tahle je o řád vzácnější a účet už za sebou má.
    /// 2. **Napodobit hlas je to jediné, co má udělat.** Brief přeformuluje hotový text a haiku na
    ///    to stačilo, protože návěští `ADDED`/`BURNING`/`NEXT` nesla kus významu za něj. Tady není
    ///    žádná struktura, která by za model udržela styl — a tělo review odchází pod mým jménem.
    ///
    /// `claude` si tedy vybere sám, jako u překladu nálezů a dotažení textu issue.
    static func arguments(prompt: String) -> [String] {
        [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--strict-mcp-config",
            "--allowedTools", allowedTools,
            "--disallowedTools", ClaudeCommand.disallowedTools,
        ]
    }

    /// Prompt. **Zadání je formulace, ne rozhodování** — co se převzalo, co zůstalo sporné a jaký
    /// verdikt z toho plyne, rozhodla `Policy` (#520); tady se to jenom napíše mým hlasem.
    ///
    /// **Čtyři pravidla a každé zavírá jednu cestu, jak by tělo mohlo tvrdit víc, než co je
    /// v panelu:**
    ///
    /// - **Sporné se nesmí vydávat za vyřízené.** Je to ta jediná věta, na které celá skupina
    ///   #520–#521 stojí: když se část nálezů převezme sama a část ne, musí být poznat které —
    ///   a tělo review je první místo, kde se to dá zamluvit.
    /// - **Žádné nové nálezy.** Session kód nečte, takže věta o souboru, který v zadání není, je
    ///   z definice vymyšlená.
    /// - **Žádný verdikt v textu.** Verdikt je `event` v payloadu a zůstává **návrhem** (#114);
    ///   odstavec, který napíše „schvaluju“, by tvrdil rozhodnutí, které jsem neudělal.
    /// - **Vzorky jsou vzor stylu, ne obsahu.** Bez tohohle model přebírá z minulých review
    ///   konkrétní jména souborů a čísla PR — změřeno u briefu na jiném materiálu (#516).
    static func prompt(input: String) -> String {
        """
        Napiš **tělo review** pro pull request — jeden odstavec česky, mým hlasem. Níž je hotové \
        zadání: co reviewery našli, co si z toho aplikace vzala do rozdělaného review, co nechala \
        jako sporné, a **ukázky mých starších těl review** jako vzor stylu.

        Napiš **jen ten odstavec**. Nic jiného — bez nadpisu, bez odrážek, bez uvozovek kolem \
        celého textu a bez poznámky o tom, co jsi udělal.

        Pravidla:
        - Nejvýš **\(bodyLimit) znaků**.
        - Mluv **jen o tom, co je v zadání**. Nic si nedomýšlej, žádné další nálezy nepřidávej \
        a žádný soubor, který v zadání není, nejmenuj.
        - **Sporné nálezy nevydávej za vyřízené.** Když v zadání sporné jsou, řekni to — jednou \
        větou a bez výčtu, seznam je v panelu.
        - **Nepiš verdikt.** Žádné „schvaluju“, „vyžaduju změny“ ani „LGTM“: o verdiktu rozhoduje \
        člověk jedním kliknutím jinde.
        - Ukázky mých review jsou vzor **stylu** — délky věty, oslovení, míry zdvořilosti. \
        Neopisuj z nich jména souborů, čísla ani obsah.
        - Když ukázky nejsou, piš **neutrálně a stručně**; styl si nevymýšlej.

        Zadání:
        \(input)
        """
    }

    /// Co session napsala. `nil` = nenapsala nic použitelného.
    ///
    /// **Čte se defenzivně**, jako brief a odpověď překladu: je to volný text od modelu, ne formát,
    /// na kterém bychom se dohodli. Co se tedy snese:
    ///
    /// - **`` ``` ``-blok** kolem odpovědi — model ho přidává, i když se zakáže;
    /// - **prázdné řádky** na začátku a na konci.
    ///
    /// Co se naopak **nedělá**: text se **nezkracuje**. Strop je v promptu a uříznutý konec by
    /// u textu odesílaného na GitHub uměl obrátit, co odstavec tvrdí — viz `bodyLimit`.
    static func parse(_ text: String?) -> String? {
        guard let text else { return nil }
        let body = stripFences(text).trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    /// Zahodí ```-blok kolem odpovědi. Hledají se **celé řádky** s ohradníky, ne první výskyt: tři
    /// zpětné apostrofy uvnitř věty jsou text, ne ohrada — a v těle review stojí legitimně
    /// (`` `nil` ``, blok kódu v poznámce).
    ///
    /// **Doslovná kopie `BriefCommand.stripFences` to není a nemá být sdílená**: brief si řádky
    /// filtruje ze **seznamu vět**, kdežto tady je výsledkem **jeden odstavec** a záleží na tom,
    /// že se jeho vnitřní prázdné řádky zachovají.
    private static func stripFences(_ text: String) -> String {
        TextLines.content(text)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .joined(separator: "\n")
    }
}
