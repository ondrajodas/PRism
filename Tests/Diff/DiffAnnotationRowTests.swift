import Foundation
import Testing

@testable import PRism

/// **Věta *proč* jako vlastní řádek mezi bloky** (#525).
///
/// Dvě tvrzení, na kterých to stojí, se rozbijí potichu:
///
/// 1. **Bloky kódu zůstanou, jaké byly** — tedy tytéž identity a tytéž řádky v nich. Kdyby věta
///    blok rozťala, změnila by se jeho výška a s ní i skok na nález (`DiffRow.blockSpot`) a karty
///    v okraji (#503). Výšku měří `DiffAnnotationRoomTests` na nakresleném bloku; tady se tvrdí
///    **složení**, které tu výšku určuje.
/// 2. **Kde není souřadnice hunku, není ani věta.** Rozbalený kontext hunky slévá (`merged`)
///    a řádky pak jdou nepřetržitě za sebou; věta uprostřed by z jednoho bloku udělala dva.
@Suite("Věta proč v řádcích diffu (#525)")
struct DiffAnnotationRowTests {
    private static let layouts: [DiffLayout] = [.unified, .split]

    private func claudeFile() throws -> FileDiff {
        let diff = DiffParser.parse(try Fixture.text("gh/pr-diff-ordinary.diff"))
        return try #require(diff.files.first { $0.displayPath == "CLAUDE.md" })
    }

    private func annotations(_ indexes: [Int]) -> [Int: HunkAnnotation] {
        Dictionary(uniqueKeysWithValues: indexes.map { index in
            (
                index,
                HunkAnnotation(
                    file: "CLAUDE.md",
                    hunk: index + 1,
                    why: "Rozepisuje tvrdou podmínku, aby se dala kontrolovat grepem.",
                    source: index == 0 ? "z commitu docs: rozepsat podmínku" : nil
                )
            )
        })
    }

    /// Seznam tak, jak ho `DiffView` sype do `ForEach` — tedy **po slití do bloků**.
    private func rendered(
        _ file: FileDiff,
        layout: DiffLayout,
        annotations: [Int: HunkAnnotation] = [:],
        revealed: RevealedLines = RevealedLines(),
        content: [String] = []
    ) -> [DiffRow] {
        let rows = DiffRow.rows(
            of: file,
            layout: layout,
            revealed: revealed,
            content: content,
            annotations: annotations
        )
        return layout == .split ? DiffRow.blockedPairs(rows) : DiffRow.blocked(rows)
    }

    private func sentences(_ rows: [DiffRow]) -> [HunkAnnotation] {
        rows.compactMap { row in
            guard case .annotation(_, let annotation) = row else { return nil }
            return annotation
        }
    }

    /// Složení bloků kódu: identita a řádky v každém z nich. **To je to, co určuje výšku** —
    /// proto se srovnává tohle, a ne délka seznamu.
    private func blocks(_ rows: [DiffRow]) -> [(id: String, lines: Int)] {
        rows.compactMap { row in
            switch row {
            case .block(let id, let block): (id, block.lines.count)
            case .pairBlock(let id, let pair): (id, pair.count)
            default: nil
            }
        }
    }

    // MARK: - Kde věta stojí

    @Test("Věta stojí hned pod souřadnicí svého hunku", arguments: Self.layouts)
    func theSentenceSitsRightBelowItsHunkHeader(layout: DiffLayout) throws {
        let rows = rendered(try claudeFile(), layout: layout, annotations: annotations([0, 1]))

        let spots = rows.indices.filter { if case .annotation = rows[$0] { true } else { false } }
        #expect(spots.count == 2)
        for spot in spots {
            guard case .hunk = rows[spot - 1] else {
                Issue.record("nad větou nestojí hlavička hunku, ale \(rows[spot - 1])")
                return
            }
        }
    }

    /// **Bez anotací ani jeden řádek navíc.** Je to měřidlo pro test níž: kdyby seznam nesl větu
    /// vždycky, „vypnuto = nic“ by platilo samo od sebe.
    @Test("Bez anotací v seznamu žádná věta není", arguments: Self.layouts)
    func noAnnotationsMeansNoRow(layout: DiffLayout) throws {
        #expect(sentences(rendered(try claudeFile(), layout: layout)).isEmpty)
    }

    /// **Vypnutý přepínač = prázdná mapa = žádný řádek.** Cesta se tvrdí celá, od `Policy` po
    /// seznam řádků, protože právě mezi nimi se dá „schovat“ zaměnit za „nevyrobit“.
    @Test("Vypnutý přepínač žádnou větu nevyrobí", arguments: Self.layouts)
    func theToggleOffProducesNoRow(layout: DiffLayout) throws {
        let file = try claudeFile()
        let record = StoredAnnotations(
            pullRequest: PRIdentifier(repo: RepoID(owner: "ondrajodas", name: "PRism"), number: 525),
            headSha: "aaaa1111",
            hunks: [HunkAnnotation(file: "CLAUDE.md", hunk: 1, why: "Věta.", source: nil)],
            files: [],
            outcome: .finished,
            sessionID: nil,
            answered: true,
            dropped: 0,
            finishedAt: Date(timeIntervalSince1970: 1),
            usage: nil
        )
        let off = rendered(
            file,
            layout: layout,
            annotations: Policy.hunkAnnotations(of: record, in: file, isOn: false)
        )
        let on = rendered(
            file,
            layout: layout,
            annotations: Policy.hunkAnnotations(of: record, in: file, isOn: true)
        )

        #expect(sentences(off).isEmpty)
        #expect(sentences(on).count == 1)
    }

    /// Věta nese **zdroj, když ho má** — a bez zdroje se nezahazuje.
    @Test("Věta bez zdroje se nezahazuje")
    func aSentenceWithoutASourceSurvives() throws {
        let drawn = sentences(rendered(try claudeFile(), layout: .unified, annotations: annotations([0, 1])))
        #expect(drawn.count == 2)
        #expect(drawn.contains { $0.source != nil })
        #expect(drawn.contains { $0.source == nil })
    }

    // MARK: - Geometrie bloků

    /// **Bloky kódu se anotacemi nemění.** Tvrzení o tom, že se něco **nestalo**.
    @Test("Věta nad hunkem nezmění složení bloků kódu", arguments: Self.layouts)
    func theSentenceDoesNotChangeTheBlocks(layout: DiffLayout) throws {
        let file = try claudeFile()
        let without = blocks(rendered(file, layout: layout))
        let with = blocks(rendered(file, layout: layout, annotations: annotations([0, 1])))

        #expect(!without.isEmpty, "měřidlo: v seznamu nejsou žádné bloky")
        #expect(without.map(\.id) == with.map(\.id))
        #expect(without.map(\.lines) == with.map(\.lines))
    }

    /// Totéž nad **rozbaleným** kontextem: tam jsou bloky delší a hunk je slitý s tím nad ním,
    /// takže by se rozťal ten největší z nich.
    @Test("Ani nad rozbaleným kontextem se bloky nemění", arguments: Self.layouts)
    func theBlocksSurviveRevealedContext(layout: DiffLayout) throws {
        var revealed = RevealedLines()
        revealed.reveal(185...542)   // celá mezera mezi prvním a druhým hunkem
        let content = (1...600).map { "řádek \($0)" }
        let file = try claudeFile()

        let without = blocks(rendered(file, layout: layout, revealed: revealed, content: content))
        let with = blocks(rendered(
            file,
            layout: layout,
            annotations: annotations([0, 1]),
            revealed: revealed,
            content: content
        ))

        #expect(!without.isEmpty, "měřidlo: v seznamu nejsou žádné bloky")
        #expect(without.map(\.id) == with.map(\.id))
        #expect(without.map(\.lines) == with.map(\.lines))
    }

    /// **Slitý hunk větu nedostane.** Je to cena za pravidlo z #469 a je zapsaná: věta se vrátí,
    /// jak se kontext sbalí (`Zobrazit jen diff`).
    @Test("Slitý hunk větu nedostane", arguments: Self.layouts)
    func aMergedHunkGetsNoSentence(layout: DiffLayout) throws {
        var revealed = RevealedLines()
        revealed.reveal(185...542)
        let rows = rendered(
            try claudeFile(),
            layout: layout,
            annotations: annotations([0, 1]),
            revealed: revealed,
            content: (1...600).map { "řádek \($0)" }
        )

        // První hunk hlavičku má (nad ním zbývá skrytý úsek), druhý je slitý — takže z dvou
        // anotací zbude jedna, a zbývá ta patřící k prvnímu hunku.
        #expect(sentences(rows).count == 1)
        #expect(sentences(rows).first?.hunk == 1)
    }

    // MARK: - Identita

    /// Identita řádku je **z indexu hunku**, ne z pořadí v seznamu: rozbalení kontextu řádky
    /// přidává, takže by se odvozená identita posunula — a jsou to identity, podle kterých
    /// `ForEach` řádky rozeznává.
    @Test("Věty mají identitu z hunku, ne z pořadí")
    func theIdentityComesFromTheHunk() throws {
        let file = try claudeFile()
        let plain = rendered(file, layout: .unified, annotations: annotations([0, 1]))
        var revealed = RevealedLines()
        revealed.reveal(1...170)
        let revealedRows = rendered(
            file,
            layout: .unified,
            annotations: annotations([0, 1]),
            revealed: revealed,
            content: (1...600).map { "řádek \($0)" }
        )

        let ids = { (rows: [DiffRow]) in
            rows.compactMap { row -> String? in
                guard case .annotation(let id, _) = row else { return nil }
                return id
            }
        }
        // Rozbalení až na začátek souboru slije **první** hunk, takže mu věta odpadne; ta druhá
        // si drží tutéž identitu jako bez rozbalení.
        #expect(ids(plain) == ["\(file.id)|a0", "\(file.id)|a1"])
        #expect(ids(revealedRows) == ["\(file.id)|a1"])
    }

    /// Identity řádků diffu se **nesmí křížit**: na `id` se skáče z panelu nálezů i z hledání.
    @Test("Identita věty se s ničím jiným netrefí", arguments: Self.layouts)
    func theIdentityIsUnique(layout: DiffLayout) throws {
        let rows = rendered(try claudeFile(), layout: layout, annotations: annotations([0, 1]))
        let ids = rows.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
