import Foundation
import Testing

@testable import PRism

/// **Rozhovor v tabu `Zeptat se` se nekreslí líným seznamem** (#452, pravidlo z #361).
///
/// Osa konverzace šla u #361 z `LazyVStack`u na pevný `VStack` a důvod byl kruh
/// `updateItemPhases` → `propagate_dirty`, který se v líném seznamu **nemá kde neutvořit**. Pravidlo
/// z toho zbylo v `CLAUDE.md`: líný seznam patří tam, kde je seznam **neomezený** (diff — tisíce
/// řádků), ne tam, kde má strop.
///
/// Rozhovor má strop **o řád níž než osa**: osa jich má nejvýš čtyři stovky (`ConversationQuery`
/// se ptá `first: 100` na čtyři seznamy), kdežto tady je každá zpráva **zaplacená session**, takže
/// pár desítek je hodně. Kdyby jich někdo někdy nasbíral stovky, platí pro ně tatáž mez jako pro
/// osu — a ta se rozvrhuje celá.
///
/// Konstrukce nad zdrojáky je tatáž jako u `ConversationAxisEagerTests`: řádkové komentáře se
/// zahazují, protože zrovna o `LazyVStack`u se v tom souboru píše v próze.
@Suite("Rozhovor bez líného seznamu (#452)")
struct AskLogEagerTests {
    @Test("V rozhovoru není líný seznam")
    func theLogIsNotLazy() throws {
        let code = try Self.source(of: "AskView")

        for pattern in ConversationAxisEagerTests.forbidden {
            #expect(!code.contains(pattern), "AskView má \(pattern) — kolo z #361 se tím stěhuje sem")
        }
    }

    /// Kontrola měřidla: bez ní by prázdný nález mohl znamenat i „soubor se nenačetl“.
    @Test("Zdroják tabu se doopravdy čte")
    func theSourceIsActuallyRead() throws {
        let code = try Self.source(of: "AskView")

        #expect(code.count > 500, "AskView vyšel prázdný, test netvrdí nic")
        #expect(code.contains("VStack(alignment: .leading, spacing: 14)"))
        #expect(code.contains("ScrollView"))
    }

    private static func source(of name: String) throws -> String {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "App/Views/\(name).swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        return TextLines.content(text)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}
