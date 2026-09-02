import Foundation
import Testing

@testable import PRism

/// Rozhodnutí nad katalogem repozitářů (#532): co je platné jméno organizace, co je starší než
/// den a co se o katalogu smí napsat.
@Suite("Policy – katalog repozitářů")
struct RepositoryCatalogPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_756_800_000)

    private func snapshot(
        _ organization: String,
        repositories: Int,
        fetchedAt: Date,
        hitLimit: Bool = false
    ) -> RepositorySnapshot {
        RepositorySnapshot(
            organization: organization,
            fetchedAt: fetchedAt,
            listing: OrganizationRepositories(
                repositories: (1...max(1, repositories)).prefix(repositories).map {
                    OrganizationRepository(
                        repo: RepoID(owner: organization, name: "r\($0)"),
                        openPullRequests: 0,
                        lastPushedAt: nil
                    )
                },
                hitLimit: hitLimit
            )
        )
    }

    // MARK: - Jméno organizace

    @Test("Obalové mezery a zavináč se srazí")
    func normalizesTypedNames() {
        #expect(Policy.organizationName(from: "  keboola ") == "keboola")
        #expect(Policy.organizationName(from: "@keboola") == "keboola")
        #expect(Policy.organizationName(from: "ondrajodas") == "ondrajodas")
        #expect(Policy.organizationName(from: "go-gh_2.0") == "go-gh_2.0")
    }

    /// Z jména vzniká cesta `catalogs/<org>.json` a na té cestě se maže — takže `..` ani lomítko
    /// projít nesmí.
    @Test("Jméno, ze kterého by šla složit cesta ven z cache, se odmítne")
    func rejectsPathTricks() {
        #expect(Policy.organizationName(from: "..") == nil)
        #expect(Policy.organizationName(from: ".") == nil)
        #expect(Policy.organizationName(from: "../../etc") == nil)
        #expect(Policy.organizationName(from: "keboola/vault") == nil)
        #expect(Policy.organizationName(from: "") == nil)
        #expect(Policy.organizationName(from: "   ") == nil)
        #expect(Policy.organizationName(from: "s mezerou") == nil)
        #expect(Policy.organizationName(from: "---") == nil)
    }

    @Test("Duplicity a rozepsané řádky se do seznamu nedostanou")
    func filtersTheConfiguredList() {
        #expect(Policy.searchOrganizations(["keboola", "", "@keboola", "cli"]) == ["keboola", "cli"])
    }

    /// Pořadí je pořadí ze souboru: je to seznam, který si člověk skládá sám, a přerovnat mu ho
    /// pod rukou znamená, že po každém uložení hledá, kam se řádek poděl.
    @Test("Pořadí zůstává takové, jaké je v konfiguraci")
    func keepsTheConfiguredOrder() {
        #expect(Policy.searchOrganizations(["zzz", "aaa"]) == ["zzz", "aaa"])
    }

    // MARK: - Stáří

    @Test("Dotáhne se, co chybí, a to, co je starší než den")
    func picksWhatNeedsFetching() {
        let fresh = snapshot("cli", repositories: 2, fetchedAt: now.addingTimeInterval(-3600))
        let old = snapshot("keboola", repositories: 3, fetchedAt: now.addingTimeInterval(-25 * 3600))

        let stale = Policy.staleOrganizations(
            ["cli", "keboola", "ondrajodas"],
            snapshots: ["cli": fresh, "keboola": old],
            now: now
        )

        #expect(stale == ["keboola", "ondrajodas"])
    }

    /// Přesně den je hranice, na které se obnovuje — jinak by se výpis obnovoval o tik později
    /// každý den a hranice by se v testu nedala trefit.
    @Test("Přesně den starý snímek se obnoví")
    func refreshesExactlyAtTheBoundary() {
        let snapshot = snapshot("cli", repositories: 1, fetchedAt: now.addingTimeInterval(-24 * 3600))

        #expect(Policy.staleOrganizations(["cli"], snapshots: ["cli": snapshot], now: now) == ["cli"])
    }

    /// Posunuté hodiny nemají spustit tři čtvrtě minuty práce při každém otevření nastavení.
    @Test("Razítko z budoucnosti se bere jako čerstvé")
    func treatsFutureStampsAsFresh() {
        let snapshot = snapshot("cli", repositories: 1, fetchedAt: now.addingTimeInterval(3600))

        #expect(Policy.staleOrganizations(["cli"], snapshots: ["cli": snapshot], now: now).isEmpty)
    }

    // MARK: - Souhrn

    @Test("Bez organizací se nepíše nic")
    func saysNothingWithoutOrganizations() {
        let status = Policy.repositoryCatalogStatus(organizations: [], snapshots: [:], refreshing: [])

        #expect(status == .noOrganizations)
        #expect(Policy.repositoryCatalogSummary(status, now: now) == nil)
    }

    @Test("Nastavená, ale nikdy nedotažená organizace to řekne")
    func saysWhenNothingWasFetchedYet() {
        let status = Policy.repositoryCatalogStatus(
            organizations: ["keboola"],
            snapshots: [:],
            refreshing: []
        )

        #expect(status == .neverFetched)
        #expect(Policy.repositoryCatalogSummary(status, now: now) == "Zatím nenačteno")
    }

    /// Souhrn nad **dvěma** organizacemi musí platit i pro tu starší — s nejnovějším razítkem by
    /// se nad týden starým seznamem psalo, že se obnovil před minutou.
    @Test("Souhrn bere nejstarší razítko, ne nejnovější")
    func summarizesFromTheOldestStamp() throws {
        let older = now.addingTimeInterval(-7200)
        let status = Policy.repositoryCatalogStatus(
            organizations: ["keboola", "cli"],
            snapshots: [
                "keboola": snapshot("keboola", repositories: 4, fetchedAt: older),
                "cli": snapshot("cli", repositories: 2, fetchedAt: now),
            ],
            refreshing: []
        )

        #expect(status == .loaded(repositories: 6, oldest: older, missing: 0, hitLimit: false))
        let summary = try #require(Policy.repositoryCatalogSummary(status, now: now))
        #expect(summary == "6 rep · obnoveno \(older.formatted(date: .omitted, time: .shortened))")
    }

    /// Sražený výpis nesmí tvrdit, kolik jich je — jen kolik jich je vidět.
    @Test("Sražený výpis se přizná")
    func admitsTruncation() throws {
        let status = Policy.repositoryCatalogStatus(
            organizations: ["keboola"],
            snapshots: ["keboola": snapshot("keboola", repositories: 5, fetchedAt: now, hitLimit: true)],
            refreshing: []
        )

        let summary = try #require(Policy.repositoryCatalogSummary(status, now: now))
        #expect(summary.hasPrefix("nejméně 5 rep · "))
    }

    /// Součet, který jednu organizaci mlčky vynechá, tvrdí víc, než co data unesou.
    @Test("Nenačtená organizace se do součtu nezapočítá a je vidět")
    func countsMissingOrganizationsApart() throws {
        let status = Policy.repositoryCatalogStatus(
            organizations: ["keboola", "cli"],
            snapshots: ["keboola": snapshot("keboola", repositories: 3, fetchedAt: now)],
            refreshing: []
        )

        #expect(status == .loaded(repositories: 3, oldest: now, missing: 1, hitLimit: false))
        let summary = try #require(Policy.repositoryCatalogSummary(status, now: now))
        #expect(summary.hasSuffix("· 1 organizace nenačtena"))
    }

    @Test("Během dotahování se ukazuje průběh")
    func showsProgressWhileRefreshing() {
        let one = Policy.repositoryCatalogStatus(
            organizations: ["keboola"],
            snapshots: [:],
            refreshing: ["keboola"]
        )
        #expect(Policy.repositoryCatalogSummary(one, now: now) == "Obnovuje se…")

        let two = Policy.repositoryCatalogStatus(
            organizations: ["keboola", "cli"],
            snapshots: [:],
            refreshing: ["keboola"]
        )
        #expect(Policy.repositoryCatalogSummary(two, now: now) == "Obnovuje se… 1/2")
    }

    /// Snímek z jiného dne s holým časem vypadá jako „před chvílí“ — a to je zrovna u katalogu
    /// s denní obnovou ta informace, na kterou se člověk ptá.
    @Test("Snímek z jiného dne nese i datum")
    func showsTheDateForOlderSnapshots() throws {
        let yesterday = now.addingTimeInterval(-30 * 3600)
        let status = Policy.repositoryCatalogStatus(
            organizations: ["keboola"],
            snapshots: ["keboola": snapshot("keboola", repositories: 1, fetchedAt: yesterday)],
            refreshing: []
        )

        let summary = try #require(Policy.repositoryCatalogSummary(status, now: now))
        #expect(summary.contains(yesterday.formatted(date: .abbreviated, time: .shortened)))
    }

    /// Souhrn je **jediné místo, kde se o katalogu píše** (oprava z renderu) — na řádcích
    /// organizací žádný stav není, takže se nemůže zdvojit.
    @Test("Rozepsaný řádek do souhrnu nespadne")
    func ignoresAHalfTypedRow() {
        let status = Policy.repositoryCatalogStatus(
            organizations: Policy.searchOrganizations(["", "  "]),
            snapshots: [:],
            refreshing: []
        )

        #expect(status == .noOrganizations)
        #expect(Policy.repositoryCatalogSummary(status, now: now) == nil)
    }
}
