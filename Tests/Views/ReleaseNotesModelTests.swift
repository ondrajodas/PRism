import Foundation
import Testing

@testable import PRism

@MainActor
@Suite("Novinky")
struct ReleaseNotesModelTests {
    private func release(_ tag: String, at day: Int) -> Release {
        Release(
            tag: tag,
            name: "\(tag) — něco",
            publishedAt: Date(timeIntervalSince1970: Double(day) * 86_400),
            body: "notes",
            url: URL(string: "https://github.com/ondrajodas/PRism/releases/tag/\(tag)")!
        )
    }

    private var history: [Release] { [release("v1.1.0", at: 2), release("v1.0.0", at: 1)] }

    /// Předvolby v paměti, ne skutečné `UserDefaults`: značka naposledy viděného vydání se
    /// nesmí míchat mezi testy ani sahat do předvoleb aplikace. Vlastní suite to neřeší —
    /// nechává po sobě soubor v `~/Library/Preferences`, viz `PreferenceStoring`.
    private func withPreferences(_ body: (InMemoryPreferences) async throws -> Void) async rethrows {
        try await body(InMemoryPreferences())
    }

    private func model(
        _ preferences: InMemoryPreferences,
        _ releases: [Result<[Release], any Error>]
    ) -> (ReleaseNotesModel, FakeGitHubGateway) {
        let gateway = FakeGitHubGateway(always: .success([]), releases: releases)
        return (ReleaseNotesModel(gateway: gateway, preferences: preferences), gateway)
    }

    // MARK: - Načtení

    @Test("Načtená historie je seřazená a vybere se nejnovější")
    func loadsSortedAndSelectsNewest() async throws {
        try await withPreferences { preferences in
            let (model, _) = model(preferences, [.success(history)])

            await model.load()

            #expect(model.releases.map(\.tag) == ["v1.1.0", "v1.0.0"])
            #expect(model.selection == "v1.1.0")
        }
    }

    /// Zadání #127: „výsledek v paměti do konce běhu“ — okno se otevírá opakovaně a každé
    /// otevření by jinak stálo podproces.
    @Test("Historie se tahá jednou za běh, ne při každém otevření okna")
    func loadsOnlyOnce() async throws {
        try await withPreferences { preferences in
            let (model, gateway) = model(preferences, [.success(history)])

            await model.load()
            await model.load()

            #expect(gateway.releaseRequests == 1)
        }
    }

    // MARK: - Selhání

    @Test("Bez sítě je v okně důvod, ne prázdný seznam")
    func failureIsVisible() async throws {
        try await withPreferences { preferences in
            let (model, _) = model(preferences, [.failure(GitHubError.network("nic tam není"))])

            await model.load()

            guard case .failed(let reason) = model.state else {
                Issue.record("Očekáván stav .failed, přišel \(model.state)")
                return
            }
            #expect(reason.contains("nic tam není"))
            #expect(model.releases.isEmpty)
        }
    }

    /// Kdyby se značka posunula po selhání, vydání, o kterých aplikace neví, by se už nikdy
    /// neohlásila — tatáž past jako u snímku ohlášených PR (#85).
    @Test("Po selhání se značka neposune")
    func failureDoesNotMoveTheMark() async throws {
        try await withPreferences { preferences in
            let (model, _) = model(preferences, [.failure(GitHubError.timedOut)])

            #expect(await model.showsNewReleaseAfterStart() == false)
            #expect(model.lastSeenTag == nil)
        }
    }

    @Test("Zkusit znovu načte i po selhání")
    func retryLoads() async throws {
        try await withPreferences { preferences in
            let (model, _) = model(preferences, [.failure(GitHubError.timedOut), .success(history)])

            await model.load()
            await model.reload()

            #expect(model.releases.map(\.tag) == ["v1.1.0", "v1.0.0"])
        }
    }

    // MARK: - Značka a otevření po aktualizaci

    /// Bez tohohle pravidla vypadá po prvním startu všechno jako nové a okno zařve celou
    /// historií — proto se značka jen založí a nic se neotevře.
    @Test("První spuštění mlčí a jen si značku založí")
    func firstRunIsSilent() async throws {
        try await withPreferences { preferences in
            let (model, _) = model(preferences, [.success(history)])

            #expect(await model.showsNewReleaseAfterStart() == false)
            #expect(model.unseen.isEmpty)
            #expect(model.lastSeenTag == "v1.1.0")
        }
    }

    @Test("Nové vydání proti značce okno otevře a označí")
    func opensAfterUpdate() async throws {
        try await withPreferences { preferences in
            let (first, _) = model(preferences, [.success(history)])
            _ = await first.showsNewReleaseAfterStart()

            let released = [release("v1.1.1", at: 3)] + history
            let (second, _) = model(preferences, [.success(released)])

            #expect(await second.showsNewReleaseAfterStart())
            #expect(second.unseen == ["v1.1.1"])
            #expect(second.selection == "v1.1.1")
            // Značka se posune až otevřením okna, ne rozhodnutím ho otevřít — viz níž.
            #expect(second.lastSeenTag == "v1.1.0")
        }
    }

    /// **Nejdůležitější test tohohle chování.** Kdo si zapíše „ukázal jsem“ dřív, než se to
    /// povedlo, tu hlášku už nikdy nepošle — tatáž past jako u snímku ohlášených PR (#85).
    /// Stalo se to v provozu hned u prvního releasu, který se měl sám ohlásit: okno se
    /// neotevřelo, ale značka se posunula, takže se to vydání nedalo ohlásit už nikdy.
    @Test("Značka se posune až tím, že se okno opravdu ukáže")
    func marksOnlyWhenTheWindowAppears() async throws {
        try await withPreferences { preferences in
            let (first, _) = model(preferences, [.success(history)])
            _ = await first.showsNewReleaseAfterStart()

            let (model, _) = model(preferences, [.success([release("v1.1.1", at: 3)] + history)])
            #expect(await model.showsNewReleaseAfterStart())
            #expect(model.lastSeenTag == "v1.1.0")

            // Tohle dělá `ReleaseNotesView.task`, až se okno ukáže.
            model.markAsSeen()
            #expect(model.lastSeenTag == "v1.1.1")
        }
    }

    /// Když se okno neotevře, značka zůstane — a příští spuštění to zkusí znovu. Bez toho
    /// je vydání ohlášené „na papíře“ a nikdy se neukáže.
    @Test("Neotevřené okno vydání neztratí, příští spuštění ho nabídne znovu")
    func retriesWhenTheWindowNeverAppeared() async throws {
        try await withPreferences { preferences in
            let (first, _) = model(preferences, [.success(history)])
            _ = await first.showsNewReleaseAfterStart()

            let released = [release("v1.1.1", at: 3)] + history
            let (failedToShow, _) = model(preferences, [.success(released)])
            #expect(await failedToShow.showsNewReleaseAfterStart())

            // Okno se neukázalo, takže `markAsSeen()` nikdo nezavolal — a další start to
            // nabídne znovu.
            let (nextStart, _) = model(preferences, [.success(released)])
            #expect(await nextStart.showsNewReleaseAfterStart())
            #expect(nextStart.unseen == ["v1.1.1"])
        }
    }

    @Test("Při dalším spuštění beze změny se okno neotevře")
    func doesNotOpenOnTheNextRun() async throws {
        try await withPreferences { preferences in
            let (first, _) = model(preferences, [.success(history)])
            _ = await first.showsNewReleaseAfterStart()

            let (second, _) = model(preferences, [.success([release("v1.1.1", at: 3)] + history)])
            #expect(await second.showsNewReleaseAfterStart())
            second.markAsSeen()

            let (third, _) = model(preferences, [.success([release("v1.1.1", at: 3)] + history)])
            #expect(await third.showsNewReleaseAfterStart() == false)
        }
    }

    /// Hlavní okno jde zavřít a otevřít znovu, čímž se kontrola pustí podruhé — a `unseen` se
    /// v rámci běhu nemění, takže bez pojistky by okno vyskočilo pokaždé. „Jednou“ je zadání.
    @Test("V jednom běhu se okno nabídne jen jednou")
    func offersOnlyOncePerRun() async throws {
        try await withPreferences { preferences in
            let (first, _) = model(preferences, [.success(history)])
            _ = await first.showsNewReleaseAfterStart()

            let (model, _) = model(preferences, [.success([release("v1.1.1", at: 3)] + history)])

            #expect(await model.showsNewReleaseAfterStart())
            #expect(await model.showsNewReleaseAfterStart() == false)
            // Odznaky přitom zůstávají — okno je pořád otevřené a má na nich co ukazovat.
            #expect(model.unseen == ["v1.1.1"])
        }
    }

    /// Nález Copilota na #142: pojistka „jednou za běh“ nesmí značku posunout ani ve chvíli,
    /// kdy se okno v tomhle běhu už jednou nabídlo. Hlavní okno jde zavřít a otevřít, takže
    /// druhý průchod by vydání odbyl, aniž by ho kdo viděl — tedy #141 o větev vedle.
    @Test("Druhé nabídnutí v témž běhu značku neposune")
    func secondOfferKeepsTheMark() async throws {
        try await withPreferences { preferences in
            let (first, _) = model(preferences, [.success(history)])
            _ = await first.showsNewReleaseAfterStart()

            let released = [release("v1.1.1", at: 3)] + history
            let (offered, _) = model(preferences, [.success(released)])
            #expect(await offered.showsNewReleaseAfterStart())

            // Okno se neukázalo; hlavní okno se zavřelo a otevřelo, takže kontrola běží znovu.
            #expect(await offered.showsNewReleaseAfterStart() == false)
            #expect(offered.lastSeenTag == "v1.1.0")

            // A příští spuštění to proto nabídne znovu.
            let (nextStart, _) = model(preferences, [.success(released)])
            #expect(await nextStart.showsNewReleaseAfterStart())
        }
    }

    @Test("Selhání pojistku nespotřebuje, takže další pokus okno otevřít může")
    func failureDoesNotConsumeTheOffer() async throws {
        try await withPreferences { preferences in
            let (first, _) = model(preferences, [.success(history)])
            _ = await first.showsNewReleaseAfterStart()

            let released = [release("v1.1.1", at: 3)] + history
            let (model, _) = model(preferences, [.failure(GitHubError.timedOut), .success(released)])

            #expect(await model.showsNewReleaseAfterStart() == false)
            #expect(await model.showsNewReleaseAfterStart())
        }
    }

    /// Odznaky mají v otevřeném okně zůstat — jinak by zhasly v tomtéž okamžiku, kdy se okno
    /// objeví, a nebylo by podle čeho poznat, co je nového.
    @Test("Posunutí značky nezhasne odznaky nového")
    func markingKeepsTheBadges() async throws {
        try await withPreferences { preferences in
            let (first, _) = model(preferences, [.success(history)])
            _ = await first.showsNewReleaseAfterStart()

            let (second, _) = model(preferences, [.success([release("v1.1.1", at: 3)] + history)])
            await second.load()
            second.markAsSeen()

            #expect(second.unseen == ["v1.1.1"])
            #expect(second.lastSeenTag == "v1.1.1")
        }
    }

    @Test("Prázdná historie značku nezaloží a nic neotevře")
    func emptyHistoryMarksNothing() async throws {
        try await withPreferences { preferences in
            let (model, _) = model(preferences, [.success([])])

            #expect(await model.showsNewReleaseAfterStart() == false)
            #expect(model.lastSeenTag == nil)
        }
    }
}
