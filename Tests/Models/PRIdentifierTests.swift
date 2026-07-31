import Foundation
import Testing

@testable import PRism

@Suite("PRIdentifier")
struct PRIdentifierTests {
    private let prism = RepoID(owner: "ondrajodas", name: "PRism")

    @Test("Formátuje se jako owner/repo#číslo")
    func formatsAsRepoHashNumber() {
        #expect(PRIdentifier(repo: prism, number: 12).description == "ondrajodas/PRism#12")
    }

    @Test("Parsuje owner/repo#číslo")
    func parsesRepoHashNumber() {
        #expect(PRIdentifier("ondrajodas/PRism#12") == PRIdentifier(repo: prism, number: 12))
    }

    @Test(
        "Odmítá neplatný zápis",
        arguments: [
            "",
            "ondrajodas/PRism",
            "ondrajodas/PRism#",
            "ondrajodas/PRism#abc",
            "ondrajodas/PRism#0",
            "ondrajodas/PRism#-1",
            "ondrajodas/PRism#1.5",
            "ondrajodas/PRism# 1",
            "ondrajodas/PRism#1#2",
            "#12",
            "ondrajodas#12",
        ]
    )
    func rejectsMalformedInput(raw: String) {
        #expect(PRIdentifier(raw) == nil)
    }

    @Test("Kóduje se jako jediný řetězec")
    func encodesAsSingleString() throws {
        let json = try encodedJSON(PRIdentifier(repo: prism, number: 12))

        #expect(json == #"["ondrajodas\/PRism#12"]"#)
    }

    @Test("Přežije round-trip přes Codable")
    func survivesCodableRoundTrip() throws {
        let id = PRIdentifier(repo: prism, number: 12)

        #expect(try roundTrip(id) == id)
    }

    @Test("Dekódování nesmyslu selže")
    func decodingMalformedStringFails() {
        let data = Data(#"["ondrajodas/PRism"]"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([PRIdentifier].self, from: data)
        }
    }

    @Test("Jde použít jako klíč slovníku a v JSONu je z něj objekt")
    func worksAsDictionaryKey() throws {
        let byPR = [PRIdentifier(repo: prism, number: 12): ReviewState.queued]

        let json = String(decoding: try JSONEncoder().encode(byPR), as: UTF8.self)

        #expect(json.hasPrefix(#"{"ondrajodas\/PRism#12":"#))
        #expect(try JSONDecoder().decode([PRIdentifier: ReviewState].self, from: Data(json.utf8)) == byPR)
    }
}
