import Foundation

/// Sazba Markdownu v číslech — velikosti nadpisů, písmo kódu a mezery mezi bloky (#279).
///
/// **Čisté funkce, žádné view.** Vzniklo to proto, že obojí se dělalo náhodou: nadpisy měly
/// `level <= 2 ? .headline : .subheadline`, tedy **dvě velikosti na šest úrovní** (`#` a `##`
/// vypadaly stejně), a mezi bloky byla jedna mezera pro všechno, takže nadpis uprostřed dlouhého
/// popisu PR neměl nad sebou o nic víc místa než další odstavec — a strukturu nebylo v čem vidět.
///
/// Škála je **poměrová k základní velikosti**, ne tabulka pevných čísel: tentýž Markdown se sází
/// v popisu PR (12,5), v komentáři (12,5) i v okně s novinkami (13), takže by pevná čísla znamenala
/// buď tři tabulky, nebo jednu, která nikde nesedí.
enum MarkdownTypography {
    /// Nadpis podle úrovně.
    ///
    /// Poměry jsou vlastní, ne GitHubovy: GitHub sází na 16 px a `#` má 2×, což by při 12,5 dalo
    /// 25 bodů — do panelu širokého 300 bodů se takový nadpis vejde třikrát a vedle prózy vypadá
    /// jako titulek okna. Škála je proto stlačená (1,7× až 0,9×), ale **monotónní**: každá úroveň
    /// je menší než ta nad ní, což je to, co má úroveň vůbec dělat.
    ///
    /// Krok mezi třetí a pátou úrovní je **schválně roztažený** na celý bod (15 → 13 → 12):
    /// v první verzi #279 byly poměry 1,16× / 1,0× / 0,94×, tedy 14,5 → 12,5 → 11,75, a na
    /// vyrendrované ukázce byly ty tři úrovně od sebe **nerozeznatelné** — což je zrovna ta vada,
    /// kvůli které se škála zaváděla.
    ///
    /// `#` a `##` mají navíc **linku pod sebou**, jako na GitHubu — od třetí úrovně už ne, jinak
    /// by z popisu PR byla mříž.
    static func heading(level: Int, base: Double) -> Heading {
        let level = min(max(level, 1), 6)
        let scale = [1.7, 1.4, 1.2, 1.04, 0.96, 0.9][level - 1]
        return Heading(
            size: round(base * scale * 2) / 2,
            isBold: level <= 2,
            hasRule: level <= 2,
            // Šestá úroveň je na GitHubu tlumená — je to úroveň „skoro popisek“ a bez ztlumení by
            // se od pětky nedala poznat: 11 bodů proti 11,75.
            isMuted: level == 6
        )
    }

    /// Písmo kódu — bloku i inline. O stupeň menší než próza, protože monospace vypadá při stejné
    /// velikosti větší; `max` drží čitelnost, kdyby si někdo řekl o drobnou prózu.
    static func codeSize(base: Double) -> Double {
        max(round((base - 1.5) * 2) / 2, 9)
    }

    /// Mezera **nad** blokem, podle toho, co je před ním.
    ///
    /// Rytmus se řídí přechodem, ne blokem samotným, protože o mezeru jde vždycky mezi dvěma
    /// věcmi: dvě položky seznamu patří k sobě (těsně), nadpis začíná něco nového (volně) a text
    /// pod nadpisem k tomu nadpisu patří (těsně). Jedna mezera pro všechno je přesně to, co dělá
    /// z dlouhého popisu PR jednolitou plochu.
    ///
    /// `nil` znamená první blok — ten mezeru nad sebou mít nesmí, jinak by se sazba odlepila od
    /// horní hrany karty a odsazení kolem by přestalo platit.
    static func spacing(after previous: MarkdownBlock?, before block: MarkdownBlock) -> Double {
        guard let previous else { return 0 }
        // Nadpis potřebuje místo **nad** sebou, ať je vidět, že odděluje. Za to se pod ním
        // utahuje, protože to, co následuje, k němu patří.
        if case .heading = block { return 12 }
        if case .heading = previous { return 4 }
        if isTight(previous), isTight(block) { return 2 }
        return 7
    }

    /// Bloky, které stojí v sérii a mezera mezi nimi je odsazení uvnitř jednoho celku, ne mezi
    /// dvěma. Položky seznamu a řádky tabulky; odstavce ne — ty jsou každý za sebe.
    private static func isTight(_ block: MarkdownBlock) -> Bool {
        switch block {
        case .listItem, .table: true
        default: false
        }
    }

    /// Nadpis v číslech. `isBold` a `hasRule` jdou zvlášť schválně: linka je vlastnost úrovně,
    /// ne řez písma, a kdyby se odvozovala z tučnosti, nešlo by jedno změnit bez druhého.
    struct Heading: Equatable, Sendable {
        let size: Double
        let isBold: Bool
        let hasRule: Bool
        let isMuted: Bool
    }
}
