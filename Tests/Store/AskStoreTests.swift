import Foundation
import Testing

@testable import PRism

/// Uložené rozhovory (#452) — proti **skutečnému** disku nad dočasnou složkou, jako
/// `ReviewDraftStore`: celé je to o tom, co na disku zůstane.
@Suite("AskStore")
struct AskStoreTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let store: AskStore
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
        store = AskStore(layout: layout)
    }

    private func conversation(_ texts: [String], sessionID: String? = "s1") -> AskConversation {
        AskConversation(
            pullRequest: pr,
            messages: texts.enumerated().map { index, text in
                AskMessage(
                    speaker: index.isMultiple(of: 2) ? .mine : .claude,
                    text: text,
                    at: Date(timeIntervalSince1970: Double(index))
                )
            },
            sessionID: sessionID
        )
    }

    @Test("Rozhovor se uloží a přečte i s navázáním")
    func roundTrip() async throws {
        try await store.save(conversation(["proč?", "protože"]))

        let loaded = try await store.load(for: pr)

        #expect(loaded?.messages.map(\.text) == ["proč?", "protože"])
        #expect(loaded?.sessionID == "s1")
    }

    @Test("Bez souboru se vrací nic, ne chyba")
    func missingIsNil() async throws {
        #expect(try await store.load(for: pr) == nil)
    }

    /// **Prázdný rozhovor se maže, ne ukládá** — jinak by v cache zůstal soubor po každém PR,
    /// které si někdo jen otevřel, a „rozhovor existuje“ by přestalo něco znamenat.
    @Test("Prázdný rozhovor soubor smaže")
    func emptyDeletes() async throws {
        try await store.save(conversation(["proč?"]))
        #expect(FileManager.default.fileExists(atPath: layout.askFile(for: pr).path()))

        try await store.save(AskConversation(pullRequest: pr))

        #expect(!FileManager.default.fileExists(atPath: layout.askFile(for: pr).path()))
        #expect(try await store.load(for: pr) == nil)
    }

    /// Jméno souboru není pravda — tou je `pullRequest` uvnitř. Rozchod by znamenal, že se v tabu
    /// jednoho PR ukáže rozhovor o jiném.
    @Test("Cizí rozhovor v souboru se odmítne")
    func foreignConversationIsRejected() async throws {
        let other = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 99)
        try await store.save(AskConversation(
            pullRequest: other,
            messages: [AskMessage(speaker: .mine, text: "x", at: Date(timeIntervalSince1970: 0))]
        ))
        // Podstrčí soubor pod cizí jméno.
        try FileManager.default.copyItem(at: layout.askFile(for: other), to: layout.askFile(for: pr))

        await #expect(throws: AskStoreError.self) { try await store.load(for: pr) }
    }

    /// **Symlink by přečetl soubor mimo cache.** Aplikace si ho sama nevyrobí, ale „nikdy nesahat
    /// na uživatelovy soubory“ je tvrdá podmínka a nemá viset na tom, že si to někdo pamatuje —
    /// tatáž kontrola, jakou má `ReviewDraftStore` (#106).
    @Test("Symbolický odkaz na místě rozhovoru se odmítne")
    func symlinkIsRejected() async throws {
        let outside = directory.url.appending(path: "mimo.json")
        try Data("{}".utf8).write(to: outside)
        let file = layout.askFile(for: pr)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)

        await #expect(throws: AskStoreError.self) { try await store.load(for: pr) }
    }

    /// Nečitelný soubor **vyhodí chybu**, nevrátí `nil`: tichá nula by znamenala, že se zaplacený
    /// rozhovor tváří jako neexistující — a příští otázka by začala novou session a zaplatila
    /// kontext znovu.
    @Test("Rozbitý soubor se ohlásí, nezamlčí")
    func brokenFileThrows() async throws {
        let file = layout.askFile(for: pr)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{ tohle není json".utf8).write(to: file)

        await #expect(throws: (any Error).self) { try await store.load(for: pr) }
    }

    /// **Klíčem je PR, ne `headSha`** (na rozdíl od nálezů) — proto je v cestě jen číslo.
    @Test("Cesta k rozhovoru nenese commit")
    func theFileIsKeyedByPullRequestOnly() {
        let path = layout.askFile(for: pr).path(percentEncoded: false)

        #expect(path.hasSuffix("/ask/cli/cli/42.json"))
    }
}
