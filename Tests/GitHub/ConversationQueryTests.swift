import Foundation
import Testing

@testable import PRism

/// Argumenty, kterými se dotaz na konverzaci posílá `gh`. Je to kontrakt s `gh`, ne detail
/// — stejně jako u `GhSearchQuery` a seznamu `--json` polí.
@Suite("ConversationQuery")
struct ConversationQueryTests {
    /// Owner a jméno se schválně **liší** — na `cli/cli` by test rozdělení prošel i tehdy,
    /// kdyby kód posílal jméno na místo ownera.
    private let id = PRIdentifier(repo: RepoID(owner: "ondrajodas", name: "PRism"), number: 32)

    @Test("Jde to přes gh api graphql")
    func callsTheGraphQLEndpoint() {
        let arguments = ConversationQuery.arguments(for: id)

        #expect(arguments.prefix(2) == ["api", "graphql"])
    }

    /// Repo se posílá **rozdělené** na `owner` a `repo`, ne jako `owner/repo` — GraphQL má
    /// dva argumenty a slepené jméno by hledalo repozitář se lomítkem v názvu.
    @Test("Owner a repo jdou zvlášť")
    func splitsTheRepository() {
        let arguments = ConversationQuery.arguments(for: id)

        #expect(arguments.contains("owner=ondrajodas"))
        #expect(arguments.contains("repo=PRism"))
        #expect(!arguments.contains { $0.contains("ondrajodas/PRism") })
    }

    /// `number` a `page` jsou v GraphQL `Int!`. `-f` je pošle jako řetězec a dotaz spadne
    /// na typu, takže musí jít přes `-F`.
    @Test("Čísla se posílají přes -F, dotaz přes -f")
    func sendsNumbersAsTypedValues() throws {
        let arguments = ConversationQuery.arguments(for: id, pageSize: 50)

        let numberIndex = try #require(arguments.firstIndex(of: "number=32"))
        #expect(arguments[numberIndex - 1] == "-F")

        let pageIndex = try #require(arguments.firstIndex(of: "page=50"))
        #expect(arguments[pageIndex - 1] == "-F")

        let queryIndex = try #require(arguments.firstIndex { $0.hasPrefix("query=") })
        #expect(arguments[queryIndex - 1] == "-f")
    }

    /// Kdyby z dotazu vypadlo pole, přestane se o něm vědět — a chybějící `isResolved` by
    /// znamenalo, že se vyřešená vlákna ukazují jako otevřená.
    @Test("Dotaz se ptá na všechno, na čem konverzace stojí")
    func asksForEveryFieldTheModelNeeds() {
        let document = ConversationQuery.document

        for field in [
            "viewer", "reviews", "reviewThreads", "comments",
            "isResolved", "isOutdated", "originalLine", "diffSide",
            "replyTo", "totalCount", "hasNextPage", "submittedAt",
            // Bez práv by okno nabízelo `Vyřešit` i tam, kde na to reviewer právo nemá —
            // a tlačítko, které vždycky selže, je horší než žádné.
            "viewerCanResolve", "viewerCanUnresolve",
            // Bez hunku by v `Přehledu` zůstal komentář bez kódu, ke kterému se váže (#158) —
            // a jinde než tady se u zastaralého vlákna vzít nedá.
            "diffHunk",
        ] {
            #expect(document.contains(field), "v dotazu chybí \(field)")
        }
    }

    /// Stránkuje se jedním číslem pro všechny seznamy, ať se nemůže stát, že se komentáře
    /// uvnitř vláken utnou dřív než vlákna sama.
    @Test("Velikost stránky platí na všechny seznamy")
    func usesOnePageSizeEverywhere() {
        let document = ConversationQuery.document

        #expect(document.components(separatedBy: "first: $page").count - 1 == 4)
    }
}
