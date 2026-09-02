import Foundation
import Testing

@testable import PRism

/// Cache seznamu repozitářů (#532): zápis, čtení, stáří a hlavně to, že se **nedotahuje při
/// každém úhozu**. Poslední jmenované je jediné, co drží celou věc pohromadě — dotažení stojí nad
/// `keboola` 46,8 s.
@MainActor
@Suite("RepositoryCatalog")
struct RepositoryCatalogTests {
    private func listing(_ organization: String, _ names: [String], hitLimit: Bool = false)
        -> OrganizationRepositories
    {
        OrganizationRepositories(
            repositories: names.map {
                OrganizationRepository(
                    repo: RepoID(owner: organization, name: $0),
                    openPullRequests: 1,
                    lastPushedAt: nil
                )
            },
            hitLimit: hitLimit
        )
    }

    private func catalog(
        _ gateway: FakeGitHubGateway,
        _ workspace: TemporaryDirectory,
        time: FakeTimeSource
    ) -> RepositoryCatalog {
        RepositoryCatalog(
            gateway: gateway,
            store: RepositoryCatalogStore(layout: CacheLayout(root: workspace.url)),
            time: time
        )
    }

    private func gateway(_ listings: [String: OrganizationRepositories]) -> FakeGitHubGateway {
        let gateway = FakeGitHubGateway(always: .success([]))
        gateway.organizationRepositories = listings
        return gateway
    }

    // MARK: - Zápis a čtení

    @Test("Dotažený výpis se uloží a přečte se z disku i po restartu")
    func writesAndReadsBack() async throws {
        let workspace = try TemporaryDirectory()
        let time = FakeTimeSource()
        let source = gateway(["cli": listing("cli", ["cli", "go-gh"])])

        await catalog(source, workspace, time: time).refreshStale(organizations: ["cli"])

        // Druhá instance = jiné okno nastavení, tedy prázdná paměť a čtení z disku.
        let reopened = catalog(gateway([:]), workspace, time: time)
        await reopened.load(organizations: ["cli"])

        let snapshot = try #require(reopened.snapshots["cli"])
        #expect(snapshot.repositories.map { $0.repo.name } == ["cli", "go-gh"])
        #expect(snapshot.fetchedAt == time.now)
    }

    @Test("Sražený výpis si tu značku podrží i přes disk")
    func keepsTheTruncationFlagOnDisk() async throws {
        let workspace = try TemporaryDirectory()
        let time = FakeTimeSource()
        let source = gateway(["keboola": listing("keboola", ["a", "b"], hitLimit: true)])

        await catalog(source, workspace, time: time).refreshStale(organizations: ["keboola"])
        let reopened = catalog(gateway([:]), workspace, time: time)
        await reopened.load(organizations: ["keboola"])

        #expect(reopened.snapshots["keboola"]?.hitLimit == true)
    }

    // MARK: - Stáří

    @Test("Čerstvý výpis se podruhé netahá")
    func doesNotRefetchAFreshSnapshot() async throws {
        let workspace = try TemporaryDirectory()
        let time = FakeTimeSource()
        let source = gateway(["cli": listing("cli", ["cli"])])
        let catalog = catalog(source, workspace, time: time)

        await catalog.refreshStale(organizations: ["cli"])
        time.advance(by: 3600)
        await catalog.refreshStale(organizations: ["cli"])

        #expect(source.repositoryRequests == ["cli"])
    }

    @Test("Po dni se výpis dotáhne znovu")
    func refetchesAfterADay() async throws {
        let workspace = try TemporaryDirectory()
        let time = FakeTimeSource()
        let source = gateway(["cli": listing("cli", ["cli"])])
        let catalog = catalog(source, workspace, time: time)

        await catalog.refreshStale(organizations: ["cli"])
        time.advance(by: 25 * 3600)
        await catalog.refreshStale(organizations: ["cli"])

        #expect(source.repositoryRequests == ["cli", "cli"])
    }

    /// Tlačítko `Obnovit` se stáří neptá — jinak by nad čerstvým katalogem nedělalo nic a vypadalo
    /// by jako rozbité.
    @Test("Obnovit dotáhne i čerstvý výpis")
    func theButtonIgnoresFreshness() async throws {
        let workspace = try TemporaryDirectory()
        let time = FakeTimeSource()
        let source = gateway(["cli": listing("cli", ["cli"])])
        let catalog = catalog(source, workspace, time: time)

        await catalog.refreshStale(organizations: ["cli"])
        await catalog.refresh(organizations: ["cli"])

        #expect(source.repositoryRequests == ["cli", "cli"])
    }

    // MARK: - Nedotahuje se při každém úhozu

    /// **Nejcennější test tady**: nic v katalogu nesmí viset na změně textu v poli. Psaní
    /// `keboola` po písmenech je sedm hodnot; kdyby se na každou z nich sáhlo na GitHub, byla by
    /// z jednoho dopsaného řádku sedmkrát tři čtvrtě minuty práce a sedm podprocesů `gh`.
    ///
    /// Test to tvrdí tím, že prochází mezistavy tak, jak vznikají při psaní, a **nevolá nic** —
    /// katalog se ptá jedině tehdy, když si o to někdo řekne (`refreshStale`, `refresh`).
    @Test("Psaní v poli nedotahuje nic")
    func typingFetchesNothing() async throws {
        let workspace = try TemporaryDirectory()
        let source = gateway(["keboola": listing("keboola", ["vault"])])
        let catalog = catalog(source, workspace, time: FakeTimeSource())

        // Co dělá formulář při psaní: mění konfiguraci a překresluje sekci.
        for prefix in ["k", "ke", "keb", "kebo", "kebool", "keboola"] {
            _ = Policy.repositoryCatalogSummary(
                Policy.repositoryCatalogStatus(
                    organizations: Policy.searchOrganizations([prefix]),
                    snapshots: catalog.snapshots,
                    refreshing: catalog.refreshing
                ),
                now: Date()
            )
        }

        #expect(source.repositoryRequests.isEmpty)
    }

    /// Druhý klik uprostřed dotažení nesmí pustit týž dotaz podruhé.
    @Test("Organizace, která se právě tahá, se nezařadí podruhé")
    func doesNotFetchTheSameOrganizationTwiceAtOnce() async throws {
        let workspace = try TemporaryDirectory()
        let source = gateway(["cli": listing("cli", ["cli"])])
        let catalog = catalog(source, workspace, time: FakeTimeSource())

        await catalog.refresh(organizations: ["cli", "cli", "@cli"])

        #expect(source.repositoryRequests == ["cli"])
        #expect(catalog.refreshing.isEmpty)
    }

    // MARK: - Chyby

    /// Organizace, na kterou účet nevidí, a organizace bez repozitářů vypadají v okně jinak
    /// stejně — proto věta, ne prázdný seznam.
    @Test("Nedostupná organizace dostane větu, ne prázdno")
    func reportsAnUnreachableOrganization() async throws {
        let workspace = try TemporaryDirectory()
        let source = gateway([:])
        source.organizationFailures["tajna"] = GitHubError.notFound("tajna neexistuje")
        let catalog = catalog(source, workspace, time: FakeTimeSource())

        await catalog.refresh(organizations: ["tajna"])

        #expect(catalog.failure(for: "tajna")?.contains("tajna neexistuje") == true)
        #expect(catalog.snapshots["tajna"] == nil)
    }

    /// Starý seznam je pořád lepší než žádný a věta u řádku říká, že je starý — kdežto prázdno
    /// by vypadalo jako organizace bez repozitářů.
    @Test("Selhané obnovení nezahodí, co už v cache je")
    func keepsThePreviousSnapshotOnFailure() async throws {
        let workspace = try TemporaryDirectory()
        let source = gateway(["cli": listing("cli", ["cli", "go-gh"])])
        let catalog = catalog(source, workspace, time: FakeTimeSource())

        await catalog.refresh(organizations: ["cli"])
        source.organizationFailures["cli"] = GitHubError.network("bez sítě")
        await catalog.refresh(organizations: ["cli"])

        #expect(catalog.snapshots["cli"]?.repositories.count == 2)
        #expect(catalog.failure(for: "cli")?.contains("bez sítě") == true)
    }

    /// Jedna nedostupná organizace nesmí vzít ostatní — je to tatáž úvaha jako u částečné odpovědi
    /// na hlavy PR (#420).
    @Test("Jedna nedostupná organizace nezastaví ty ostatní")
    func oneFailureDoesNotStopTheRest() async throws {
        let workspace = try TemporaryDirectory()
        let source = gateway(["cli": listing("cli", ["cli"])])
        source.organizationFailures["tajna"] = GitHubError.notFound("nevidím tam")
        let catalog = catalog(source, workspace, time: FakeTimeSource())

        await catalog.refresh(organizations: ["tajna", "cli"])

        #expect(catalog.failure(for: "tajna") != nil)
        #expect(catalog.snapshots["cli"]?.repositories.count == 1)
    }

    // MARK: - Úklid

    /// Do `catalogs/` eviction nechodí, takže by tam po smazané organizaci ležela stovka
    /// kilobajtů navždycky.
    @Test("Organizace smazaná z nastavení ztratí soubor v cache")
    func discardsFilesOfRemovedOrganizations() async throws {
        let workspace = try TemporaryDirectory()
        let layout = CacheLayout(root: workspace.url)
        let source = gateway([
            "cli": listing("cli", ["cli"]),
            "keboola": listing("keboola", ["vault"]),
        ])
        let catalog = catalog(source, workspace, time: FakeTimeSource())

        await catalog.refresh(organizations: ["cli", "keboola"])
        #expect(FileManager.default.fileExists(atPath: layout.catalogFile(for: "keboola").path))

        await catalog.load(organizations: ["cli"])

        #expect(FileManager.default.fileExists(atPath: layout.catalogFile(for: "cli").path))
        #expect(!FileManager.default.fileExists(atPath: layout.catalogFile(for: "keboola").path))
    }

    /// Prázdný seznam znamená buď „žádnou organizaci nemám“, nebo „konfigurace se ještě
    /// nenačetla“ — a smazat cache na tom druhém by stálo desítky sekund na organizaci.
    @Test("Prázdný seznam cache nesmaže")
    func doesNotWipeTheCacheOnAnEmptyList() async throws {
        let workspace = try TemporaryDirectory()
        let layout = CacheLayout(root: workspace.url)
        let source = gateway(["cli": listing("cli", ["cli"])])
        let catalog = catalog(source, workspace, time: FakeTimeSource())
        await catalog.refresh(organizations: ["cli"])

        await catalog.load(organizations: [])

        #expect(FileManager.default.fileExists(atPath: layout.catalogFile(for: "cli").path))
    }

    /// Nečitelný soubor se bere jako nedotažená organizace: dotáhne se znovu a součet ji
    /// nezapočítá. Položit kvůli němu celé čtení by schovalo i to, co je v pořádku.
    @Test("Rozbitý soubor v cache nepoloží zbytek katalogu")
    func survivesABrokenFile() async throws {
        let workspace = try TemporaryDirectory()
        let layout = CacheLayout(root: workspace.url)
        let source = gateway(["cli": listing("cli", ["cli"])])
        await catalog(source, workspace, time: FakeTimeSource()).refresh(organizations: ["cli"])
        try FileManager.default.createDirectory(at: layout.catalogs, withIntermediateDirectories: true)
        try "{ tohle není snímek".write(
            to: layout.catalogFile(for: "keboola"),
            atomically: true,
            encoding: .utf8
        )

        let reopened = catalog(gateway([:]), workspace, time: FakeTimeSource())
        await reopened.load(organizations: ["cli", "keboola"])

        #expect(reopened.snapshots["cli"] != nil)
        #expect(reopened.snapshots["keboola"] == nil)
    }
}
