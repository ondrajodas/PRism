import Foundation
import Testing

@testable import PRism

/// **Kdo našeptávání emotikonů má a kdo ne** (#483) — tvrzení nad zdrojáky.
///
/// Rozbije se to potichu ze dvou stran naráz. Kdyby nabídka **chyběla** ve třetím poli, byl by
/// z toho composer, ve kterém `:` nedělá nic — a to se pozná až ve chvíli, kdy tam někdo píše.
/// Kdyby **přebyla** v tabu `Zeptat se`, sešli by se v jednom poli dva zájemci o `Return`
/// (`Policy.claimsReturnShortcut`, #452) a vyhrál by ten zaregistrovaný později (#184).
///
/// Za běhu se ani jedno zjistit nedá: stav se plní klávesnicí, kterou testovací host nemá. Ze
/// zdrojáků se to přečíst dá — tatáž konstrukce jako `SingleWayOutTests` a `GlobalAppearanceTests`,
/// včetně zahazování řádkových komentářů (o boxu se v dokumentaci mluví a vysvětlení nemá test
/// zakazovat).
@Suite("Zapojení našeptávání emotikonů (#483)")
struct EmojiFieldWiringTests {
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private struct Source {
        let path: String
        /// Jen kód — řádky, které začínají `//`, jsou pryč.
        let code: String
    }

    private func sources(under folder: String) throws -> [Source] {
        let root = Self.repository.appending(path: folder)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { throw SourceError.unreadable(root.path) }

        var files: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // `TextLines`, ne `split(separator: "\n")` — pravidlo repa platí i v testech.
            let code = TextLines.content(text)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            files.append(
                Source(path: url.path.replacingOccurrences(of: root.path + "/", with: ""), code: code)
            )
        }
        guard !files.isEmpty else { throw SourceError.unreadable(root.path) }
        return files
    }

    private enum SourceError: Error {
        case unreadable(String)
    }

    /// **Tři pole, jmenovitě.** Ne „aspoň tři“ a ne počet: kdyby jedno ubylo a jiné přibylo, vyjde
    /// počet stejně.
    ///
    /// Hledá se **založení boxu** (`EmojiSuggestionBox()`), protože to je ta věc, kterou má vlastnit
    /// právě jeden majitel na pole: on ho podá do pole a on z něj kreslí nabídku. Že se ty dvě
    /// poloviny nerozešly, hlídá test níž.
    @Test("Nabídku zapínají tři pole a jsou to ta tři")
    func enablesTheMenuInExactlyThreeFields() throws {
        let application = try sources(under: "App")
        let enabling = application
            .filter { $0.code.contains("EmojiSuggestionBox()") }
            .map(\.path)
            .sorted()

        #expect(enabling == [
            "Views/ConversationComposerView.swift",   // komentář pod PR (#216)
            "Views/DraftPanel.swift",                 // tělo review v panelu
            "Views/ThreadBubbleView.swift",           // odpověď do vlákna (#73)
        ])

        // A každý z nich **jeden box**: dva boxy v jednom view znamenají dvě nabídky, ze kterých se
        // aspoň jedna nekreslí.
        for path in enabling {
            let file = try #require(application.first { $0.path == path })
            #expect(file.code.components(separatedBy: "EmojiSuggestionBox()").count - 1 == 1)
        }
    }

    /// **Tab `Zeptat se` nabídku nemá.** Jeho composer si `DraftTextField` bere sám, takže by mu
    /// stačilo přidat jedno slovo — a přišel by o `Return`, kterým se otázka odesílá.
    @Test("Prompt v tabu Zeptat se nabídku nemá")
    func leavesTheAskComposerAlone() throws {
        let application = try sources(under: "App")
        let ask = try #require(application.first { $0.path == "Views/AskComposer.swift" })

        #expect(!ask.code.contains("suggestions:"))
        #expect(!ask.code.contains("EmojiSuggestionBox"))

        // A pro jistotu z druhé strany: pole si kurzor bere **jen** se zapnutou nabídkou, takže
        // `TextEditor(text:selection:)` smí stát v jednom jediném souboru.
        let withSelection = application
            .filter { $0.code.contains("TextEditor(text:") && $0.code.contains("selection:") }
            .map(\.path)
        #expect(withSelection == ["Views/DraftTextField.swift"])
    }

    /// **Kdo pole našeptáváním vybaví, ten nabídku taky kreslí.** Rozejít se to umí potichu: pole
    /// s boxem, ze kterého nikdo nekreslí, je pole, ve kterém `:` nedělá nic — a naopak nabídka bez
    /// pole je mrtvý overlay.
    @Test("Kdo box podá, ten nabídku kreslí")
    func drawsTheMenuWhereverTheBoxIsGiven() throws {
        let application = try sources(under: "App")

        for file in application where file.code.contains("EmojiSuggestionBox()") {
            // **Dva různé řetězce, ne jeden**: `suggestions: emoji` stojí v obou voláních (do pole
            // i do nabídky), takže by jedno tvrzení prošlo i s vyndaným polem — ověřeno vloženou
            // regresí. Za jménem boxu je proto v jednom případě čárka (v poli za ním jdou další
            // parametry) a v druhém uzavírací závorka.
            #expect(file.code.contains("suggestions: emoji,"), "\(file.path) box do pole nepodává")
            #expect(
                file.code.contains("EmojiSuggestionMenu(suggestions: emoji)"),
                "\(file.path) nabídku nekreslí"
            )
            #expect(file.code.contains("emojiMenuAbove"), "\(file.path) nabídku nekotví nad plochu")
        }
        for file in application where file.code.contains("emojiMenuAbove") {
            // Modifikátor sám se odečítá — v něm to jméno stojí jako definice.
            guard file.path != "Views/EmojiSuggesting.swift" else { continue }
            #expect(
                file.code.contains("EmojiSuggestionBox()"),
                "\(file.path) kreslí nabídku, ale žádný box nedrží"
            )
        }
    }

    /// **Cesta ven se nemění o nic.** Není to devátá metoda `ReviewPublishing`, není to nové volání
    /// `GitHubGateway` a není to nové povolení — je to chování textového pole. Tvrdí se to na
    /// souborech, které kvůli #483 vznikly: kdyby v některém z nich `gh` nebo publisher stál,
    /// vedla by cesta ven odjinud než z `App/Publish/`.
    @Test("Soubory našeptávání o cestě ven nevědí")
    func keepsTheEmojiFilesAwayFromTheWayOut() throws {
        let files = [
            "Policy/EmojiSuggestion.swift",
            "Support/EmojiCatalog.swift",
            "Support/EmojiTable.swift",
            "Models/Emoji.swift",
            "Views/EmojiSuggesting.swift",
            "Views/EmojiSuggestionBox.swift",
            "Views/EmojiSuggestionMenu.swift",
        ]
        let application = try sources(under: "App")

        for path in files {
            let file = try #require(application.first { $0.path == path }, "chybí \(path)")
            #expect(!file.code.contains("ReviewPublishing"), "\(path) zná cestu ven")
            #expect(!file.code.contains("GitHubGateway"), "\(path) zná gateway")
            // A ani podproces: cesta ke `gh` i spouštění jdou v tomhle repu přes tyhle dva typy.
            #expect(!file.code.contains("ToolPaths"), "\(path) zná cesty k binárkám")
            #expect(!file.code.contains("Subprocess"), "\(path) spouští podproces")
        }
    }

    /// **Katalog je v aplikaci, ne z GitHubu.** `GET /emojis` vrací adresy obrázků, ne znaky, a
    /// seznam se nemění — takže dotaz kvůli textovému poli by byla závislost bez užitku.
    @Test("Nikdo se GitHubu na emotikony neptá")
    func doesNotAskGitHubForEmoji() throws {
        for file in try sources(under: "App") {
            #expect(!file.code.contains("/emojis"), "\(file.path) se ptá GitHubu na emotikony")
        }
    }
}
