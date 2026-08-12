import Foundation
import Testing

@testable import PRism

/// Obsah souboru na řádky (#295).
///
/// Vlastní sada, protože tohle je druhá polovina číslování diffu: čísla z hunků se páruje
/// s **indexy v tomhle seznamu**, takže když se dělení rozejde s `DiffParser`, rozbalený kontext
/// ukáže jiný kód, než o kterém mluví nález — a nikde to nespadne.
@Suite("FileExpansion — řádky souboru")
struct FileExpansionTests {

    @Test("Soubor s CRLF se načte po řádcích, ne jako jeden řádek")
    func splitsCRLFContent() {
        let content = "#include <windows.h>\r\n\r\nint main()\r\n{\r\n    return 0;\r\n}\r\n"

        #expect(FileExpansion.lines(of: content) == [
            "#include <windows.h>", "", "int main()", "{", "    return 0;", "}",
        ])
    }

    /// Tentýž soubor se `CRLF` a s `LF` musí dát **tytéž** řádky — jinak by se rozbalený kontext
    /// nedal porovnat s řádky z diffu a `SyntaxRunCache` (#153, #224) by nesla dvě verze téhož
    /// řádku.
    @Test("CRLF a LF dávají stejné řádky")
    func splitsCRLFSameAsLF() {
        let crlf = "alfa\r\nbeta\r\ngama\r\n"

        #expect(FileExpansion.lines(of: crlf) == FileExpansion.lines(of: "alfa\nbeta\ngama\n"))
    }

    /// Zakončení na konci souboru nedělá řádek navíc — jinak by soubor „měl“ o řádek víc, než
    /// kolik jich číslují hunky, a odkrytý rozsah by se ořezával na špatnou délku.
    @Test("Koncové zakončení nedělá prázdný řádek navíc", arguments: ["\n", "\r\n"])
    func dropsTrailingTerminator(_ terminator: String) {
        #expect(FileExpansion.lines(of: "alfa\(terminator)beta\(terminator)").count == 2)
    }

    @Test("Prázdný soubor nemá žádný řádek")
    func handlesEmptyFile() {
        #expect(FileExpansion.lines(of: "").isEmpty)
    }

    /// Prázdné řádky uvnitř souboru **zůstávají** — bez nich by se indexy rozešly s čísly
    /// z hunků, což je tichá záměna řádku za jiný.
    @Test("Prázdné řádky uvnitř souboru zůstávají")
    func keepsEmptyLinesInside() {
        #expect(FileExpansion.lines(of: "alfa\r\n\r\n\r\nbeta") == ["alfa", "", "", "beta"])
    }
}
