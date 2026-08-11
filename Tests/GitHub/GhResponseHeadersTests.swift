import Testing
@testable import PRism

/// Rozbor hlaviček z `gh api -i` (#292).
///
/// Je to čistá funkce nad tvarem výstupu `gh`, takže se testuje **výčtem** — a hlavně na
/// **skutečném** výstupu. Do #292 tady byl jen test nad ručně napsaným řetězcem s `LF`
/// zakončením a zeleně procházel, přitom v aplikaci rozbor nefungoval **u žádného** checku:
/// `gh` totiž hlavičky zakončuje `CRLF` a `"\r\n"` je ve Swiftu jeden `Character`.
struct GhResponseHeadersTests {
    // MARK: - Skutečný výstup

    /// **Tenhle test je ta regrese.** Fixture je bajt za bajtem výstup
    /// `gh api -X HEAD -i repos/home-assistant/core/actions/jobs/93885235707/logs`
    /// (veřejné repo), tedy `LF` za stavovým řádkem a `CRLF` za každou hlavičkou.
    ///
    /// Fixture je v `.gitattributes` označená `-text`; bez toho by ji `core.autocrlf=input`
    /// znormalizovala na `LF` a test by přestal testovat, kvůli čemu vznikl.
    @Test("Velikost se přečte ze skutečného výstupu gh, který má CRLF")
    func readsTheRealOutput() throws {
        let output = try Fixture.text("gh/job-log-head.txt")

        // Kontrola samotné fixture: kdyby v ní `CR` nebyl, test by zezelenal i s tou chybou,
        // kterou má chytat.
        #expect(output.contains("\r\n"), "fixture přišla o CRLF — viz .gitattributes")
        // A past navíc, kterou ta odpověď doopravdy má: `Content-Length` je i **v hodnotě**
        // `Access-Control-Expose-Headers`, a to na řádku **před** tou skutečnou hlavičkou. Hledat
        // podřetězec by tedy vrátilo výčet jmen, ne číslo.
        #expect(output.contains("Accept-Ranges,Content-Length,Date"))
        #expect(GhResponseHeaders(output: output).contentLength == .bytes(237_141))
    }

    /// Rozdělení řádků je celá podstata #292, takže se tvrdí i samo o sobě: hlaviček je v té
    /// odpovědi devatenáct, ne jedna.
    @Test("CRLF rozdělí řádky, ne slepí do jednoho")
    func splitsOnCarriageReturnLineFeed() throws {
        let headers = GhResponseHeaders(output: try Fixture.text("gh/job-log-head.txt"))

        #expect(headers.blocks.count == 1)
        #expect(headers.lastStatusCode == 200)
        #expect(headers.blocks[0].fields.count == 19)
        #expect(headers.lastValue(of: "server")?.hasPrefix("Windows-Azure-Blob") == true)
    }

    // MARK: - Zakončení řádků

    /// Všechna tři zakončení dávají tentýž výsledek — `CR` sám je tu proto, že ho `HTTP/1.0`
    /// servery a starší proxy pořád posílají a je to tentýž tvar chyby.
    @Test("Zakončení řádku o výsledek nerozhoduje", arguments: ["\n", "\r\n", "\r"])
    func acceptsEveryLineEnding(ending: String) {
        let output = "HTTP/1.1 200 OK\(ending)Content-Type: text/plain\(ending)Content-Length: 42\(ending)"

        #expect(GhResponseHeaders(output: output).contentLength == .bytes(42))
    }

    // MARK: - Velikost písmen

    /// `HTTP/2` nese jména hlaviček **lowercase**, `HTTP/1.1` Title-Case. Kdyby se porovnávalo
    /// citlivě, selhalo by to jen na části odpovědí — což se hledá horší než selhání vždycky.
    /// Inline, protože `gh` v tomhle repu jde na Azure blob přes `HTTP/1.1`; lowercase odpověď
    /// se ze skutečného provozu nesehnala.
    @Test("Jméno hlavičky se porovnává bez ohledu na velikost písmen")
    func matchesHeaderNamesCaseInsensitively() {
        let http2 = "HTTP/2.0 200 OK\r\ncontent-length: 1024\r\n"
        let shouty = "HTTP/1.1 200 OK\r\nCONTENT-LENGTH: 1024\r\n"

        #expect(GhResponseHeaders(output: http2).contentLength == .bytes(1_024))
        #expect(GhResponseHeaders(output: shouty).contentLength == .bytes(1_024))
    }

    // MARK: - Víc bloků za sebou

    /// `-i` u redirectu umí vypsat i odpověď před ním a ta má `Content-Length: 0`. Rozhoduje
    /// **poslední blok**: kdyby se brala první hlavička, vyšel by každý log jako prázdný a strop
    /// by ho pustil ke stažení bez ohledu na velikost.
    @Test("Rozhoduje poslední blok hlaviček, ne první")
    func readsTheLastBlock() {
        let output = """
            HTTP/2.0 302 Found\r
            Content-Length: 0\r
            Location: https://productionresultssa0.blob.core.windows.net/x\r
            \r
            HTTP/1.1 200 OK\r
            Content-Length: 8777952\r

            """

        let headers = GhResponseHeaders(output: output)
        #expect(headers.blocks.count == 2)
        #expect(headers.lastStatusCode == 200)
        #expect(headers.contentLength == .bytes(8_777_952))
    }

    /// A obráceně: hlavička z **prvního** bloku se do výsledku nesmí protáhnout. Poslední odpověď
    /// je ta, kterou `gh` doopravdy dostal — velikost odjinud by popisovala jiné tělo.
    @Test("Velikost z bloku před redirectem se nepoužije")
    func ignoresSizeFromEarlierBlocks() {
        let output = """
            HTTP/1.1 200 OK\r
            Content-Length: 1234\r
            \r
            HTTP/1.1 200 OK\r
            Content-Type: text/plain\r

            """

        #expect(GhResponseHeaders(output: output).contentLength == .missingHeader(status: 200))
    }

    // MARK: - Čtyři různá „velikost nevyšla“

    /// Prázdný výstup s nulovým návratovým kódem — tak se chová `gh api -X HEAD` **bez `-i`**,
    /// takže je to zrovna ten stav, do kterého se dá spadnout zapomenutým argumentem.
    @Test("Prázdný výstup je vlastní stav")
    func reportsNoOutput() {
        #expect(GhResponseHeaders(output: "").contentLength == .noOutput)
        #expect(GhResponseHeaders(output: "\r\n\r\n").contentLength == .noOutput)
    }

    @Test("Chybový stav odpovědi se pozná i s kódem")
    func reportsHTTPFailure() {
        let output = "HTTP/1.1 404 Not Found\r\nContent-Length: 21\r\n"

        #expect(GhResponseHeaders(output: output).contentLength == .httpFailure(status: 404))
    }

    @Test("Chybějící Content-Length je vlastní stav, ne nula")
    func reportsMissingHeader() {
        let output = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n"

        #expect(GhResponseHeaders(output: output).contentLength == .missingHeader(status: 200))
    }

    /// Výstup, který hlavičky vůbec nejsou (třeba varování `gh` na stdout). `status: nil` říká,
    /// že tam nebyl ani stavový řádek — tedy že to nejsou hlavičky, ne že chybí jedna hodnota.
    @Test("Výstup bez stavového řádku se pozná")
    func reportsMissingHeaderWithoutStatusLine() {
        #expect(GhResponseHeaders(output: "x: y").contentLength == .missingHeader(status: nil))
    }

    @Test("Nečitelná hodnota Content-Length se nehádá")
    func reportsUnreadableValue() {
        let output = "HTTP/1.1 200 OK\r\nContent-Length: hodně\r\n"

        #expect(GhResponseHeaders(output: output).contentLength == .unreadableValue("hodně"))
    }

    /// Nula je legitimní odpověď („tělo tady není“), ne chyba rozboru — a rozhodně ne důvod
    /// tvářit se, že velikost neznáme.
    @Test("Nulová velikost je nula, ne neznámo")
    func readsZeroAsZero() {
        #expect(GhResponseHeaders(output: "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n").contentLength == .bytes(0))
    }

    // MARK: - Tvar stavového řádku

    /// Stavový řádek bez kódu se **přeskočí, ne zahodí blok**: hlavička s velikostí je pořád dobrá
    /// a vyhodit ji kvůli nerozebranému prvnímu řádku by z drobnosti udělalo vypnutou funkci —
    /// tedy zrovna to, co #292 předvedl.
    @Test("Rozbitý stavový řádek velikost nezahodí")
    func ignoresBrokenStatusLines() {
        #expect(GhResponseHeaders(output: "HTTP/1.1\r\nContent-Length: 7\r\n").contentLength == .bytes(7))
        #expect(GhResponseHeaders(output: "HTTP/1.1\r\nContent-Length: 7\r\n").lastStatusCode == nil)
    }

    /// Hlavička s dvojtečkou v hodnotě (`Location`, `Date`) se nesmí rozpadnout — dělí se
    /// **jen na první** dvojtečce.
    @Test("Hodnota s dvojtečkou zůstane celá")
    func keepsColonsInsideValues() {
        let output = "HTTP/1.1 200 OK\r\nLocation: https://blob.example.com:443/a?b=c\r\n"

        #expect(GhResponseHeaders(output: output).lastValue(of: "location")
            == "https://blob.example.com:443/a?b=c")
    }
}
