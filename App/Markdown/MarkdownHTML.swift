import Foundation

/// Inline HTML z komentářů na GitHubu na text, kterému rozumí Markdown.
///
/// GFM povoluje HTML a **boti ho používají pořád** — `linear-code` posílá `<details>`,
/// `<summary>`, `<p>` a `<a href>`, Dependabot totéž. Bez tohohle se v okně místo komentáře
/// ukazují surové tagy, což je nejhorší ze všech možností: text tam je, ale nedá se číst.
///
/// Odkazy se **převádějí**, ne zahazují: `<a href="u">t</a>` → `[t](u)`, takže z nich
/// `AttributedString` udělá klikatelný odkaz. Ostatní tagy jdou pryč, protože jejich význam
/// (`<p>`, `<b>`) se v okně nemá čím projevit a `<div>` už vůbec.
///
/// **Inline kód se nechává být.** `Array<T>` mezi zpětnými apostrofy není tag a ztratit ho
/// znamená ztratit zrovna to, o čem kolega píše nejčastěji.
///
/// Čisté funkce, žádné I/O, **nikdy nevyhodí výjimku**.
enum MarkdownHTML {
    /// Je v textu vůbec něco, co by se dalo strhnout? Šetří práci u běžného komentáře,
    /// ve kterém žádné HTML není.
    static func containsMarkup(_ source: String) -> Bool {
        source.contains("<") || source.contains("&")
    }

    /// Strhne HTML — ale **jen mimo inline kód**.
    ///
    /// Text mezi zpětnými apostrofy je kód a `Array<T>` nebo `Result<OK, Err>` v něm není tag.
    /// Bez téhle výjimky by z komentáře zmizely generické typy, tedy zrovna to, o čem kolega
    /// nejčastěji píše — a v okně by stálo něco jiného, než co napsal.
    static func stripped(_ source: String) -> String {
        guard containsMarkup(source) else { return source }
        return segments(of: source)
            .map { segment in segment.isCode ? segment.text : plain(segment.text) }
            .joined()
    }

    private static func plain(_ source: String) -> String {
        guard containsMarkup(source) else { return source }
        var text = source
        text = anchors(in: text)
        text = lineBreaks(in: text)
        text = withoutTags(text)
        return entities(in: text)
    }

    /// Rozdělí text na kusy kódu a kusy prózy — **včetně samotných apostrofů**, takže spojením
    /// vyjde původní text.
    ///
    /// Pravidlo je Markdownové: kód otevírá běh zpětných apostrofů a zavírá ho běh **stejné
    /// délky** (proto ` ``x`` ` unese apostrof uvnitř). Neuzavřený běh kódem není — apostrof
    /// v běžné větě se stane, a spolknout kvůli němu půl komentáře je horší než neošetřený tag.
    private static func segments(of source: String) -> [(text: String, isCode: Bool)] {
        var result: [(text: String, isCode: Bool)] = []
        var prose = ""
        var rest = Substring(source)

        while let start = rest.firstIndex(of: "`") {
            let fence = rest[start...].prefix(while: { $0 == "`" })
            let afterFence = rest[fence.endIndex...]

            guard let closing = closingRun(of: fence.count, in: afterFence) else {
                // Neuzavřený běh: bere se jako obyčejný text a pokračuje se za ním.
                prose += rest[..<fence.endIndex]
                rest = afterFence
                continue
            }

            prose += rest[..<start]
            result.append((prose, false))
            prose = ""
            result.append((String(rest[start..<closing.upperBound]), true))
            rest = rest[closing.upperBound...]
        }

        result.append((prose + rest, false))
        return result
    }

    /// Rozsah zavíracího běhu o dané délce, nebo `nil`, když v textu není.
    private static func closingRun(of length: Int, in text: Substring) -> Range<Substring.Index>? {
        var index = text.startIndex
        while let start = text[index...].firstIndex(of: "`") {
            let run = text[start...].prefix(while: { $0 == "`" })
            if run.count == length { return start..<run.endIndex }
            index = run.endIndex
            guard index < text.endIndex else { return nil }
        }
        return nil
    }

    /// `<a href="…">text</a>` → `[text](…)`.
    ///
    /// Jednoduché uvozovky i bez uvozovek se řeší taky — bot si formát vybírá sám a rozdíl
    /// mezi `href="x"` a `href='x'` nemá rozhodovat o tom, jestli je odkaz klikatelný.
    private static func anchors(in source: String) -> String {
        let pattern = /<a\b[^>]*?href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>(.*?)<\/a\s*>/
            .ignoresCase()
        return source.replacing(pattern) { match in
            let url = match.output.1 ?? match.output.2 ?? match.output.3 ?? ""
            let text = withoutTags(String(match.output.4))
            // Odkaz bez textu by v Markdownu zmizel úplně, takže se z něj stane holá URL.
            return text.isEmpty ? String(url) : "[\(text)](\(url))"
        }
    }

    private static func lineBreaks(in source: String) -> String {
        source.replacing(/<br\s*\/?>/.ignoresCase(), with: "\n")
    }

    private static func withoutTags(_ source: String) -> String {
        source.replacing(/<[^>]+>/, with: "")
    }

    /// Jen ty entity, které v komentářích opravdu chodí. Úplná tabulka by byla slovník
    /// o stovkách položek pro text, ve kterém se objeví pětkrát do roka.
    ///
    /// `&amp;` se dekóduje **naposled**, jinak by z `&amp;lt;` vyšlo `<` místo `&lt;`.
    private static func entities(in source: String) -> String {
        var text = source
        for (entity, character) in [
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
        ] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.replacingOccurrences(of: "&amp;", with: "&")
    }
}
