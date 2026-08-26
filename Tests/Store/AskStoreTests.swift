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

    /// **Symlink v rodičovské složce vyvede ven čtení, zápis i mazání** — a tady se tvrdí, že se
    /// to nestalo (nález Copilota na #458; do té doby měla hranici jen `delete`).
    ///
    /// Je to ten druh testu, který `CLAUDE.md` označuje za nejcennější: tvrdí, že se něco
    /// **NEstalo**. Kdyby kontrola vypadla, projde všechno ostatní — soubor se uloží, přečte
    /// i smaže, jen o kus vedle, v cizí složce.
    ///
    /// Odkaz je na **složce**, ne na souboru: to je ten případ, který `CacheLayout.isSymbolicLink`
    /// nezachytí (ptá se na samotný soubor) a chytá ho jedině `contains`, který rozbaluje rodiče.
    @Suite("Rozhovor mimo cache")
    struct OutsideTheCache {
        private let cache: TemporaryDirectory
        private let elsewhere: TemporaryDirectory
        private let layout: CacheLayout
        private let store: AskStore
        private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
        /// Soubor, na který ten odkaz míří — cizí, tedy přesně to, na co se sahat nesmí.
        private let stranger: URL

        init() throws {
            cache = try TemporaryDirectory()
            elsewhere = try TemporaryDirectory()
            layout = CacheLayout(root: cache.url)
            store = AskStore(layout: layout)

            // `ask/cli` je odkaz ven, takže `ask/cli/cli/42.json` leží po rozbalení v cizí složce.
            let owner = layout.askFile(for: pr).deletingLastPathComponent().deletingLastPathComponent()
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
            try Data(#"{"pullRequest":{"repo":{"owner":"cli","name":"cli"},"number":42},"messages":[]}"#.utf8)
                .write(to: stranger)
        }

        private func conversation() -> AskConversation {
            AskConversation(
                pullRequest: pr,
                messages: [AskMessage(speaker: .mine, text: "proč?", at: Date(timeIntervalSince1970: 0))]
            )
        }

        @Test("Čtení mimo cache se odmítne, cizí soubor se nepřečte")
        func loadRefuses() async throws {
            await #expect(throws: AskStoreError.self) { try await store.load(for: pr) }
        }

        @Test("Zápis mimo cache se odmítne a cizí soubor zůstane, jaký byl")
        func saveLeavesTheStrangerAlone() async throws {
            let before = try Data(contentsOf: stranger)

            await #expect(throws: AskStoreError.self) { try await store.save(conversation()) }

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

    /// **Klíčem je PR, ne `headSha`** (na rozdíl od nálezů) — proto je v cestě jen číslo.
    @Test("Cesta k rozhovoru nenese commit")
    func theFileIsKeyedByPullRequestOnly() {
        let path = layout.askFile(for: pr).path(percentEncoded: false)

        #expect(path.hasSuffix("/ask/cli/cli/42.json"))
    }
}
