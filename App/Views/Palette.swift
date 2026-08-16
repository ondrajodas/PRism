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
/// Světlá i tmavá varianta se řídí **vzhledem, ve kterém se zrovna kreslí** (`Color(light:dark:)`
/// níž), takže se nic nezadrátuje natvrdo do jednoho režimu. Ten vzhled je od #278 buď systémový,
/// nebo vynucený přepínačem v railu — pro paletu je to jedno a **musí to tak zůstat**:
/// přepínač volí režim, ne barvy, takže tady kvůli němu nepřibývá žádné větvení.
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

    /// Stavy z palety návrhu (`--ok`, `--crit`) — kapsle stavu PR v hlavičce (#218), souhrn checků
    /// (#215), `[!TIP]` v sazbě Markdownu (#279) a od #277 i **zelená a červená celého diffu**.
    ///
    /// **Ne systémová `.green` / `.red`.** Kapsle stavu je plná plocha s textem v barvě podkladu
    /// (`--panel`), a systémová zelená je na to příliš světlá — bílý text na ní není čitelný.
    ///
    /// **Diff si je od #277 bere taky** — přes `DiffLineView.signColor(of:)`, tedy pořád jeden
    /// zdroj, aby se `+` v řádku nerozešlo s `+12` v hlavičce nad ním. **Změna proti #218**, kde
    /// stálo, že se sem zelená a červená z diffu tahat nesmí, protože tokeny jsou pro odznaky
    /// a puntíky. Otočilo to měření: systémová zelená měla ve světlém režimu na znaku `+` kontrast
    /// **2,01** proti pozadí přidaného řádku a **2,22** na ploše hlavičky, tedy pod hranicí
    /// čitelnosti; `ok` má na týchž místech **4,65** a **5,08**. V tmavém režimu je to výměna
    /// 7,42 → 5,95, tedy pořád s velkou rezervou. Dvě sady barev z toho nevznikly — je to naopak
    /// o jednu méně.
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

    /// Pozadí přidaného a odebraného řádku diffu (#277) — `--add-bg` a `--del-bg` z návrhu.
    ///
    /// **Ne `.green.opacity(0.12)`**, jak to bylo do #277 — tedy tentýž důvod jako u `critLine`
    /// o pár řádků výš: skrz krytí prosvítá podklad, takže barva **není hodnota, ale výsledek**.
    /// Bylo to vidět v tmavém režimu, kde se systémová zelená mísí směrem k černé: plocha přidaného
    /// bloku vycházela `#152B22`, tedy tmavý obdélník, ze kterého „přidáno“ nebylo poznat.
    ///
    /// **Světlá je z návrhu doslova** (`--add-bg: #E3FBE8`, `--del-bg: #FFEBE9`) a měřením vyšla
    /// lépe než to, co v aplikaci vycházelo ze skládání: odlišení od plochy ΔE 13,0 proti 10,1
    /// u přidaného a řetězec IntelliJ Light 4,86 proti 4,81. U odebraného je ΔE 8,9 proti 10,6, zato
    /// řetězec 4,63 proti 4,52 — a rozhoduje návrh, ne o dvě desetiny lepší číslo.
    ///
    /// **Tmavá je vědomá odchylka od návrhu** a je to celý důvod, proč #277 vzniklo: návrh má
    /// v tmavém režimu `rgba(63, 185, 80, 0.13)`, tedy `ok` s krytím — a to nad `panel` složí
    /// `#172922`, čímž **reprodukuje přesně tu stížnost** (ΔE 14,6, tedy ještě o kus slabší než
    /// systémová zelená, kterou aplikace měla). Hodnota je proto vyčíslená a vznikla mixem
    /// `ok`/`crit` **do černé**, ne do plochy (24 % u přidaného, 22 % u odebraného). Sám mockup se
    /// u toho **nepřekresluje potichu** — návrh schvaluje uživatel (#286), takže se ta čtyři tmavá
    /// `rgba` nabízejí k překreslení, ne mění; do té doby drží odchylku tenhle komentář a záznam
    /// rozhodnutí ve specifikaci.
    ///
    /// Stojí to na jednom pozorování: WCAG kontrast textu závisí **jen na světlosti**, kdežto
    /// odlišení plochy roste i se **sytostí** (ΔE2000) — sytější tón při téže světlosti tedy odliší
    /// plochu a text nad ní nechá na pokoji. Proti mixu do plochy (`#1B3827`) vychází stejné
    /// odlišení, ale řetězec Darculy na něm spadne na 3,17 místo 3,76.
    ///
    /// | tmavý režim | ΔE proti ploše | přidaný ↔ odebraný | řetězec | klíč. slovo |
    /// |---|---|---|---|---|
    /// | návrh (`rgba(ok, 0.13)` → `#172922`) | 14,6 / 13,0 | 26,3 | 3,78 | 4,56 |
    /// | do #277 (`#152B22` / `#2E1A20`) | 16,0 / 13,2 | 28,9 | 3,73 | 4,50 |
    /// | od #277 (`#0F2C13` / `#371210`) | 21,8 / 19,7 | 36,8 | 3,76 | 4,53 |
    static let diffAdded = Color(light: 0xE3FBE8, dark: 0x0F2C13)
    static let diffRemoved = Color(light: 0xFFEBE9, dark: 0x371210)

    /// Word-level vrstva (#153) — `--add-hi` a `--del-hi` z návrhu: **druhá vrstva nad pozadím
    /// řádku**, ne jiná barva písma.
    ///
    /// **Světlá je z návrhu doslova** (`#ABEFC0` / `#FFC9C6`) a je na obou mírách lepší než to, co
    /// v aplikaci vycházelo z krytí 50 %: řetězec 4,01 proti 3,37 u přidaného a 3,65 proti 2,44
    /// u odebraného, při ΔE 12,0 a 11,4 proti svému řádku.
    ///
    /// **Tmavá drží pravidlo návrhu, ne jeho hodnotu**: `--add-hi` je `ok` na 30 % nad pozadím
    /// řádku, a to pozadí se u #277 změnilo (viz `diffAdded`), takže se přepočítalo — `#1D5625` je
    /// právě těch 30 % nad novým řádkem. Do #277 to bylo krytí **50 %** nad slabším pozadím, což
    /// dávalo `#227E3D`: plocha na první pohled jiná (ΔE 29,5), ale **obarvení syntaxe pod ní
    /// zmizelo** — řetězec Darculy měl kontrast **1,27**, tedy text k nepřečtení právě na tom
    /// slově, kvůli kterému se člověk kouká.
    ///
    /// | tmavý režim | ΔE proti řádku | řetězec | klíč. slovo |
    /// |---|---|---|---|
    /// | do #277 (`#227E3D` / `#962E33`) | 29,5 / 24,4 | 1,27 / 1,91 | 1,53 / 2,30 |
    /// | od #277 (`#1D5625` / `#712521`) | 13,9 / 13,2 | 2,16 / 2,63 | 2,60 / 3,17 |
    ///
    /// **Je to vědomá výměna**: vrstva je méně hlasitá, zato se pod ní dá číst. Odlišení zůstává nad
    /// hranicí „na první pohled jiná plocha“ (ΔE 13,9 z 10 potřebných) a proti **ploše** okna je ten
    /// kus vzdálený ΔE 33, protože pozadí řádku pod ním zesílilo.
    static let diffAddedWord = Color(light: 0xABEFC0, dark: 0x1D5625)
    static let diffRemovedWord = Color(light: 0xFFC9C6, dark: 0x712521)

    /// Šrafa prázdného protějšku dvojice v pohledu vedle sebe (#277) — tam, kde na téhle straně
    /// řádek **není**.
    ///
    /// Do #277 se v bloku kódu nekreslilo nic, takže „tady řádek není“ bylo od „řádek se nezměnil“
    /// k nerozeznání — tatáž plocha, ΔE 0,0. Návrh na to má šrafu
    /// (`repeating-linear-gradient(45deg, …)` u `tr.empty-side`) a nese ji **textura, ne plocha**:
    /// pod plochou obsahu už v tmavém režimu není kam ztmavovat a zesvětlit ji znamená, že díra
    /// křičí hlasitěji než změna vedle ní.
    ///
    /// Hodnota je `ink` na 5 % z návrhu, ale **vyčíslená** — díra leží vždycky na `surface`, takže
    /// složený výsledek je přesný a nezávisí na podkladu. Pruh je od plochy vzdálený ΔE 2,5 ve
    /// světlém a 3,4 v tmavém režimu; nese to **rozestup** (pruh 5 bodů, mezera 5 bodů), ne
    /// kontrast — polovina plochy, na které se textura pozná i u jediného řádku. Geometrii drží
    /// `DiffMissingHatch`.
    static let diffMissingStripe = Color(light: 0xF3F3F4, dark: 0x1C1F26)

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

    /// Konstatování — **stav, se kterým se nic nedělá** (#309). `--mint` z návrhu.
    ///
    /// Dvojice k akcentu, a je to celý důvod, proč token vznikl: v řádku tabulky nálezů stojí
    /// vedle sebe věci, na které se **klikne** (`Převzít`, `Vrátit`, `⋯`), a věci, které se jen
    /// **čtou** (`2×`, `✓ v mém review`). Do #309 měly obojí barvu akcentu, takže se na odznak
    /// shody dvou reviewerů dalo zkoušet klikat. Dělí je proto barva:
    ///
    /// - **`accent`** = co aplikace nabízí udělat, nebo co zrovna dělá (akce, běžící review,
    ///   živý řádek, aktivní záložka);
    /// - **`mint`** = co aplikace tvrdí, že platí (odznak shody, převzatý nález, odmítnuté
    ///   review).
    ///
    /// Návrh to nese stejně a **nikde jinde mint nemá**: `.pill.mint` u `2×` a `.frow .acts .in`
    /// u `✓ v mém review` jsou jeho jediné dva výskyty na celé stránce. Mint proto **není barva
    /// stavů obecně** — běžící review je v návrhu `.pill.run`, tedy akcent.
    ///
    /// **Ne `accent.opacity(…)`** — tatáž úvaha jako u `critLine` a `diffAdded`: skrz krytí
    /// prosvítá podklad, takže by odznak vyšel jinak na ploše řádku než na podbarveném živém
    /// řádku.
    ///
    /// **Tmavá je z návrhu doslova** (`--mint: #2DD4BF`) a měřením vychází jako nejčitelnější
    /// token v celé rodině: 9,90 na ploše řádku proti 7,25 u `ok` a 5,64 u akcentu.
    ///
    /// **Světlá je vědomá odchylka od návrhu** (`--mint: #0E8F80` → `#0C7E71`, ΔE 6,2). Hodnota
    /// z návrhu měla na ploše řádku kontrast **3,99**, a byla tím **jediným** stavovým tokenem
    /// pod hranicí AA 4,5: `ok` má 5,08, `crit` 5,36, `find` 4,91, `stale` 4,87, akcent 6,14.
    /// Odznak stavu by tak byl to nejsvětlejší v řádku — zrovna ten, který má říct, že se s tím
    /// nic dělat nemusí, by se četl hůř než všechno kolem. Ztmavení je proto **na rodinu, ne na
    /// hranici**: na všech čtyřech podkladech vychází do 0,05 stejně jako `find` vedle něj
    /// (4,95 / 4,70 / 4,29 / 4,06 proti 4,91 / 4,66 / 4,25 / 4,02).
    ///
    /// Mockup se u toho **nepřekresluje potichu** — návrh schvaluje uživatel (#286), takže se
    /// `--mint` ve světlé větvi nabízí k překreslení (#299), a do té doby drží odchylku tenhle
    /// komentář a záznam rozhodnutí ve specifikaci.
    ///
    /// **Ne systémová `.mint`**, kterou do #309 brala `ReviewStateAppearance` na odmítnuté review.
    /// Byly by to dvě tyrkysové pro jedno sdělení — a k tomu ta nejhorší možná dvojice: v tmavém
    /// režimu je systémová (`#00DAC3`) od tokenu vzdálená **ΔE 1,6**, tedy k nerozeznání, kdežto
    /// ve světlém (`#00C8B3`) ΔE 22,9. Odmítnuté review by tak vypadalo jednou stejně a jednou
    /// jinak než ostatní tyrkysová v okně. Ta světlá je navíc **nečitelná**: kontrast **2,12**
    /// proti ploše řádku, kdežto token má 4,95.
    ///
    /// **Nesplyne s tím, co v okně už něco znamená**: proti `ok` (prošlý check) ΔE 16,6 světlá /
    /// 21,1 tmavá, proti `stale` (zastarání) 37,9 / 39,4. Všechna čísla drží `MintTokenTests`.
    static let mint = Color(light: 0x0C7E71, dark: 0x2DD4BF)
}

extension Color {
    /// Barva ze dvou hexů — pro světlý a tmavý režim.
    ///
    /// Přes `NSColor(name:dynamicProvider:)`, protože jen ten se přepne **za běhu** — když si
    /// člověk režim přepne v systému, i když si ho od #278 vynutí v railu (`NSApp.appearance`;
    /// uzávěr se ptá na vzhled, ne na systém, takže mu je jedno, odkud přišel).
    /// `Color(uiColor:)` obdoba na macOS není a dvě konstanty
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
