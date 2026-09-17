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

    /// Model. **Vynucený, a je to výjimka z úmluvy „model se nevolí“** (#516, po změření ceny).
    ///
    /// Ostatní session model nevynucují (`IntentTextCommand`, překlad nálezů) — `claude` si vybere
    /// sám a u nás to je `opus-5`. U briefu se to změřilo a vyšlo **$0,46 za tři věty**, tedy
    /// ~14 $ měsíčně při `firstTickOfDay`. Měření ukázalo, **kde ty peníze jsou**, a je to
    /// nečekané: vstup z `Policy.briefInput` je ~1 000 tokenů, tedy **2 % účtu**. Zbytek je
    /// **boot session** — ~42 až 48 tisíc tokenů systémového promptu a jmen nástrojů, které CLI
    /// zapíše do hodinové cache. Cena briefu je tedy prakticky `boot × cena zápisu do cache`, a ta
    /// se řídí **jedině modelem**.
    ///
    /// Proto `haiku`, a stojí to na třech věcech:
    ///
    /// 1. **Je to přeformulování hotového textu**, ne úvaha nad cizím kódem — tatáž třída jako
    ///    překlad nálezů. Model tu nic neposuzuje; co je na tahu a co hoří, rozhodla `Policy`.
    /// 2. **Je to jediná session, která se pouští bez kliknutí a podle kalendáře**, takže je to ta,
    ///    u které nepovšimnutá cena bolí nejvíc.
    /// 3. **Změřeno: ~$0,09 místo ~$0,46 za studený běh** — tedy ~2,50 $ místo ~14 $ měsíčně.
    ///
    /// **Co se tím platí, a je to změřené, ne odhadnuté**: haiku píše sušeji a bez souvislostí,
    /// které opus dá („a po novém commitu nálezy zastaraly“). Strukturu z #516 to snese, protože
    /// návěští nese kus významu, který dřív musela nést próza. Čísla i oba výstupy vedle sebe jsou
    /// v [`docs/testovani.md`](docs/testovani.md).
    ///
    /// **Konfigurovaný model se sem nebere schválně.** `GlobalConfig` odpovídá na otázku „se
    /// kterým modelem se **kontroluje kód**“; brief žádný kód nečte, takže by to byla odpověď na
    /// jinou otázku.
    static let model = "haiku"

    /// Kolik má brief času, než se session zabije.
    ///
    /// **Tři minuty, ne dvě jako překlad nálezů** — a je to změřené, ne opatrnost. Haiku na tenhle
    /// prompt spotřebuje 3,5 až 6 tisíc tokenů přemýšlení a doběhne za **30 až 64 s**; dvouminutový
    /// limit by nad tím nejdelším měřeným během měl rezervu už jen dvojnásobnou a počet tokenů
    /// přemýšlení je napříč běhy **rozkolísaný** (měřeno 3 564 až 5 924 na tomtéž vstupu). Kolik přemýšlení bude, navíc
    /// spoluurčuje `effortLevel` z **uživatelova** nastavení, do kterého aplikace nevidí.
    ///
    /// Nekonfiguruje se, jako u rozhovoru a u konfliktů: knoflík, který si nikdo nenastaví, je
    /// jen řádek v nastavení.
    static let timeout: Duration = .seconds(180)

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
    /// **`--strict-mcp-config` je tady kvůli ceně i kvůli času, a je změřené oboje.** Bez něj
    /// `claude` nabootuje **43 MCP serverů a 129 nástrojů** z uživatelova prostředí — session
    /// s prázdnou sadou z nich nemůže použít ani jeden, ale jejich jména se do systémového promptu
    /// stejně zapíšou. Vypnutí ubere ~5 100 tokenů bootu (47 676 → 42 555) a **~8 s** čekání na
    /// spouštění těch serverů. Není to ta velká úspora — tou je model —, ale je zadarmo.
    ///
    /// **Model se naopak vynucuje** (`model`), a je to výjimka z úmluvy u ostatních session; proč,
    /// je u té konstanty i s naměřenými čísly.
    static func arguments(prompt: String) -> [String] {
        [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--model", model,
            "--strict-mcp-config",
            "--allowedTools", allowedTools,
            "--disallowedTools", ClaudeCommand.disallowedTools,
        ]
    }

    /// Kolik znaků smí mít jedna věta. **Do promptu, ne do `Policy`** — a je to rozhodnutí.
    ///
    /// Zkrátit dlouhou větu po jejím příchodu **nejde bez ztráty významu**: uříznutý konec umí
    /// obrátit, co věta tvrdí, a blok, který brief ořízne, začne tvrdit něco jiného než session.
    /// Délka je tedy **tvar odpovědi**, a ten umí ovlivnit jedině model — `Policy` na něj nemá čím
    /// sáhnout, aniž by lhala. Proto strop stojí v zadání a **nikde se nevynucuje**.
    static let sentenceLimit = 140

    /// Prompt. **Zadání je formulace, ne rozhodování** — co je na tahu a co blokuje, je už
    /// rozhodnuté v `Policy.briefInput`; tady se to jenom čte nahlas.
    ///
    /// **Tři pojmenované otázky, ne „napiš tři věty“** (#516, po proklikání). Volné zadání vydalo
    /// souvislý odstavec, ve kterém byly tři různé věci natěsnané za sebou — a takový špalek se
    /// musí přečíst celý, aby z něj vypadla jedna. Klíče `ADDED` / `BURNING` / `NEXT` tedy nejsou
    /// formátování, ale **rozdělení práce**: každá věta má vlastní otázku a v okně vlastní návěští.
    ///
    /// **Vynechání řádku je v zadání výslovně dovolené**, a je to ta mez proti „tvrdí víc, než data
    /// unesou“: struktura, která si vynutí větu na každou otázku, si o vymyšlenou větu přímo říká.
    /// Prázdno u jedné otázky je legitimní odpověď (`BriefCommand.parse` vrátí jeden nebo dva
    /// řádky), ne porucha.
    ///
    /// **Zákaz vypisovat seznamy** je tam ze stejného důvodu, proč brief vůbec je: čísla pull
    /// requestů stojí v pruzích **pod** ním, takže věta, která je zopakuje, nešetří nic.
    ///
    /// Věta „nic si nedomýšlej“ v něm je, ale **není to ta mez, na které to stojí** — tou je
    /// prázdná sada nástrojů. Model, který si vymyslí PR, vymyslí ho i s tou větou; rozdíl je
    /// v tom, že se o skutečném repozitáři nemá jak dozvědět nic.
    static func prompt(input: String) -> String {
        """
        Jsi hlas aplikace PRism, která hlídá pull requesty k review. Níž je **hotový stav \
        aplikace**. Odpověz z něj na tři otázky, každou **jednou větou** česky, v druhé osobě \
        jednotného čísla:

        \(BriefPart.added.key): co přibylo nebo doběhlo
        \(BriefPart.burning.key): co nejvíc hoří
        \(BriefPart.next.key): co si vzít první

        Každý řádek začni tím klíčem a dvojtečkou. Nic jiného nepiš — bez nadpisu, bez odrážek, \
        bez uvozovek a bez prázdných řádků mezi nimi.

        Pravidla:
        - Řádek, na který ve vstupu odpověď není, **vynech celý**. Nepiš, že něco chybí.
        - Každá věta nejvýš **\(sentenceLimit) znaků**.
        - Jmenuj **nejvýš jeden** pull request na řádek. Seznamy čísel nevypisuj — ta jsou \
        v pruzích pod briefem.
        - Mluv jenom o tom, co je ve vstupu. Nic si nedomýšlej, nic nedopočítávej a příčiny \
        nevysvětluj. Čísla a jména opisuj přesně (`keboola/job-queue #727`).

        Stav aplikace:
        \(input)
        """
    }

    /// Co session napsala, rozebrané na pojmenované řádky. `nil` = nenapsala nic použitelného.
    ///
    /// **Čte se defenzivně**, jako účet agenta a odpověď překladu: je to volný text od modelu, ne
    /// formát, na kterém bychom se dohodli. Co se tedy snese:
    ///
    /// - **`` ``` ``-blok** kolem odpovědi (`stripFences`);
    /// - **markdownová ozdoba** návěští (`**ADDED:**`, `- ADDED:`) — model ji přidává, i když se
    ///   zakáže, a řádek kvůli hvězdičce propadnout nemá;
    /// - **cizí řádky**, které klíčem nezačínají: zahodí se. Próza kolem odpovědi je šum, ne věta
    ///   briefu, a pustit ji dál by znamenalo nakreslit ji pod cizí návěští;
    /// - **týž klíč dvakrát**: platí první výskyt. Druhá odpověď na tutéž otázku je oprava, kterou
    ///   nikdo nepotvrdil — a tiše vybrat tu pozdější je hádání.
    ///
    /// **Pořadí je naše, ne modelovo** (`BriefPart.allCases`): návěští v okně mají stát pořád
    /// stejně, jinak se blok při každém shrnutí přeskládá a nedá se přelétnout okem.
    ///
    /// **Prázdno je porucha, ne prázdný brief** — blok s prázdným místem je k nerozeznání od
    /// vypnutého, takže ani jeden řádek znamená `nil` a věta o tom, že se to nepovedlo.
    static func parse(_ text: String?) -> [BriefLine]? {
        guard let text else { return nil }
        var found: [BriefPart: String] = [:]
        for line in TextLines.content(stripFences(text)) {
            guard let (part, body) = labelled(line), found[part] == nil else { continue }
            found[part] = body
        }
        let lines = BriefPart.allCases.compactMap { part in
            found[part].map { BriefLine(part: part, text: $0) }
        }
        return lines.isEmpty ? nil : lines
    }

    /// Znaky, které se kolem návěští odřezávají — mezery a markdownová ozdoba.
    private static let decoration = CharacterSet(charactersIn: " \t*_-#•·>")

    /// Rozebere jeden řádek na návěští a větu. `nil` = řádek žádným klíčem nezačíná, nebo za
    /// klíčem nic nestojí.
    ///
    /// Klíče se **neprolínají** (`ADDED`, `BURNING`, `NEXT`), takže může sednout nejvýš jeden
    /// a nezáleží na pořadí, ve kterém se zkoušejí.
    private static func labelled(_ line: some StringProtocol) -> (BriefPart, String)? {
        let bare = line.trimmingCharacters(in: decoration)
        // Velikost písmen se odpouští: klíč je ASCII, takže `uppercased()` délku nemění a
        // `dropFirst` nad původním řetězcem ukazuje na totéž místo.
        let upper = bare.uppercased()
        for part in BriefPart.allCases where upper.hasPrefix(part.key) {
            // **Za klíčem musí stát dvojtečka.** Bez téhle podmínky by se návěštím stala každá
            // věta, která tím slovem náhodou začíná — a její první slovo by zmizelo. Ozdoba mezi
            // klíčem a dvojtečkou (`**ADDED**:`) se přitom odečítá.
            let rest = String(bare.dropFirst(part.key.count)).trimmingCharacters(in: decoration)
            guard rest.hasPrefix(":") else { return nil }
            let body = rest.dropFirst().trimmingCharacters(in: decoration)
            return body.isEmpty ? nil : (part, body)
        }
        return nil
    }

    /// Zahodí ```-blok kolem odpovědi. Hledají se **celé řádky** s ohradníky, ne první výskyt:
    /// tři zpětné apostrofy uvnitř věty jsou text, ne ohrada.
    private static func stripFences(_ text: String) -> String {
        TextLines.content(text)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .joined(separator: "\n")
    }
}
