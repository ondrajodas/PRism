import Foundation

/// Tělo jedné události po ořezu na strop (#327).
struct RawSessionBody: Equatable, Sendable {
    /// Co se ukáže. `nil` = tělo je prázdné, takže se nekreslí vůbec.
    let text: String?
    /// Přiznání ořezu na místě, kde nastal. `nil` = neořezalo se.
    let cut: String?
}

extension Policy {
    /// Okno, ve kterém se transcript ukazuje: **poslední 4 MB**, zarovnané na začátek řádku.
    ///
    /// **Bajty, ne řádky, a je to změřené** (#327, 922 transcriptů pod `~/.claude/projects`).
    /// Největší má 53,3 MB a jen **2 348 řádků**, takže ocas o 6 000 řádcích, kterým se ořezává
    /// log jobu (`Policy.logTailLines`), by na něm nezabral vůbec — „ocas“ by byl celých 53 MB.
    /// Medián souboru je 271 kB, nad 1 MB jich je 123 a nad 10 MB čtrnáct.
    ///
    /// **Stav „moc velký“ tím mizí úplně**, na rozdíl od logu checku, kde ho vynutila síť: soubor
    /// je lokální, takže se dá číst od konce (`seek`). U logu to nešlo — `Range` přes `gh` se na
    /// redirect do Azure blobu nepřenese a vrátí celých 8,78 MB (změřeno u #214).
    static let rawSessionWindowBytes = 4 * 1024 * 1024

    /// Strop na **jednu událost**: 8 kB.
    ///
    /// Bez druhého stropu by ocas session byl jeden výpis souboru — nejdelší změřený řádek
    /// transcriptu má **7,5 MB** (53 řádků nad 100 kB, medián řádku 1 604 B), takže jeden
    /// `tool_result` umí sežrat celé okno.
    static let rawSessionEventBytes = 8 * 1024

    /// Odkud a kolik se z transcriptu čte.
    ///
    /// `offset` je začátek okna v bajtech, `length` jeho délka. U souboru pod stropem je to celý
    /// soubor a `offset` je nula — tedy stav bez ořezu, ve kterém se nic nepřiznává.
    ///
    /// **U zkráceného souboru se čte o jeden bajt víc — ten před oknem.** Je to sonda na hranici
    /// řádku a bez ní se ztrácela **první celá událost** okna (nálezem Copilota na #408): zarovnání
    /// zahazuje zbytek řádku před oknem, jenže když `fileBytes − 4 MB` padne přesně na začátek
    /// řádku, není co zahazovat — a „první zakončení v okně“ by sebralo celou první událost
    /// a `omittedBytes` by tvrdil větší zkrácení, než nastalo. S tím jedním bajtem je odpověď
    /// v datech: je-li to zakončení řádku, okno začíná na hranici.
    ///
    /// Záporná nebo nesmyslná velikost (soubor zmizel pod rukama) vyjde na prázdné okno, ne na pád.
    static func rawSessionWindow(fileBytes: Int) -> (offset: Int, length: Int) {
        let total = max(fileBytes, 0)
        guard total > rawSessionWindowBytes else { return (0, total) }
        return (total - rawSessionWindowBytes - 1, rawSessionWindowBytes + 1)
    }

    /// Kolik bajtů se ze začátku okna zahodí, aby okno začínalo **na začátku řádku**.
    ///
    /// Okno je ocas souboru, takže jeho první řádek je obvykle jen konec řádku, jehož začátek leží
    /// před oknem — a takový zbytek není JSON, takže by z něj byl nečitelný řádek u **každého**
    /// zkráceného transcriptu.
    ///
    /// **Když v okně není zakončení řádku, za kterým by ještě něco bylo, nezahodí se nic** — jen
    /// případné pokračovací bajty UTF-8 na samém začátku. Je to ten změřený případ jednoho řádku
    /// o 7,5 MB: zahodit celé okno by znamenalo prázdný sheet nad souborem, ve kterém něco je,
    /// kdežto takhle z něj zbyde jedna nečitelná událost — a ta aspoň ukáže, co v souboru stojí.
    ///
    /// **„Za kterým by ještě něco bylo“ tam stát musí** (chyceno testem): řádek delší než celé okno
    /// končí zakončením na **posledním bajtu** okna, takže hledání prvního zakončení by zahodilo
    /// všechno až na nic.
    ///
    /// **Hledá se `LF` i `CR`, ne jen `LF`** (nálezem Copilota na #408). Dělení řádků drží
    /// `TextLines` a to zná `LF`, `CRLF` i samotné `CR` — takže s transcriptem zakončeným `CR` by
    /// zarovnání nenašlo nic, okno by začalo uprostřed záznamu a jeho první událost by byla
    /// nečitelná, přestože soubor je v pořádku. `CRLF` se přitom musí spotřebovat **celé**: jinak
    /// by okno začínalo osamoceným `LF`, tedy prázdným řádkem.
    ///
    /// Pokračovací bajty (`10xxxxxx`) se zahazují proto, že `offset` padne doprostřed znaku:
    /// bez toho by dekódování skončilo chybou a okno by hlásilo „soubor nemá platné UTF-8“
    /// o souboru, který ho má.
    static func rawSessionPrefixDrop(_ window: Data, isTail: Bool) -> Int {
        guard isTail else { return 0 }
        if let end = window.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            var after = window.index(after: end)
            // `CRLF` je jedno zakončení, ne dvě.
            if window[end] == 0x0D, after < window.endIndex, window[after] == 0x0A {
                after = window.index(after: after)
            }
            if after < window.endIndex {
                return window.distance(from: window.startIndex, to: after)
            }
        }
        var dropped = 0
        var index = window.startIndex
        while dropped < 3, index < window.endIndex, window[index] & 0xC0 == 0x80 {
            dropped += 1
            index = window.index(after: index)
        }
        return dropped
    }

    /// Tělo události po ořezu na strop — a **přiznání ořezu na místě, kde nastal**.
    ///
    /// Ořezává se **na celých řádcích**, dokud to jde: rozpůlený řádek výstupu příkazu vypadá jako
    /// řádek, který ten příkaz vypsal. Když se přes strop přehoupne už první řádek (změřený případ
    /// 7,5 MB v jednom `tool_result`), řeže se uprostřed něj — jinak by z takové události nebylo
    /// vidět nic.
    ///
    /// **Zbytek se hlásí v řádcích, nebo v bajtech, podle toho, co má smysl.** Pod megabajt řekne
    /// počet řádků, kolik toho chybí ke čtení; nad megabajt už počet řádků neznamená nic (7,5MB
    /// `tool_result` je **jeden** řádek), takže se hlásí velikost.
    ///
    /// **Jednořádkový zbytek se hlásí taky velikostí** (a je to úmysl, ne mez o jedno vedle):
    /// „+ 1 řádek“ neřekne, jestli chybí čtyřicet znaků nebo devět kilobajtů, kdežto „+ 8,7 kB“
    /// ano. Totéž u řezu uprostřed řádku, kde by se zbytek počítal jako celý řádek.
    static func rawSessionBody(_ text: String, limit: Int = rawSessionEventBytes) -> RawSessionBody {
        // **Prázdnost se posuzuje jinak, než co se sundá** (nálezem Copilota na #408). Sundávají se
        // jen zakončení řádků — mezery na konci umí být součástí výstupu nástroje a tělo se má
        // ukázat tak, jak v transcriptu stojí. Tělo, ve kterém není nic než bílé znaky, se přitom
        // nekreslí vůbec: byl by z něj prázdný odsazený řádek pod hlavičkou.
        let trimmed = trimmingTrailingLineTerminators(text)
        guard trimmed.contains(where: { !$0.isWhitespace }) else {
            return RawSessionBody(text: nil, cut: nil)
        }
        guard trimmed.utf8.count > limit else { return RawSessionBody(text: trimmed, cut: nil) }

        let head = rawSessionHead(of: trimmed, limit: limit)
        return RawSessionBody(
            text: String(trimmed[..<head.text]),
            cut: rawSessionCut(of: trimmed[head.rest...], onLineBoundary: head.onLineBoundary)
        )
    }

    /// Kolik z těla se do stropu vejde — celé řádky, a když ani první nestačí, tak jeho začátek.
    ///
    /// **Dva indexy, ne jeden.** `text` končí posledním znakem, který se ukáže, kdežto `rest` začíná
    /// **za** zakončením řádku: zakončení není obsah, takže by v ukázaném těle bylo prázdným řádkem
    /// na konci, a v zbytku by se počítalo jako o řádek víc, než se doopravdy neukázalo.
    ///
    /// **Dělí se jen `limit` bajtů, ne celé tělo**, a je to změřené: `TextLines` dělí po
    /// `Character`ech (kvůli `CRLF`, #295), což je nad megabajty drahé — a tělo, které se ořezává, je
    /// z definice delší než strop. Kde se řeže, se pozná z toho, že poslední řádek toho prefixu je
    /// useknutý; zbytek se tady nedělí vůbec (a v `rawSessionCut(of:onLineBoundary:)` jen pod
    /// megabajtem, kde je počet řádků k něčemu).
    private static func rawSessionHead(
        of text: String,
        limit: Int
    ) -> (text: String.Index, rest: String.Index, onLineBoundary: Bool) {
        let safe = text[..<characterBoundary(in: text, atByte: limit)]
        // Poslední řádek prefixu končí na hranici stropu, takže se dál pokračuje v těle — celý není.
        // Bere se ten před ním; `nil` znamená, že se nevešel ani jeden celý.
        if let line = TextLines.all(safe).dropLast().last {
            return (line.endIndex, text.index(after: line.endIndex), true)
        }

        // Ani první řádek se nevejde: řeže se na hranici **znaku**, ať se neroztrhne kódový bod —
        // rozpůlený znak v `NSTextView`u nakreslí otazník v kosočtverci a ve zkopírovaném přepisu
        // je z něj vadné UTF-8.
        let index = safe.endIndex
        return (index, index, false)
    }

    /// Index nejblíž `byte`-tému bajtu, který je hranicí znaku.
    ///
    /// **Přes `utf8` view, ne po znacích**: `String(text[i]).utf8.count` v cyklu alokuje `String` na
    /// každý znak, a u stropu 8 kB je to osm tisíc alokací na událost.
    private static func characterBoundary(in text: String, atByte byte: Int) -> String.Index {
        let utf8 = text.utf8
        guard byte < utf8.count else { return text.endIndex }
        var boundary = utf8.index(utf8.startIndex, offsetBy: byte)
        var index = String.Index(boundary, within: text)
        while index == nil, boundary > utf8.startIndex {
            boundary = utf8.index(before: boundary)
            index = String.Index(boundary, within: text)
        }
        return index ?? text.startIndex
    }

    /// Věta o tom, co za ořezem těla zbylo. `nil` u prázdného zbytku.
    ///
    /// **Po řezu uprostřed řádku se hlásí vždycky bajty**: zbytek začíná půlkou řádku, takže by se
    /// počítal jako celý — a „+ 4 řádky“ nad třemi řádky a fragmentem je číslo, které nesedí.
    ///
    /// Řádky se počítají **teprve po** obou podmínkách, ne před nimi: zbytek umí mít megabajty
    /// (jeden změřený `tool_result` má 7,5 MB) a dělení po `Character`ech je nad takovým textem
    /// zrovna ta práce, kterou má strop ušetřit.
    private static func rawSessionCut(of rest: Substring, onLineBoundary: Bool) -> String? {
        let bytes = rest.utf8.count
        guard bytes > 0 else { return nil }
        guard onLineBoundary, bytes < 1024 * 1024 else {
            return "… + \(bytes.formatted(.byteCount(style: .file))) nad strop události"
        }
        let lines = TextLines.content(rest).count
        guard lines > 1 else {
            return "… + \(bytes.formatted(.byteCount(style: .file))) nad strop události"
        }
        let counted = Plural.czech(lines, one: "řádek", few: "řádky", many: "řádků")
        return "… + \(counted) nad strop události"
    }

    /// Zakončení řádků na konci textu — v transcriptu je nese skoro každý blok a v přepisu by
    /// z nich byly prázdné řádky mezi událostmi.
    ///
    /// **Jen zakončení, nic jiného**, a `isLineTerminator` jako všude jinde v repu (#295): mezery
    /// a tabulátory na konci řádku jsou obsah, který nám nikdo nedal právo měnit.
    private static func trimmingTrailingLineTerminators(_ text: String) -> String {
        var result = Substring(text)
        while let last = result.last, last.isLineTerminator {
            result.removeLast()
        }
        return String(result)
    }

    /// `.shown`, nebo `.empty`? — jediné místo, kde se to rozhoduje.
    ///
    /// **Prázdný sheet by vypadal jako „session nic nedělala“**, což je to samé tvrzení, jakému se
    /// vyhýbá rozdíl mezi `čisté` a `spadlo`. `TranscriptStore` ten stav sám nerozlišuje (prázdný
    /// soubor se přečte v pořádku a vydá nic), takže ho musí rozlišit tohle.
    static func rawSessionState(of transcript: RawTranscript) -> RawTranscriptState {
        guard transcript.events.isEmpty else { return .shown(transcript) }
        return .empty(bytes: transcript.fileBytes)
    }

    /// Co sheet nabídne v patičce.
    ///
    /// Tři různá „přepis tu není“ mají **různý další krok**, a právě to je důvod, proč se nesmí
    /// slít do jedné hlášky:
    ///
    /// - **není** — konečná odpověď, tedy **jen `Zavřít`**: nabízet opakování u odpovědi, která se
    ///   nezmění, je slib, který se nemá čím naplnit, a `Ukázat v Finderu` ani cesta nemají kam
    ///   ukázat;
    /// - **nedá se přečíst** — soubor leží dál, takže se nabízí obojí: zkusit znovu i podívat se
    ///   na něj mimo aplikaci;
    /// - **prázdný** — u běžící session je to **dočasný** stav, takže `Načíst znovu` smysl má;
    ///   `Ukázat v Finderu` jedině tehdy, když v souboru vůbec nějaké bajty jsou (u souboru
    ///   o nule velikosti není v Finderu co si prohlédnout).
    ///
    /// `Zkopírovat přepis` **a cestu** je jen tam, kde přepis je. Je to takhle nakreslené (`.acts2`
    /// u tří stavů v sekci 20 návrhu) a drží to jednu věc: u chybového stavu je odpověď v **hlášce**,
    /// ne v tom, co se dá odsud vzít pryč — kopírovat cestu k souboru, který není, je nabídka jít se
    /// podívat na nic.
    static func rawSessionActions(for state: RawTranscriptState) -> [RawSessionAction] {
        switch state {
        case .loading:
            return [.close]
        case .shown:
            return [.close, .copyTranscript, .copyPath, .revealInFinder, .reload]
        case .missing:
            return [.close]
        case .unreadable:
            return [.close, .revealInFinder, .reload]
        case .empty(let bytes):
            return bytes > 0 ? [.close, .revealInFinder, .reload] : [.close, .reload]
        }
    }

    /// Kterou session dráha umí otevřít. `nil` = tlačítko se **nekreslí**.
    ///
    /// Chybí-li `session_id` nebo pracovní strom, není z čeho odvodit cestu k transcriptu
    /// (`TranscriptLocation.transcript(ofSession:in:projects:)`), takže by tlačítko otevřelo sheet,
    /// který nemá co ukázat. Je to tatáž podmínka jako u `Zkopírovat resume` — a **zašedlé** by tu
    /// bylo horší: tvrdilo by „tady se to dělá, jen teď ne“, kdežto u dráhy bez session se to
    /// nedělá nikdy.
    static func rawSessionTarget(of lane: ReviewerLane, slug: String) -> RawSessionTarget? {
        guard let sessionID = lane.sessionID, let worktree = lane.worktree else { return nil }
        return RawSessionTarget(
            sessionID: sessionID,
            worktree: worktree,
            skill: lane.skill,
            slug: slug
        )
    }

    /// Kolik od snímku přibylo. `nil` = nepřibylo nic, nebo se velikost nezjišťovala.
    ///
    /// **Záporný přírůstek se nehlásí**: soubor umí i zmenšit (session se přepsala, úklid cache),
    /// a `přibylo −2 MB` je věta, která nic neznamená. `nil` je odpověď „není co říct“, ne nula.
    static func rawSessionGrowth(snapshot: Int, now: Int?) -> Int? {
        guard let now, now > snapshot else { return nil }
        return now - snapshot
    }

    // MARK: - Velikost sheetu

    /// Podlaha sheetu s přepisem. Pod tohle ho nepustí ani tažení — je to `contentMinSize` okna
    /// sheetu, takže je ta mez vidět rukou, ne jen v kódu.
    static let rawSessionSheetMinWidth: CGFloat = 720
    static let rawSessionSheetMinHeight: CGFloat = 420

    /// Výchozí velikost, se kterou se sheet otevře, dokud si uživatel nenatáhl vlastní.
    ///
    /// **Širší, než návrh kreslí** (`max-width: 940px` u `.win.sm` v sekci 20) a je to změřené,
    /// ne odhadnuté: přepis **zalamuje** (vědomá odchylka od návrhu, viz `TranscriptTextView`), takže
    /// úzký sheet neznamená, že se text nevejde — znamená, že jeden řádek výstupu je pár řádků sazby
    /// a scrolluje se přes ně. Nad skutečným transcriptem (2,8 MB, 432 189 znaků přepisu, 5 236
    /// logických řádků; mono 10,5 b = 6,49 b na znak) vychází sazba takhle
    /// (`RawSessionMeasurement.wrappingByWidth`):
    ///
    /// | Šířka sheetu | Znaků na řádek | Řádků sazby | Proti logickým |
    /// |---|---|---|---|
    /// | 720 (**dřív** jediná, viz níž) | 104 | 7 341 | 1,40× |
    /// | 940 (návrh) | 138 | 6 672 | 1,27× |
    /// | **1 180 (nově)** | **175** | **6 220** | **1,19×** |
    /// | 1 600 | 240 | 5 870 | 1,12× |
    /// | 2 400 | 363 | 5 571 | 1,06× |
    ///
    /// Ze 720 na 1 180 ubude **15 %** řádků sazby, tedy 2,4 řádku na každý bod šířky; dál je to
    /// 0,8 řádku na bod (do 1 600) a 0,37 (do 2 400). Zlom je proto tady, a proto se strop netáhne
    /// ke `codeSheetWidthCap` (2 700), kterým se řídí sheet s logem — ten je na jeden dlouhý výpis,
    /// tenhle na střídání prózy a výstupů. Zbytek si dotáhne tažení, které si to pamatuje.
    static let rawSessionSheetIdealWidth: CGFloat = 1_180
    static let rawSessionSheetIdealHeight: CGFloat = 760

    /// Kolik zůstane kolem sheetu na obrazovce (dohromady, ne na stranu).
    ///
    /// Uložená velikost se o to ořezává, protože se **natáhne na jedné obrazovce a otevírá na
    /// druhé**: 3 000 bodů z ultrawide monitoru by na notebooku byl sheet přes celou plochu
    /// a přes hrany. AppKit sám clampuje jen **výšku** ke hraně obrazovky (změřeno: 1 040
    /// požadovaných → 917 daných), šířku nechá přetéct.
    static let rawSessionSheetScreenMargin: CGFloat = 120

    /// Poslední mez, kdyby obrazovka nebyla známá — je to **pojistka proti nesmyslu v
    /// `UserDefaults`** (soubor se dá editovat rukou), ne návrhové rozhodnutí. Skutečný strop je
    /// obrazovka.
    static let rawSessionSheetCap = CGSize(width: 6_000, height: 4_000)

    /// S jakou velikostí se sheet otevře: **uloženou, když je použitelná, jinak výchozí**.
    ///
    /// Nula znamená „nic uloženého“, ne nulový sheet — `@AppStorage` bez zapsané hodnoty vrací
    /// právě ji, a odlišit „neuloženo“ od „uloženo“ je potřeba k tomu, aby výchozí velikost mohla
    /// dál vycházet z obrazovky.
    ///
    /// Ořez je **při použití, ne při zápisu** (tatáž úvaha jako u šířky panelu nálezů): v
    /// `UserDefaults` může být cokoli — ruční editace, hodnota z jiného monitoru, jiný rozsah ze
    /// starší verze — a `frame(idealWidth:)` se zápornou hodnotou rozhodí celé okno.
    static func rawSessionSheetSize(storedWidth: Double, storedHeight: Double, screen: CGSize?) -> CGSize {
        let bounds = rawSessionSheetBounds(screen: screen)
        guard storedWidth.isFinite, storedHeight.isFinite, storedWidth > 0, storedHeight > 0 else {
            return CGSize(
                width: min(rawSessionSheetIdealWidth, bounds.width),
                height: min(rawSessionSheetIdealHeight, bounds.height)
            )
        }
        return CGSize(
            width: min(max(storedWidth, rawSessionSheetMinWidth), bounds.width),
            height: min(max(storedHeight, rawSessionSheetMinHeight), bounds.height)
        )
    }

    /// Jak velký smí sheet být: obrazovka bez okrajů, nebo pojistka, když obrazovku neznáme.
    /// Nikdy pod podlahu — na displeji, kam se `720` nevejde, rozhoduje podlaha, ne okraj.
    private static func rawSessionSheetBounds(screen: CGSize?) -> CGSize {
        guard let screen, screen.width.isFinite, screen.height.isFinite,
              screen.width > 0, screen.height > 0
        else { return rawSessionSheetCap }
        return CGSize(
            width: max(screen.width - rawSessionSheetScreenMargin, rawSessionSheetMinWidth),
            height: max(screen.height - rawSessionSheetScreenMargin, rawSessionSheetMinHeight)
        )
    }

    /// Má se uložená velikost přepsat naměřenou? `nil` = **nezapisovat**.
    ///
    /// Je to tentýž tvar jako `Policy.hoverChange(from:to:)` a ze stejného důvodu: rozhodnutí
    /// „tohle je změna, kterou stojí za to zapsat“ patří na jedno místo, kde se dá vyčerpat výčtem.
    ///
    /// Porovnává se s tím, **s čím se sheet otevřel**, ne s uloženou hodnotou: velikost, o kterou si
    /// aplikace řekla sama, není volba uživatele, takže se neukládá — jinak by se nula („nic
    /// uloženého“) při prvním otevření přepsala na konkrétní číslo a výchozí velikost by přestala
    /// vycházet z obrazovky.
    ///
    /// **Mezistav rozvržení tahle funkce ale nepozná, a nemá ho poznat**: sheet se rozvrhuje dvakrát
    /// a v prvním průchodu hlásí **podlahu** (změřeno sondou: 500×300 a hned po ní 700×500 při
    /// ideálu 700×500). Podlaha je přitom legitimní velikost — kdo si sheet stáhne až na ni, má ji
    /// mít zapamatovanou —, takže ji nelze zamítnout tady. Zahazuje ji **odmlka ve view**
    /// (`RawSessionSheet.resizeSettle`); je na to test, který tvrdí, že se otevřením a zavřením
    /// neuloží nic.
    ///
    /// Pod podlahu se nezapisuje: sheet se pod ni nedostane (je to `contentMinSize` okna), takže
    /// menší číslo je mezistav rozvržení, ne velikost okna.
    static func rawSessionSheetResize(opened: CGSize, measured: CGSize) -> CGSize? {
        guard measured.width.isFinite, measured.height.isFinite else { return nil }
        let rounded = CGSize(width: measured.width.rounded(), height: measured.height.rounded())
        guard rounded.width >= rawSessionSheetMinWidth, rounded.height >= rawSessionSheetMinHeight
        else { return nil }
        let asked = CGSize(width: opened.width.rounded(), height: opened.height.rounded())
        guard rounded != asked else { return nil }
        return rounded
    }
}
