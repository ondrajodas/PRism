import Foundation

/// Konec logu k zobrazení a kolik se ho nevešlo (#214).
///
/// Vlastní typ, ne `String`: **tiše zkrácený log tvrdí, že job začal uprostřed**, takže se počet
/// vynechaných řádků musí nést spolu s textem — tatáž úmluva jako `ConversationShortfall` a jako
/// u osy běhu (#203).
struct LogTail: Hashable, Sendable {
    /// Řádky, které se ukazují — už bez ANSI a bez timestampů.
    let text: String
    /// Kolik starších řádků se nevešlo. `0` = log je celý.
    let omittedLines: Int
    /// Kolik řádků `text` má.
    ///
    /// Nese se s textem schválně, i když by se z něj dal spočítat: **výška okýnka se z něj počítá
    /// při každém překreslení** (#292), a scan megabajtového textu na každý průchod `body` je zrovna
    /// to, co #224 zakazuje. Tady je zdarma — `logTail` si řádky stejně dělí.
    let lineCount: Int

    var isTruncated: Bool { omittedLines > 0 }
}

/// Jde se pro log vůbec? (#214)
///
/// **Nad stropem se nestahuje vůbec**, protože jinak by se stáhlo 8,78 MB (4 s) jen proto, aby se
/// zjistilo, že se nemají ukazovat. Cena rozhodnutí, ať je zapsaná: nad stropem odpadá i **konec**
/// logu, tedy zrovna u toho největšího, kde je odchod do prohlížeče nejotravnější. Obejít to
/// částečným stažením nejde — `Range` přes `gh` nefunguje (změřeno: hlavička se na redirect do
/// Azure blobu nepřenese a vrátí se celých 8,78 MB).
enum LogAvailability: Hashable, Sendable {
    case fetchable
    /// Věta s **konkrétní velikostí** — `Log má 8,4 MB, na zobrazení je moc velký.`
    case tooLarge(String)
}

extension Policy {
    /// Kolik řádků konce logu se ukazuje: **6 000** (do #292 tři stovky, pak 2 000, do #303 4 000).
    ///
    /// **Cena o tom nerozhoduje.** Do #292 rozhodovala: konec logu kreslil SwiftUI `Text`
    /// se `.fixedSize()`, který roste kvadraticky. Od #292 ho kreslí `LogTailTextView` nad TextKitem,
    /// takže na největším logu z našich repů (8,78 MB) stojí v jednom běhu **300 řádků 2,58 ms,
    /// 2 000 řádků 2,02 ms, 6 000 řádků 5,45 ms a 10 000 řádků 14,34 ms** — proti 124 ms, 6,4 s,
    /// 57,6 s a 206 s u SwiftUI `Text`u. Projíždění má medián snímku 0,00 ms u všech.
    ///
    /// **Zvednuto na výslovné přání po proklikání** (#303, do té doby 4 000 — a u #292 chvíli 2 000
    /// s odůvodněním, že se do okýnka vejde jen ~20 řádků naráz). Měření to unese a **skutečné logy
    /// tomu dávají smysl**: `Tests` joby na našich repech mají 5 899 / 5 920 / 5 933 řádků, tedy sedí
    /// zrovna v pásmu mezi starou a novou mezí — se 4 000 se ořezávaly, se 6 000 se ukážou **celé**.
    ///
    /// **`Ukázat celý log` tím o smysl nepřišel** a je to změřené, ne odhadnuté: z devíti změřených
    /// logů zůstávají nad mezí tři (16 013 / 16 270 / 25 533 řádků), takže se u nich pořád ukáže
    /// „starších N řádků se nevešlo“ a sheet má co dodat. Cena zvednutí, ať je zapsaná: v okýnku
    /// o 441 bodech (30 řádků) je 6 000 řádků **200 obrazovek** scrollování, takže dál se nezvedá
    /// samotný ocas — od téhle mezi výš je to práce pro sheet a pro odkaz na GitHub.
    static let logTailLines = 6_000

    /// Číslo jobu z odkazu na check (#214).
    ///
    /// Odkaz vypadá jako `https://github.com/o/r/actions/runs/<runId>/job/<jobId>`, a **totéž číslo
    /// funguje i jako check-run ID** pro anotace (ověřeno: `/check-runs/<id>/annotations` vrátilo
    /// 200). Model tedy nepotřebuje druhé volání, jen tenhle rozbor.
    ///
    /// `nil` je **běžná odpověď, ne chyba**: `link` job ID mít nemusí. CodeQL má
    /// `https://github.com/cli/cli/runs/92918586381` (bez `/job/`), bors dokonce
    /// `https://bors.rust-lang.org`. U takového checku se detail **nenabízí** — tlačítko
    /// `Ukázat log`, které skončí chybou, je horší než tlačítko, které tam není.
    static func jobID(from link: URL?) -> Int? {
        guard let link, link.host()?.hasSuffix("github.com") == true else { return nil }
        let parts = link.pathComponents
        // Hledá se `job` a číslo **za ním**, ne poslední složka cesty: `…/runs/<runId>` je taky
        // číslo na konci, ale je to běh, ne job — a log běhu je všech jeho jobů (u změřeného PR
        // 23), tedy přesně to, co se stahovat nemá.
        guard let index = parts.lastIndex(of: "job"), index + 1 < parts.count else { return nil }
        return Int(parts[index + 1])
    }

    /// Sundá ANSI escape sekvence.
    ///
    /// V obou změřených logách jsou (116 řádků v 8,78MB logu, 73 v tom malém) — bez toho se
    /// v okně objeví `^[[36;1m` uprostřed věty. Kreslí se to jako text, ne jako barvy: obarvení
    /// podle ANSI by znamenalo vlastní parser stavu terminálu, a to je na čtení konce logu drahé.
    static func strippingANSI(_ text: String) -> String {
        // `ESC [ … <písmeno>` (CSI) i `ESC ] … BEL` (OSC, hlásí titulek okna) — druhé se
        // v Actions logách objevuje u `##[group]` sekvencí.
        var result = ""
        result.reserveCapacity(text.count)
        var iterator = text.startIndex
        while iterator < text.endIndex {
            let character = text[iterator]
            guard character == "\u{1B}" else {
                result.append(character)
                iterator = text.index(after: iterator)
                continue
            }
            iterator = text.index(after: iterator)
            guard iterator < text.endIndex else { break }
            if text[iterator] == "[" {
                iterator = text.index(after: iterator)
                // Parametry sekvence: číslice, středníky a spol. Končí to prvním písmenem.
                while iterator < text.endIndex, !text[iterator].isLetter {
                    iterator = text.index(after: iterator)
                }
                if iterator < text.endIndex { iterator = text.index(after: iterator) }
            } else if text[iterator] == "]" {
                // OSC končí `BEL` nebo `ESC \`; **nikdy se nepřežene za konec řádku**, aby
                // rozbitá sekvence nesnědla zbytek logu. Konec řádku je `isLineTerminator`, ne
                // `"\n"`: v logu s `CRLF` je zlom jeden `Character` `"\r\n"`, který se `"\n"`
                // nerovná — takže by ta pojistka nezabrala právě tam, kde je potřeba (#292).
                while iterator < text.endIndex, text[iterator] != "\u{7}", !text[iterator].isLineTerminator {
                    iterator = text.index(after: iterator)
                }
                if iterator < text.endIndex, text[iterator] == "\u{7}" {
                    iterator = text.index(after: iterator)
                }
            }
        }
        return result
    }

    /// Řádky logu — **na jakémkoli zakončení**, tedy `LF`, `CRLF` i samotné `CR`.
    ///
    /// `split(separator: "\n")` na to nestačí: `"\r\n"` je ve Swiftu **jeden `Character`**, takže
    /// se na něm nerozdělí a z logu z Windows runneru by byl jediný řádek — konec logu by pak byl
    /// celý log, věta „nevešlo se“ by mlčela a v okně by z toho byla jedna nekonečná řádka. Je to
    /// tatáž past, na které u #292 skončil rozbor hlaviček `gh -i`; v obou změřených logách z našich
    /// repů `CR` sice není, ale zakončení řádků si vybírá runner, ne my.
    ///
    /// **Samotné dělení je od #295 v `TextLines`** a tady zůstává jen jméno pro volající. Do té doby
    /// tu bylo `whereSeparator: \.isNewline`, tedy druhé místo, kde se rozhodovalo, co je řádek —
    /// a `isNewline` je navíc širší, než co runner vyrábí (viz `Character.isLineTerminator`).
    static func logLines(of text: String) -> [Substring] {
        TextLines.all(text)
    }

    /// Sundá timestamp ze začátku řádku.
    ///
    /// V Actions logu ho má **skoro každý řádek** (změřeno: 25 528 z 25 534) a zabírá 28 znaků —
    /// tedy ukrajuje šířku zrovna tam, kde je potřeba přečíst konec dlouhé assertace. Zadání
    /// nabízí schovat, nebo zešednout; **schovává se**, protože zešednutí by šířku nevrátilo
    /// a v jednolitém textu (viz `SelectableCodeView`) by stálo obarvení po řádcích.
    ///
    /// Kdo časy potřebuje, má celý log na GitHubu — odkaz zůstává vždycky.
    static func strippingTimestamps(_ text: String) -> String {
        logLines(of: text)
            .map { line -> Substring in
                guard let space = line.firstIndex(of: " "), isTimestamp(line[line.startIndex..<space])
                else { return line }
                return line[line.index(after: space)...]
            }
            .joined(separator: "\n")
    }

    /// Je to `2026-08-11T16:09:11.2636913Z`? Ověřuje se **tvar, ne délka**: počet desetinných míst
    /// se u GitHubu liší a natvrdo daný počet znaků by ho jednou nechal v textu.
    private static func isTimestamp(_ candidate: Substring) -> Bool {
        guard candidate.count >= 20, candidate.hasSuffix("Z") else { return false }
        let digitsAndSeparators = candidate.allSatisfy {
            $0.isNumber || $0 == "-" || $0 == ":" || $0 == "." || $0 == "T" || $0 == "Z"
        }
        return digitsAndSeparators && candidate.contains("T")
    }

    /// Konec logu k zobrazení: **ořezává se od konce a řekne se, kolik se nevešlo**.
    ///
    /// Ořez je věc **zobrazení, ne úspory stahování** — `…/actions/jobs/{id}/logs` vrací celý log
    /// jedním requestem, takže text už v paměti je (změřeno u #214). Proto se z něj bere ocas
    /// a celý zůstává k dispozici pro `Ukázat celý log`.
    static func logTail(_ raw: String, lines limit: Int = Policy.logTailLines) -> LogTail {
        let clean = strippingTimestamps(strippingANSI(raw))
        // Poslední prázdný řádek za koncovým `\n` není řádek logu — jinak by se `nevešlo`
        // počítalo o jeden vedle a u krátkého logu by tvrdilo ořez, který nenastal.
        var all = logLines(of: clean)
        if all.last?.isEmpty == true { all.removeLast() }
        guard all.count > limit else {
            return LogTail(text: all.joined(separator: "\n"), omittedLines: 0, lineCount: all.count)
        }
        return LogTail(
            text: all.suffix(limit).joined(separator: "\n"),
            omittedLines: all.count - limit,
            lineCount: limit
        )
    }

    /// Strop na velikost logu, který se **vůbec stáhne**: 10 MB.
    ///
    /// **Zvednuto z 2 MB u #292, a taky měřením** (#214 měřilo taky, jen měřilo něco jiného —
    /// vysvětlení níž). Změřeno na největším logu, který na našich repech je
    /// (`keboola/job-queue-daemon`, job 93844012547 — 8,78 MB, 25 533 řádků, nejdelší řádek 2 258
    /// znaků, 272 řádků nad tisíc znaků):
    ///
    /// | Co | 2 MB | 8,78 MB |
    /// |---|---|---|
    /// | otevření sheetu (`setAttributedString` + kresba) | 5,61 ms | **6,20 ms** |
    /// | projíždění, medián snímku | 0,00 ms | **0,00 ms** |
    /// | projíždění, nejhorší snímek | 0,01 ms | **0,00 ms** |
    /// | skok na konec dokumentu | 1,67 ms | **1,10 ms** |
    ///
    /// **Proč #214 vyšlo jinak** (220 ms / 850 ms): měřilo `ensureLayout(for:)` + `usedRect(for:)`,
    /// tedy **vynucenou sazbu celého dokumentu** — a to je jediná věc, kterou aplikace nedělá.
    /// `SelectableCodeView` jen předá text a TextKit sází **líně po viewportu**. Poučení, které přežije
    /// tenhle strop: měřit se musí ta cesta, kterou kód doopravdy jde, jinak z měření vyjde strop
    /// o řád nižší, než je potřeba.
    ///
    /// **Proč tedy vůbec nějaký strop**, když sazba nic nestojí: stahování. 8,78 MB stahuje `gh`
    /// **5,75 / 27,44 / 10,67 s** ve třech měřeních za sebou (síť, ne CPU), a celý text zůstává
    /// v paměti okna. 10 MB je proto mez nad změřeným maximem s rezervou, ne mez daná kreslením —
    /// a protože se stahování dá zrušit (sbalení checku `gh` zabije, změřeno), je čekání volba, ne
    /// zásek.
    static let logSizeLimit = 10 * 1024 * 1024

    /// Dá se log ukázat, nebo je moc velký?
    ///
    /// Rozhoduje se **z `Content-Length`, dřív než se něco stáhne**: `HEAD` je levný a **konstantně**
    /// levný (změřeno: ~1,2 s u 33 kB i u 8,78 MB), takže věta o velikosti není odhad. Bez toho by
    /// strop znamenal stáhnout 8,78 MB jen proto, aby se zjistilo, že se nemají ukazovat.
    static func logAvailability(bytes: Int) -> LogAvailability {
        guard bytes > logSizeLimit else { return .fetchable }
        let size = bytes.formatted(.byteCount(style: .file))
        return .tooLarge("Log má \(size), na zobrazení je moc velký.")
    }

    /// Věta, dokud se log stahuje — `Stahuji konec logu (8,4 MB)…`.
    ///
    /// **Velikost v ní je, když ji `HEAD` řekl** (#292). Není to ozdoba: se stropem na 10 MB se čeká
    /// vteřiny až desítky vteřin (změřeno 5,75 / 27,44 / 10,67 s na 8,78 MB) a spinner, který k tomu
    /// nic neřekne, je po půl minutě k nerozeznání od zamrznutí. Bez velikosti se **neslibuje nic** —
    /// odhad by tvrdil víc, než data unesou.
    static func logDownloadNotice(bytes: Int?) -> String {
        guard let bytes else { return "Stahuji konec logu…" }
        return "Stahuji konec logu (\(bytes.formatted(.byteCount(style: .file))))…"
    }

    /// Věta o tom, kolik se nevešlo — `— starších 3 812 řádků se nevešlo —`, jak to má návrh.
    ///
    /// `nil` u neořezaného logu: hlavička, která tvrdí ořez u celého logu, je horší než žádná.
    static func logTailNotice(_ tail: LogTail) -> String? {
        guard tail.isTruncated else { return nil }
        let lines = Plural.czech(tail.omittedLines, one: "řádek", few: "řádky", many: "řádků")
        return "— starších \(lines) se nevešlo —"
    }
}
