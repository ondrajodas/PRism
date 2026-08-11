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

    /// Stavy z palety návrhu (`--ok`, `--crit`) — kapsle stavu PR v hlavičce (#218) a od #277
    /// i **zelená a červená celého diffu**.
    ///
    /// **Ne systémová `.green` / `.red`.** Kapsle stavu je plná plocha s textem v barvě podkladu
    /// (`--panel`), a systémová zelená je na to příliš světlá — bílý text na ní není čitelný.
    ///
    /// **Diff si je od #277 bere taky** — přes `DiffLineView.signColor(of:)`, tedy pořád jeden
    /// zdroj, aby se `+` v řádku nerozešlo s `+12` v hlavičce nad ním. **Změna proti #218**, kde
    /// stálo, že se sem zelená a červená z diffu tahat nesmí, protože tokeny jsou pro odznaky
    /// a puntíky. Otočilo to měření: systémová zelená měla ve světlém režimu na znaku `+` kontrast
    /// **2,01** proti pozadí přidaného řádku a **2,22** na ploše hlavičky, tedy pod hranicí
    /// čitelnosti; `ok` má na týchž místech **4,60** a **5,08**. V tmavém režimu je to výměna
    /// 7,42 → 5,95, tedy pořád s velkou rezervou. Dvě sady barev z toho nevznikly — je to naopak
    /// o jednu méň.
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

    /// Pozadí přidaného a odebraného řádku diffu, jeho word-level vrstvy (#153) a prázdného
    /// protějšku v pohledu vedle sebe (#277).
    ///
    /// **Ne `.green.opacity(0.12)`**, jak to bylo do #277 — tedy tentýž důvod jako u `critLine`
    /// o pár řádků výš: skrz krytí prosvítá podklad, takže barva **není hodnota, ale výsledek**.
    /// Tady to bylo vidět v tmavém režimu, kde se systémová zelená mísí směrem k černé: plocha
    /// přidaného bloku vycházela `#152B22`, tedy tmavý obdélník, ze kterého „přidáno“ nebylo
    /// poznat. Hodnoty jsou proto vyčíslené, zvlášť pro každý režim.
    ///
    /// **Tmavá vznikla mixem `ok`/`crit` do černé, ne do plochy** (24 % u přidaného, 22 %
    /// u odebraného). Rozhodlo měření a stojí na tom, že WCAG kontrast textu závisí **jen na
    /// světlosti**, kdežto odlišení plochy roste i se **sytostí** (ΔE2000). Sytější tón při téže
    /// světlosti tedy odliší plochu a text nad ní nechá na pokoji — proti mixu do plochy
    /// (`#1B3827`) vychází stejné odlišení při ΔE 21,0, ale řetězec Darculy na něm spadne na 3,17
    /// místo 3,76.
    ///
    /// | tmavý režim | ΔE proti ploše | přidaný ↔ odebraný | řetězec | klíč. slovo |
    /// |---|---|---|---|---|
    /// | do #277 (`#152B22` / `#2E1A20`) | 16,0 / 13,2 | 28,9 | 3,73 | 4,50 |
    /// | od #277 (`#0F2C13` / `#371210`) | 21,8 / 19,7 | 36,8 | 3,76 | 4,53 |
    ///
    /// **Světlá zůstala na hodnotách, které vycházely dosud** (`#E7F8EB` / `#FFE7E8`, tedy složený
    /// výsledek dvanáctiprocentní systémové zelené nad bílou). Není to opomenutí: přepočet z `ok`
    /// do bílé vyjde na obou mírách **horší** (ΔE 10,1 → 8,3 a řetězec 4,82 → 4,52), protože `ok`
    /// je pro světlý režim tmavá zelená a nad bílou z ní je šedozelená. Světlý režim se tím nemá jak
    /// zhoršit: na renderu se plocha liší o **jednu až dvě hodnoty z 255** — skládání krytí
    /// v renderu není tentýž výpočet jako v gamma prostoru, takže na hodnotu to nesedne, ale pod
    /// rozdílem, který jde vidět, to je.
    static let diffAdded = Color(light: 0xE7F8EB, dark: 0x0F2C13)
    static let diffRemoved = Color(light: 0xFFE7E8, dark: 0x371210)

    /// Word-level vrstva (#153): **druhá vrstva nad pozadím řádku**, ne jiná barva písma.
    ///
    /// Sytější tón téže barvy — změněný kus se má lišit od zbytku **svého** řádku. Do #277 to bylo
    /// krytí 50 % nad řádkem, což v tmavém režimu dávalo `#227E3D`: plocha na první pohled jiná
    /// (ΔE 29,5), ale **obarvení syntaxe pod ní zmizelo** — řetězec Darculy na ní měl kontrast
    /// **1,27**, tedy text k nepřečtení právě na tom slově, kvůli kterému se člověk kouká.
    ///
    /// | tmavý režim | ΔE proti řádku | řetězec | klíč. slovo |
    /// |---|---|---|---|
    /// | do #277 (`#227E3D` / `#962E33`) | 29,5 / 24,4 | 1,27 / 1,91 | 1,53 / 2,30 |
    /// | od #277 (`#205D28` / `#7C2925`) | 16,1 / 15,5 | 1,97 / 2,37 | 2,37 / 2,86 |
    ///
    /// **Je to vědomá výměna**: vrstva je méně hlasitá, zato se pod ní dá číst. Odlišení zůstává
    /// nad hranicí „na první pohled jiná plocha“ (ΔE 16 z 10) a proti **ploše** okna je ten kus
    /// vzdálený ΔE 35, protože pozadí řádku pod ním zesílilo. Světlá varianta se nemění.
    static let diffAddedWord = Color(light: 0x8DE0A2, dark: 0x205D28)
    static let diffRemovedWord = Color(light: 0xFF9092, dark: 0x7C2925)

    /// Prázdný protějšek dvojice v pohledu vedle sebe (#277) — tam, kde na téhle straně řádek
    /// **není**.
    ///
    /// Do #277 se v bloku kódu nekreslil vůbec, takže „tady řádek není“ bylo od „řádek se
    /// nezměnil“ k nerozeznání (ΔE 0,0 — tatáž plocha). Plocha je proto **tmavší** než plocha
    /// obsahu, ne světlejší: co v souboru je, leží nad podkladem, kdežto díra je podklad sám
    /// (hodnota je `background`, tedy nejtmavší patro okna).
    ///
    /// **Sama plocha na to ale nestačí** a je to změřené: v tmavém režimu je od plochy vzdálená
    /// jen ΔE 3,3, protože pod `surface` už není kam ztmavovat. Rozhoduje proto **šrafa**
    /// (`DiffMissingHatch`), tedy odlišení **texturou** místo světlostí — pruh je od plochy díry
    /// vzdálený ΔE 11,3. Zesvětlit plochu by šlo, jen by tím díra začala křičet hlasitěji než
    /// přidaný řádek vedle ní (ΔE 7,3 u `#242A36`), a to je obrácená hierarchie.
    static let diffMissing = Color(light: 0xF4F6FA, dark: 0x080A0F)
    /// Pruh šrafy prázdného protějšku. Hodnota je `line`, tedy barva obrysů — díra je prázdné
    /// místo, ne plocha se stavem, takže si vlastní tón nezaslouží.
    static let diffMissingStripe = Color(light: 0xDDE2ED, dark: 0x262C3A)

    /// Zastarání — force push, nálezy proti staré hlavě, vlákno bez místa v dnešním diffu.
    ///
    /// Vlastní token, ne `.orange` (#216): systémová oranžová je **výstraha**, kdežto `--stale`
    /// z návrhu je okrová a znamená „platilo to, dneska už ne“. Vedle červené blokujícího nálezu
    /// se ty dvě systémové barvy pletly do jedné škály naléhavosti, kterou zastarání nemá.
    static let stale = Color(light: 0x9A6700, dark: 0xD4A72C)

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
