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
    ///
    /// Pět seznamů, ne čtyři: od #171 patří mezi ně i časová osa. Zvedlo se to vědomě —
    /// tenhle test si toho všiml jako první.
    @Test("Velikost stránky platí na všechny seznamy")
    func usesOnePageSizeEverywhere() {
        let document = ConversationQuery.document

        #expect(document.components(separatedBy: "first: $page").count - 1 == 5)
    }

    /// Bez událostí by v `Přehledu` chyběl push, vyžádané review i merge (#171) — a vzít se
    /// jinde než tady nedají.
    ///
    /// **Každý typ v `itemTypes` musí mít i svůj fragment.** Změřeno na živém API: typ uvedený
    /// bez fragmentu dorazí jako `{"__typename": "ClosedEvent"}` a nic víc, takže by z něj
    /// v okně vyšel prázdný řádek.
    @Test("Dotaz se ptá na události časové osy")
    func asksForTimelineEvents() {
        let document = ConversationQuery.document

        for field in [
            "timelineItems",
            "PULL_REQUEST_COMMIT", "REVIEW_REQUESTED_EVENT", "REVIEW_REQUEST_REMOVED_EVENT",
            "HEAD_REF_FORCE_PUSHED_EVENT", "READY_FOR_REVIEW_EVENT", "CONVERT_TO_DRAFT_EVENT",
            "MERGED_EVENT", "CLOSED_EVENT", "REOPENED_EVENT", "BASE_REF_CHANGED_EVENT",
            "PullRequestCommit", "ReviewRequestedEvent", "ReviewRequestRemovedEvent",
            "HeadRefForcePushedEvent", "ReadyForReviewEvent", "ConvertToDraftEvent",
            "MergedEvent", "ClosedEvent", "ReopenedEvent", "BaseRefChangedEvent",
            "messageHeadline", "requestedReviewer", "avatarUrl",
            // Vyžádaný reviewer umí být bot (`github-actions`), a bez tohohle fragmentu
            // z něj dorazí jen `__typename` — tedy „někdo si vyžádal review“ bez toho kdo.
            "on Bot",
        ] {
            #expect(document.contains(field), "v dotazu chybí \(field)")
        }
    }

    /// Identita události se bere **z GraphQL**, ne z jejího obsahu: na PR běžně stojí za
    /// sebou několik shodných párů „vyžádal review / odebral“ a při shodě na sekundu by se
    /// v `ForEach` slily do jedné. Jeden fragment na `Node` místo deseti polí.
    @Test("Události se ptají na id přes fragment na Node")
    func asksForNodeIdentity() {
        #expect(ConversationQuery.document.contains("on Node { id }"))
    }

    /// Bot se musí poznat i tam, kde událost **udělal** — `github-actions requested a review`
    /// vypadá jinak než člověk. `__typename` proto patří k aktérovi, ne jen k uzlu osy.
    @Test("Aktér nese jméno, obrázek i to, jestli je to bot")
    func asksWhetherTheActorIsABot() throws {
        let document = ConversationQuery.document

        let fragment = try #require(document.components(separatedBy: "fragment actorFields on Actor").last)
        let body = try #require(fragment.components(separatedBy: "}").first)
        #expect(body.contains("__typename"))
        #expect(body.contains("login"))
        #expect(body.contains("avatarUrl"))
    }

    /// Review, komentáře pod PR ani vlákna do `itemTypes` **nepatří**: přehled je má
    /// z vlastních seznamů, takže z časové osy by vyšly podruhé.
    @Test("Časová osa nepřináší podruhé to, co přehled už má")
    func doesNotAskForItemsTheOverviewAlreadyHas() {
        let document = ConversationQuery.document

        for duplicate in ["PULL_REQUEST_REVIEW", "ISSUE_COMMENT"] {
            #expect(!document.contains(duplicate), "\(duplicate) by se v přehledu objevil dvakrát")
        }
    }
}
