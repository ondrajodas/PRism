import Foundation
import Testing

@testable import PRism

/// Otevření přepisu surové session ze storu (#327).
///
/// Proti **fake** `TranscriptReading`, protože tady se testuje to, co store dělá s odpovědí — tři
/// různá „přepis tu není“, které se nesmí slít, a přírůstek v patičce. Skutečné čtení disku má
/// vlastní suitu (`RawTranscriptSnapshotTests`).
@Suite("AppStore — surová session")
@MainActor
struct AppStoreRawSessionTests {
    private let target = RawSessionTarget(
        sessionID: "abc-123",
        worktree: URL(filePath: "/Users/ondra/cache/worktrees/o/r/6-abc"),
        skill: "security-review",
        slug: "o/r#412"
    )

    private func store(_ reader: FakeTranscriptReader) -> AppStore {
        AppStore(gateway: FakeGitHubGateway(always: .success([])), transcripts: reader)
    }

    private func transcript(events: Int, fileBytes: Int) -> RawTranscript {
        RawTranscript(
            events: (0..<events).map {
                TranscriptEvent(id: $0, at: nil, kind: .prose, subject: "próza · 4 B", body: "text")
            },
            fileBytes: fileBytes
        )
    }

    // MARK: - Tři různá „přepis tu není“

    @Test("Přepis, který je, se ukáže")
    func aTranscriptThatExistsIsShown() async throws {
        let reader = FakeTranscriptReader([:])
        reader.snapshots = ["abc-123": transcript(events: 3, fileBytes: 900)]
        let store = store(reader)

        await store.openRawSession(target)

        guard case .shown(let shown) = try #require(store.rawSession?.state) else {
            Issue.record("čekal se přepis")
            return
        }
        #expect(shown.events.count == 3)
    }

    @Test("Chybějící přepis je vlastní stav, ne prázdná obrazovka")
    func aMissingTranscriptIsItsOwnState() async throws {
        let store = store(FakeTranscriptReader([:]))

        await store.openRawSession(target)

        #expect(store.rawSession?.state == .missing)
    }

    /// **`do`/`catch`, ne `try?`.** Ten by obě odpovědi slil do `nil`, protože Swift výsledek `try?`
    /// nad funkcí vracející optional zplošťuje — a chybějící přepis by pak vypadal stejně jako ten,
    /// který se nedá přečíst. Přitom u prvního nemá `Načíst znovu` co dělat a u druhého ano.
    @Test("Nečitelný přepis se nesmí slít s chybějícím")
    func unreadableIsNotTheSameAsMissing() async throws {
        let reader = FakeTranscriptReader([:])
        reader.snapshotFailing = ["abc-123"]
        let store = store(reader)

        await store.openRawSession(target)

        #expect(store.rawSession?.state == .unreadable(TranscriptUnreadable.invalidEncoding.reason))
        #expect(store.rawSession?.state != .missing)
    }

    @Test("Prázdný přepis se nesmí slít s tím, který se nedá přečíst")
    func emptyIsNotTheSameAsUnreadable() async throws {
        let reader = FakeTranscriptReader([:])
        reader.snapshots = ["abc-123": RawTranscript(fileBytes: 0)]
        let store = store(reader)

        await store.openRawSession(target)

        #expect(store.rawSession?.state == .empty(bytes: 0))
    }

    /// Sheet se otevírá hned a obsah dorazí za chvíli — tlačítko, po kterém se pár desetin sekundy
    /// nic nestane, vypadá jako tlačítko, které nic neudělalo.
    @Test("Bez čtečky transcriptů se to řekne, nepředstírá se prázdno")
    func withoutAReaderItSaysSo() async throws {
        let store = AppStore(gateway: FakeGitHubGateway(always: .success([])))

        await store.openRawSession(target)

        guard case .unreadable = try #require(store.rawSession?.state) else {
            Issue.record("čekal se nečitelný stav")
            return
        }
    }

    // MARK: - Načíst znovu a zavření

    @Test("Načíst znovu doopravdy čte znovu")
    func reloadReadsAgain() async throws {
        let reader = FakeTranscriptReader([:])
        reader.snapshots = ["abc-123": transcript(events: 1, fileBytes: 100)]
        let store = store(reader)

        await store.openRawSession(target)
        reader.snapshots = ["abc-123": transcript(events: 4, fileBytes: 400)]
        await store.reloadRawSession()

        #expect(reader.snapshotCount == 2)
        guard case .shown(let shown) = try #require(store.rawSession?.state) else {
            Issue.record("čekal se přepis")
            return
        }
        #expect(shown.events.count == 4)
    }

    /// Snímek má megabajty a mimo otevřený sheet ho nikdo nečte — takže po zavření **nesmí zůstat**.
    @Test("Zavření sheetu snímek zahodí")
    func closingDropsTheSnapshot() async throws {
        let reader = FakeTranscriptReader([:])
        reader.snapshots = ["abc-123": transcript(events: 2, fileBytes: 200)]
        let store = store(reader)

        await store.openRawSession(target)
        store.closeRawSession()

        #expect(store.rawSession == nil)
    }

    @Test("Načíst znovu po zavření nic nečte")
    func reloadAfterClosingDoesNothing() async throws {
        let reader = FakeTranscriptReader([:])
        reader.snapshots = ["abc-123": transcript(events: 2, fileBytes: 200)]
        let store = store(reader)

        await store.openRawSession(target)
        store.closeRawSession()
        await store.reloadRawSession()

        #expect(reader.snapshotCount == 1)
        #expect(store.rawSession == nil)
    }

    /// **Cíl sám na rozlišení nestačí** (nálezem Copilota na #408): dvě čtení **téhož** cíle se od
    /// sebe poznají jedině generací, a to pomalejší z nich nesmí přepsat novější. Bez ní by dvě
    /// kliknutí na `Načíst znovu` skončila u snímku, o který nikdo nežádal.
    @Test("Pomalejší čtení nepřepíše novější snímek téže session")
    func aSlowerReadDoesNotOverwriteANewerOne() async throws {
        let reader = FakeTranscriptReader([:])
        reader.snapshots = ["abc-123": transcript(events: 1, fileBytes: 100)]
        let store = store(reader)
        await store.openRawSession(target)

        // Dvě čtení téhož cíle: to druhé (novější) dorazí a to první se pak nesmí propsat.
        reader.snapshots = ["abc-123": transcript(events: 9, fileBytes: 900)]
        let stale = store.rawSession?.generation
        await store.reloadRawSession()

        #expect(store.rawSession?.generation != stale)
        guard case .shown(let shown) = try #require(store.rawSession?.state) else {
            Issue.record("čekal se přepis")
            return
        }
        #expect(shown.events.count == 9)
    }

    // MARK: - Přírůstek

    @Test("Přírůstek se počítá proti velikosti při snímku")
    func growthIsMeasuredAgainstTheSnapshot() async throws {
        let reader = FakeTranscriptReader([:])
        reader.snapshots = ["abc-123": transcript(events: 1, fileBytes: 1_000)]
        reader.sizes = ["abc-123": 1_000]
        let store = store(reader)

        await store.openRawSession(target)
        #expect(store.rawSessionGrowth() == nil)

        reader.sizes = ["abc-123": 3_400]
        await store.refreshRawSessionSize()

        #expect(store.rawSessionGrowth() == 2_400)
    }

    /// Dotaz na velikost je **jeden dotaz na atributy souboru**, ne druhé čtení okna — kvůli jednomu
    /// číslu v patičce by přečtení 4 MB bylo to nejdražší v celém sheetu.
    @Test("Tik přírůstku okno nečte znovu")
    func theGrowthTickDoesNotReadTheWindow() async throws {
        let reader = FakeTranscriptReader([:])
        reader.snapshots = ["abc-123": transcript(events: 1, fileBytes: 1_000)]
        reader.sizes = ["abc-123": 5_000]
        let store = store(reader)

        await store.openRawSession(target)
        await store.refreshRawSessionSize()
        await store.refreshRawSessionSize()

        #expect(reader.snapshotCount == 1)
    }

    @Test("Přírůstek u stavu bez přepisu se nehlásí")
    func noGrowthWithoutATranscript() async throws {
        let reader = FakeTranscriptReader([:])
        reader.sizes = ["abc-123": 5_000]
        let store = store(reader)

        await store.openRawSession(target)

        #expect(store.rawSession?.state == .missing)
        #expect(store.rawSessionGrowth() == nil)
    }

    /// Dvě rychlá kliknutí na dvou dráhách by jinak nakreslila přepis jedné session pod titulkem
    /// druhé — a to je chyba, kterou nikdo nepozná, protože obojí vypadá jako platný přepis.
    @Test("Přepis cizí session se pod jiným titulkem neukáže")
    func aSnapshotOfAnotherSessionIsNotShown() async throws {
        let reader = FakeTranscriptReader([:])
        reader.snapshots = ["abc-123": transcript(events: 3, fileBytes: 900)]
        let store = store(reader)
        let other = RawSessionTarget(
            sessionID: "jina-session",
            worktree: target.worktree,
            skill: "docs-review",
            slug: "o/r#412"
        )

        await store.openRawSession(target)

        #expect(store.rawSessionState(of: other) == .loading)
        guard case .shown = store.rawSessionState(of: target) else {
            Issue.record("čekal se přepis té session, na kterou se ptáme")
            return
        }
    }

    // MARK: - Cesta

    /// Doslovný JSON se v okně neukazuje: soubor je lokální, takže na to stačí cesta a Finder.
    @Test("Cesta k transcriptu se odvodí ze stromu a session")
    func thePathComesFromTheWorktreeAndSession() {
        let store = store(FakeTranscriptReader([:]))

        let path = store.rawSessionPath(of: target).path(percentEncoded: false)

        #expect(path.hasSuffix("/abc-123.jsonl"))
        #expect(path.contains(".claude/projects/"))
    }
}
