import Foundation
import Testing

@testable import PRism

/// Dávkový dotaz na hlavičku a slévatelnost vlastních PR (#572) — jeden dokument na celou sadu
/// a rozbor odpovědi.
///
/// **Nejcennější tvrzení je to o počtu**: 23 vlastních PR z 16 repozitářů je **jeden** argument
/// `query=` a jedno spuštění `gh` (změřeno 2,60–3,64 s a 1 bod z 5000/h). Po jednom to bylo
/// 46 volání a 29,6 s — a nikdo by si toho nevšiml, protože výsledek by byl stejný.
///
/// Druhá polovina jsou tvrzení o tom, co se do mapy **nedostane**: chybějící alias a nedopočítaná
/// slévatelnost (`UNKNOWN`) znamenají obojí „nevíme“, a to se nesmí zapsat jako odpověď.
@Suite("Dotaz na slévatelnost vlastních PR (#572)")
struct MergeReadinessQueryTests {
    private let ids = [
        PRIdentifier("cli/cli#14360")!,
        PRIdentifier("cli/cli#14356")!,
    ]
}

// MARK: - Dokument a argumenty

extension MergeReadinessQueryTests {
    /// Jeden dokument, jedno `query=`, dva aliasy — a **žádný dotaz na PR zvlášť**.
    @Test("Dvě PR jsou jeden dotaz")
    func buildsASingleQuery() {
        let arguments = MergeReadinessQuery.arguments(for: ids)

        #expect(arguments.prefix(3) == ["api", "graphql", "-f"])
        #expect(arguments.count { $0.hasPrefix("query=") } == 1)
        let document = arguments.first { $0.hasPrefix("query=") }!
        for index in 0..<2 {
            #expect(document.contains("\(MergeReadinessQuery.alias(index)): repository("))
        }
        #expect(document.contains("pr2:") == false)
    }

    /// Owner, jméno a číslo jdou **typovanou proměnnou**, ne do textu dokumentu — tatáž past jako
    /// u `PullRequestHeadsQuery`.
    @Test("Hodnoty jdou přes -F, ne do dokumentu")
    func passesValuesAsVariables() {
        let arguments = MergeReadinessQuery.arguments(
            for: ids + [PRIdentifier("vercel/next.js#97830")!]
        )

        #expect(arguments.count { $0 == "-F" } == 9)
        #expect(arguments.contains("owner0=cli"))
        #expect(arguments.contains("number0=14360"))
        #expect(arguments.contains("name2=next.js"))
        let document = arguments.first { $0.hasPrefix("query=") }!
        #expect(document.contains("next.js") == false)
    }

    /// **Pole jsou ta, která si aplikace tahá i po jednom.** Kdyby v dotazu jedno chybělo, složil
    /// by se z odpovědi jiný `PullRequest`, než jaký vrátí `fetchDetail(id:)` — a rozdíl mezi
    /// hlavičkou po startu a hlavičkou po otevření záložky se v okně nepozná.
    @Test("Dotaz si říká o tatáž pole jako dotaz po jednom")
    func asksForTheSameFieldsAsTheSingleQuery() {
        let document = MergeReadinessQuery.document(for: 1)

        for field in GhPullRequestDetail.jsonFields.split(separator: ",") {
            // `author` je jediná odchylka: `--json author` vrací objekt celý, v GraphQL se pole
            // vyjmenovávají.
            let expected = field == "author" ? "author { login }" : String(field)
            #expect(document.contains(expected), "v dotazu chybí \(field)")
        }
        for field in GhBranchStatus.jsonFields.split(separator: ",") {
            #expect(document.contains(String(field)), "v dotazu chybí \(field)")
        }
    }

    /// **Poloha větve proti základu v dotazu není, a je to rozhodnutí.** `compare` potřebuje jméno
    /// základu a hlavu, tedy hodnoty z **téhle** odpovědi, a GraphQL na sourozenecké pole odkázat
    /// neumí. Deska ji nepotřebuje a záložka si ji dotáhne sama.
    @Test("Dotaz se neptá na polohu větve")
    func doesNotAskForTheDivergence() {
        let document = MergeReadinessQuery.document(for: 3)

        #expect(document.contains("compare") == false)
        #expect(document.contains("aheadBy") == false)
    }

    /// Alias je **pozice v dotazu**, ne `owner/name#číslo`.
    @Test("Alias je platné GraphQL jméno")
    func namesAliasesByPosition() {
        #expect(MergeReadinessQuery.alias(0) == "pr0")
        #expect(MergeReadinessQuery.alias(22) == "pr22")
    }
}

// MARK: - Rozbor odpovědi

extension MergeReadinessQueryTests {
    private func response(_ fixture: String) throws -> GhMergeReadinessResponse {
        try GhOutput.decoder.decode(
            GhMergeReadinessResponse.self,
            from: Fixture.data("gh/\(fixture)")
        )
    }

    /// Skutečná odpověď z živého API (`cli/cli#14360` a `#14356`) — dvě hlavičky a dvě
    /// slévatelnosti, složené **týmiž dekodéry**, jaké čtou `gh pr view --json`.
    @Test("Odpověď se spáruje se vstupním polem")
    func mapsTheAnswerBackToTheInput() throws {
        let readiness = try response("pr-merge-readiness.json").readiness(of: ids)

        #expect(readiness.count == 2)
        let first = try #require(readiness[ids[0]])
        #expect(first.detail.id == ids[0])
        #expect(first.detail.headSha == "091c24d7025772ca632bf443e3c3d4d8f9bdce91")
        #expect(first.detail.baseRef == "trunk")
        #expect(first.detail.state == .open)
        #expect(first.detail.isCrossRepository == false)
        #expect(first.status.mergeability == .mergeable)
        // `BLOCKED` u `MERGEABLE` je běžný stav u repa bez práva zápisu (změřeno na `cli/cli`).
        #expect(first.status.mergeState == .blocked)
        // Poloha větve v hromadné odpovědi **není** — dotáhne ji až otevřená záložka.
        #expect(first.status.divergence == nil)
    }

    /// **Částečná odpověď je odpověď**, a je to skutečný výstup: dotaz na tři PR, z nichž jedna je
    /// v repozitáři, který neexistuje, vrátil data ke zbytku a `errors` k němu (`gh` u toho skončil
    /// kódem 1).
    ///
    /// **A mergnutý PR se z ní zahodí.** GitHub u něj vrací `mergeable: UNKNOWN` navždycky
    /// (změřeno na `PRism#470`, tady na `cli/cli#14363`) — zapsat to jako odpověď by znamenalo,
    /// že se na to PR do dalšího pohybu nikdo nezeptá.
    @Test("Chybějící alias ani nedopočítaná slévatelnost se nezapíší")
    func keepsOnlyWhatItKnows() throws {
        let asked = [ids[0], PRIdentifier("cli/cli#14363")!, PRIdentifier("ondrajodas/there-is-no-such-repo#1")!]

        let readiness = try response("pr-merge-readiness-partial.json").readiness(of: asked)

        #expect(readiness.count == 1)
        #expect(readiness[asked[0]]?.detail.headSha == "091c24d7025772ca632bf443e3c3d4d8f9bdce91")
        #expect(readiness[asked[1]] == nil, "UNKNOWN je „ještě jsem nepočítal“, ne odpověď")
        #expect(readiness[asked[2]] == nil, "chybějící alias je „nevíme“")
    }

    /// Uzel, kterému nerozumíme, **nepoloží celou sadu**. Jedno PR bez autora (smazaný účet, bot)
    /// by jinak znamenalo prázdný pruh `K merge` u všech ostatních.
    ///
    /// Testuje se **inline JSONem** — PR bez autora se ze skutečných dat nesehnal.
    @Test("Uzel bez autora nepoloží zbytek odpovědi")
    func survivesAnUnreadableNode() throws {
        let json = """
        {"data":{"pr0":{"pullRequest":{"number":14360,"title":"bez autora","author":null,
          "headRefOid":"aaaa1111","baseRefOid":"bbbb2222","url":"https://github.com/cli/cli/pull/14360",
          "updatedAt":"2026-09-04T21:56:43Z","state":"OPEN","isDraft":false,"body":"",
          "headRefName":"a","baseRefName":"trunk","isCrossRepository":false,
          "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN"}},
        "pr1":{"pullRequest":{"number":14356,"title":"s autorem","author":{"login":"williammartin"},
          "headRefOid":"cccc3333","baseRefOid":"dddd4444","url":"https://github.com/cli/cli/pull/14356",
          "updatedAt":"2026-09-04T21:56:43Z","state":"OPEN","isDraft":false,"body":"",
          "headRefName":"b","baseRefName":"trunk","isCrossRepository":false,
          "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN"}}}}
        """
        let response = try GhOutput.decoder.decode(
            GhMergeReadinessResponse.self,
            from: Data(json.utf8)
        )

        let readiness = response.readiness(of: ids)

        #expect(readiness[ids[0]] == nil)
        #expect(readiness[ids[1]]?.detail.headSha == "cccc3333")
    }

    /// **Cizí číslo v odpovědi se nepřiřadí.** Hlavička se páruje s pozicí v dotazu, takže by
    /// posunutá odpověď tiše přiřadila cizí hlavu k našemu PR — a nálezy se klíčují `headSha`.
    /// Hlídá to `GhPullRequestDetail.pullRequest(id:)`, tady se ověřuje, že se ta chyba **zahodí**,
    /// ne že položí celou sadu.
    @Test("PR s cizím číslem se do mapy nedostane")
    func refusesAMismatchedNumber() throws {
        let json = """
        {"data":{"pr0":{"pullRequest":{"number":999,"title":"jiné PR","author":{"login":"x"},
          "headRefOid":"aaaa1111","baseRefOid":"bbbb2222","url":"https://github.com/cli/cli/pull/999",
          "updatedAt":"2026-09-04T21:56:43Z","state":"OPEN","isDraft":false,"body":"",
          "headRefName":"a","baseRefName":"trunk","isCrossRepository":false,
          "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN"}}}}
        """
        let response = try GhOutput.decoder.decode(
            GhMergeReadinessResponse.self,
            from: Data(json.utf8)
        )

        #expect(response.readiness(of: [ids[0]]).isEmpty)
    }
}
