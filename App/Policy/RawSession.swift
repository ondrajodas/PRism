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
    /// Záporná nebo nesmyslná velikost (soubor zmizel pod rukama) vyjde na prázdné okno, ne na pád.
    static func rawSessionWindow(fileBytes: Int) -> (offset: Int, length: Int) {
        let total = max(fileBytes, 0)
        guard total > rawSessionWindowBytes else { return (0, total) }
        return (total - rawSessionWindowBytes, rawSessionWindowBytes)
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
    /// Pokračovací bajty (`10xxxxxx`) se zahazují proto, že `offset` padne doprostřed znaku:
    /// bez toho by dekódování skončilo chybou a okno by hlásilo „soubor nemá platné UTF-8“
    /// o souboru, který ho má.
    static func rawSessionPrefixDrop(_ window: Data, isTail: Bool) -> Int {
        guard isTail else { return 0 }
        if let end = window.firstIndex(of: 0x0A), window.index(after: end) < window.endIndex {
            return window.distance(from: window.startIndex, to: end) + 1
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
    /// `tool_result` je **jeden** řádek), takže se hlásí velikost. Totéž platí u řezu uprostřed
    /// řádku: „+ 1 řádek“ by u megabajtu bylo zavádějící.
    static func rawSessionBody(_ text: String, limit: Int = rawSessionEventBytes) -> RawSessionBody {
        let trimmed = trimmingTrailingNewlines(text)
        guard !trimmed.isEmpty else { return RawSessionBody(text: nil, cut: nil) }
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
    private static func trimmingTrailingNewlines(_ text: String) -> String {
        var result = Substring(text)
        while let last = result.last, last.isLineTerminator || last == " " || last == "\t" {
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
}
