import Foundation
import Testing

@testable import PRism

/// Výpis repozitářů organizace (#532) — čtvrtá dvacátá metoda gateway, a jediná, která se
/// nevejde do společného limitu.
@Suite("GhGateway – repozitáře organizace")
struct GhRepositoryListTests {
    private let gh = URL(filePath: KnownPath.gh)

    private func gateway(
        _ runner: ProcessRunning,
        limit: Int = 1000,
        repositoryTimeout: Duration = .seconds(300)
    ) -> GhGateway {
        GhGateway(gh: gh, runner: runner, repositoryLimit: limit, repositoryTimeout: repositoryTimeout)
    }

    @Test("Výpis si řekne o tři pole, ze kterých se skládá řádek nabídky")
    func asksForTheThreeFields() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "[]")

        _ = try await gateway(runner).repositories(in: "keboola")

        #expect(runner.invocations == [
            .init(executable: gh, arguments: [
                "repo", "list", "keboola",
                "--limit", "1000",
                "--json", "nameWithOwner,pullRequests,pushedAt",
            ]),
        ])
    }

    /// Změřeno 46,8 s nad `keboola`, tedy víc než půldruhého násobku společných třiceti sekund.
    /// Bez vlastního limitu by výpis té organizace **vždycky** skončil `timedOut` — a to je
    /// chyba, která se v testu s prázdným výstupem nepozná.
    @Test("Výpis rep běží s vlastním, delším limitem než ostatní volání")
    func usesItsOwnTimeout() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "[]")

        _ = try await gateway(runner, repositoryTimeout: .seconds(300)).repositories(in: "keboola")

        #expect(runner.timeouts == [.seconds(300)])
    }

    @Test("Skutečný výstup gh se přečte na repozitáře")
    func decodesRealOutput() async throws {
        let runner = try FakeProcessRunner(exitCode: 0, standardOutput: Fixture.text("gh/repo-list.json"))

        let listing = try await gateway(runner).repositories(in: "cli")

        #expect(listing.repositories.count == 10)
        let first = try #require(listing.repositories.first)
        #expect(first.repo == RepoID(owner: "cli", name: "go-internal"))
        #expect(first.openPullRequests == 0)
        #expect(first.lastPushedAt == ISO8601DateFormatter().date(from: "2026-09-02T07:42:48Z"))
        let cli = try #require(listing.repositories.first { $0.repo.name == "cli" })
        #expect(cli.openPullRequests == 59)
    }

    /// `keboola` na strop **doopravdy naráží** (změřeno: `--limit 1000` vydalo přesně 1000
    /// položek), takže se z počtu musí poznat, že výpis není celý — jinak by okno tvrdilo
    /// „tisíc rep“ nad organizací, která jich má víc.
    @Test("Dosažený strop je vidět z odpovědi")
    func reportsHittingTheLimit() async throws {
        let full = "[" + (1...3).map { #"{"nameWithOwner":"org/r\#($0)","pullRequests":{"totalCount":0}}"# }
            .joined(separator: ",") + "]"
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: full)

        let listing = try await gateway(runner, limit: 3).repositories(in: "org")

        #expect(listing.repositories.count == 3)
        #expect(listing.hitLimit)
    }

    @Test("Výpis pod stropem se za sražený nevydává")
    func doesNotClaimTruncationBelowTheLimit() async throws {
        let runner = FakeProcessRunner(
            exitCode: 0,
            standardOutput: #"[{"nameWithOwner":"org/r1","pullRequests":{"totalCount":2}}]"#
        )

        let listing = try await gateway(runner, limit: 3).repositories(in: "org")

        #expect(!listing.hitLimit)
    }

    /// Prázdné repo `pushedAt` nemá. V měřeném výpisu tisíce rep `keboola` nebylo ani jedno,
    /// takže je to inline JSON — a je tu napsané proč.
    @Test("Repo bez pushedAt výpis nepoloží")
    func survivesARepositoryWithoutPushedAt() async throws {
        let runner = FakeProcessRunner(
            exitCode: 0,
            standardOutput: #"[{"nameWithOwner":"org/empty","pullRequests":{"totalCount":0}}]"#
        )

        let listing = try await gateway(runner).repositories(in: "org")

        #expect(listing.repositories.first?.lastPushedAt == nil)
    }

    /// Jedno nepřečtené jméno mezi tisícem nemá vzít organizaci celou — na rozdíl od
    /// vyhledávání PR, kde se z jména klíčují nálezy.
    @Test("Neplatné jméno zahodí položku, ne celý výpis")
    func dropsOnlyTheUnreadableItem() async throws {
        let runner = FakeProcessRunner(
            exitCode: 0,
            standardOutput: #"""
            [{"nameWithOwner":"bez-lomitka","pullRequests":{"totalCount":1}},
             {"nameWithOwner":"org/dobre","pullRequests":{"totalCount":1}}]
            """#
        )

        let listing = try await gateway(runner).repositories(in: "org")

        #expect(listing.repositories.map { $0.repo.description } == ["org/dobre"])
    }

    /// Řádek v nastavení vzniká prázdný a `gh repo list ""` je jistá chyba za jedno volání navíc.
    @Test("Na prázdnou organizaci se gateway neptá")
    func doesNotAskForAnEmptyOrganization() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "[]")

        let listing = try await gateway(runner).repositories(in: "   ")

        #expect(runner.invocations.isEmpty)
        #expect(listing.repositories.isEmpty)
    }

    /// Organizace, kterou `gh` nezná, musí dát **větu z odpovědi**, ne prázdný seznam. Text je
    /// skutečný výstup `gh repo list` na neexistující jméno.
    @Test("Nedostupná organizace vrátí chybu s větou od gh")
    func reportsTheSentenceFromGh() async throws {
        let runner = FakeProcessRunner(
            exitCode: 1,
            standardError: "the owner handle \"neexistuje-xyz\" was not recognized as either a GitHub user or an organization"
        )

        do {
            _ = try await gateway(runner).repositories(in: "neexistuje-xyz")
            Issue.record("Nedostupná organizace měla skončit chybou.")
        } catch let error as GitHubError {
            // Věta se musí dostat až k uživateli — prázdný seznam by vypadal jako organizace
            // bez repozitářů.
            #expect(error.userDescription.contains("was not recognized"))
        }
    }
}
