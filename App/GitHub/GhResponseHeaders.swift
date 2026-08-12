import Foundation

/// Hlavičky, které vypíše `gh api -i`.
///
/// Vlastní typ, ne pár řádků uvnitř gateway: je to čistá funkce nad **skutečným** tvarem výstupu
/// `gh`, a ten má tři vlastnosti, na kterých se rozbor dá potichu rozbít.
///
/// 1. **Řádky hlaviček končí `CRLF`**, jen stavový řádek `LF` (ověřeno `od -c` na živém výstupu,
///    fixture `gh/job-log-head.txt`). A `"\r\n"` je ve Swiftu **jeden `Character`**, takže
///    `split(separator: "\n")` na něm **nerozdělí** — z celého bloku hlaviček zbyde jediný
///    „řádek“ a nenajde se v něm nic. Tohle stálo #292: `Content-Length` nevyšel u žádného
///    checku, přitom v shellu byl vidět, protože tam ho čtou oči, a ne Swift.
/// 2. **Jména hlaviček nemají zaručenou velikost písmen.** Za redirectem přišly Title-Case
///    (`Content-Length`), ale `HTTP/2` je nese lowercase — porovnání citlivé na velikost by tedy
///    selhalo jen na části odpovědí, což je horší než nefunkční vždycky.
/// 3. **Bloků hlaviček může být víc za sebou.** `-i` u redirectu umí vypsat i tu odpověď před ním
///    a ta má `Content-Length: 0`. Rozhoduje proto **poslední blok**, ne první nalezená hlavička —
///    jinak by každý log vyšel jako prázdný a strop by ho pustil bez ohledu na velikost.
struct GhResponseHeaders: Equatable, Sendable {
    /// Jedna hlavička. `name` je vždycky **malými písmeny**, aby se porovnání nedalo minout.
    struct Field: Equatable, Sendable {
        let name: String
        let value: String
    }

    /// Hlavičky jedné odpovědi. `statusCode` je `nil`, když blok stavový řádek neměl.
    struct Block: Equatable, Sendable {
        var statusCode: Int?
        var fields: [Field] = []
    }

    /// Bloky v pořadí výpisu; poslední je ta odpověď, kterou `gh` doopravdy dostal.
    let blocks: [Block]

    init(output: String) {
        var blocks: [Block] = []
        // **Dělí se na jakémkoli zakončení řádku**, ne na `"\n"` — viz bod 1 v dokumentaci typu.
        // Pravidlo drží `TextLines` (#295): do té doby tady stálo `isNewline`, což je oproti tomu,
        // co `gh` vyrábí, širší (viz `Character.isLineTerminator`) — a hlavně to bylo **druhé**
        // místo, kde se dělení rozhodovalo.
        for line in TextLines.nonEmpty(output) {
            if let status = Self.statusCode(in: line) {
                blocks.append(Block(statusCode: status))
            } else if let field = Self.field(in: line) {
                // Hlavičky bez stavového řádku před nimi pořád patří do bloku — výstup, který
                // stav vůbec nemá, se nemá zahodit celý.
                if blocks.isEmpty { blocks.append(Block(statusCode: nil)) }
                blocks[blocks.count - 1].fields.append(field)
            }
        }
        self.blocks = blocks
    }

    /// `gh` nevypsal ani stav, ani jedinou hlavičku.
    var isEmpty: Bool { blocks.isEmpty }

    /// Stav poslední odpovědi — tedy té za posledním redirectem.
    var lastStatusCode: Int? { blocks.last?.statusCode }

    /// Hodnota hlavičky **z posledního bloku**; jméno se porovnává bez ohledu na velikost písmen.
    ///
    /// Schválně jen z posledního: hlavička odpovědi před redirectem popisuje redirect, ne tělo,
    /// takže sáhnout si do ní znamená hlásit velikost něčeho jiného.
    func lastValue(of name: String) -> String? {
        let wanted = name.lowercased()
        return blocks.last?.fields.last { $0.name == wanted }?.value
    }

    /// `HTTP/1.1 200 OK` → `200`. `nil` = tenhle řádek stavový není.
    private static func statusCode(in line: Substring) -> Int? {
        guard line.hasPrefix("HTTP/") else { return nil }
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        return Int(parts[1])
    }

    /// `Content-Length: 237141` → `(content-length, 237141)`. `nil` = řádek bez dvojtečky.
    private static func field(in line: Substring) -> Field? {
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return nil }
        return Field(name: name, value: parts[1].trimmingCharacters(in: .whitespaces))
    }
}

/// Co odpověď řekla o velikosti těla — a když neřekla, tak proč.
///
/// **Vyjmenované stavy, ne `Int?`**: „`gh` nevypsal nic“, „odpověď měla chybový stav“, „hlavička
/// tam není“ a „hlavička tam je, ale není to číslo“ jsou čtyři různé věci. Sloučené do jednoho
/// `nil` se nedají ani odlišit, ani přišpendlit testem — a u #292 z nich v okně zbyla jedna věta
/// („Výstupu gh nerozumím“), se kterou se nedalo nic udělat. Payload u případů je proto součást
/// zadání: je to to, co se dá v testu tvrdit.
enum ContentLengthReading: Equatable, Sendable {
    /// Velikost těla v bajtech.
    case bytes(Int)
    /// `gh` skončil v pořádku, ale nevypsal ani stav, ani hlavičku.
    case noOutput
    /// Poslední stav odpovědi nebyl 2xx, takže velikost není čeho.
    case httpFailure(status: Int)
    /// Hlavičky přišly, `Content-Length` mezi nimi není. `status` je poslední stav (`nil` = ani
    /// stavový řádek tam nebyl, tedy výstup nejsou hlavičky).
    case missingHeader(status: Int?)
    /// `Content-Length` tam je, ale hodnota není nezáporné číslo.
    case unreadableValue(String)
}

extension GhResponseHeaders {
    /// Velikost těla podle hlaviček poslední odpovědi.
    var contentLength: ContentLengthReading {
        guard !isEmpty else { return .noOutput }
        if let status = lastStatusCode, !(200..<300).contains(status) {
            return .httpFailure(status: status)
        }
        guard let raw = lastValue(of: "content-length") else {
            return .missingHeader(status: lastStatusCode)
        }
        guard let bytes = Int(raw), bytes >= 0 else { return .unreadableValue(raw) }
        return .bytes(bytes)
    }
}
