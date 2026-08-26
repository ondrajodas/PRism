import Foundation
import Testing

@testable import PRism

/// **Které podoby `DiffRow` se v diffu doopravdy nakreslí** (#446).
///
/// `DiffView` sype do `ForEach` vždycky výsledek `DiffRow.blocked(_:)`, resp.
/// `blockedPairs(_:)` — a ty slijí **každý** `.line` do `.block`, resp. **každou** `.pair`
/// do `.pairBlock`. Do `DiffRowView` proto z diffu žádná `.pair` nedojde a `.line` jen
/// v jediném případě, který `paired(_:)` nechává celý: **poznámka `git`u ve split pohledu**
/// (`\ No newline at end of file`).
///
/// Proč to má vlastní sadu: mrtvá větev svádí k tomu se na ni spolehnout. U #438 se kvůli ní
/// hledal výkonový problém na špatném místě — zadání znělo „neviditelný diff počítá geometrii
/// svých řádků“ a měření pak ukázalo, že diff se na geometrii řádku neptá ani vepředu, protože
/// řádky kreslí bloky. Bez tvrzení nad daty je „tahle větev je kulisa“ jen domněnka, kterou
/// nikdo nepřečte.
///
/// **Tvrdí se to z obou stran.** Nula `.pair` v nakresleném seznamu by sama o sobě mohla
/// znamenat i „test si vyrobil diff, ve kterém dvojice nejsou“, takže je vedle toho kontrola
/// měřidla: v mezikroku (`DiffRow.rows(of:layout:.split)`) dvojice **být musí**. A protože
/// `rendered(_:layout:)` je opis toho výrazu z `DiffView`, hlídá stráž nad zdrojákem, že jiná
/// cesta do `DiffRowView` nevede.
@Suite("Co diff kreslí za řádky (#446)")
struct DiffRenderedRowsTests {
    /// Skutečné výstupy `gh pr diff` — na vymyšleném diffu by tvrzení platilo o fixture,
    /// ne o diffu.
    private static let fixtures = [
        "gh/pr-diff-ordinary.diff",
        "gh/pr-diff-rename.diff",
        "gh/pr-diff-deleted.diff",
        "gh/pr-diff-crlf.diff",
        "gh/pr-diff-binary.diff",
    ]

    private static let layouts: [DiffLayout] = [.unified, .split]

    /// Seznam, který `DiffView` sype do `ForEach`.
    ///
    /// Je to **opis** výrazu z `DiffView.rows(of:)`, ne volání téže funkce — ten výraz je uvnitř
    /// `some View`, tedy odsud nedosažitelný. Že se ty dva nerozejdou, drží stráž
    /// `theDiffFeedsTheRowViewFromOnePlace()`.
    private func rendered(_ file: FileDiff, layout: DiffLayout, threads: [ReviewThread] = []) -> [DiffRow] {
        let rows = DiffRow.rows(of: file, layout: layout, threads: threads)
        return layout == .split ? DiffRow.blockedPairs(rows) : DiffRow.blocked(rows)
    }

    private func files(_ fixture: String) throws -> [FileDiff] {
        DiffParser.parse(try Fixture.text(fixture)).files
    }

    private func lines(in rows: [DiffRow]) -> [DiffLine] {
        rows.compactMap { row in
            guard case .line(_, let line) = row else { return nil }
            return line
        }
    }

    private func pairs(in rows: [DiffRow]) -> [(left: DiffLine?, right: DiffLine?)] {
        rows.compactMap { row in
            guard case .pair(_, let left, let right) = row else { return nil }
            return (left, right)
        }
    }

    /// Cizí vlákno u řádku — blok se na něm přeruší, takže se z jednoho udělají dva.
    private func thread(path: String, line: Int) -> ReviewThread {
        ReviewThread(
            id: "t\(line)",
            path: path,
            line: line,
            originalLine: line,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }

    /// Soubor, ve kterém `git` uvnitř hunku poznamenává chybějící konec řádku. Fixture na to
    /// v repu není — všechny stažené diffy jsou ze souborů, které konec řádku mají.
    private func fileWithAGitNote() throws -> FileDiff {
        let diff = DiffParser.parse([
            "diff --git a/Cart.php b/Cart.php",
            "--- a/Cart.php",
            "+++ b/Cart.php",
            "@@ -25,4 +25,4 @@",
            " kontext",
            "-staré",
            "\\ No newline at end of file",
            "+nové",
            " další",
        ].joined(separator: "\n"))
        return try #require(diff.files.first)
    }

    // MARK: - `.pair` se nekreslí nikdy

    /// **To hlavní u #446.** Dvojice je mezikrok mezi `paired(_:)` a `blockedPairs(_:)`; ke
    /// kreslení se nedostane v žádném pohledu a u žádného druhu souboru.
    @Test("Dvojice se do kreslení nedostane", arguments: fixtures, layouts)
    func noPairIsEverRendered(fixture: String, layout: DiffLayout) throws {
        for file in try files(fixture) {
            #expect(
                pairs(in: rendered(file, layout: layout)).isEmpty,
                "\(file.displayPath) v pohledu \(layout) poslal ke kreslení dvojici"
            )
        }
    }

    /// Bubliny blok **ukončují**, takže je to zrovna ten vstup, po kterém by osamocená dvojice
    /// mohla zbýt — kdyby `blockedPairs(_:)` slévala jen souvislé úseky delší než jeden řádek.
    @Test("Dvojice nezbude ani mezi bublinami", arguments: layouts)
    func noPairSurvivesBetweenBubbles(layout: DiffLayout) throws {
        let file = try #require(try files("gh/pr-diff-ordinary.diff").first)
        let inTheMiddle = try #require(file.hunks.first?.lines.compactMap(\.newNumber).dropFirst().first)

        let rows = rendered(file, layout: layout, threads: [thread(path: file.displayPath, line: inTheMiddle)])

        // Kontrola měřidla: bez rozťatého bloku by tvrzení platilo o jiném vstupu, než o jaký jde.
        #expect(rows.contains { if case .thread = $0 { true } else { false } })
        #expect(pairs(in: rows).isEmpty)
    }

    /// Kontrola měřidla: kdyby dvojice nebyly ani v mezikroku, netvrdila by nula výš nic.
    @Test("V mezikroku dvojice být musí")
    func pairsExistBeforeBlocking() throws {
        let file = try #require(try files("gh/pr-diff-ordinary.diff").first)

        #expect(!pairs(in: DiffRow.rows(of: file, layout: .split)).isEmpty)
    }

    // MARK: - `.line` se kreslí jen jako poznámka `git`u ve split pohledu

    /// V pohledu pod sebou se slévá **všechno**, i poznámka `git`u — ta je v bloku jen ztlumený
    /// řádek (viz `DiffBlockCompositionTests`).
    @Test("V pohledu pod sebou nezbude ani jeden samostatný řádek", arguments: fixtures)
    func noLineSurvivesUnified(fixture: String) throws {
        for file in try files(fixture) {
            #expect(
                lines(in: rendered(file, layout: .unified)).isEmpty,
                "\(file.displayPath) poslal ke kreslení samostatný řádek"
            )
        }
        #expect(lines(in: rendered(try fileWithAGitNote(), layout: .unified)).isEmpty)
    }

    /// **Druhá polovina odpovědi na #446**: větev `.line` v `DiffRowView` mrtvá **není**.
    /// `paired(_:)` nechává `meta` řádek celý (poznámka `git`u není obsah souboru, takže nemá
    /// stranu) a `blockedPairs(_:)` slévá jen dvojice — do `DiffRowView` tedy dojde jako `.line`.
    @Test("Poznámka gitu zůstane ve split pohledu samostatným řádkem")
    func theGitNoteStaysALineInSplit() throws {
        let rendered = rendered(try fileWithAGitNote(), layout: .split)

        let lines = lines(in: rendered)
        #expect(lines.count == 1)
        #expect(lines.first?.kind == .meta)
        #expect(lines.first?.text == "No newline at end of file")
        // A kód kolem ní se pořád kreslí bloky — poznámka je výjimka, ne návrat k řádkům.
        #expect(rendered.contains { if case .pairBlock = $0 { true } else { false } })
    }

    /// Ve staženém diffu poznámka není, takže by se dalo uvěřit, že větev `.line` živá není.
    /// Tenhle test říká, že to je vlastnost fixtures, ne kódu.
    @Test("Ve stažených diffech poznámka není", arguments: fixtures)
    func theFixturesCarryNoGitNote(fixture: String) throws {
        for file in try files(fixture) {
            #expect(lines(in: rendered(file, layout: .split)).isEmpty, "\(file.displayPath)")
        }
    }

    // MARK: - Stráž nad zdrojáky

    /// `DiffRowView` se plní **z jednoho místa a jedním výrazem**.
    ///
    /// Bez toho by tvrzení výš platila o funkci, kterou si testy zavolaly samy. Druhý volající
    /// `DiffRowView` (nebo výraz bez slévání) by znamenal, že do kreslení vede cesta, na kterou
    /// tahle sada nedosáhne — tatáž konstrukce jako `SingleWayOutTests`.
    @Test("Do kreslení řádků vede jediná cesta")
    func theDiffFeedsTheRowViewFromOnePlace() throws {
        let callers = try Self.sources(matching: "DiffRowView(")
        #expect(callers == ["DiffView.swift"], "DiffRowView má plnit jedině DiffView")
        #expect(
            try Self.source(of: "DiffView")
                .contains("layout == .split ? DiffRow.blockedPairs(rows) : DiffRow.blocked(rows)"),
            "seznam ke kreslení se má skládat slitím do bloků"
        )
    }

    /// Druhá cesta, jak nakreslit dvojici řádků, v aplikaci **není**.
    ///
    /// `DiffPairView` byl přesně to: sto řádků paralelního kreslení, na které se od #157
    /// nedostalo, protože `blockedPairs(_:)` slije i jedinou dvojici. Zůstal `DiffPairBlockView`.
    ///
    /// Nedosažitelná větev `.pair` proto **nekreslí prázdno**, ale týž blok jako každá jiná
    /// dvojice — tichá díra v diffu je horší než řádek navíc. Že to opravdu vyjde stejně, je
    /// ověřené renderem (obě větve daly bajt po bajtu tentýž PNG, viz popis PR k #446); tady
    /// zbývá to, co jde tvrdit bez okna: obě vedou do jedné funkce.
    @Test("Dvojici umí nakreslit jediný view")
    func onlyOneViewDrawsAPairOfLines() throws {
        #expect(try Self.sources(matching: "DiffPairView(").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: Self.views.appending(path: "DiffPairView.swift").path))

        let row = try Self.source(of: "DiffRowView")
        #expect(
            row.ranges(of: "DiffPairBlockRowView(").count == 1,
            "dvojici má skládat jedno místo, jinak se ty dvě větve rozejdou"
        )
        #expect(row.contains("pairBlock(id, DiffPairBlock(left: [left], right: [right], ids: [id]))"))
    }

    /// Kontrola, že se zdrojáky doopravdy čtou — jinak by prázdný nález prošel jako splněné
    /// tvrzení.
    @Test("Zdrojáky se doopravdy čtou")
    func theSourcesAreActuallyRead() throws {
        #expect(try Self.source(of: "DiffView").count > 500)
        #expect(try Self.source(of: "DiffRowView").count > 500)
        // Že se prochází **celé `App/`**, ne jen `App/Views`: `DiffRow.swift` leží v `App/Diff/`,
        // takže bez rekurze by v seznamu nebyl — a prázdný nález výš by mohl znamenat i „druhá
        // cesta leží ve složce, kam se stráž nedívá“.
        #expect(try Self.swiftFiles().contains { $0.lastPathComponent == "DiffRow.swift" })
        // A že slévání do bloků volá taky jen `DiffView` — druhý skladatel seznamu ke kreslení by
        // znamenal druhou cestu, i kdyby `DiffRowView` plnil pořád jeden.
        #expect(try Self.sources(matching: "DiffRow.blockedPairs(") == ["DiffView.swift"])
    }

    private static let app = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "App")

    private static let views = app.appending(path: "Views")

    /// Všechny zdrojáky aplikace, **rekurzivně** — ne jen `App/Views`. Volající `DiffRowView` může
    /// v principu ležet kdekoli, a stráž, která se dívá do jedné složky, by druhou cestu
    /// nenašla. Tatáž konstrukce jako `SingleWayOutTests`.
    private static func swiftFiles() throws -> [URL] {
        guard let walker = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else {
            throw SourceError.unreadable(app.path)
        }
        let files = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        guard !files.isEmpty else { throw SourceError.unreadable(app.path) }
        return files
    }

    private enum SourceError: Error {
        case unreadable(String)
    }

    /// Jména zdrojáků, ve kterých vzor stojí mimo komentář.
    private static func sources(matching needle: String) throws -> [String] {
        try swiftFiles()
            .filter { try source(at: $0).contains(needle) }
            .map(\.lastPathComponent)
            .sorted()
    }

    private static func source(of view: String) throws -> String {
        try source(at: views.appending(path: "\(view).swift"))
    }

    /// Zdroják **bez řádkových komentářů** — tatáž konstrukce jako v `SingleWayOutTests`
    /// a `DiffLineGeometryTests`: o obou views se v repu píše v próze, takže by je vysvětlující
    /// komentáře nacházely samy a stráž by tvrdila pravý opak toho, co má.
    private static func source(at url: URL) throws -> String {
        let text = try String(contentsOf: url, encoding: .utf8)
        return TextLines.content(text)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}
