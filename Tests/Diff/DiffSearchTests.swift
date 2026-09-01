import Foundation
import Testing

@testable import PRism

/// Hledání v diffu nad modelem (#152).
///
/// Testuje se **výčtem nad čistou funkcí**: co se najde, co se nenajde a v jakém pořadí. Nejcennější
/// jsou tady ta negativní tvrzení — že se **nehledá mimo hunky** (rozsah, o kterém pruh mluví)
/// a že prázdný dotaz nenajde nic. Obojí se rozbije potichu: v okně by to vypadalo jako čistý
/// výsledek.
@Suite("Hledání v diffu — model")
struct DiffSearchTests {
    private func diff(path: String = "src/Vault/SecretClient.php") -> Diff {
        DiffParser.parse([
            "diff --git a/\(path) b/\(path)",
            "--- a/\(path)",
            "+++ b/\(path)",
            "@@ -96,6 +96,7 @@",
            "     private const FLUSH_TIMEOUT = 5;",
            " ",
            "-        $this->client->put($key, $value, ['timeout' => self::FLUSH_TIMEOUT]);",
            "+        $this->client->putMultiple($chunk, ['timeout' => self::FLUSH_TIMEOUT_MS]);",
            "+        $this->logger->debug('flushed');",
            " }",
        ].joined(separator: "\n"))
    }

    private func query(_ text: String, caseSensitive: Bool = false) -> DiffSearchQuery {
        DiffSearchQuery(text: text, isCaseSensitive: caseSensitive)
    }

    // MARK: - Porovnávání na řádku

    @Test("Nerozlišuje velikost, dokud se o to neřekne")
    func ignoresCaseByDefault() {
        let text = "let Total = TOTAL + total"
        #expect(DiffSearch.ranges(in: text, query: query("total")).count == 3)
        #expect(DiffSearch.ranges(in: text, query: query("total", caseSensitive: true)).count == 1)
    }

    /// `.literal` v porovnání je rozhodnutí, ne detail: v kódu se hledá jméno, takže `e` se nemá
    /// shodovat s `é`. Že se `.literal` a `.caseInsensitive` **dají kombinovat**, je ověřené
    /// spuštěním tady, ne přečtené v dokumentaci.
    @Test("Diakritiku nesjednocuje")
    func doesNotFoldDiacritics() {
        #expect(DiffSearch.ranges(in: "let cena = 1", query: query("céna")).isEmpty)
        #expect(DiffSearch.ranges(in: "let céna = 1", query: query("CÉNA")).count == 1)
    }

    @Test("Prázdný dotaz nenajde nic")
    func emptyQueryFindsNothing() {
        #expect(DiffSearch.ranges(in: "cokoli", query: query("")).isEmpty)
        #expect(!query("").isActive)
    }

    /// Překrývající se výskyty se **nepočítají dvakrát**: dva podklady nad týmiž znaky by se
    /// v textu složily do jednoho a počet by pak tvrdil něco, co v okně vidět není.
    @Test("Výskyty se nepřekrývají")
    func matchesDoNotOverlap() {
        let ranges = DiffSearch.ranges(in: "aaaa", query: query("aa"))
        #expect(ranges.count == 2)
        #expect(ranges.map { "aaaa".distance(from: "aaaa".startIndex, to: $0.lowerBound) } == [0, 2])
    }

    /// Emoji je jeden `Character`, ale **dva** kódy v UTF-16 — a právě v nich měří
    /// `NSAttributedString`, do kterého se zvýraznění nasazuje. Rozsah proto musí umět přežít
    /// převod, jinak podklad sedne o kus doprava (tatáž třída chyby jako u #275).
    @Test("Rozsah přežije převod na UTF-16 i za emoji")
    func rangesSurviveUTF16Conversion() {
        let text = "// 🚀 flush(FLUSH_TIMEOUT)"
        let ranges = DiffSearch.ranges(in: text, query: query("FLUSH_TIMEOUT"))
        let range = try! #require(ranges.first)
        let nsRange = NSRange(range, in: text)
        #expect((text as NSString).substring(with: nsRange) == "FLUSH_TIMEOUT")
    }

    // MARK: - Výskyty v souboru

    @Test("Najde v kontextu, v odebraném i v přidaném řádku")
    func findsInEveryKindOfLine() throws {
        let file = try #require(diff().files.first)
        let hits = DiffSearch.hits(in: file, query: query("FLUSH_TIMEOUT"))
        #expect(hits.count == 3)
        #expect(hits.map(\.line.kind) == [.context, .removed, .added])
        #expect(hits.allSatisfy { $0.path == "src/Vault/SecretClient.php" })
        #expect(hits.allSatisfy { $0.occurrence == 0 })
    }

    /// Pořadí je pořadí **na obrazovce**, ne podle druhu řádku ani podle čísla: podle něj skáčou
    /// šipky, takže obrácené pořadí by znamenalo, že `↓` jde nahoru.
    @Test("Pořadí výskytů je pořadí řádků")
    func hitsFollowTheRowOrder() throws {
        let file = try #require(diff().files.first)
        // `$this` je na odebraném řádku, na tom přidaném s `putMultiple` a na `logger` řádku pod ním.
        let hits = DiffSearch.hits(in: file, query: query("$this"))
        #expect(hits.map { $0.line.text.contains("putMultiple") } == [false, true, false])
        #expect(hits.map(\.line.kind) == [.removed, .added, .added])
    }

    @Test("Víc výskytů na řádku je víc zastávek")
    func countsEveryOccurrenceOnALine() {
        let diff = DiffParser.parse([
            "diff --git a/a.php b/a.php",
            "--- a/a.php",
            "+++ b/a.php",
            "@@ -1,1 +1,1 @@",
            "+$key = $key . $key;",
        ].joined(separator: "\n"))
        let file = diff.files[0]
        #expect(DiffSearch.hits(in: file, query: query("$key")).map(\.occurrence) == [0, 1, 2])
    }

    /// **Tohle je to negativní tvrzení, na kterém stojí věta v pruhu**: mimo hunky se nehledá.
    /// Kdyby se hledalo v obsahu souboru, přestal by být rozsah tím, co pruh říká.
    @Test("Mimo hunky se nehledá, dokud se kontext nerozbalí")
    func doesNotSearchOutsideTheHunks() throws {
        let file = try #require(diff().files.first)
        // Řádek 1 souboru v žádném hunku není — hunk začíná na 96.
        let content = (1...120).map { $0 == 1 ? "use Psr\\Log\\LoggerInterface;" : "// řádek \($0)" }

        #expect(DiffSearch.hits(in: file, query: query("LoggerInterface")).isEmpty)

        var revealed = RevealedLines()
        revealed.reveal(1...95)
        let afterReveal = DiffSearch.hits(
            in: file,
            query: query("LoggerInterface"),
            revealed: revealed,
            content: content
        )
        #expect(afterReveal.count == 1)
        #expect(afterReveal.first?.line.newNumber == 1)
    }

    @Test("Binárka ani soubor beze změny obsahu nic nenajde")
    func findsNothingInFilesWithoutHunks() {
        let binary = FileDiff(
            oldPath: "logo.png",
            newPath: "logo.png",
            change: .modified,
            isBinary: true,
            hunks: []
        )
        let empty = FileDiff(oldPath: "a.php", newPath: "b.php", change: .renamed, isBinary: false, hunks: [])
        #expect(DiffSearch.hits(in: binary, query: query("png")).isEmpty)
        #expect(DiffSearch.hits(in: empty, query: query("php")).isEmpty)
    }

    // MARK: - Výskyty v celém diffu a počty

    @Test("Napříč soubory se hledá v pořadí, ve kterém jsou v diffu")
    func walksFilesInOrder() {
        let text = [
            "diff --git a/first.php b/first.php",
            "--- a/first.php",
            "+++ b/first.php",
            "@@ -1,1 +1,2 @@",
            " const TIMEOUT = 1;",
            "+const TIMEOUT_MS = 1000;",
            "diff --git a/second.php b/second.php",
            "--- a/second.php",
            "+++ b/second.php",
            "@@ -1,1 +1,1 @@",
            "+$timeout = TIMEOUT;",
        ].joined(separator: "\n")
        let hits = DiffSearch.hits(in: DiffParser.parse(text), query: query("TIMEOUT")) { _ in FileExpansion() }
        // Ve `second.php` jsou dva: `$timeout` i `TIMEOUT` — hledání nerozlišuje velikost, dokud
        // se o to neřekne, takže i tohle je součást tvrzení.
        #expect(hits.map(\.path) == ["first.php", "first.php", "second.php", "second.php"])
        #expect(DiffSearch.counts(of: hits) == ["first.php": 2, "second.php": 2])

        let strict = DiffSearch.hits(
            in: DiffParser.parse(text),
            query: query("TIMEOUT", caseSensitive: true)
        ) { _ in FileExpansion() }
        #expect(DiffSearch.counts(of: strict) == ["first.php": 2, "second.php": 1])
    }

    /// Klíčem počtu je `displayPath` — tedy to, co kreslí hlavička souboru. Se starou cestou
    /// přejmenovaného souboru by se kapsle s počtem nepotkala se svým souborem.
    @Test("Počet se klíčuje cestou, pod kterou soubor v okně vystupuje")
    func countsUseTheDisplayPath() {
        let text = [
            "diff --git a/old/Name.php b/new/Name.php",
            "similarity index 90%",
            "rename from old/Name.php",
            "rename to new/Name.php",
            "--- a/old/Name.php",
            "+++ b/new/Name.php",
            "@@ -1,1 +1,1 @@",
            "+const TIMEOUT = 1;",
        ].joined(separator: "\n")
        let diff = DiffParser.parse(text)
        let hits = DiffSearch.hits(in: diff, query: query("TIMEOUT")) { _ in FileExpansion() }
        #expect(DiffSearch.counts(of: hits) == ["new/Name.php": 1])
    }

    @Test("Prázdný dotaz nevrátí výskyty ani nad celým diffem")
    func emptyQueryOverTheWholeDiff() {
        #expect(DiffSearch.hits(in: diff(), query: query("")) { _ in FileExpansion() }.isEmpty)
    }

    // MARK: - Kotva skoku

    /// **Kotva se musí trefit do něčeho, co v seznamu doopravdy je** — tentýž invariant, jaký
    /// u nálezů hlídá `DiffJumpTargetTests`. Ve split pohledu nese dvojice `id` **pravého** řádku,
    /// takže výskyt na odebraném řádku je zrovna ten případ, který se rozbije potichu: `scrollTo`
    /// na neexistující `id` neudělá nic.
    @Test("Kotva výskytu je v seznamu, v obou pohledech", arguments: [DiffLayout.unified, .split])
    func anchorsExistInTheList(layout: DiffLayout) throws {
        let diff = diff()
        let file = try #require(diff.files.first)
        let rows = DiffRow.rows(of: file, layout: layout)
        let blocked = layout == .split ? DiffRow.blockedPairs(rows) : DiffRow.blocked(rows)
        let ids = Set(blocked.map(\.id))
        let index = DiffRow.blockIDs(in: blocked)

        for hit in DiffSearch.hits(in: file, query: query("FLUSH_TIMEOUT")) {
            let anchor = try #require(DiffRow.anchor(in: diff, hit: hit, layout: layout))
            #expect(ids.contains(index[anchor] ?? anchor), "kotva \(anchor) není v seznamu")
        }
    }

    @Test("Kotva výskytu v rozbaleném kontextu ukazuje na jeho řádek")
    func anchorsRevealedLines() throws {
        let diff = diff()
        let file = try #require(diff.files.first)
        let content = (1...120).map { $0 == 1 ? "use Psr\\Log\\LoggerInterface;" : "// řádek \($0)" }
        var revealed = RevealedLines()
        revealed.reveal(1...95)
        let hit = try #require(
            DiffSearch.hits(in: file, query: query("LoggerInterface"), revealed: revealed, content: content).first
        )
        let anchor = try #require(
            DiffRow.anchor(in: diff, hit: hit, revealed: revealed, content: content)
        )
        #expect(anchor == "\(file.id)|c1")
    }

    /// Když řádek v seznamu není (mezitím přišel nový commit, kontext se sbalil), vrací se
    /// **soubor** — odskočit aspoň na něj je pořád lepší než nehnout se. Nikdy ne `nil` u souboru,
    /// který v diffu je.
    @Test("Zmizelý řádek skočí aspoň na soubor")
    func fallsBackToTheFile() throws {
        let diff = diff()
        let file = try #require(diff.files.first)
        let ghost = DiffSearchHit(
            path: file.displayPath,
            line: DiffLine(kind: .added, oldNumber: nil, newNumber: 9999, text: "FLUSH_TIMEOUT"),
            occurrence: 0
        )
        #expect(DiffRow.anchor(in: diff, hit: ghost) == file.id)
    }

    @Test("Výskyt v souboru, který v diffu není, kotvu nedostane")
    func unknownFileHasNoAnchor() {
        let hit = DiffSearchHit(
            path: "nikde.php",
            line: DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: "x"),
            occurrence: 0
        )
        #expect(DiffRow.anchor(in: diff(), hit: hit) == nil)
    }
}
