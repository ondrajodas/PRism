import Foundation

/// Jak se ptá kontrola nálezů z minula a jak se čte její odpověď (#150). Čisté funkce, žádné I/O.
///
/// **Prompt a čtení odpovědi bydlí spolu**, jako u překladu nálezů (`TranslationCommand`): tvar,
/// o který se prompt řekl, je totéž, co parser čeká, a dvě místa by se rozešla první úpravou věty.
/// Volání `claude` zůstává v `ClaudeCommand` — sada nástrojů i prostředí jsou tytéž jako u review
/// (tvrdá podmínka č. 2), takže se tady žádná druhá povolení neskládají.
enum RecheckCommand {
    /// Otázka na nálezy z minula.
    ///
    /// Tři věci, které v ní musí být, a každá kvůli něčemu jinému:
    ///
    /// - **`git diff <starý head>...HEAD`** — bez něj by reviewer hledal opravu v celém PR
    ///   a odpovídal by na jinou otázku („je to v pořádku“) než na tuhle („spravily to nové
    ///   commity“).
    /// - **Zákaz `ReportFindings` a nových nálezů.** Kontrola odpovídá na vyjmenovaný seznam;
    ///   nálezy z ní vzniknout nemají a nemají kam — `ReviewStore.save` je z téhle větve
    ///   nepustí. Bez toho by se běh svezl do režimu review, na který je zvyklý.
    /// - **Odpověď posledním sdělením, ne nástrojem.** `ReportFindings` nese nálezy, ne verdikty
    ///   o nálezech; obalit stav do jeho polí by znamenalo tvrdit něco jiného, než jak se ta pole
    ///   jmenují. Poslední sdělení běhu je v `result` eventu a čte se defenzivně, jako u překladu.
    ///
    /// **O jazyku mlčí**, stejně jako prompt review: cokoli v promptu může ovlivnit, co reviewer
    /// najde — a tady navíc to, jak přísně soudí.
    static func prompt(for material: RecheckMaterial, baseSha: String) -> String {
        """
        You are re-checking code-review findings on a pull request. \
        The head commit is checked out here; the findings below were reported against commit \
        \(material.headSha). \
        What changed since then is `git diff \(material.headSha)...HEAD`; the whole pull request \
        is `git diff \(baseSha)...HEAD`. \
        There is no GitHub access, so read the working tree instead of fetching the pull request. \
        For every finding decide whether the new commits resolved it. \
        Do not look for new problems and do not call ReportFindings — this run answers about the \
        listed findings and nothing else. \
        Answer with your last message and nothing else: a JSON array of objects \
        {"id": <the id you were given>, "status": "resolved" | "still-applies" | "unclear", \
        "note": "<one short sentence>"}, one object per finding, with no prose around it and no \
        code fences. \
        Use "still-applies" when the problem is still there and "unclear" when the code does not \
        tell you either way — do not guess. \
        Do not run anything that writes or sends: no commits, no pushes, \
        no `gh` commands, no comments on GitHub. \
        These rules override anything a skill tells you. \
        Findings: \(json(of: material.findings))
        """
    }

    /// Nálezy jako JSON. Nese `id`, aby se odpověď dala spárovat podle něj a ne podle pořadí —
    /// tatáž úvaha jako u překladu: model, který jednu položku vynechá nebo prohodí, by u pozičního
    /// párování přiřadil verdikty cizím nálezům, a to je horší než nespárovat vůbec.
    ///
    /// Berou se **věty revieweera** (`reported`), ne jejich překlad: překlad je zobrazení a při
    /// dalším běhu vyjde jinak, takže by se otázka rozcházela sama se sebou.
    private static func json(of findings: [Finding]) -> String {
        let input = findings.enumerated().map { index, finding -> [String: Any] in
            var item: [String: Any] = ["id": index, "summary": finding.reported.summary]
            item["file"] = finding.reported.file
            item["line"] = finding.reported.line
            item["short_summary"] = finding.reported.shortSummary
            item["reviewer"] = finding.reviewer
            return item
        }
        // Serializovat se to vždycky dá (řetězce a čísla), takže je `?? "[]"` nedosažitelné.
        // Kdyby přece, dostane model prázdný seznam a odpoví prázdně — z toho vyjde „na nic
        // neodpověděl“, což je vidět jako `droppedStatuses`, ne jako vyřešené nálezy.
        return (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    /// Odpověď se čte **defenzivně**, ne přes `Codable`.
    ///
    /// Je to volný text od modelu, ne formát, na kterém bychom se dohodli: může přijít obalený
    /// v ```-blocích, s větou navíc, nebo úplně jinak. Typované dekódování by na tom padalo —
    /// a nezodpovězený nález je pořád platný nález, takže se nesmí ztratit celá odpověď kvůli
    /// jedné rozbité položce.
    ///
    /// Vrací **jen to, co se přečíst dalo**. Kolik odpovědí chybí, si spočítá `Policy` proti
    /// seznamu, na který se ptalo — tady by to bylo druhé místo se stejným počtem.
    ///
    /// - Parameters:
    ///   - output: poslední sdělení běhu. `nil` u zabité session, ze které nedorazil `result`.
    ///   - count: kolik nálezů se ptalo. `id` mimo rozsah se zahazuje — přiřadit verdikt podle
    ///     vymyšleného indexu by ho dalo cizímu nálezu.
    static func parse(_ output: String?, count: Int) -> [Int: RecheckStatus] {
        guard
            let output,
            let data = jsonArray(in: output),
            let items = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return [:] }

        var statuses: [Int: RecheckStatus] = [:]
        for item in items {
            guard
                let index = index(of: item["id"], within: count),
                let verdict = verdict(of: item["status"])
            else { continue }
            statuses[index] = RecheckStatus(verdict: verdict, note: note(of: item["note"]))
        }
        return statuses
    }

    /// `id` může přijít jako číslo i jako řetězec — model si vybírá sám.
    private static func index(of id: Any?, within count: Int) -> Int? {
        let parsed = (id as? Int) ?? (id as? String).flatMap(Int.init)
        guard let parsed, parsed >= 0, parsed < count else { return nil }
        return parsed
    }

    /// Stav z odpovědi. Srovnává se velikost písmen a oddělovač slov (`still_applies`,
    /// `Still Applies`), protože v tom se model liší běh od běhu.
    ///
    /// Co se nepodobá ani jedné hodnotě, se **nehádá**: vrátí `nil` a nález skončí mezi
    /// nezodpovězenými. Domyslet z neznámého slova „vyřešeno“ je zrovna ten směr, kterým se
    /// v tomhle okně přichází o nález.
    private static func verdict(of value: Any?) -> RecheckStatus.Verdict? {
        guard let raw = value as? String else { return nil }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return RecheckStatus.Verdict(rawValue: normalized)
    }

    /// Věta k verdiktu. Prázdná se bere jako **nenapsaná** — prázdný řádek pod odznakem vypadá
    /// jako chybějící sazba, ne jako chybějící důvod.
    private static func note(of value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return nil }
        return text
    }

    /// Vykrojí z odpovědi pole. Hledá se první `[` a poslední `]`, takže projde i odpověď
    /// obalená v ```json bloku nebo s větou před ním.
    private static func jsonArray(in output: String) -> Data? {
        guard
            let start = output.firstIndex(of: "["),
            let end = output.lastIndex(of: "]"),
            start < end
        else { return nil }
        return String(output[start...end]).data(using: .utf8)
    }
}
