import Foundation
import Testing

@testable import PRism

/// Uložené anotace hunků (#524) — proti **skutečnému** disku nad dočasnou složkou, jako
/// `ReadMarkStore` a `AskStore`: celé je to o tom, co na disku zůstane.
@Suite("AnnotationStore (#524)")
struct AnnotationStoreTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let store: AnnotationStore
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
        store = AnnotationStore(layout: layout)
    }

    private func annotations(
        for pullRequest: PRIdentifier? = nil,
        headSha: String = "aaaa1111",
        hunks: [HunkAnnotation] = [],
        files: [FileAnnotation] = [],
        outcome: ReviewRunOutcome = .finished,
        answered: Bool = true,
        dropped: Int = 0
    ) -> StoredAnnotations {
        StoredAnnotations(
            pullRequest: pullRequest ?? pr,
            headSha: headSha,
            hunks: hunks,
            files: files,
            outcome: outcome,
            sessionID: "s1",
            answered: answered,
            dropped: dropped,
            finishedAt: Date(timeIntervalSince1970: 7),
            usage: nil
        )
    }

    @Test("Anotace se uloží a přečtou celé")
    func roundTrip() async throws {
        try await store.save(
            annotations(
                hunks: [HunkAnnotation(file: "a.swift", hunk: 2, why: "věta", source: "z commitu x")],
                files: [FileAnnotation(file: "a.swift", kind: .refactor)],
                dropped: 3
            )
        )

        let loaded = try await store.load(for: pr)

        #expect(loaded?.headSha == "aaaa1111")
        #expect(loaded?.hunks.first?.hunk == 2)
        #expect(loaded?.hunks.first?.source == "z commitu x")
        #expect(loaded?.files.first?.kind == .refactor)
        #expect(loaded?.dropped == 3)
        #expect(loaded?.finishedAt == Date(timeIntervalSince1970: 7))
    }

    /// **Běh, ze kterého nevypadlo nic, se ukládá taky** — na rozdíl od prázdných značek `Prošlo`.
    /// „Zkusilo se to a nedoběhlo“ je odpověď, za kterou se zaplatilo, a bez souboru by se v okně
    /// nedala odlišit od „nikdy neběželo“ — tedy od stavu, který si vyžádá běh druhý.
    @Test("Prázdný a nečitelný běh se uloží taky")
    func anEmptyRunIsStoredAsWell() async throws {
        try await store.save(annotations(outcome: .timedOut, answered: false))

        let loaded = try await store.load(for: pr)

        #expect(loaded?.isEmpty == true)
        #expect(loaded?.answered == false)
        #expect(loaded?.outcome == .timedOut)
    }

    /// **Přepisuje, nedopisuje**: užitečná je vždycky jen sada pro dnešní hlavu.
    @Test("Nový běh ten předchozí přepíše")
    func savingOverwrites() async throws {
        try await store.save(
            annotations(headSha: "aaaa1111", hunks: [
                HunkAnnotation(file: "a.swift", hunk: 1, why: "stará", source: nil)
            ])
        )
        try await store.save(
            annotations(headSha: "bbbb2222", hunks: [
                HunkAnnotation(file: "b.swift", hunk: 1, why: "nová", source: nil)
            ])
        )

        let loaded = try await store.load(for: pr)

        #expect(loaded?.headSha == "bbbb2222")
        #expect(loaded?.hunks.map(\.why) == ["nová"])
    }

    @Test("Bez souboru se vrací nic, ne chyba")
    func missingIsNil() async throws {
        #expect(try await store.load(for: pr) == nil)
    }

    @Test("Mazání je idempotentní")
    func deleteIsIdempotent() async throws {
        try await store.save(annotations())
        try await store.delete(for: pr)
        try await store.delete(for: pr)

        #expect(try await store.load(for: pr) == nil)
    }

    /// Jméno souboru není pravda — tou je `pullRequest` uvnitř. Rozchod by znamenal větu nad
    /// hunkem, která mluví o cizím PR.
    @Test("Cizí anotace v souboru se odmítnou")
    func foreignAnnotationsAreRejected() async throws {
        let other = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 99)
        try await store.save(annotations(for: other))
        try FileManager.default.copyItem(
            at: layout.annotationFile(for: other),
            to: layout.annotationFile(for: pr)
        )

        await #expect(throws: AnnotationStoreError.self) { try await store.load(for: pr) }
    }

    /// **Symlink by přečetl soubor mimo cache** — tvrdá podmínka č. 3, ne opatrnost.
    @Test("Symbolický odkaz na místě anotací se odmítne")
    func symlinkIsRejected() async throws {
        let outside = directory.url.appending(path: "mimo.json")
        try Data("{}".utf8).write(to: outside)
        let file = layout.annotationFile(for: pr)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)

        await #expect(throws: AnnotationStoreError.self) { try await store.load(for: pr) }
    }

    /// Nečitelný soubor **vyhodí chybu**, nevrátí `nil`: tichá nula by znamenala, že se zaplacená
    /// session tváří jako neproběhlá — a příští otevření PR by ji zaplatilo znovu.
    @Test("Rozbitý soubor se ohlásí, nezamlčí")
    func brokenFileThrows() async throws {
        let file = layout.annotationFile(for: pr)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{ tohle není json".utf8).write(to: file)

        await #expect(throws: (any Error).self) { try await store.load(for: pr) }
    }

    /// **Jeden soubor na PR, hlavu nese obsah.** Soubor na hlavu by znamenal záznamy, které nikdo
    /// nikdy nepřečte a nic nemaže — anotace z jiné hlavy se neukáže ani jako zastaralá.
    @Test("Cesta k anotacím nenese commit")
    func theFileIsKeyedByPullRequestOnly() {
        let path = layout.annotationFile(for: pr).path(percentEncoded: false)

        #expect(path.hasSuffix("/annotations/cli/cli/42.json"))
    }
}
