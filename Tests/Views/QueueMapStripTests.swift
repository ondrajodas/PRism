import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Mini pás mapy PR v řádku fronty (#502).
///
/// Tři třídy tvrzení, a dvě z nich se dají pokazit **potichu**:
///
/// - **výška řádku fronty se nemění** (#325). Pás je šest bodů vysoký a řádek má dvě řádky textu,
///   takže se do nich vejde — ale kdyby ne, fronta by se s prvním doběhlým review posunula
///   a nešlo by poznat, čím. Měří se `fittingSize` mimo obrazovku, ne odhadem z konstant;
/// - **pás se vejde i do nejužšího okna**. Řádek si vedle něj drží titulek a odznak stavu; 636
///   bodů je nejmenší šířka obsahu (nejužší okno bez railu), a i tam musí řádek zůstat na jedné
///   řádce;
/// - **druhá kresba pásu v okně není** — tvrdí se to nad zdrojáky. Kdyby si mini pás barvy
///   dosadil sám, rozešly by se s velkým pásem tak, že by si toho všiml jedině člověk, který
///   vidí obojí naráz.
@Suite("Mini pás mapy PR v řádku (#502)")
@MainActor
struct QueueMapStripTests {
    // MARK: - Měřená výška a šířka

    @Test("Pás výšku řádku fronty nezvedne")
    func doesNotGrowTheRow() {
        // Kdyby pás výšku zvedl, fronta by se posunula po prvním doběhlém review — a nešlo by
        // poznat, jestli přibyl řádek, nebo se jen zvětšil.
        #expect(height(of: row(map: map())) == height(of: row(map: nil)))
    }

    @Test("V nejužším okně zůstává řádek s pásem na jedné řádce")
    func fitsTheNarrowestWindow() {
        // 636 bodů je obsah nejužšího okna bez railu. Kdyby se titulek s pásem a odznakem
        // nevešel, `HStack` by ho zalomil — a to je na výšce vidět.
        let narrow = height(of: row(map: map()), width: 636)
        let wide = height(of: row(map: map()), width: 900)

        #expect(narrow == wide, "v 636 b vyšlo \(narrow), v 900 b \(wide)")
        #expect(narrow == height(of: row(map: nil), width: 636))
    }

    /// Pás si o velikost **říká sám a pevně** (#375, #220): v řádku líného seznamu se
    /// nevyjednává, takže `Canvas` dostane rámec, ne pružinu. Bez rámce by vyšel nulový —
    /// `Canvas` si o šířku sám neřekne.
    @Test("Pás má pevných 110 × 6 bodů")
    func hasAFixedSize() {
        let hosting = NSHostingView(rootView: QueueMapStrip(map: map()))

        #expect(hosting.fittingSize == CGSize(width: QueueMapStrip.width, height: QueueMapStrip.height))
    }

    /// **Sedm souborů se do 110 bodů vejde tak, že je na ně vidět** — tvrzení o té konkrétní
    /// šířce, ne o pravidle (to má `PullRequestMapTests`). Nejmenší segment má 4,2 bodu, tedy
    /// nad minimem, a mezery zůstávají; pás v řádku je proto pořád mapa, ne barevný pruh.
    @Test("Nad referenčním rozložením je v pásu vidět každý soubor")
    func everyFileStaysVisible() {
        let geometry = PullRequestMapGeometry(
            segments: map().segments,
            width: QueueMapStrip.width,
            spacing: QueueMapStrip.spacing
        )

        #expect(geometry.spacing == QueueMapStrip.spacing)
        #expect(geometry.widths.allSatisfy { $0 >= Policy.mapSegmentMinimum - 0.001 })
        // Poslední segment končí na hraně pásu — vpravo nezbývá prázdný pruh, který by se čtl
        // jako „a tady už nic není“.
        #expect(abs(geometry.end - QueueMapStrip.width) < 0.001)
    }

    // MARK: - Jedna kresba, jedno skládání

    /// **Plochu segmentů kreslí jedna funkce.** Hledá se v kódu bez řádkových komentářů a bez
    /// mezer (`Source.condensed`), protože o mapě se v komentářích mluví na deseti místech —
    /// stráž nad surovým textem by tvrdila něco jiného než tenhle test.
    @Test("Barvu segmentu rozhoduje jediné místo")
    func onlyOnePlacePaintsASegment() throws {
        let painting = try sources(matching: "Policy.mapFill(")

        #expect(painting == ["App/Views/PullRequestMapView.swift"], "kreslí to \(painting)")
        // A mini pás si kresbu **půjčuje**, nekreslí vlastní: kdyby v něm stálo `context.fill`,
        // byl by to druhý výklad toho, co je červený a co tlumený segment.
        let strip = try condensed(at: "App/Views/QueueMapStrip.swift")
        #expect(strip.contains("PullRequestMapView.drawSegments("))
        #expect(!strip.contains("context.fill("))
    }

    /// **Mapu skládá jedna funkce `Policy`, a volají ji dvě místa**: detail PR (pás pod hlavičkou)
    /// a store (pás v řádku fronty). Třetí volající by znamenal třetí podobu téže mapy.
    @Test("Mapu skládají dvě místa, obojí přes Policy")
    func twoPlacesComposeTheMap() throws {
        let composing = try sources(matching: "Policy.pullRequestMap(")

        #expect(
            composing == ["App/Store/AppStore+QueueMap.swift", "App/Views/PullRequestDetailView.swift"],
            "skládá to \(composing)"
        )
    }

    /// **`SpectrumBar` odešel** (#502) — a s ním jméno `ReviewerShare`. Tvrdí se to nad
    /// zdrojáky, protože mrtvý typ nic neshodí: zůstal by ležet a sváděl by na něj sáhnout.
    @Test("Spektrum reviewerů v aplikaci není")
    func theSpectrumIsGone() throws {
        #expect(try sources(matching: "ReviewerShare").isEmpty)
        #expect(try sources(matching: "SpectrumBar").isEmpty)
    }

    // MARK: - Příprava

    /// Referenční rozložení ze sekce 42 návrhu — sedm souborů `keboola/vault#85`, ve kterých
    /// `composer.lock` mění 2 790 řádků. **Tatáž data jako v `PullRequestMapTests`**, aby se
    /// měřená šířka a testované pravidlo bavily o jednom pásu.
    private func map() -> PullRequestMap {
        Policy.pullRequestMap(
            files: [
                ("src/Vault/SecretClient.php", 24),
                ("src/Vault/Encryptor.php", 43),
                ("src/Vault/SecretNotFound.php", 21),
                ("tests/SecretClientTest.php", 64),
                ("composer.json", 4),
                ("composer.lock", 2790),
                ("phpunit.xml.dist", 6),
            ].map(file(_:))
        )
    }

    private func file(_ input: (path: String, lines: Int)) -> FileDiff {
        FileDiff(
            oldPath: input.path,
            newPath: input.path,
            change: .modified,
            isBinary: false,
            hunks: [
                DiffHunk(
                    oldStart: 1,
                    oldCount: input.lines,
                    newStart: 1,
                    newCount: input.lines,
                    heading: "",
                    lines: (0..<input.lines).map {
                        DiffLine(kind: .added, oldNumber: nil, newNumber: $0 + 1, text: "nové")
                    }
                )
            ],
            blobs: "aaa..bbb"
        )
    }

    private func row(map: PullRequestMap?) -> PullRequestRow {
        PullRequestRow(
            pullRequest: PullRequestSummary(
                id: PRIdentifier("keboola/vault#85")!,
                title: "chore: modernize dependencies (Symfony 8-ready, PHPUnit 11)",
                author: "odinuv",
                url: URL(string: "https://github.com/keboola/vault/pull/85")!,
                updatedAt: Date(timeIntervalSince1970: 1_000_000),
                state: .open
            ),
            reviewState: .completed(findings: 3),
            row: QueueRow(blocking: 1),
            map: map
        )
    }

    /// Rozvržení mimo obrazovku — accessibility tree se v okně mimo obrazovku nenaplní (změřeno
    /// u #269), zato `fittingSize` odpoví. Tatáž cesta jako `PullRequestRowPromptTests`.
    private func height(of row: PullRequestRow, width: Double = 520) -> Double {
        NSHostingView(rootView: row.frame(width: width)).fittingSize.height
    }

    // MARK: - Stráž nad zdrojáky

    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Cesty zdrojáků v `App/`, ve kterých ten řetězec stojí **v kódu**. Prázdný výsledek u vzoru,
    /// který má být vidět, je chyba stráže, ne zelený test — proto se čtení souborů nedá spolknout.
    private func sources(matching pattern: String) throws -> [String] {
        let root = Self.repository.appending(path: "App")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw SourceError.unreadable(root.path)
        }
        var hits: [String] = []
        var seen = 0
        for case let url as URL in walker where url.pathExtension == "swift" {
            seen += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            guard Self.condensed(text).contains(pattern.filter { !$0.isWhitespace }) else { continue }
            hits.append(url.path.replacingOccurrences(of: Self.repository.path + "/", with: ""))
        }
        // Kdyby se `App/` nepřečetlo, vyšlo by „nikde to není“ na každý vzor.
        guard seen > 100 else { throw SourceError.unreadable("v App/ jen \(seen) zdrojáků") }
        return hits.sorted()
    }

    private func condensed(at path: String) throws -> String {
        Self.condensed(try String(contentsOf: Self.repository.appending(path: path), encoding: .utf8))
    }

    /// Kód **bez řádkových komentářů a bez mezer**. Komentáře se odečítají, protože se o mapě
    /// v nich píše; mezery proto, že ve Swiftu je mezera uvnitř volání volná (#490, #550).
    private static func condensed(_ text: String) -> String {
        // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
        TextLines.content(text)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
            .filter { !$0.isWhitespace }
    }

    private enum SourceError: Error {
        case unreadable(String)
    }
}
