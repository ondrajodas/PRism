import Foundation

/// Návrh změny kódu (#528) — složení bloku z výběru řádků a jeho přečtení zpátky z markdownu.
///
/// Všechno jsou čisté funkce nad daty, která už v aplikaci jsou: diff (u composeru) a `diffHunk`
/// vlákna (u čtení). **Nic odsud neodesílá** — blok je text komentáře a odchází s review přes
/// `ReviewPublishing.submit`, tedy tou cestou, která tu byla dřív.
extension Policy {
    /// Jazyk fence, kterým GitHub návrh pozná. Konstanta, protože ho čte skládání i rozpoznávání
    /// — dva literály by se rozešly a rozejití by bylo vidět až na GitHubu.
    static let suggestionLanguage = "suggestion"

    // MARK: - Skládání z výběru (composer)

    /// Blok předvyplněný **původními řádky** výběru, nebo věta, proč to nejde.
    ///
    /// Předvyplňuje se schválně: návrh psaný z ruky se s kódem, na který se váže, rozejde hned
    /// při prvním překlepu v odsazení — a GitHub takový návrh přijme, jen z něj vyjde jiný soubor,
    /// než jaký měl vzniknout. Takhle se **přepisuje**, ne píše.
    ///
    /// Tři důvody odmítnutí, a každý je vlastní věta:
    ///
    /// - **výběr v diffu není** — kotva ukazuje na řádek, který se nekreslí (rozbalený kontext,
    ///   jiný soubor);
    /// - **výběr je ze staré verze souboru** — návrh se aplikuje na hlavu PR, takže k odebranému
    ///   řádku nemá co nahradit;
    /// - **výběr přesahuje přes hranici hunku** — mezi hunky leží kód, který diff neukazuje,
    ///   a návrh by ho přepsal taky.
    static func suggestionOffer(for anchor: DraftAnchor, in file: FileDiff) -> SuggestionOffer {
        let sides = [anchor.side] + (anchor.start.map { [$0.side] } ?? [])
        guard sides.allSatisfy({ $0 == .right }) else { return .refused(suggestionRefusalOldSide) }
        let lines = suggestionLines(of: anchor, in: file)
        guard !lines.isEmpty else { return .refused(suggestionRefusalMissing) }

        let hunks = Set(lines.compactMap { hunkIndex(of: $0, in: file) })
        guard hunks.count == 1 else { return .refused(suggestionRefusalAcrossHunks) }

        // Odebraný řádek uvnitř rozsahu se **vynechá**: v nové verzi souboru neexistuje, takže
        // ho návrh nemá čím nahradit — a GitHub sám nahrazuje jen to, co je na pravé straně.
        let kept = lines.filter { $0.newNumber != nil }
        guard !kept.isEmpty else { return .refused(suggestionRefusalOldSide) }

        let text = kept.map(\.text)
        return .available(CodeSuggestion(original: text, replacement: text))
    }

    /// Řádky výběru v pořadí, jak stojí v souboru — u jednořádkové kotvy ten jediný.
    private static func suggestionLines(of anchor: DraftAnchor, in file: FileDiff) -> [DiffLine] {
        guard anchor.isRange else {
            let line = file.hunks.lazy.flatMap(\.lines).first { $0.newNumber == anchor.line }
            return line.map { [$0] } ?? []
        }
        return rangeLinesInOrder(of: anchor, in: file)
    }

    /// Ve kterém hunku řádek leží. `nil` = v žádném (rozbalený kontext #47).
    ///
    /// Rovnost celého řádku stačí: čísla jsou v ní, takže dva hunky nemají jak vydat tentýž.
    private static func hunkIndex(of line: DiffLine, in file: FileDiff) -> Int? {
        file.hunks.firstIndex { $0.lines.contains(line) }
    }

    static let suggestionRefusalMissing =
        "Návrh se dá napsat jen k řádkům, které diff ukazuje — tenhle výběr v žádném hunku není."
    static let suggestionRefusalOldSide =
        "Návrh se aplikuje na hlavu PR, takže potřebuje řádek, který v nové verzi souboru je — vybraný je ze staré."
    static let suggestionRefusalAcrossHunks =
        "Návrh musí být celý v jednom hunku. Vybrané řádky leží ve dvou a mezi nimi je kód, který diff neukazuje — návrh by přepsal i ten."

    /// Blok tak, jak se vloží do těla komentáře.
    ///
    /// Zakončení řádků skládá aplikace (`\n`), takže se tady **nedělí nic cizího** — vstupem jsou
    /// texty řádků diffu, které `DiffParser` už rozdělil. Prázdný návrh je legitimní: fence bez
    /// jediného řádku znamená „tenhle kus smaž“.
    static func suggestionFence(replacing lines: [String]) -> String {
        (["```\(suggestionLanguage)"] + lines + ["```"]).joined(separator: "\n")
    }

    /// Blok vložený do rozepsaného textu — i s prázdným řádkem před ním, když už se něco píše.
    ///
    /// Prázdný řádek je podmínka, ne kosmetika: fence nalepený hned pod odstavec je v markdownu
    /// pořád fence, ale odstavec nad ním se s ním u přísnějších sazečů slije. Je to jediná cesta,
    /// kterou do pole komentáře přibude text jinak než klávesnicí — proto obecné jméno, i když
    /// blok je dneska jedině návrh změny.
    static func blockInsertion(of block: String, into body: String) -> String {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return block }
        return body.hasSuffix("\n") ? "\(body)\n\(block)" : "\(body)\n\n\(block)"
    }

    // MARK: - Čtení zpátky (vlákno, panel, zadání)

    /// Návrhy, které v těle komentáře stojí — spárované s tím, co nahrazují.
    ///
    /// **Jen bloky nejvyšší úrovně.** Fence uvnitř citace nebo `<details>` je ukázka, ne návrh:
    /// GitHub z citovaného návrhu tlačítko `Apply` taky nedělá, a kdyby se kreslil jako mini diff,
    /// tvrdil by, že se dá přijmout něco, co je jen odcitované.
    static func suggestions(in body: String, replacing original: [String] = []) -> [CodeSuggestion] {
        suggestions(in: MarkdownParser.parse(body), replacing: original)
    }

    /// Totéž nad **už rozloženým** textem (pravidlo #224).
    ///
    /// Existuje kvůli tomu, kde se na návrhy ptá okno: bublina vlákna je buňka líného seznamu,
    /// takže „nese tenhle komentář návrh?“ padne při každém překreslení. Rozklad markdownu je
    /// přitom funkce textu a `MarkdownRenderCache` ho už drží — tahle podoba dovolí ptát se nad
    /// ním. `Policy` cache nezná a znát nemá: je to čistá funkce, kterou volající krmí.
    static func suggestions(in blocks: [MarkdownBlock], replacing original: [String] = []) -> [CodeSuggestion] {
        blocks.compactMap { block in
            guard case .code(let language, let lines) = block,
                  language?.lowercased() == suggestionLanguage
            else { return nil }
            return CodeSuggestion(original: original, replacement: lines)
        }
    }

    /// Nese komentář návrh? Ptá se na to okno u tlačítka i zadání pro agenta, takže je to jedna
    /// funkce — dvě různá „obsahuje suggestion“ by se rozešla.
    static func hasSuggestion(in body: String) -> Bool {
        !suggestions(in: body).isEmpty
    }

    /// Co návrh ve vlákně nahrazuje — **řádek, u kterého vlákno visí**.
    ///
    /// Bere se z `diffHunk`u, protože ten končí přesně u komentovaného řádku (ověřeno u #158).
    /// Prázdné pole znamená „nevíme“ a mini diff pak kreslí jen zelenou stranu.
    ///
    /// **Je to jeden řádek, i když návrh nese tři, a je to zapsaná mez.** Kde rozsah vlákna
    /// začíná, `ReviewThread` nedrží (`startLine` se v konverzačním dotazu netahá) — a tvrdit
    /// červeně dva řádky, které jsme si domysleli, je horší než nakreslit ten jeden, o kterém
    /// data mluví. Proto hlavička bloku počítá **nové** řádky, ne nahrazované.
    static func suggestionOriginal(of thread: ReviewThread) -> [String] {
        guard let hunk = thread.diffHunk else { return [] }
        // Poznámky `git`u a hlavička hunku obsah souboru nejsou. Znaménko se strhává, ne řádek:
        // prázdný kontextový řádek přijde jako `" "` nebo prázdný a v obou případech je to
        // prázdný řádek souboru.
        let content = TextLines.content(hunk)
            .filter { !$0.hasPrefix("@@") && !$0.hasPrefix("\\") }
        guard let last = content.last else { return [] }
        guard let first = last.first, first == "+" || first == "-" || first == " " else {
            return [String(last)]
        }
        return [String(last.dropFirst())]
    }

    /// Jak vysoké má být pole komentáře, když v něm návrh je.
    ///
    /// `TextEditor` s obsahem **neroste** (bere výšku, jakou dostane), takže do pole vysokého na
    /// dva řádky se blok se čtyřmi vejde jedině scrollováním — a to je zrovna u návrhu ta nejhorší
    /// možná podoba: přepisují se v něm původní řádky, tedy je potřeba je vidět naráz. Vyšší pole
    /// se nasazuje **jen tam, kde návrh je**; u jednovětého komentáře by zabíralo místo diffu.
    static func draftEditorHeight(hasSuggestion: Bool) -> Double {
        hasSuggestion ? 132 : 54
    }

    /// Popisek nad mini diffem — `návrh · 2 řádky`.
    ///
    /// Počítá **nové** řádky, protože ty návrh nese celé; kolik jich nahrazuje, se u vlákna
    /// neví (viz `suggestionOriginal(of:)`). Návrh bez jediného řádku je mazání, a to se musí
    /// říct slovem — `návrh · 0 řádků` by vypadalo jako prázdný blok.
    static func suggestionLabel(of suggestion: CodeSuggestion) -> String {
        guard !suggestion.replacement.isEmpty else { return "návrh · smazat" }
        return "návrh · " + Plural.czech(
            suggestion.replacement.count,
            one: "řádek",
            few: "řádky",
            many: "řádků"
        )
    }
}
