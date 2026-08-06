import Foundation
import Testing

@testable import PRism

/// Kde `claude` vede transcript (#97).
///
/// Pravidla jsou **změřená spuštěním** `claude` ve složkách s vyrobenými názvy, ne odhadnutá
/// ze zadání — to mluvilo jen o `/` a mezerách. Kdyby se mangling rozešel, transcript se
/// nenajde a nálezy po pádu zůstanou ležet.
@Suite("Cesta k transcriptu")
struct TranscriptLocationTests {
    private func mangled(_ path: String) -> String {
        TranscriptLocation.mangled(URL(filePath: path))
    }

    @Test("Lomítka a mezery se mění na pomlčku")
    func replacesSlashesAndSpaces() {
        #expect(
            mangled("/Users/ondra/Library/Application Support/PRism/worktrees/keboola/job-queue/725-c66a21f9")
                == "-Users-ondra-Library-Application-Support-PRism-worktrees-keboola-job-queue-725-c66a21f9"
        )
    }

    /// Změřeno: `…/scratchpad/tečka test.v2/sub` → `…-scratchpad-te-ka-test-v2-sub`.
    /// Tečka i diakritika jdou taky na pomlčku, takže to není pravidlo o třech znacích.
    @Test("Tečka i diakritika jdou na pomlčku")
    func replacesDotsAndDiacritics() {
        #expect(mangled("/a/tečka test.v2/sub") == "-a-te-ka-test-v2-sub")
    }

    /// Změřeno: `a_b+c~d(e)f'g,h@i#j` → `a-b-c-d-e-f-g-h-i-j`. Pravidlo je „všechno mimo
    /// `[A-Za-z0-9-]`“, tedy včetně podtržítka — a to je v názvech repozitářů běžné.
    @Test("Všechno mimo písmena, číslice a pomlčku jde na pomlčku", arguments: [
        ("/a/a_b", "-a-a-b"),
        ("/a/a+b", "-a-a-b"),
        ("/a/a~b", "-a-a-b"),
        ("/a/a(b)c", "-a-a-b-c"),
        ("/a/a'b", "-a-a-b"),
        ("/a/a,b", "-a-a-b"),
        ("/a/a@b", "-a-a-b"),
        ("/a/a#b", "-a-a-b"),
    ])
    func replacesEverythingElse(path: String, expected: String) {
        #expect(mangled(path) == expected)
    }

    /// Změřeno na cestě `/private/tmp/claude-501/-Users-…`, ze které vyšlo `-claude-501--Users`.
    /// Kdyby se pomlčky slučovaly, dvě různé cesty by vyšly na jednu složku.
    @Test("Pomlčky se nesluřují")
    func keepsRepeatedDashes() {
        #expect(mangled("/tmp/x/-Users-y") == "-tmp-x--Users-y")
    }

    @Test("Velikost písmen se zachovává")
    func keepsCase() {
        #expect(mangled("/a/PRism") == "-a-PRism")
    }

    @Test("Transcript je session id s příponou v té složce")
    func buildsTheTranscriptPath() {
        let url = TranscriptLocation.transcript(
            ofSession: "7acd841c-fc1f-4f84-9a94-1f8ea345b5b3",
            in: URL(filePath: "/a/b"),
            projects: URL(filePath: "/root/projects")
        )

        #expect(url.path(percentEncoded: false)
            == "/root/projects/-a-b/7acd841c-fc1f-4f84-9a94-1f8ea345b5b3.jsonl")
    }
}
