import Foundation
import Testing

@testable import PRism

/// Adresa, kterou dostane systém, aby otevřel soubor v editoru (#530).
///
/// Testuje se **výčtem přes všechny tři editory**, protože každý z nich má jiný tvar a jediné, co
/// je na tom společné, je cesta — a právě ta se dá pokazit tiše: mezera, diakritika nebo dvojtečka
/// ve jméně souboru rozhodne o tom, jestli editor otevře jiný soubor, jiný řádek, nebo nic.
@Suite("Policy — otevření souboru v editoru (#530)")
struct EditorLinkTests {
    private let file = URL(filePath: "/Users/j/Library/Application Support/PRism/worktrees/cli/cli/42-abc/src/App.swift")

    // MARK: - Tvar adresy

    @Test("Tři editory, tři tvary adresy — s řádkem")
    func composesEveryScheme() {
        let expected: [ExternalEditor: String] = [
            .xcode: "xcode://open?url=file:///Users/j/Library/Application%20Support/PRism/worktrees/cli/cli/42-abc/src/App.swift&line=81",
            .vscode: "vscode://file/Users/j/Library/Application%20Support/PRism/worktrees/cli/cli/42-abc/src/App.swift:81",
            .cursor: "cursor://file/Users/j/Library/Application%20Support/PRism/worktrees/cli/cli/42-abc/src/App.swift:81",
        ]

        for editor in ExternalEditor.allCases {
            let url = Policy.editorURL(editor, file: file, line: 81)
            #expect(url?.absoluteString == expected[editor], "\(editor.rawValue)")
        }
    }

    /// Nález o souboru jako celku řádek nemá — a `:1` by tvrdilo, že je na prvním.
    @Test("Bez řádku se do adresy žádný nedopíše")
    func omitsTheLineWhenThereIsNone() {
        let expected: [ExternalEditor: String] = [
            .xcode: "xcode://open?url=file:///a/b.swift",
            .vscode: "vscode://file/a/b.swift",
            .cursor: "cursor://file/a/b.swift",
        ]

        for editor in ExternalEditor.allCases {
            let url = Policy.editorURL(editor, file: URL(filePath: "/a/b.swift"), line: nil)
            #expect(url?.absoluteString == expected[editor], "\(editor.rawValue)")
        }
    }

    /// Nula ani záporné číslo neexistují a `:0` by editor v lepším případě ignoroval, v horším
    /// skočil na začátek a tvrdil, že nález je tam.
    @Test("Řádek 0 a záporný se zahazují jako by nebyl", arguments: [0, -1, -81])
    func dropsNonPositiveLines(_ line: Int) {
        for editor in ExternalEditor.allCases {
            let withLine = Policy.editorURL(editor, file: URL(filePath: "/a/b.swift"), line: line)
            let without = Policy.editorURL(editor, file: URL(filePath: "/a/b.swift"), line: nil)
            #expect(withLine == without, "\(editor.rawValue)")
        }
    }

    // MARK: - Escapování

    /// Mezera a diakritika jsou v cestě do cache **běžné**: `Application Support` má mezeru vždycky
    /// a jméno souboru z cizího repa může být cokoli.
    ///
    /// **Netvrdí se to doslovným řetězcem, a je to změřené, ne opatrnost**: `URL(filePath:)`
    /// i `appending(path:)` vydávají cestu **rozloženou** (NFD) — `Příliš` z nich vyjde jako
    /// `Pr̆ i ́ l i s̆`, tedy `%CC%8C` místo `%C5%99`. Hardcodovaná složená podoba by test dělala
    /// červeným nad kódem, který je v pořádku. Tvrdí se proto to, na čem doopravdy záleží: v adrese
    /// nezůstane nic mimo ASCII a **dekóduje se zpátky na tutéž cestu**.
    @Test("Mezera a diakritika se procentují")
    func escapesSpacesAndDiacritics() {
        let file = URL(filePath: "/a b/Příliš žluťoučký.swift")
        let path = file.path(percentEncoded: false)

        let cursor = Policy.editorURL(.cursor, file: file, line: 3)?.absoluteString
        #expect(cursor?.hasPrefix("cursor://file/a%20b/") == true)
        #expect(cursor?.allSatisfy(\.isASCII) == true)
        #expect(
            cursor?
                .replacingOccurrences(of: "cursor://file", with: "")
                .replacingOccurrences(of: ":3", with: "")
                .removingPercentEncoding == path
        )

        let xcode = Policy.editorURL(.xcode, file: file, line: 3)?.absoluteString
        #expect(xcode?.hasPrefix("xcode://open?url=file:///a%20b/") == true)
        #expect(xcode?.allSatisfy(\.isASCII) == true)
        #expect(
            xcode?
                .replacingOccurrences(of: "xcode://open?url=file://", with: "")
                .replacingOccurrences(of: "&line=3", with: "")
                .removingPercentEncoding == path
        )
    }

    /// **Dvojtečka ve jméně souboru je ta nejtišší vada z celého #530**: u VS Code a Cursoru dělí
    /// číslo řádku, takže neescapovaná by editor poslala na jiné místo — a vypadalo by to, že
    /// nález sedí jinde.
    @Test("Dvojtečka ve jméně souboru se procentuje, jinak by dělila řádek")
    func escapesColonsInTheName() {
        let file = URL(filePath: "/a/we:ird.swift")

        #expect(
            Policy.editorURL(.vscode, file: file, line: 12)?.absoluteString
                == "vscode://file/a/we%3Aird.swift:12"
        )
    }

    /// U Xcodu leží cesta v **query**, takže `&` a `=` v ní dělí parametry — `urlPathAllowed` je
    /// propouští, protože v cestě nedělí nic.
    @Test("Ampersand, rovnítko a plus se procentují kvůli query u Xcodu")
    func escapesQuerySeparators() {
        let file = URL(filePath: "/a/b&c=d+e.swift")

        #expect(
            Policy.editorURL(.xcode, file: file, line: 7)?.absoluteString
                == "xcode://open?url=file:///a/b%26c%3Dd%2Be.swift&line=7"
        )
        // Sada je jedna pro všechny tři schválně — dvě by znamenaly dvě odpovědi na jednu otázku.
        #expect(
            Policy.editorURL(.vscode, file: file, line: 7)?.absoluteString
                == "vscode://file/a/b%26c%3Dd%2Be.swift:7"
        )
    }

    /// Lomítko zůstává nedotčené: cesta v adrese má být čitelná a v obou tvarech je legální.
    @Test("Lomítka se nechávají, adresa má být čitelná")
    func keepsSlashes() {
        let url = Policy.editorURL(.vscode, file: URL(filePath: "/a/b/c.swift"), line: nil)
        #expect(url?.absoluteString.contains("/a/b/c.swift") == true)
    }

    // MARK: - Texty

    /// Předložka je součástí pádu, protože se u jednoho z nich mění — `"v " + title` by vyrobilo
    /// „v VS Code“.
    @Test("Popisek tlačítka jmenuje editor a skloňuje předložku")
    func namesTheEditorInTheTitle() {
        #expect(Policy.openInEditorTitle(.xcode) == "Otevřít v Xcodu")
        #expect(Policy.openInEditorTitle(.vscode) == "Otevřít ve VS Code")
        #expect(Policy.openInEditorTitle(.cursor) == "Otevřít v Cursoru")
    }

    /// Věta u tlačítka musí říct, že se needituje uživatelův klon — a u vlastního PR i to, že se
    /// otevírá strom, ze kterého vede cesta ven.
    @Test("Věta u tlačítka mluví o kopii z cache, u vlastního PR o stromu -sync")
    func explainsWhichCopyOpens() {
        for editor in ExternalEditor.allCases {
            let mine = Policy.editorNote(editor, ownership: .mine)
            let theirs = Policy.editorNote(editor, ownership: .theirs)

            #expect(mine.contains("kopii z cache aplikace"), "\(editor.rawValue)")
            #expect(mine.contains("ne tvůj klon"), "\(editor.rawValue)")
            #expect(mine.contains("-sync"), "\(editor.rawValue)")
            #expect(mine.contains("Force push"), "\(editor.rawValue)")

            #expect(theirs.contains("kopii z cache aplikace"), "\(editor.rawValue)")
            // U cizího PR se `-sync` nezmiňuje: žádný takový strom tam není a věta o něm by
            // slibovala cestu ven, která na cizím PR neexistuje.
            #expect(!theirs.contains("-sync"), "\(editor.rawValue)")
        }
    }

    // MARK: - Ze kterého stromu

    /// Strom pro srovnání větve vyhrává, protože je to ten jediný, ze kterého vede oprava ven
    /// (#466). Strom review stojí v odpojené hlavě.
    @Test("Strom -sync má přednost před stromem review")
    func prefersTheSyncWorktree() {
        let sync = URL(filePath: "/cache/worktrees/cli/cli/42-sync")
        let review = URL(filePath: "/cache/worktrees/cli/cli/42-abc")

        #expect(Policy.editorTree(sync: sync, review: review) == sync)
        #expect(Policy.editorTree(sync: nil, review: review) == review)
        #expect(Policy.editorTree(sync: sync, review: nil) == sync)
        #expect(Policy.editorTree(sync: nil, review: nil) == nil)
    }

    // MARK: - Hlášky

    /// Odmítnutí kvůli hranici cache se **nesmí slít** s obecným „nepodařilo se otevřít“: je to
    /// jediný stav v téhle akci, který znamená, že aplikace mířila někam, kam nesmí.
    @Test("Každé odmítnutí má vlastní větu")
    func hasItsOwnSentenceForEveryRefusal() {
        let outside = Policy.editorRefusalNote(.outsideCache, path: "src/App.swift")
        let link = Policy.editorRefusalNote(.symbolicLink, path: "src/App.swift")

        #expect(outside != link)
        #expect(outside.contains("mimo cache"))
        #expect(link.contains("symbolický odkaz"))
        #expect(Policy.editorMissingFileNote("src/App.swift").contains("src/App.swift"))
        #expect(Policy.editorRefusedBySystemNote(.cursor).contains("Cursor"))
        #expect(Policy.editorNoWorktreeNote.contains("pracovní kopii"))
    }

    /// **Nesložená adresa se nesmí hlásit jako cesta mimo cache** — a přesně to tady stálo do
    /// vlastní revize diffu. Je to pojistka, která selhat prakticky nemá čím, o to snáz by v ní
    /// nepravdivá věta přežila: *mířili jsme mimo cache* je jediná věta v téhle akci, u které se
    /// má někdo zarazit, a přestane platit v tu chvíli, kdy ji řekne i něco jiného.
    @Test("Nesložená adresa má vlastní větu, ne tu o cestě mimo cache")
    func doesNotBorrowTheOutsideCacheSentence() {
        for editor in ExternalEditor.allCases {
            let address = Policy.editorAddressNote(editor, path: "src/App.swift")

            #expect(address != Policy.editorRefusalNote(.outsideCache, path: "src/App.swift"))
            #expect(!address.contains("mimo cache"), "\(editor.rawValue)")
            #expect(address.contains(editor.title), "\(editor.rawValue)")
            #expect(address.contains("src/App.swift"), "\(editor.rawValue)")
        }
    }
}
