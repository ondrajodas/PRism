import Foundation

/// Kus kódu, ke kterému se vlákno váže — konec `diffHunk`u z GitHubu (#158).
///
/// **Poslední řádek je ten komentovaný.** GitHub posílá hunk od začátku po komentovaný řádek,
/// takže kontext je jenom **před** ním (změřeno na `cli/cli#13084`, všech 38 vláken, na obou
/// stranách diffu). Pět řádků za komentářem, jak chtělo zadání #158, by se dalo dopočítat
/// jedině ze souboru na `originalCommit.oid` — tedy novou čtecí metodou gateway, kterou dnešní
/// `fetchFile(id:path:)` není (čte dnešní hlavu PR). Vlastní cena, vlastní rozhodnutí; kontext
/// před řádkem je zdarma a je to totéž, co ukazuje GitHub ve svém zabaleném vlákně.
struct ThreadSnippet: Hashable, Sendable {
    /// Řádky k vykreslení, v pořadí, jak jsou v souboru. Nikdy prázdné — prázdný úryvek se
    /// vůbec nevyrobí (`Policy.snippet(of:)` vrátí `nil`), aby v `Přehledu` nevznikl rámeček
    /// bez obsahu.
    let lines: [DiffLine]
    /// Zbylo z hunku něco, co není vidět? Musí to být poznat: ze sta devadesáti řádků se
    /// ukazuje šest, a úryvek, který vypadá jako celý kontext, tvrdí víc, než unese — tatáž
    /// kategorie jako `ConversationPage.isTruncated`.
    let isTruncated: Bool
}

extension Policy {
    /// Kolik řádků kontextu **před** komentovaným řádkem se ukáže.
    ///
    /// Pět podle zadání #158. Medián hunku je 190 řádků (změřeno), takže vykreslit ho celý
    /// nejde — komentář by se v kódu utopil a v `Přehledu` by na jedno vlákno padla obrazovka.
    static let threadSnippetContext = 5

    /// Úryvek kódu k vláknu, nebo `nil`, když se nemá z čeho vzít.
    ///
    /// `nil` znamená „vykresli vlákno jako dřív, bez kódu“ — u vlákna, kterému `diffHunk`
    /// nedorazil (starší odpověď), a u hunku, ze kterého parser nevytáhl ani jeden řádek.
    /// Prázdný rámeček by tvrdil, že kontext je prázdný, což je jiná věc než „nevíme“.
    ///
    /// **Hunk se obaluje syntetickou hlavičkou souboru.** `DiffParser` zařazuje řádky podle
    /// stavu a před první `diff --git` hlavičkou nemá řádek kam patřit — samotný `@@` blok by
    /// tedy celý spadl do `unrecognizedLines`. Parser se kvůli tomu **neupravuje**: na jeho
    /// invariantu „nerozpoznaný řádek se počítá“ visí důvěra v celý diff, takže obalit vstup
    /// je levnější než oslabit kontrolu.
    ///
    /// Zkracuje se **až tady, ne při mapování odpovědi**: kolik řádků je vidět, je rozhodnutí,
    /// a to patří na jedno místo, kde se dá změnit bez zásahu do modelu.
    static func snippet(of thread: ReviewThread, context: Int = threadSnippetContext) -> ThreadSnippet? {
        guard let hunk = thread.diffHunk, !hunk.isEmpty else { return nil }

        let diff = DiffParser.parse(synthesizedDiff(of: hunk, path: thread.path))
        let lines = diff.files.flatMap { $0.hunks.flatMap(\.lines) }
        guard !lines.isEmpty else { return nil }

        // `max(1, …)`, ne `context + 1`: záporný kontext by `suffix(_:)` **položil** (má na to
        // precondition), a `lines` má být podle typu vždycky neprázdné. Nejmenší smysluplný
        // úryvek je samotný komentovaný řádek, takže tam se to srazí.
        let shown = lines.suffix(max(1, context + 1))
        return ThreadSnippet(
            lines: Array(shown),
            // Nerozpoznaný řádek se počítá jako zkrácení: úryvek pak není spojitý kus souboru
            // a tvrdit u něj „tohle je celý kontext“ by bylo nepravdivé. Bezpečný směr je
            // jediný — přiznat, že něco chybí.
            isTruncated: shown.count < lines.count || diff.unrecognizedLines > 0
        )
    }

    /// Hunk jako diff jednoho souboru.
    ///
    /// Stačí **hlavička `diff --git`**, žádné `---`/`+++`: jediné, co parser potřebuje, je vědět,
    /// že soubor začal, a cesty z hlavičky pak nikdo nečte — jazyk na obarvení se bere z vlákna
    /// (`ThreadSnippetView`). Dva řádky navíc kvůli údaji, který se nikam nedostane, by byly
    /// mrtvá váha. Cesta se do hlavičky přesto píše ta pravá, ať syntetický diff popisuje týž
    /// soubor jako hunk sám.
    ///
    /// **Řádkové zlomy z cesty se musí zahodit.** Cestu určuje autor PR a git jméno souboru
    /// s `\n` unese, takže bez toho by šlo do hlavičky propašovat další řádky diffu — třeba
    /// vlastní `@@` blok — a v `Přehledu` by se ukázal kód, který v souboru není. Placeholder
    /// místo cesty by hrozbu zavřel taky, ale nechal by v `FileDiff` nesmyslnou cestu jako past
    /// pro toho, kdo by ji jednou chtěl číst.
    private static func synthesizedDiff(of hunk: String, path: String) -> String {
        "diff --git a/\(oneLine(path)) b/\(oneLine(path))\n\(hunk)"
    }

    /// Text bez řádkových zlomů — tentýž postup, jakým si hlavička bubliny krátí komentář
    /// na jeden řádek.
    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
