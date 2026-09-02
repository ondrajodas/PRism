import Foundation
import Testing

@testable import PRism

/// Uložené značky `Prošlo` (#500) — proti **skutečnému** disku nad dočasnou složkou, jako
/// `AskStore` a `ReviewDraftStore`: celé je to o tom, co na disku zůstane.
@Suite("ReadMarkStore")
struct ReadMarkStoreTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let store: ReadMarkStore
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
        store = ReadMarkStore(layout: layout)
    }

    private func marks(_ entries: [String: String?]) -> ReadMarks {
        ReadMarks(
            pullRequest: pr,
            marks: entries.mapValues { ReadMark(blobs: $0, markedAt: Date(timeIntervalSince1970: 7)) }
        )
    }

    @Test("Značky se uloží a přečtou i s otiskem")
    func roundTrip() async throws {
        try await store.save(marks(["src/Cart.swift": "aaa..bbb"]))

        let loaded = try await store.load(for: pr)

        #expect(loaded?.marks["src/Cart.swift"]?.blobs == "aaa..bbb")
        #expect(loaded?.marks["src/Cart.swift"]?.markedAt == Date(timeIntervalSince1970: 7))
    }

    /// Chybějící otisk je **hodnota, ne chybějící údaj** (přejmenování beze změny obsahu), takže
    /// `nil` musí přežít cestu na disk a zpátky — jinak by se z `read` po restartu stalo
    /// `změněno od prošlého`.
    @Test("Chybějící otisk se uloží jako chybějící, ne jako prázdný řetězec")
    func missingBlobsSurvive() async throws {
        try await store.save(marks(["docs/A.md": nil]))

        let loaded = try await store.load(for: pr)

        #expect(loaded?.marks["docs/A.md"] != nil)
        #expect(loaded?.marks["docs/A.md"]?.blobs == nil)
    }

    @Test("Bez souboru se vrací nic, ne chyba")
    func missingIsNil() async throws {
        #expect(try await store.load(for: pr) == nil)
    }

    /// **Prázdné značky se mažou, ne ukládají** — jinak by v cache zůstal soubor po každém PR,
    /// u kterého si někdo něco zaškrtl a zase odškrtl.
    @Test("Prázdné značky soubor smažou")
    func emptyDeletes() async throws {
        try await store.save(marks(["src/Cart.swift": "aaa..bbb"]))
        #expect(FileManager.default.fileExists(atPath: layout.readMarkFile(for: pr).path()))

        try await store.save(ReadMarks(pullRequest: pr))

        #expect(!FileManager.default.fileExists(atPath: layout.readMarkFile(for: pr).path()))
        #expect(try await store.load(for: pr) == nil)
    }

    /// Jméno souboru není pravda — tou je `pullRequest` uvnitř. Rozchod by znamenal, že se
    /// v diffu jednoho PR zaškrtnou soubory jiného.
    @Test("Cizí značky v souboru se odmítnou")
    func foreignMarksAreRejected() async throws {
        let other = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 99)
        try await store.save(ReadMarks(
            pullRequest: other,
            marks: ["src/Cart.swift": ReadMark(blobs: "a..b", markedAt: Date(timeIntervalSince1970: 1))]
        ))
        // Podstrčí soubor pod cizí jméno.
        try FileManager.default.copyItem(
            at: layout.readMarkFile(for: other),
            to: layout.readMarkFile(for: pr)
        )

        await #expect(throws: ReadMarkStoreError.self) { try await store.load(for: pr) }
    }

    /// **Symlink by přečetl soubor mimo cache.** Tatáž kontrola, jakou má `AskStore` (#458)
    /// a `ReviewDraftStore` (#106) — a je to tvrdá podmínka č. 3, ne opatrnost.
    @Test("Symbolický odkaz na místě značek se odmítne")
    func symlinkIsRejected() async throws {
        let outside = directory.url.appending(path: "mimo.json")
        try Data("{}".utf8).write(to: outside)
        let file = layout.readMarkFile(for: pr)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)

        await #expect(throws: ReadMarkStoreError.self) { try await store.load(for: pr) }
    }

    /// Nečitelný soubor **vyhodí chybu**, nevrátí `nil`: tichá nula znamená v okně nezaškrtnutý
    /// diff, tedy tvrzení „tohle jsi nečetl“ nad souborem, který na disku je.
    @Test("Rozbitý soubor se ohlásí, nezamlčí")
    func brokenFileThrows() async throws {
        let file = layout.readMarkFile(for: pr)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{ tohle není json".utf8).write(to: file)

        await #expect(throws: (any Error).self) { try await store.load(for: pr) }
    }

    /// **Klíčem je PR, ne `headSha`** — na tom celá značka stojí: klíčovaná commitem by zmizela
    /// právě tím pushem, kvůli kterému se člověk do diffu vrací.
    @Test("Cesta ke značkám nenese commit")
    func theFileIsKeyedByPullRequestOnly() {
        let path = layout.readMarkFile(for: pr).path(percentEncoded: false)

        #expect(path.hasSuffix("/read-marks/cli/cli/42.json"))
    }

    /// **Symlink v rodičovské složce vyvede ven čtení, zápis i mazání** — a tady se tvrdí, že se
    /// to nestalo. Je to ten druh testu, který `CLAUDE.md` označuje za nejcennější: kdyby kontrola
    /// vypadla, projde všechno ostatní — jen o kus vedle, v cizí složce.
    @Suite("Značky mimo cache")
    struct OutsideTheCache {
        private let cache: TemporaryDirectory
        private let elsewhere: TemporaryDirectory
        private let layout: CacheLayout
        private let store: ReadMarkStore
        private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
        /// Soubor, na který ten odkaz míří — cizí, tedy přesně to, na co se sahat nesmí.
        private let stranger: URL

        init() throws {
            cache = try TemporaryDirectory()
            elsewhere = try TemporaryDirectory()
            layout = CacheLayout(root: cache.url)
            store = ReadMarkStore(layout: layout)

            // `read-marks/cli` je odkaz ven, takže `read-marks/cli/cli/42.json` leží po rozbalení
            // v cizí složce.
            let owner = layout.readMarkFile(for: pr)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: owner.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: elsewhere.url.appending(path: "cli"),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(at: owner, withDestinationURL: elsewhere.url)

            stranger = elsewhere.url.appending(path: "cli/42.json")
            try Data(#"{"pullRequest":{"repo":{"owner":"cli","name":"cli"},"number":42},"marks":{}}"#.utf8)
                .write(to: stranger)
        }

        @Test("Čtení mimo cache se odmítne, cizí soubor se nepřečte")
        func loadRefuses() async throws {
            await #expect(throws: ReadMarkStoreError.self) { try await store.load(for: pr) }
        }

        @Test("Zápis mimo cache se odmítne a cizí soubor zůstane, jaký byl")
        func saveLeavesTheStrangerAlone() async throws {
            let before = try Data(contentsOf: stranger)
            let marks = ReadMarks(
                pullRequest: pr,
                marks: ["a.swift": ReadMark(blobs: "a..b", markedAt: Date(timeIntervalSince1970: 1))]
            )

            await #expect(throws: ReadMarkStoreError.self) { try await store.save(marks) }

            #expect(try Data(contentsOf: stranger) == before, "zápis sáhl mimo cache")
        }

        @Test("Mazání mimo cache cizí soubor nesmaže")
        func deleteLeavesTheStrangerAlone() async throws {
            try await store.delete(for: pr)

            #expect(
                FileManager.default.fileExists(atPath: stranger.path(percentEncoded: false)),
                "mazání sáhlo mimo cache"
            )
        }
    }
}
