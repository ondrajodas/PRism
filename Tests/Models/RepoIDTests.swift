import Foundation
import Testing

@testable import PRism

@Suite("RepoID")

struct RepoIDTests {
    @Test("Formátuje se jako owner/repo")
    func formatsAsOwnerSlashName() {
        #expect(RepoID(owner: "ondrajodas", name: "PRism").description == "ondrajodas/PRism")
    }

    @Test("Parsuje owner/repo")
    func parsesOwnerSlashName() {
        #expect(RepoID("ondrajodas/PRism") == RepoID(owner: "ondrajodas", name: "PRism"))
    }

    @Test("Tečky a pomlčky v názvu jsou v pořádku")
    func acceptsDotsAndDashes() {
        #expect(RepoID("keboola-dev/my.repo_v2") == RepoID(owner: "keboola-dev", name: "my.repo_v2"))
    }

    @Test(
        "Odmítá neplatný zápis",
        arguments: [
            "",
            "PRism",
            "/PRism",
            "ondrajodas/",
            "ondrajodas/PRism/extra",
            "ondra jodas/PRism",
            "ondrajodas/PR ism",
            "ondrajodas/PRism#12",
            // Z identifikátoru se skládá cesta do cache a na té cestě se maže —
            // krok „nahoru" v ní nemá co dělat.
            "../..",
            "./PRism",
            "ondrajodas/..",
        ]
    )
    func rejectsMalformedInput(raw: String) {
        #expect(RepoID(raw) == nil)
    }

    @Test("Kóduje se jako jediný řetězec")
    func encodesAsSingleString() throws {
        let json = try encodedJSON(RepoID(owner: "ondrajodas", name: "PRism"))

        #expect(json == #"["ondrajodas\/PRism"]"#)
    }

    @Test("Přežije round-trip přes Codable")
    func survivesCodableRoundTrip() throws {
        let repo = RepoID(owner: "ondrajodas", name: "PRism")

        #expect(try roundTrip(repo) == repo)
    }

    @Test("Dekódování nesmyslu selže")
    func decodingMalformedStringFails() {
        let data = Data(#"["PRism"]"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([RepoID].self, from: data)
        }
    }

    @Test("Jde použít jako klíč slovníku a v JSONu je z něj objekt")
    func worksAsDictionaryKey() throws {
        let repo = RepoID(owner: "ondrajodas", name: "PRism")
        let byRepo = [repo: "manual"]

        let json = String(decoding: try JSONEncoder().encode(byRepo), as: UTF8.self)

        #expect(json == #"{"ondrajodas\/PRism":"manual"}"#)
        #expect(try JSONDecoder().decode([RepoID: String].self, from: Data(json.utf8)) == byRepo)
    }
}
