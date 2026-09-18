import Foundation

/// Jak se `claude` volá kvůli anotacím hunků (#524) a jak se čte jeho odpověď. Čisté funkce,
/// žádné I/O.
///
/// **Prompt a čtení odpovědi bydlí spolu**, jako u kontroly nálezů (`RecheckCommand`) a překladu:
/// tvar, o který se prompt řekne, je totéž, co parser čeká, a dvě místa by se rozešla první úpravou
/// věty. Samotný tvar je v `AnnotationSchema`, protože se z něj **skládá** i popis do promptu.
///
/// **Nepřibývá sada povolení, a je to to tvrzení.** Anotační session běží s **doslova toutéž**
/// sadou jako rozhovor nad PR (`AskCommand.allowedTools`) — liší se **promptem a parserem**, ne
/// povoleními. Do #524 tu stála vlastní konstanta s `ReportAnnotations`; když nástroj odpadl
/// (viz `AnnotationSchema`), zbyl by z ní druhý literál s týmž obsahem, tedy druhé místo, kde se
/// dá tvrdá podmínka č. 2 porušit. Delegace je tu ze stejného důvodu, z jakého bere agent na
/// vlastním PR sadu od slévání konfliktů (#510).
enum AnnotateCommand {
    /// Argumenty. Dvě konstanty, obě **cizí a sdílené**:
    ///
    /// - **`--allowedTools` je `AskCommand.allowedTools`** — `Read`, `Grep`, `Glob` na kód
    ///   v pracovní kopii a `Bash(git:*)` na `git diff <base>...HEAD` a `git log` (bez commitů by
    ///   se „proč“ nemělo odkud vzít). `ReportFindings` v ní **není**: anotace není nález a tohle
    ///   je druhá polovina té hranice — nemá se kam zapsat, ani kdyby chtěla. `Skill` v ní taky
    ///   není, ze stejného důvodu jako u rozhovoru (#452).
    /// - **`--disallowedTools` je `ClaudeCommand.disallowedTools`**, tedy tatáž konstanta jako
    ///   u všech ostatních session.
    ///
    /// **Model se bere z konfigurace**, jako u rozhovoru (#452): odpovědí je úvaha nad cizím kódem,
    /// ne mechanický převod, takže se tahle session má ptát tím modelem, kterým tahle aplikace
    /// mluví.
    static func arguments(prompt: String, model: String? = nil) -> [String] {
        var arguments = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--allowedTools", AskCommand.allowedTools,
            "--disallowedTools", ClaudeCommand.disallowedTools,
        ]
        if let model, !model.isEmpty {
            arguments += ["--model", model]
        }
        return arguments
    }

    /// Prompt. **Natvrdo, needitovatelně** — jako u kontroly nálezů (#150) a překladu: odpověď
    /// čte parser podle tvaru ze schématu, takže editovatelné zadání by rozbilo **čtení**, ne jen
    /// výsledek. Editovatelný je jedině prompt review (#281).
    ///
    /// **Věty o tvaru odpovědi se sem skládají z `AnnotationSchema.instruction`**, ne píšou ručně:
    /// dvě pravdy o tvaru by se rozešly a to rozejití by v okně vypadalo jako model, který pole
    /// nevyplňuje.
    ///
    /// **Česky se píše rovnou, nepřekládá se.** Nálezy mají vlastní překladovou session (#94),
    /// protože je jich hodně a `category` u nich musí zůstat anglicky jako slug s vazbou na
    /// blokující sadu. Anotace je proti tomu **věta pro mě**, žádný slug v ní není a druhá session
    /// by zdvojnásobila cenu u textu o řád kratšího než nález.
    ///
    /// **Jazyk je poslední věta promptu** (#592, `AnnotationSchema.language`), ne přívlastek
    /// v popisu pole: v popisu tvaru stál do #592 a u diffu plného cizojazyčného textu **neplatil**.
    /// Poslední je proto, že věta o jazyku má platit i proti tomu, co session viděla v kódu — je to
    /// tatáž úvaha jako u věty o přírůstku v `Policy.reviewPromptCore` (#517), kde platí ta
    /// poslední. Zákaz zápisu tím **neslábne**: drží ho `--disallowedTools`, ne pořadí vět
    /// v promptu (viz `ReviewPromptTemplate`).
    ///
    /// **Parametr na jazyk tu není schválně** (#592, po proklikání): anotace je text v okně vedle
    /// českých popisků, ne obsah review, takže `findingsLanguage` do téhle cesty nepatří. Co nemá
    /// parametr, nedá se nastavením rozhodit — a druhá cesta k jazyku tím nemá kde vzniknout.
    static func prompt(baseSha: String) -> String {
        """
        You are explaining a pull request that is checked out here — not reviewing it. \
        See the changes with `git diff \(baseSha)...HEAD` and read the commits behind them with \
        `git log \(baseSha)..HEAD`; there is no GitHub access, so read the working tree instead \
        of fetching the pull request. \
        \(AnnotationSchema.instruction) \
        Do not run anything that writes or sends: no commits, no pushes, no `gh` commands, \
        no comments on GitHub. \
        \(AnnotationSchema.language)
        """
    }

    /// Co se z posledního sdělení přečetlo.
    ///
    /// **`answered` je oddělené od prázdných seznamů schválně**, přesně jako `calledReportFindings`
    /// u revieweera: „odpověď se nedala přečíst“ a „nemám co dodat“ jsou různé věci a v okně se
    /// nesmí slít. Tady to platí **víc** než u nálezů: odpověď posledním sdělením je zrovna to
    /// místo, kde sběr umí tiše nefungovat (`docs/claude-cli.md`) — session, která si tvar
    /// nepřečte, napíše prózu a bez tohohle příznaku by z toho vyšlo „diff nemá nic zajímavého“.
    struct Answer: Equatable, Sendable {
        var hunks: [HunkAnnotation] = []
        var files: [FileAnnotation] = []
        /// Přišla odpověď ve tvaru, který se dal přečíst? `false` = **nesbíralo se nic**.
        var answered = false
        /// Kolik položek se nepodařilo přečíst.
        var dropped = 0
    }

    /// Odpověď se čte **defenzivně**, ne přes `Codable`, ze stejného důvodu jako u kontroly
    /// nálezů: je to volný text od modelu, ne formát, na kterém bychom se dohodli — může přijít
    /// obalený v ```-blocích nebo s větou navíc. Typované dekódování by na tom padalo celé, kdežto
    /// takhle se ztrácí jen ta položka, která je rozbitá.
    ///
    /// **Ani jeden ze dvou seznamů není povinný**: session, která popsala soubory a na hunky
    /// nedošla, poslala pravdu o té půlce, kterou poslala. Chybí-li ale **oba** — nebo není-li
    /// v odpovědi objekt vůbec —, nepřečetlo se nic a `answered` zůstává `false`.
    ///
    /// - Parameter output: poslední sdělení běhu. `nil` u zabité session, ze které `result`
    ///   nedorazil — a je to ten stav, kvůli kterému se z **částečné** anotace neuloží nic.
    static func parse(_ output: String?) -> Answer {
        guard
            let output,
            let data = jsonObject(in: output),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return Answer() }

        let hunks = object[AnnotationSchema.Key.hunks] as? [[String: Any]]
        let files = object[AnnotationSchema.Key.files] as? [[String: Any]]
        guard hunks != nil || files != nil else { return Answer() }

        var answer = Answer(answered: true)
        for item in hunks ?? [] {
            guard let annotation = hunkAnnotation(from: item) else {
                answer.dropped += 1
                continue
            }
            answer.hunks.append(annotation)
        }
        for item in files ?? [] {
            guard let annotation = fileAnnotation(from: item) else {
                answer.dropped += 1
                continue
            }
            answer.files.append(annotation)
        }
        // **Slévá se, i když je odpověď jedna**: `hunks` je seznam od modelu, takže v něm můžou
        // stát dvě položky o témže hunku — a dvě věty nad jedním kusem kódu se nakreslit nedají.
        // Rozhodnutí „co je totéž místo“ leží v `Policy`, ne tady, přesně jako u nálezů.
        answer.hunks = Policy.mergedHunkAnnotations([], reporting: answer.hunks)
        answer.files = Policy.mergedFileAnnotations([], reporting: answer.files)
        return answer
    }

    /// Anotace jednoho hunku z odpovědi. Vadná položka se **zahazuje a počítá** — tichá ztráta by
    /// se v okně nedala odlišit od session, která tu část diffu prostě nepopsala.
    ///
    /// Povinné je `file`, `hunk` a `why`; `hunk` musí být **kladné celé číslo**, protože se jím
    /// indexuje do hunků souboru. Zbytek je v `AnnotationSchema.hunkFields` a čte se podle něj.
    static func hunkAnnotation(from object: [String: Any]) -> HunkAnnotation? {
        guard let file = nonEmpty(object[AnnotationSchema.Key.file]),
              let hunk = positiveNumber(object[AnnotationSchema.Key.hunk]),
              let why = nonEmpty(object[AnnotationSchema.Key.why])
        else { return nil }
        return HunkAnnotation(
            file: file,
            hunk: hunk,
            why: why,
            source: nonEmpty(object[AnnotationSchema.Key.source])
        )
    }

    /// Druh změny u souboru z odpovědi.
    ///
    /// **Neznámý druh se nehádá** — položka se zahodí a započítá. Výčet je to, podle čeho itinerář
    /// řadí, takže hodnota mimo něj by byla šestý druh, o kterém nikdo nerozhodl.
    static func fileAnnotation(from object: [String: Any]) -> FileAnnotation? {
        guard let file = nonEmpty(object[AnnotationSchema.Key.file]),
              let raw = object[AnnotationSchema.Key.kind] as? String,
              let kind = FileChangeKind(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return FileAnnotation(file: file, kind: kind)
    }

    /// Neprázdný ořezaný řetězec, nebo `nil`. Prázdné `why` je totéž co žádné: řádek nad hunkem
    /// bez textu vypadá jako rozbitá kresba, ne jako chybějící anotace.
    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Kladné celé číslo, i když dorazí textem.
    ///
    /// **`as? Int` tady být nesmí**: `JSONSerialization` mapuje `true` na `NSNumber`, takže by
    /// z `true` vyšel hunk 1 — a anotace by se posadila k cizímu kusu kódu. `2.5` se ze stejného
    /// důvodu zahazuje, neořezává.
    ///
    /// **`value is Bool` tou kontrolou ale není, a je to změřené.** `JSONSerialization` vydá pro
    /// `1` i `0` obyčejné `__NSCFNumber` — jenže to se do `Bool`u bridguje, takže `1 is Bool` vyjde
    /// **`true`** (`42 is Bool` už `false`). Kontrola napsaná takhle by tedy zahodila přesně ta
    /// dvě čísla, která v diffu padnou nejčastěji: **hunk 1**. Rozlišit se to dá jedině podle
    /// skutečného typu — `__NSCFBoolean` má vlastní `CFTypeID`.
    private static func positiveNumber(_ value: Any?) -> Int? {
        let candidate: Int?
        if let number = value as? NSNumber, !isBoolean(number) {
            let whole = number.intValue
            candidate = Double(whole) == number.doubleValue ? whole : nil
        } else {
            candidate = (value as? String).flatMap(Int.init)
        }
        return candidate.flatMap { $0 > 0 ? $0 : nil }
    }

    /// Je to `true`/`false`, nebo číslo? Viz `positiveNumber` — `is Bool` na to odpověď nedá.
    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// Vykrojí z odpovědi objekt. Hledá se první `{` a poslední `}`, takže projde i odpověď
    /// obalená v ```json bloku nebo s větou před ním — přesně jako `RecheckCommand.jsonArray`,
    /// jen pro objekt místo pole.
    private static func jsonObject(in output: String) -> Data? {
        guard
            let start = output.firstIndex(of: "{"),
            let end = output.lastIndex(of: "}"),
            start < end
        else { return nil }
        return String(output[start...end]).data(using: .utf8)
    }
}
