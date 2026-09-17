import Foundation

/// Jak se `claude` volá kvůli briefu na domově (#516). Čisté funkce, žádné I/O.
///
/// **Šestá vyjmenovaná session** vedle revieweera, dotažení textu issue (#345), rozhovoru (#452),
/// slévání konfliktů (#467) a agenta na vlastním PR (#510) — a **druhá s prázdnou sadou**, po
/// překladu nálezů.
enum BriefCommand {
    /// Sada nástrojů — **prázdná**, jako u překladu nálezů (tvrdá podmínka č. 2).
    ///
    /// Brief je **transformace textu**: dostane hotový stav aplikace (`Policy.briefInput`)
    /// a přeformuluje ho do tří vět. Session, která nemůže nic spustit, nemůže ani omylem sáhnout
    /// na repozitář, na disk ani na `gh` — a tím je rozdíl mezi *čtením nahlas* a *review logikou*
    /// vidět z argumentů, ne jen z promptu.
    ///
    /// **Konstanta, ne prázdný literál u volajícího.** Prázdný řetězec v seznamu argumentů se dá
    /// přehlédnout i přepsat; pojmenovaná konstanta je to, na co se dá ukázat testem
    /// (`SessionToolSetsTests`).
    static let allowedTools = ""

    /// Kolik má brief času, než se session zabije.
    ///
    /// **Dvě minuty**, jako překlad nálezů, a ze stejného důvodu: je to jeden krátký odstavec
    /// bez jediného nástroje, takže delší běh znamená, že se něco zaseklo — ne že se přemýšlí.
    /// Nekonfiguruje se, jako u rozhovoru a u konfliktů: knoflík, který si nikdo nenastaví, je
    /// jen řádek v nastavení.
    static let timeout: Duration = .seconds(120)

    /// Argumenty jednoho běhu.
    ///
    /// `--output-format stream-json` (a s ním povinné `--verbose`) kvůli **ceně**: účet nese
    /// `result` event a session, která stojí peníze a neukáže kolik, je vada. Překlad nálezů
    /// bufferovaný zůstává, protože jeho cena se počítá do běhu review, kdežto brief je běh sám
    /// za sebe.
    ///
    /// **`--disallowedTools` je `ClaudeCommand.disallowedTools`**, tedy tatáž konstanta jako
    /// u ostatních pěti session. Nad prázdnou sadou nezavírá nic, co by nebylo zavřené — a právě
    /// proto tady je: tvrdá podmínka „na GitHub se nic neposílá“ nemá stát na tom, že je povolený
    /// seznam zrovna prázdný.
    ///
    /// **Model se nevolí.** Je to mechanické přeformulování hotového textu, jako u překladu nálezů
    /// a dotažení textu issue — ne úvaha nad cizím kódem, kvůli které si rozhovor a review berou
    /// model z konfigurace.
    static func arguments(prompt: String) -> [String] {
        [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--allowedTools", allowedTools,
            "--disallowedTools", ClaudeCommand.disallowedTools,
        ]
    }

    /// Prompt. **Zadání je formulace, ne rozhodování** — co je na tahu a co blokuje, je už
    /// rozhodnuté v `Policy.briefInput`; tady se to jenom čte nahlas.
    ///
    /// Věta „nic si nedomýšlej“ v něm je, ale **není to ta mez, na které to stojí** — tou je
    /// prázdná sada nástrojů. Model, který si vymyslí PR, vymyslí ho i s tou větou; rozdíl je
    /// v tom, že se o skutečném repozitáři nemá jak dozvědět nic.
    static func prompt(input: String) -> String {
        """
        Jsi hlas aplikace PRism, která hlídá pull requesty k review. Níž je **hotový stav \
        aplikace**. Napiš z něj **přesně tři věty česky** pro člověka, který se právě podíval na \
        obrazovku: co se stalo, co hoří a co je první na řadě. Piš v druhé osobě jednotného \
        čísla, bez uvozovek, bez odrážek a bez nadpisu — jen tři věty za sebou v jednom odstavci.

        Mluv **jenom o tom, co je ve vstupu**. Nic si nedomýšlej, nic nedopočítávej a o ničem, co \
        ve vstupu není, nepiš vůbec — ani že to chybí. Čísla opisuj přesně. Repozitáře a čísla \
        pull requestů piš tak, jak jsou (`keboola/job-queue #727`).

        Stav aplikace:
        \(input)
        """
    }

    /// Co session napsala. `nil` = nenapsala nic použitelného.
    ///
    /// **Čte se defenzivně**, jako účet agenta a odpověď překladu: je to volný text od modelu, ne
    /// formát, na kterém bychom se dohodli. Může přijít obalený v ```-blocích a může přijít
    /// prázdný — a prázdný text je **porucha**, ne prázdný brief, protože blok s prázdným místem
    /// je k nerozeznání od vypnutého.
    ///
    /// Řádky se slévají do jednoho odstavce (`TextLines`, ne `split`), protože blok kreslí odstavec
    /// — a odřádkování od modelu by v něm bylo bílé místo tam, kde ho návrh nemá.
    static func parse(_ text: String?) -> String? {
        guard let text else { return nil }
        let unfenced = stripFences(text)
        let paragraph = TextLines.nonEmpty(unfenced)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return paragraph.isEmpty ? nil : paragraph
    }

    /// Zahodí ```-blok kolem odpovědi. Hledají se **celé řádky** s ohradníky, ne první výskyt:
    /// tři zpětné apostrofy uvnitř věty jsou text, ne ohrada.
    private static func stripFences(_ text: String) -> String {
        TextLines.content(text)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .joined(separator: "\n")
    }
}
