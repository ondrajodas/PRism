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
/// Čisté funkce, žádné I/O, **nikdy nevyhodí výjimku**.
enum MarkdownHTML {
    /// Je v textu vůbec něco, co by se dalo strhnout? Šetří práci u běžného komentáře,
    /// ve kterém žádné HTML není.
    static func containsMarkup(_ source: String) -> Bool {
        source.contains("<") || source.contains("&")
    }

    static func stripped(_ source: String) -> String {
        guard containsMarkup(source) else { return source }
        var text = source
        text = anchors(in: text)
        text = lineBreaks(in: text)
        text = withoutTags(text)
        return entities(in: text)
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
