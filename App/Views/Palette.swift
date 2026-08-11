import SwiftUI

/// Barvy okna podle návrhu (#180).
///
/// Do #180 bralo okno všechno ze systému. Šedá z macOS je ale **neutrální šedá**, kdežto návrh
/// stojí na neutrálech posunutých do modrofialové — tedy do stejné rodiny jako akcent. Rozdíl je
/// malý na jednom prvku a zřetelný na celém okně: systémová paleta vypadá vedle návrhu jako
/// nedodělaná, protože v ní není vidět žádné rozhodnutí.
///
/// **Jeden zdroj pro celou aplikaci.** Barva se nesmí skládat v každém view zvlášť — dvě místa
/// se rozejdou a okno pak má dvě různé „skoro stejné“ šedé. Kdo potřebuje barvu, bere ji odsud.
///
/// Světlá i tmavá varianta se řídí systémem (`Color(light:dark:)` níž), takže se nic nezadrátuje
/// natvrdo do jednoho režimu.
enum Palette {
    /// Pozadí okna — to nejtmavší patro.
    static let background = Color(light: 0xF4F6FA, dark: 0x080A0F)
    /// Plocha, na které leží obsah (seznam, diff, panel).
    static let surface = Color(light: 0xFFFFFF, dark: 0x11141B)
    /// Chrome okna: hlavička, rail, stavový řádek.
    static let chrome = Color(light: 0xF7F9FC, dark: 0x161A23)
    /// Vyvýšená plocha — aktivní záložka, tichý chip.
    static let raised = Color(light: 0xEEF1F7, dark: 0x1C212C)
    /// Linky a obrysy.
    static let line = Color(light: 0xDDE2ED, dark: 0x262C3A)
    /// Jemnější linka — spodní hrana hlavičky, oddělovače uvnitř ploch.
    static let lineSoft = Color(light: 0xE9ECF4, dark: 0x1E2430)

    /// Text: primární, sekundární (popisky, neaktivní záložka), terciární (křížek, datum).
    static let ink = Color(light: 0x131722, dark: 0xE7EAF2)
    static let ink2 = Color(light: 0x5A6379, dark: 0x98A1B5)
    static let ink3 = Color(light: 0x8B93A7, dark: 0x6B7488)

    /// Stavy z palety návrhu (`--ok`, `--crit`) — kapsle stavu PR v hlavičce (#218) a od #279
    /// i `[!TIP]` v sazbě Markdownu.
    ///
    /// **Ne systémová `.green` / `.red`.** Kapsle stavu je plná plocha s textem v barvě podkladu
    /// (`--panel`), a systémová zelená je na to příliš světlá — bílý text na ní není čitelný.
    /// Zelená a červená z diffu se sem naopak tahat nesmí: ty patří přidanému a odebranému
    /// řádku a mají jeden zdroj (`DiffLineView.signColor(of:)`), aby se `+` v řádku nerozešlo
    /// s `+12` v hlavičce nad ním.
    static let ok = Color(light: 0x1A7F37, dark: 0x3FB950)
    static let crit = Color(light: 0xCF222E, dark: 0xF85149)
    /// Nález — puntík revieweera, který něco našel. Vlastní tón mezi `ok` a `crit`, protože
    /// „něco našel“ není porucha: ta je `crit` a od nálezu se musí poznat.
    static let find = Color(light: 0xB4560A, dark: 0xE8944A)

    /// Obrys bubliny blokujícího nálezu u kódu (#185) — `color-mix(in srgb, crit 35 %, line)`
    /// z návrhu, vyčíslené.
    ///
    /// **Ne `crit.opacity(0.35)`**: skrz krytí prosvítá to, na čem obrys leží, takže by se barva
    /// měnila podle podkladu — a bublina visí střídavě nad přidaným řádkem (zelený), odebraným
    /// (červený) i kontextem. Mix je jedna barva, která vyjde všude stejně.
    static let critLine = Color(light: 0xD89FAA, dark: 0x70393F)

    /// Zastarání — force push, nálezy proti staré hlavě, vlákno bez místa v dnešním diffu.
    ///
    /// Vlastní token, ne `.orange` (#216): systémová oranžová je **výstraha**, kdežto `--stale`
    /// z návrhu je okrová a znamená „platilo to, dneska už ne“. Vedle červené blokujícího nálezu
    /// se ty dvě systémové barvy pletly do jedné škály naléhavosti, kterou zastarání nemá.
    static let stale = Color(light: 0x9A6700, dark: 0xD4A72C)

    /// Výstrahy z GitHubu (#279) — `> [!NOTE]` a spol. **Tři vlastní tóny, dva vypůjčené.**
    ///
    /// `[!TIP]` bere `ok` (rada je pozitivní sdělení a zelená v okně neznamená nic, co by radě
    /// odporovalo) a `[!IMPORTANT]` bere `accent` (akcent je barva, kterou okno upozorňuje na to
    /// své). Zbylé tři mají vlastní hex, protože GitHub jim dává přesně ty barvy, které v tomhle
    /// okně **už něco znamenají**:
    ///
    /// - `[!WARNING]` je na GitHubu `0x9A6700`, což je **na hex shodné se `stale`**. Zastarání
    ///   znamená „platilo to, dneska už ne“, kdežto výstraha „pozor na tohle“ — se stejným tónem
    ///   by okrový rámeček v komentáři vypadal jako zastaralý obsah. `alertWarning` je proto
    ///   světlejší, žlutější amber.
    /// - `[!CAUTION]` je na GitHubu `0xCF222E`, tedy **na hex shodné s `crit`**. Červená v okně
    ///   patří blokujícímu nálezu, takže se pro caution bere purpurová: pořád naléhavá, ale
    ///   nezaměnitelná s tím, co review blokuje.
    /// - `[!NOTE]` je modrá a modrou okno jinde nemá, takže se nemá s čím splést.
    ///
    /// Druh výstrahy nese navíc **ikonu a titulek** (`MarkdownAlertStyle`), takže význam nestojí
    /// jen na barvě.
    static let alertNote = Color(light: 0x0969DA, dark: 0x4493F8)
    static let alertWarning = Color(light: 0xBF8700, dark: 0xE3B341)
    static let alertCaution = Color(light: 0xBF3989, dark: 0xDB61A2)

    /// Podklad kódu v sazbě Markdownu (#279) — inline `kód` i blok mezi ` ``` `.
    ///
    /// **Průhledná, a to schválně** — na rozdíl od `critLine`, kde je krytí zakázané. Tam jde
    /// o obrys nad střídavě zeleným a červeným řádkem, tady o podklad uvnitř prózy, pod kterým je
    /// vždycky jedna plocha (`chrome` u komentáře, `surface` u popisu). Průhlednost je tu naopak
    /// to, co drží podklad jemný v obou režimech: 6 % inkoustu na světlém, 10 % na tmavém.
    static let codeFill = Color(light: 0x131722, lightAlpha: 0.06, dark: 0xE7EAF2, darkAlpha: 0.1)

    /// Akcent. **Fialová z návrhu, ne systémový akcent**: je to jediná barva, kterou si okno
    /// drží samo, protože na ní stojí identita aplikace (hranol, spektrum) — a spektrum
    /// reviewerů by se systémovým akcentem měnilo význam podle nastavení systému.
    static let accent = Color(light: 0x5B47E0, dark: 0x8B7CFF)
    /// Tichý podklad akcentu — živá šipka procházení nálezů (#219).
    ///
    /// **Ne `accent.opacity(…)`**: návrh má v tmavém režimu jiné krytí (14 %) než ve světlém
    /// (10 %), protože tatáž průhlednost vyjde na tmavém podkladu slabší. Jedno číslo pro obojí
    /// by v jednom z režimů zmizelo.
    static let accentWeak = Color(light: 0x5B47E0, lightAlpha: 0.1, dark: 0x8B7CFF, darkAlpha: 0.14)
    /// Druhý konec přechodu — zatím jediný, proužek nad kartou rozdělaných review (#181).
    /// **Nikdy jako samostatná barva**: dvě akcentové barvy vedle sebe by přestaly znamenat stav.
    static let accent2 = Color(light: 0x128FB0, dark: 0x45C8E4)
}

extension Color {
    /// Barva ze dvou hexů — pro světlý a tmavý režim.
    ///
    /// Přes `NSColor(name:dynamicProvider:)`, protože jen ten se přepne **za běhu**, když si
    /// člověk režim přepne v systému. `Color(uiColor:)` obdoba na macOS není a dvě konstanty
    /// s `@Environment(\.colorScheme)` by znamenaly, že barvu musí řešit každé view zvlášť.
    /// Krytí je u obou režimů zvlášť: návrh míchá tiché podklady (`--accent-weak`) v každém
    /// režimu jinak, protože tatáž průhlednost vyjde na tmavém podkladu slabší.
    init(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

extension NSColor {
    /// `0xRRGGBB` na barvu. Alfa je zvlášť, protože hex ji nenese — plné barvy palety ji
    /// nechávají na jedničce.
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
