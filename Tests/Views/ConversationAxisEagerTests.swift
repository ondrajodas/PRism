import Foundation
import Testing

@testable import PRism

/// **Osa konverzace se nesmí vrátit k línému seznamu** (#361, patnácté kolo).
///
/// Čtrnáctý záchvat je první, u kterého se ten kruh dá přečíst celý — a celý je uvnitř SwiftUI:
///
/// ```
/// GraphHost.runTransaction
///   GraphMutation.apply() in conformance LazyLayoutCache…
///     LazyLayoutViewCache.updateItemPhases()       ← zápis fáze položek do grafu
///       AG::Graph::value_set(…) → propagate_dirty  ← a tím zašpinění, které si řekne o další kolo
/// ```
///
/// Umístění položek (`LazySubviewPlacements.placeSubviews`, 60,3 % a 60,5 % vzorků hlavního
/// vlákna ve dvou vzorcích z živého hoření) zapíše stav, ten zašpiní graf, graf si vyžádá další
/// umístění. **Z aplikace v tom kole neběží nic** — ze 101, resp. 158 rámců `PRism.debug.dylib`
/// jsou všechny kromě dvou vstupních bodů jen value-witness kopie `ConversationRow`. Čtrnáct kol
/// zlevňování obsahu kola (#375, #379, #386, #393, #435, #438) proto záchvat nezastavilo a ani
/// nemohlo.
///
/// Pevný `VStack` je jediná podoba, u které se ta vazba **nemá kde utvořit**: v evaluačním
/// zásobníku pod řádkem osy nezůstane ani jeden `LazySubview*` atribut (měřeno
/// `ConversationAxisShapeProbe`, 300 uzlů — `LazyVStack` 2 vzorky ze 2, `VStack` 0).
///
/// Test hlídá **obojí**, protože jedno bez druhého neplatí:
///
/// - v `ConversationView` není líný seznam;
/// - osa je **shora omezená dotazem**, takže se dá rozvrhnout celá. Kdyby `ConversationQuery`
///   začal stránkovat, přestala by ta mez platit a cena prvního rozvržení by rostla bez konce
///   (změřeno: 44 uzlů 55 ms, 300 uzlů 410 ms, 400 uzlů 610 ms v Debugu).
///
/// Konstrukce nad zdrojáky je tatáž jako u `SingleWayOutTests` a `ConversationAxisFeedbackTests`:
/// řádkové komentáře se zahazují, protože zrovna o `LazyVStack`u se v tom souboru píše v próze.
@Suite("Osa konverzace bez líného seznamu (#361)")
struct ConversationAxisEagerTests {
    /// Co v ose nesmí být. `LazyVStack` je ten, který se odsud vyhodil; ostatní jsou tatáž třída
    /// — každý z nich je `LazyLayoutViewCache` s fázemi položek, jen v jiném směru.
    static let forbidden = ["LazyVStack", "LazyHStack", "LazyVGrid", "LazyHGrid"]

    @Test("V ose konverzace není líný seznam")
    func theAxisIsNotLazy() throws {
        let code = try Self.source(of: "ConversationView")
        for pattern in Self.forbidden {
            #expect(
                !code.contains(pattern),
                "ConversationView má \(pattern) — kolo z #361 se tím vrací do osy"
            )
        }
    }

    /// Kontrola měřidla: bez ní by prázdný nález mohl znamenat i „soubor se nenačetl“.
    ///
    /// Hledá se `VStack(alignment: .leading, spacing: 0)`, tedy **ta** náhrada — samotné `VStack`
    /// je v souboru i jinde (lišta, prázdný stav), takže by nedokazovalo nic o ose.
    @Test("Zdroják osy se doopravdy čte")
    func theSourceIsActuallyRead() throws {
        let code = try Self.source(of: "ConversationView")
        #expect(code.count > 500, "ConversationView vyšel prázdný, test netvrdí nic")
        #expect(code.contains("VStack(alignment: .leading, spacing: 0)"))
        #expect(code.contains("ScrollView"))
    }

    /// **Na čem ta změna stojí: osa je shora omezená.**
    ///
    /// `ConversationQuery` se ptá `first: 100` na každý ze čtyř seznamů a **nestránkuje** — co se
    /// nevejde, se hlásí jako zkrácené (`ConversationPage.isTruncated`). Uzlů proto nemůže být víc
    /// než čtyři stovky, a to je ta mez, kvůli které se osa dá rozvrhnout celá. Testuje se to
    /// **z plných stránek**, ne z konstanty: kdyby `overview` začal skládat víc položek, než kolik
    /// jich přišlo, číslo by se rozešlo potichu.
    @Test("Osa je shora omezená velikostí stránky")
    func theAxisIsBounded() {
        let size = ConversationQuery.pageSize
        #expect(size == 100)
        let entries = Policy.overview(of: Self.fullPages(size: size), renderedIn: nil)
        let rows = Policy.conversationRows(of: entries, since: nil)
        #expect(entries.count <= 4 * size, "osa přerostla čtyři plné stránky: \(entries.count)")
        // Commity se na ose slévají do jednoho uzlu, takže řádků je nejvýš tolik co položek.
        #expect(rows.count <= entries.count)
        // A zároveň se nesmí ztratit: prázdná osa by mez splnila taky a netvrdila by nic.
        #expect(rows.count >= size)
    }

    /// Konverzace s **plnými** stránkami ze všech čtyř seznamů — tedy to nejvíc, co dotaz vrátí.
    private static func fullPages(size: Int) -> Conversation {
        let comments = (0..<size).map { index in
            ThreadComment(
                id: "c\(index)",
                author: "octocat",
                body: "Komentář \(index)",
                createdAt: Date(timeIntervalSince1970: 1_753_000_000 + Double(index)),
                url: URL(string: "https://github.com/cli/cli/pull/13084#issuecomment-\(index)")!
            )
        }
        let reviews = (0..<size).map { index in
            SubmittedReview(
                id: "r\(index)",
                author: "hubot",
                state: .commented,
                body: "Review \(index)",
                submittedAt: Date(timeIntervalSince1970: 1_753_100_000 + Double(index))
            )
        }
        let threads = (0..<size).map { index in
            ReviewThread(
                id: "t\(index)",
                path: "src/Module\(index).swift",
                line: index + 1,
                originalLine: index + 1,
                side: .right,
                isResolved: false,
                isOutdated: false,
                diffHunk: nil,
                comments: ConversationPage(
                    items: [comments[index]],
                    total: 1,
                    hasNextPage: false
                )
            )
        }
        let events = (0..<size).map { index in
            TimelineEvent(
                id: "e\(index)",
                kind: .readyForReview,
                actor: nil,
                at: Date(timeIntervalSince1970: 1_753_200_000 + Double(index))
            )
        }
        return Conversation(
            viewer: "octocat",
            reviews: ConversationPage(items: reviews, total: reviews.count, hasNextPage: false),
            threads: ConversationPage(items: threads, total: threads.count, hasNextPage: false),
            comments: ConversationPage(items: comments, total: comments.count, hasNextPage: false),
            events: ConversationPage(items: events, total: events.count, hasNextPage: false)
        )
    }

    /// Zdroják view bez řádkových komentářů — tatáž konstrukce jako
    /// `ConversationAxisFeedbackTests.source(of:)`.
    static func source(of view: String) throws -> String {
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
