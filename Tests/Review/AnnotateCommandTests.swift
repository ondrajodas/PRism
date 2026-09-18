import Foundation
import Testing

@testable import PRism

/// Tvar odpovědi anotační session a její čtení (#524).
///
/// **Nejcennější tvrzení je tady to, že se nic nesebralo.** Odpověď je poslední sdělení (cesta 2),
/// a to je zrovna to místo, kde sběr umí **tiše nefungovat**: session, která si tvar nepřečte,
/// napíše prózu — a bez `answered` by z toho v okně vyšlo „k tomuhle diffu nemá co dodat“, tedy
/// věta o kódu místo věty o rozbité odpovědi.
@Suite("Anotace hunků — schéma a čtení odpovědi (#524)")
struct AnnotateCommandTests {
    // MARK: - Schéma: hranice mezi anotací a nálezem

    /// **Ve schématu není pole pro závažnost.** To je ta hranice, ne věta v promptu: model nemá
    /// kam závažnost napsat a parser ji nemá odkud přečíst. Kdyby pole přibylo, bylo by to druhé
    /// `ReportFindings` — a anotace by se dřív nebo později začaly počítat do odznaků.
    ///
    /// Tvrdí se nad **výčtem slov**, ne úsudkem: odpověď má dostat i ten, kdo pole přidává za rok
    /// a o #524 neví.
    @Test("Schéma nemá pole pro závažnost")
    func schemaHasNoSeverityField() {
        for field in AnnotationSchema.everyField {
            for word in AnnotationSchema.severityWords {
                #expect(
                    !field.name.lowercased().contains(word),
                    "pole `\(field.name)` nese závažnost přes slovo `\(word)`"
                )
            }
        }
    }

    /// Pole schématu **literálem**. `#expect(x == Schema.fields)` by neznamenalo nic — po přidání
    /// pole by prošlo dál. Cena je, že se test musí změnit vědomě, a to je celý smysl.
    @Test("Schéma má čtyři pole u hunku a dvě u souboru")
    func schemaFieldsAreListed() {
        #expect(AnnotationSchema.hunkFields.map(\.name) == ["file", "hunk", "why", "source"])
        #expect(AnnotationSchema.fileFields.map(\.name) == ["file", "kind"])
        // Nepovinné je **jen** `source`: anotace bez zdroje je pořád věta, kterou stojí za to mít.
        #expect(AnnotationSchema.everyField.filter { !$0.isRequired }.map(\.name) == ["source"])
    }

    /// **Popis do promptu se skládá z výčtu polí**, nepíše ručně — jinak by vzniklo pole, o kterém
    /// ví parser a ne model, nebo naopak. Test to ověřuje tím, že v instrukci stojí **každé**
    /// jméno pole i **každá** hodnota uzavřeného výčtu.
    @Test("Instrukce vypisuje všechna pole i celý výčet druhů")
    func instructionIsComposedFromTheFields() {
        let instruction = AnnotationSchema.instruction

        for field in AnnotationSchema.everyField {
            #expect(instruction.contains("`\(field.name)`"), "pole `\(field.name)` v promptu chybí")
        }
        for kind in FileChangeKind.allCases {
            #expect(instruction.contains(kind.rawValue), "druh `\(kind.rawValue)` v promptu chybí")
        }
        // A **říká, jak se odpovídá** — bez té věty by session sáhla po nástroji, který neexistuje.
        #expect(instruction.contains("Answer with your last message and nothing else"))
    }

    // MARK: - Čtení odpovědi

    private func answer(_ output: String?) -> AnnotateCommand.Answer {
        AnnotateCommand.parse(output)
    }

    @Test("Čistá odpověď se přečte celá")
    func readsACleanAnswer() {
        let parsed = answer(
            """
            {"hunks": [{"file": "App/A.swift", "hunk": 1, "why": "přidává bránu", \
            "source": "z commitu feat: gate"}], \
            "files": [{"file": "App/A.swift", "kind": "behaviour"}]}
            """
        )

        #expect(parsed.answered)
        #expect(parsed.dropped == 0)
        #expect(
            parsed.hunks == [
                HunkAnnotation(
                    file: "App/A.swift",
                    hunk: 1,
                    why: "přidává bránu",
                    source: "z commitu feat: gate"
                )
            ]
        )
        #expect(parsed.files == [FileAnnotation(file: "App/A.swift", kind: .behaviour)])
    }

    /// Odpověď obalená prózou nebo ```-blokem projde — je to volný text od modelu, ne formát,
    /// na kterém bychom se dohodli. Tatáž defenziva jako u kontroly nálezů (#150).
    @Test("Odpověď v code fence i s větou kolem se přečte")
    func readsAWrappedAnswer() {
        let parsed = answer(
            """
            Tady je popis:
            ```json
            {"hunks": [{"file": "a.swift", "hunk": 2, "why": "opravuje limit"}], "files": []}
            ```
            Hotovo.
            """
        )

        #expect(parsed.answered)
        #expect(parsed.hunks.count == 1)
        #expect(parsed.hunks.first?.hunk == 2)
        #expect(parsed.hunks.first?.source == nil)
    }

    // MARK: - Když se nesebralo nic

    /// **Tohle je ten test, kvůli kterému tenhle soubor je.** Odpověď bez správného tvaru nesmí
    /// vydat anotace **ani prázdné seznamy s `answered`**: v okně je rozdíl mezi „nemá co dodat“
    /// a „odpověď se nedala přečíst“ celý rozdíl mezi tvrzením o kódu a tvrzením o běhu.
    @Test(
        "Odpověď bez správného tvaru nesebere nic",
        arguments: [
            "Změny přidávají bránu do konfigurace a test k ní.",
            "",
            "[{\"file\": \"a.swift\", \"hunk\": 1, \"why\": \"pole místo objektu\"}]",
            "{\"annotations\": [{\"file\": \"a.swift\", \"hunk\": 1, \"why\": \"cizí klíč\"}]}",
            "{\"hunks\": \"ne seznam\"}",
            "{ tohle není JSON }",
        ]
    )
    func collectsNothingFromAMalformedAnswer(output: String) {
        let parsed = answer(output)

        #expect(!parsed.answered, "z `\(output)` se tvářilo, že odpověď dorazila")
        #expect(parsed.hunks.isEmpty)
        #expect(parsed.files.isEmpty)
    }

    /// Zabitá session `result` nepošle vůbec — a to je ten stav, kvůli kterému se z **částečné**
    /// anotace neuloží nic. `nil` se proto musí chovat jako rozbitá odpověď, ne jako prázdná.
    @Test("Chybějící poslední sdělení nesebere nic")
    func collectsNothingWithoutAResult() {
        let parsed = answer(nil)

        #expect(!parsed.answered)
        #expect(parsed.hunks.isEmpty)
        #expect(parsed.files.isEmpty)
    }

    /// Prázdné seznamy jsou **odpověď**, ne ticho: session se podívala a nemá co dodat. Rozdíl
    /// proti testu výš je jediné pole — `answered`.
    @Test("Prázdné seznamy jsou odpověď")
    func emptyListsCountAsAnAnswer() {
        let parsed = answer(#"{"hunks": [], "files": []}"#)

        #expect(parsed.answered)
        #expect(parsed.hunks.isEmpty)
        #expect(parsed.files.isEmpty)
        #expect(parsed.dropped == 0)
    }

    /// Jeden seznam stačí: session, která popsala soubory a na hunky nedošla, poslala pravdu
    /// o té půlce, kterou poslala.
    @Test("Jeden z obou seznamů stačí")
    func oneListIsEnough() {
        let parsed = answer(#"{"files": [{"file": "a.swift", "kind": "test"}]}"#)

        #expect(parsed.answered)
        #expect(parsed.files.count == 1)
        #expect(parsed.hunks.isEmpty)
    }

    // MARK: - Vadné položky se zahazují a počítají

    /// Vadná položka se zahodí, ale **spočítá se** — tichá ztráta by se v okně nedala odlišit
    /// od části diffu, kterou session schválně nepopsala.
    @Test("Položka bez povinného pole se zahodí a započítá")
    func dropsAndCountsIncompleteItems() {
        let parsed = answer(
            """
            {"hunks": [{"file": "a.swift", "hunk": 1, "why": "platná"}, \
            {"file": "a.swift", "why": "chybí hunk"}, \
            {"hunk": 3, "why": "chybí soubor"}, \
            {"file": "a.swift", "hunk": 4, "why": "   "}], \
            "files": [{"file": "a.swift", "kind": "neznámý"}]}
            """
        )

        #expect(parsed.answered)
        #expect(parsed.hunks.map(\.why) == ["platná"])
        #expect(parsed.files.isEmpty)
        #expect(parsed.dropped == 4)
    }

    /// **`true` nesmí projít jako hunk 1.** `JSONSerialization` mapuje `true` na `NSNumber`, takže
    /// `as? Int` by z něj číslo udělalo — a věta by se posadila k cizímu kusu kódu. Desetinné číslo
    /// se ze stejného důvodu zahazuje, neořezává; nula a záporné číslo taky, protože se indexuje
    /// od jedné.
    @Test(
        "Index hunku, který není kladné celé číslo, se zahodí",
        arguments: ["true", "2.5", "0", "-1", "null", "\"\""]
    )
    func rejectsNonPositiveHunkIndexes(raw: String) {
        let parsed = answer(#"{"hunks": [{"file": "a.swift", "hunk": \#(raw), "why": "věta"}]}"#)

        #expect(parsed.hunks.isEmpty, "`\(raw)` prošlo jako index hunku")
        #expect(parsed.dropped == 1)
    }

    /// Index poslaný **textem** projít smí — model si tvar čísla vybírá sám a `"3"` je pořád
    /// jednoznačně třetí hunk.
    @Test("Index hunku poslaný textem projde")
    func acceptsATextualHunkIndex() {
        let parsed = answer(#"{"hunks": [{"file": "a.swift", "hunk": "3", "why": "věta"}]}"#)

        #expect(parsed.hunks.first?.hunk == 3)
        #expect(parsed.dropped == 0)
    }

    /// **Neznámý druh se nehádá.** Výčet je to, podle čeho bude itinerář řadit, takže hodnota mimo
    /// něj by byla šestý druh, o kterém nikdo nerozhodl.
    @Test("Druh mimo výčet se zahodí, známý se ořeže")
    func keepsOnlyKnownChangeKinds() {
        let parsed = answer(
            """
            {"files": [{"file": "a.swift", "kind": "  refactor "}, \
            {"file": "b.swift", "kind": "chore"}]}
            """
        )

        #expect(parsed.files == [FileAnnotation(file: "a.swift", kind: .refactor)])
        #expect(parsed.dropped == 1)
    }

    /// Dvě věty o témže hunku se **slijí na poslední**: dvě anotace nad jedním kusem kódu se
    /// nakreslit nedají a model si větu rozmyslet smí. Rozhodnutí „co je totéž místo“ leží
    /// v `Policy`, ne v parseru.
    @Test("Dvě položky o témže hunku se slijí na poslední")
    func mergesDuplicateHunks() {
        let parsed = answer(
            """
            {"hunks": [{"file": "a.swift", "hunk": 1, "why": "první"}, \
            {"file": "a.swift", "hunk": 1, "why": "oprava"}, \
            {"file": "b.swift", "hunk": 1, "why": "jiný soubor"}]}
            """
        )

        #expect(parsed.hunks.map(\.why) == ["oprava", "jiný soubor"])
        #expect(parsed.dropped == 0)
    }

    // MARK: - Prompt

    /// Prompt nese **obě** cesty ke kontextu: diff i commity. Bez `git log` by se „proč“ nemělo
    /// odkud vzít a session by vysvětlovala kód z něj samotného.
    @Test("Prompt pošle session pro diff i pro commity")
    func promptCarriesBothSources() {
        let prompt = AnnotateCommand.prompt(baseSha: "base123", language: .czech)

        #expect(prompt.contains("git diff base123...HEAD"))
        #expect(prompt.contains("git log base123..HEAD"))
        #expect(prompt.contains(AnnotationSchema.instruction))
        // **Zákaz zápisu a odeslání je v promptu i tak**, i když ho drží povolení: prompt má říkat
        // totéž co sada, ne míň.
        #expect(prompt.contains("no `gh` commands"))
    }

    // MARK: - Jazyk vět (#592)

    /// Jazyk **je v promptu**, a to podle nastavení. Do #592 stál jako přívlastek v popisu pole
    /// (`why`: *„one sentence in Czech“*) a u diffu plného cizojazyčného textu neplatil — naostro
    /// z toho vyšly ruské věty.
    @Test("Prompt vyslovuje jazyk z nastavení", arguments: FindingsLanguage.allCases)
    func promptSaysTheLanguage(_ language: FindingsLanguage) {
        let prompt = AnnotateCommand.prompt(baseSha: "base123", language: language)

        #expect(prompt.contains("in \(language.promptName), whatever language the diff"))
        // A **platí proti kódu, ne jen obecně**: bez druhé poloviny věty je to zbožné přání, které
        // diff v cizím jazyce přebije.
        #expect(prompt.contains("not a property of the code you are reading"))
        for other in FindingsLanguage.allCases where other != language {
            #expect(
                !prompt.contains("in \(other.promptName), whatever language"),
                "prompt žádá i \(other.promptName)"
            )
        }
    }

    /// **Jazyk se vyslovuje na jednom místě.** Kdyby stál i v popisu pole, byly by o jazyku dvě
    /// pravdy — a rozešly by se první úpravou věty. Tvrdí se to počtem výskytů jména jazyka
    /// v celém promptu: jedna věta, jedno slovo.
    @Test("Jméno jazyka stojí v promptu jednou a v popisu polí vůbec")
    func languageIsSaidInOnePlace() {
        let prompt = AnnotateCommand.prompt(baseSha: "base123", language: .czech)

        #expect(prompt.components(separatedBy: "Czech").count - 1 == 1)
        for field in AnnotationSchema.everyField {
            for language in FindingsLanguage.allCases {
                #expect(
                    !field.meaning.contains(language.promptName),
                    "popis pole `\(field.name)` si drží jazyk sám"
                )
            }
        }
    }

    /// Věta o jazyku **vypisuje pole z výčtu**, nepíše jejich jména ručně: pole, které jako věta
    /// přibude, tím dostane jazyk samo. A **pole, která prózu nenesou**, v ní stát nesmí — cesta
    /// ani `kind` se nepřekládají.
    @Test("Věta o jazyku jmenuje pole s prózou a jen je")
    func languageSentenceNamesTheProseFields() {
        #expect(AnnotationSchema.proseFields.map(\.name) == ["why", "source"])

        let sentence = AnnotationSchema.language(.czech)
        for field in AnnotationSchema.everyField {
            #expect(
                sentence.contains("`\(field.name)`") == field.isProse,
                "pole `\(field.name)` je ve větě o jazyku, ač prózu nenese (nebo naopak)"
            )
        }
    }

    // MARK: - Čtení odpovědi je na jazyku nezávislé

    /// **Skutečné odpovědi ze dvou běhů téhož dne** — obě přes `Fixture`, ne literálem. Jedna vyšla
    /// česky, druhá rusky (`keboola/job-queue#727`), a je to ten běh, ze kterého #592 vzniklo.
    ///
    /// Tvrzení je **negativní**: parser jazyk **nepoznává ani nesahá na text**. Věta dojde do
    /// `HunkAnnotation.why` doslova, ať je v jakémkoli jazyce — takže **uložená ruská anotace se
    /// nepřekládá, ani po přepnutí nastavení**; zastará s hlavou, jako všechno ostatní u anotací.
    @Test("Odpověď se přečte doslova, ať je v jakémkoli jazyce")
    func readsTheAnswerVerbatimInAnyLanguage() throws {
        let russian = AnnotateCommand.parse(try Fixture.text("annotations/job-queue-727-russian.txt"))

        #expect(russian.answered)
        #expect(russian.dropped == 0)
        #expect(russian.hunks.count == 4)
        #expect(
            russian.hunks.first?.why
                == "Временно указывает на ветку разработки для проверки на канаре вместо стабильной версии"
        )
        #expect(russian.hunks.first?.source == "коммит 3c4d82eb")

        let czech = AnnotateCommand.parse(
            try Fixture.text("annotations/sandboxes-service-717-czech.txt")
        )

        #expect(czech.answered)
        #expect(czech.dropped == 0)
        #expect(
            czech.hunks.first?.why
                == "Odstraní konfigurační proměnnou BILLING_ENABLED, která již není potřebná po deaktivaci integraci se Billing API."
        )
        // Druhá polovina téhož: **druh změny zůstává anglickým slugem z výčtu**, protože podle něj
        // aplikace řadí a barví. Věta o jazyku se ho proto netýká.
        #expect(czech.files.first?.kind == .configuration)
    }
}
