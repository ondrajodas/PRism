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
    /// Kolik řádků konce logu se ukazuje. Víc než pár set se nepřečte a v `job.log` z Actions je
    /// to, co člověk hledá (selhaná assertace, stack trace, exit code), vždycky u konce.
    static let logTailLines = 300

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
                // rozbitá sekvence nesnědla zbytek logu.
                while iterator < text.endIndex, text[iterator] != "\u{7}", text[iterator] != "\n" {
                    iterator = text.index(after: iterator)
                }
                if iterator < text.endIndex, text[iterator] == "\u{7}" {
                    iterator = text.index(after: iterator)
                }
            }
        }
        return result
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
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
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
        var all = clean.split(separator: "\n", omittingEmptySubsequences: false)
        if all.last?.isEmpty == true { all.removeLast() }
        guard all.count > limit else {
            return LogTail(text: all.joined(separator: "\n"), omittedLines: 0)
        }
        return LogTail(
            text: all.suffix(limit).joined(separator: "\n"),
            omittedLines: all.count - limit
        )
    }

    /// Strop na velikost logu, který se **vůbec stáhne**: 2 MB.
    ///
    /// **Změřeno u #214, ne odhadnuto** (zadání to výslovně chtělo, viz #275 o ceně sazby).
    /// Dvoumegový ocas skutečného logu (`keboola/job-queue-daemon`, 5 843 řádků, nejdelší 2 003
    /// znaků) se v `NSTextView` nasází za **220 ms**, celý 8,78MB log za 850 ms — takže 2 MB
    /// je strop **s rezervou**, ne na hraně. Zůstává, protože 2 MB je asi 6 000 řádků, tedy pořád
    /// víc, než kdo přečte, a 220 ms je jednorázová cena při otevření sheetu.
    static let logSizeLimit = 2 * 1024 * 1024

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

    /// Věta o tom, kolik se nevešlo — `— starších 3 812 řádků se nevešlo —`, jak to má návrh.
    ///
    /// `nil` u neořezaného logu: hlavička, která tvrdí ořez u celého logu, je horší než žádná.
    static func logTailNotice(_ tail: LogTail) -> String? {
        guard tail.isTruncated else { return nil }
        let lines = Plural.czech(tail.omittedLines, one: "řádek", few: "řádky", many: "řádků")
        return "— starších \(lines) se nevešlo —"
    }
}
