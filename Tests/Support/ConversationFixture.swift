import Foundation

@testable import PRism

/// Syntetická konverzace pro sondy (#361): komentáře s **různě vysokým** obsahem.
///
/// Rozhoduje ta různost, ne počet — líný seznam odhaduje zbytek obsahu z toho, co už umístil,
/// takže stejně vysoké řádky by mu odhadem nikdy nepohnuly. Pět tvarů po `index % 5` (věta,
/// šest odstavců, blok kódu, odrážky, odstavce s odkazem) je zároveň to, co v ose vyrobí
/// `MarkdownText` se vším, co umí; bez odrážek a bloků kódu by se měřil jiný strom.
///
/// **Jedno místo, dvě sondy.** Do #361 (patnácté kolo) to byl privátní helper uvnitř
/// `IdleDiffSpinProbe`; `ConversationAxisShapeProbe` potřebuje **tentýž** materiál, aby se čísla
/// z obou daly číst vedle sebe, a druhá kopie by se rozešla první úpravou.
enum ConversationFixture {
    /// Konverzace složená ze samých komentářů pod PR.
    ///
    /// `shift` posune tvary o pár míst, takže **tytéž komentáře vyjdou jinak vysoké**. Je to
    /// jediný způsob, jak nechat počet i identitu na místě a rozejít jen odhad zbytku obsahu.
    static func conversation(comments: Int, shift: Int = 0) -> Conversation {
        let items = (0..<comments).map { index in
            ThreadComment(
                id: "c\(index)",
                author: index % 3 == 0 ? "octocat" : "hubot",
                body: body(index + shift),
                createdAt: Date(timeIntervalSince1970: 1_753_000_000 + Double(index) * 3600),
                url: URL(string: "https://github.com/cli/cli/pull/13084#issuecomment-\(index)")!
            )
        }
        return Conversation(
            viewer: "octocat",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: [], total: 0, hasNextPage: false),
            comments: ConversationPage(items: items, total: items.count, hasNextPage: false),
            events: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }

    /// Táž osa, jak ji dostane `ConversationView` — tedy po `Policy.overview`, ne syrová
    /// konverzace. Sonda tím měří ten seznam, který v aplikaci doopravdy je.
    static func entries(comments: Int, shift: Int = 0) -> [ConversationEntry] {
        Policy.overview(of: conversation(comments: comments, shift: shift), renderedIn: nil)
    }

    /// Kolik čeho v ose je — vypisuje se do sondy, protože na složení celý ablační scénář stojí.
    static func shapes(of comments: Int) -> String {
        let names = ["věta", "6 odstavců", "blok kódu", "4 odrážky", "2 odstavce s odkazem"]
        return names.enumerated()
            .map { index, label in "\(label): \((0..<comments).count { $0 % 5 == index })" }
            .joined(separator: ", ")
    }

    /// Pět tvarů textu, aby se výšky uzlů lišily násobně — věta, odstavce, blok kódu, odrážky.
    static func body(_ index: Int) -> String {
        switch index % 5 {
        case 0:
            "Krátká věta."
        case 1:
            (0..<6)
                .map { "Odstavec \($0) s **tučným** a `inline kódem`, dost dlouhý na to, aby se zalomil." }
                .joined(separator: "\n\n")
        case 2:
            "```swift\n" + (0..<14).map { "    let value\($0) = compute(\($0))" }.joined(separator: "\n") + "\n```"
        case 3:
            "- první\n- druhá odrážka, o které je potřeba napsat víc než jedno slovo\n- třetí\n- čtvrtá"
        default:
            "Dva odstavce.\n\nDruhý nese odkaz na [issue](https://github.com/cli/cli/pull/13084)."
        }
    }
}
