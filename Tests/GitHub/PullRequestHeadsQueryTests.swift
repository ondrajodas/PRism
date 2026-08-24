import Foundation
import Testing

@testable import PRism

/// Dávkový dotaz na hlavy pull requestů (#420) — jeden dokument na celou frontu a rozbor odpovědi.
///
/// **Nejcennější tvrzení je to o počtu**: dvanáct PR z deseti repozitářů je **jeden** argument
/// `query=` a jedno spuštění `gh`. Kdyby se to rozpadlo na dotaz per repozitář, byl by z tiku
/// desetinásobek volání — a nikdo by si toho nevšiml, protože výsledek by byl stejný.
@Suite("Dotaz na hlavy pull requestů (#420)")
struct PullRequestHeadsQueryTests {
    private let ids = [
        PRIdentifier("cli/cli#14252")!,
        PRIdentifier("microsoft/terminal#20580")!,
        PRIdentifier("vercel/next.js#97830")!,
    ]
}

// MARK: - Dokument a argumenty

extension PullRequestHeadsQueryTests {
    /// Jeden dokument, jedno `query=`, tři aliasy — a **žádný dotaz na repozitář zvlášť**.
    @Test("Tři PR z tří repozitářů jsou jeden dotaz")
    func buildsASingleQuery() {
        let arguments = PullRequestHeadsQuery.arguments(for: ids)

        #expect(arguments.prefix(3) == ["api", "graphql", "-f"])
        #expect(arguments.count { $0.hasPrefix("query=") } == 1)
        let document = arguments.first { $0.hasPrefix("query=") }!
        for index in 0..<3 {
            #expect(document.contains("\(PullRequestHeadsQuery.alias(index)): repository("))
        }
        #expect(document.contains("pr3:") == false)
    }

    /// Owner, jméno a číslo jdou **typovanou proměnnou**, ne do textu dokumentu: jméno repa je
    /// z konfigurace (uvozovky by se musely řešit) a `number` je v GraphQL `Int!`, takže `-f` by
    /// dotaz položil na typu — tatáž past jako u `ConversationQuery`.
    @Test("Hodnoty jdou přes -F, ne do dokumentu")
    func passesValuesAsVariables() {
        let arguments = PullRequestHeadsQuery.arguments(for: ids)

        #expect(arguments.count { $0 == "-F" } == 9)
        #expect(arguments.contains("owner0=cli"))
        #expect(arguments.contains("name0=cli"))
        #expect(arguments.contains("number0=14252"))
        #expect(arguments.contains("owner2=vercel"))
        #expect(arguments.contains("name2=next.js"))
        #expect(arguments.contains("number2=97830"))
        // Jméno repa v dokumentu být nesmí — jinak by se do něj vlepovalo z konfigurace.
        let document = arguments.first { $0.hasPrefix("query=") }!
        #expect(document.contains("next.js") == false)
    }

    /// Čas události stojí na `commits(last: 1)` a `oid` je tam kvůli ověření, že poslední commit je
    /// opravdu hlava. Je to jediná část dotazu, která něco stojí (0,94 s bez ní, 1,25–2,15 s s ní),
    /// takže se nesmí ztratit potichu.
    @Test("Dotaz si říká o datum hlavy")
    func asksForTheHeadDate() {
        let document = PullRequestHeadsQuery.document(for: 1)

        #expect(document.contains("headRefOid"))
        #expect(document.contains("commits(last: 1)"))
        #expect(document.contains("committedDate"))
        #expect(document.contains("oid"))
    }

    /// Alias je **pozice v dotazu**, ne `owner/name#číslo`: ve jménech repozitářů jsou pomlčky
    /// a tečky, které v GraphQL jménu být nesmí. Odpověď se proto páruje se vstupním polem.
    @Test("Alias je platné GraphQL jméno")
    func namesAliasesByPosition() {
        #expect(PullRequestHeadsQuery.alias(0) == "pr0")
        #expect(PullRequestHeadsQuery.alias(12) == "pr12")
    }
}

// MARK: - Rozbor odpovědi

extension PullRequestHeadsQueryTests {
    private func response(_ fixture: String) throws -> GhPullRequestHeadsResponse {
        try GhOutput.decoder.decode(
            GhPullRequestHeadsResponse.self,
            from: Fixture.data("gh/\(fixture)")
        )
    }

    /// Skutečná odpověď z živého API (`cli/cli`, `microsoft/terminal`, `vercel/next.js`) —
    /// tři aliasy, tři hlavy, tři data.
    @Test("Odpověď se spáruje se vstupním polem")
    func mapsTheAnswerBackToTheInput() throws {
        let heads = try response("pr-heads.json").heads(of: ids)

        #expect(heads.count == 3)
        #expect(heads[ids[0]]?.sha == "819768f67a82e9b915131fe50adc7a7269bdc17e")
        #expect(heads[ids[1]]?.sha == "03300bdf762d4c91f5030513cfd518b4d9cdcd99")
        #expect(heads[ids[2]]?.sha == "77a9efdbadfb95ec5eac5011b6ebf84ebdb360c6")
        #expect(
            heads[ids[0]]?.committedAt
                == ISO8601DateFormatter().date(from: "2026-08-24T14:11:36Z")
        )
    }

    /// **Částečná odpověď je odpověď**, a je to skutečný výstup: dotaz na tři PR, ze kterých dvě
    /// neexistují, vrátil data prvního a `errors` ke zbytku (`gh` u toho skončil kódem 1).
    /// Jedna nedostupná PR nesmí položit dotaz na frontu.
    @Test("Chybějící PR v mapě není, ostatní ano")
    func keepsWhatArrived() throws {
        let heads = try response("pr-heads-partial.json").heads(of: ids)

        #expect(heads.count == 1)
        #expect(heads[ids[0]]?.sha == "cc36d32a212a2b8b6611fb73549fe6d04fb6ec38")
        // „Nevíme“ se od „hlava se neposunula“ musí poznat — proto v mapě prostě není.
        #expect(heads[ids[1]] == nil)
        #expect(heads[ids[2]] == nil)
    }

    /// Neshoda `oid` s `headRefOid` znamená **datum nevíme**, ne datum cizího commitu: pod větou
    /// o téhle hlavě by stálo datum, které k ní nepatří.
    ///
    /// Testuje se **inline JSONem** — na živém API se to nestává (změřeno na dvanácti PR, že se
    /// `oid` s `headRefOid` shodovalo u všech), takže se ta odpověď ze skutečných dat nesehná.
    @Test("Cizí commit v odpovědi datum nedá")
    func refusesADateFromAnotherCommit() throws {
        let json = """
        {"data":{"pr0":{"pullRequest":{"headRefOid":"aaaa1111","commits":{"nodes":[
          {"commit":{"oid":"bbbb2222","committedDate":"2026-08-24T14:11:36Z"}}]}}}}}
        """
        let response = try GhOutput.decoder.decode(
            GhPullRequestHeadsResponse.self,
            from: Data(json.utf8)
        )

        let heads = response.heads(of: [ids[0]])

        #expect(heads[ids[0]]?.sha == "aaaa1111")
        #expect(heads[ids[0]]?.committedAt == nil)
    }

    /// PR bez commitů v odpovědi (prázdné spojení) dá hlavu **bez data**, ne chybu: sha je to, na
    /// co se ptáme, datum je k ní příloha.
    @Test("Prázdné spojení commitů dá hlavu bez data")
    func survivesAnEmptyConnection() throws {
        let json = """
        {"data":{"pr0":{"pullRequest":{"headRefOid":"aaaa1111","commits":{"nodes":[]}}}}}
        """
        let response = try GhOutput.decoder.decode(
            GhPullRequestHeadsResponse.self,
            from: Data(json.utf8)
        )

        #expect(response.heads(of: [ids[0]])[ids[0]] == PullRequestHead(sha: "aaaa1111", committedAt: nil))
    }
}
