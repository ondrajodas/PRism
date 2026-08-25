import Foundation
import Testing

@testable import PRism

/// **Řádek diffu se ptá na svou geometrii jedině tam, kde ji má kdo přečíst** (#438).
///
/// `DiffLineView` měl `onGeometryChange` **bezpodmínečně**, přitom rámeček slouží jedině tažení
/// rozsahu (#110) — a ta closure běží **uvnitř aktualizace grafu**, tedy i v kole, ve kterém se
/// nepřeloží ani jedno tělo. Ve dvou záchvatech #361 to bylo **369 546** a **711 018** zásahů,
/// druhá nejčastější položka v celém kole.
///
/// **Zadání #438 vinilo diff pod jiným tabem; měření to vyvrátilo** (`IdleDiffSpinProbe`
/// `lineGeometryOrigin`, čísla v `docs/testovani.md`). S diffem vepředu se `DiffLine.geometry`
/// neozve **ani jednou** — `DiffView` slévá řádky do bloků (`DiffRow.blocked(_:)`), takže tam
/// `DiffLineView` nekreslí ani jeden řádek. Zásahy jsou z **osy konverzace**, která je vepředu:
/// úryvek u vlákna (`ThreadSnippetView`) kreslí `DiffLineView` řádek po řádku a rámeček z něj
/// nemá kdo převzít.
///
/// **Proč se to tvrdí nad zdrojáky, a ne za běhu.** Práce, jejíž výsledek nikdo nepřevezme, po
/// sobě nenechá nic pozorovatelného — jediná stopa je počitadlo v `RenderDiagnostics`, a to je
/// **globál procesu**. Test, který do něj zapíše, umí položit `RenderDiagnosticsTests`
/// (tvrdí `current == nil`) a `main` je pak falešně červený; to je pravidlo z #367 a #411, ne
/// preference. Čísla proto měří sonda za `PRISM_MEASURE` a tady se drží ta struktura, ze které
/// plynou — tatáž konstrukce jako `LazyIdealSizeTests`, `ConversationAxisFeedbackTests`
/// a `SingleWayOutTests`.
///
/// **Ověřeno vložením regrese**: s `onGeometryChange` vráceným do řetězce `row` spadne první
/// test, a sonda nad osou vydá zase 242 zásahů místo nuly.
@Suite("Geometrie řádku diffu (#438)")
struct DiffLineGeometryTests {
    /// Hlavní tvrzení: čtení geometrie visí na podmínce, ne na řádku samotném.
    @Test("Rámeček se čte jen ve větvi, která ho má komu předat")
    func geometryIsReadOnlyWhereSomebodyReadsIt() throws {
        let code = try source(of: "DiffLineView")
        #expect(
            Self.occurrences(of: "onGeometryChange", in: code) == 1,
            "čtení geometrie má být na jednom místě, jinak se druhá větev připojí potichu"
        )
        #expect(
            code.contains("if reportsFrame {"),
            "onGeometryChange se má připojit jen ve větvi, která rámeček někomu předá"
        )
        #expect(
            code.contains("row.onGeometryChange("),
            "closure se má připojit až k hotovému řádku uvnitř té větve, ne do jeho řetězce"
        )
    }

    /// Podmínka musí být **obojí**: bez identity se nemá co zapsat, bez krabice není kam.
    @Test("Podmínka se ptá na identitu řádku i na krabici")
    func theConditionAsksForBoth() throws {
        let condition = try #require(
            Self.line(containing: "var reportsFrame", in: try source(of: "DiffLineView")),
            "podmínka reportsFrame v DiffLineView chybí"
        )
        #expect(condition.contains("dragID != nil"))
        #expect(condition.contains("rangeDrag.box != nil"))
    }

    /// Úryvek u vlákna na ose — to je to místo, kde se ta práce v záchvatech účtovala. Nedostane
    /// ani identitu, ani krabici, takže se rámeček nepočítá vůbec.
    @Test("Úryvek u vlákna na ose rámeček nehlásí")
    func theTimelineSnippetReportsNothing() throws {
        let code = try source(of: "ThreadSnippetView")
        #expect(code.contains("DiffLineView("), "úryvek má kreslit řádky diffu")
        #expect(!code.contains("dragID:"), "úryvek na ose se tažení rozsahu neúčastní")
        #expect(!code.contains("rangeDrag:"), "úryvek na ose nemá krabici, do které by hlásil")
    }

    /// **Kontrola měřidla**: bez tohohle by nula výš mohla znamenat i „rámeček nehlásí nikdo
    /// a tažení rozsahu je rozbité“. V diffu se předává obojí, takže se tam ta větev bere.
    @Test("V diffu se předává identita i krabice")
    func theDiffPassesBoth() throws {
        let row = try source(of: "DiffRowView")
        #expect(row.contains("dragID: id"))
        #expect(row.contains("rangeDrag: rangeDrag"))
        let pair = try source(of: "DiffPairView")
        #expect(pair.contains("dragID: dragID.map"))
        #expect(pair.contains("rangeDrag: rangeDrag"))
    }

    /// Kontrola, že se zdrojáky doopravdy čtou — jinak by prázdný nález prošel jako splněné
    /// tvrzení.
    @Test("Zdrojáky se doopravdy čtou")
    func theSourcesAreActuallyRead() throws {
        for view in ["DiffLineView", "ThreadSnippetView", "DiffRowView", "DiffPairView"] {
            #expect(try source(of: view).count > 500, "\(view) vyšel prázdný, test netvrdí nic")
        }
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        text.ranges(of: needle).count
    }

    /// První řádek obsahující vzor. `nil` = není tam, což je vlastní nález, ne prázdná shoda.
    private static func line(containing needle: String, in text: String) -> String? {
        TextLines.content(text).first { $0.contains(needle) }.map(String.init)
    }

    /// Zdroják view bez řádkových komentářů — tatáž konstrukce jako
    /// `ConversationAxisFeedbackTests.source(of:)`: o těch vzorech se v repu píše v próze, takže
    /// by je komentáře v tvrzeních nacházely samy.
    private func source(of view: String) throws -> String {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "App/Views/\(view).swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        return TextLines.content(text)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}
