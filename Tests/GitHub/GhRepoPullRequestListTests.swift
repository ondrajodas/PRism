import Foundation
import Testing

@testable import PRism

/// Otevřené pull requesty repa (#533) — pětadvacátá čtecí metoda gateway a základ druhé úrovně
/// palety ⌘K.
///
/// Nejcennější tvrzení je to poslední: **`gh pr list` neřadí podle poslední změny**. Kdyby se na
/// to spolehlo, nadpis skupiny by tvrdil `řazeno podle poslední změny` nad seznamem řazeným podle
/// čísla — a fixture je skutečný výstup, ve kterém se to pozná.
@Suite("GhGateway – otevřené PR repozitáře")
struct GhRepoPullRequestListTests {
    private let gh = URL(filePath: KnownPath.gh)
    private let cli = RepoID(owner: "cli", name: "cli")

    private func gateway(_ runner: ProcessRunning, limit: Int = 100) -> GhGateway {
        GhGateway(gh: gh, runner: runner, pullRequestLimit: limit)
    }

    @Test("Ptá se jen na otevřené a jen na pole, ze kterých se skládá řádek")
    func asksForOpenPullRequestsOnly() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "[]")

        _ = try await gateway(runner).pullRequests(in: cli)

        #expect(runner.invocations == [
            .init(executable: gh, arguments: [
                "pr", "list",
                "--repo", "cli/cli",
                "--state", "open",
                "--limit", "100",
                "--json", "number,title,author,url,updatedAt,state,isDraft",
            ]),
        ])
    }

    /// Změřeno 1,1 s nad padesáti PR v `cli/cli`, tedy o dva řády jinde než 46,8 s u výpisu
    /// organizace — vlastní, delší limit by tady byl mez bez důvodu.
    @Test("Běží ve společném limitu, ne v tom dlouhém od katalogu rep")
    func usesTheSharedTimeout() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "[]")

        _ = try await gateway(runner).pullRequests(in: cli)

        #expect(runner.timeouts == [.seconds(30)])
    }

    @Test("Skutečný výstup gh se přečte na shrnutí")
    func decodesRealOutput() async throws {
        let runner = try FakeProcessRunner(
            exitCode: 0,
            standardOutput: Fixture.text("gh/pr-list-open.json")
        )

        let pullRequests = try await gateway(runner).pullRequests(in: cli)

        #expect(pullRequests.count == 10)
        let first = try #require(pullRequests.first)
        // Repo se bere **z dotazu** — `gh pr list` ho v odpovědi nemá.
        #expect(first.id == PRIdentifier("cli/cli#14320"))
        #expect(first.title == "Add manual acceptance test workflow")
        #expect(first.author == "williammartin")
        #expect(first.url == URL(string: "https://github.com/cli/cli/pull/14320"))
        #expect(first.updatedAt == ISO8601DateFormatter().date(from: "2026-09-02T10:56:48Z"))
        // `isDraft: true` je v odpovědi vedle `state: "OPEN"`, takže se stav skládá z obojího.
        #expect(first.state == .draft)
        let open = try #require(pullRequests.first { $0.id.number == 14_315 })
        #expect(open.state == .open)
    }

    /// **Tohle je to tvrzení, kvůli kterému řadí `Policy`, ne gateway.** Ve skutečném výstupu
    /// stojí `#14282` s razítkem 28. 8. **nad** `#14259` s 31. 8., takže `gh pr list` vrací PR
    /// podle čísla. Kdo by se spolehl na pořadí z odpovědi, dostal by seznam, o kterém nadpis
    /// skupiny lže.
    @Test("gh vrací PR podle čísla, ne podle poslední změny")
    func theResponseIsNotSortedByLastChange() async throws {
        let runner = try FakeProcessRunner(
            exitCode: 0,
            standardOutput: Fixture.text("gh/pr-list-open.json")
        )

        let pullRequests = try await gateway(runner).pullRequests(in: cli)

        #expect(pullRequests.map(\.id.number) == pullRequests.map(\.id.number).sorted(by: >))
        let numbers = pullRequests.map(\.id.number)
        let older = try #require(numbers.firstIndex(of: 14_282))
        let newer = try #require(numbers.firstIndex(of: 14_259))
        // Starší razítko výš než novější — tedy pořadí, které se v `Policy` musí přerovnat.
        #expect(older < newer)
        #expect(pullRequests[older].updatedAt < pullRequests[newer].updatedAt)
    }

    /// Repo bez otevřených PR je **platný stav, ne selhání**: druhá úroveň o tom napíše větu.
    @Test("Repo bez otevřených PR vrátí prázdno, ne chybu")
    func emptyIsAValidAnswer() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "[]")

        let pullRequests = try await gateway(runner).pullRequests(in: cli)

        #expect(pullRequests.isEmpty)
    }

    /// Z tohohle shrnutí se otevírá záložka a klíčují nálezy, takže neplatné číslo musí položit
    /// celý výpis — na rozdíl od katalogu rep, kde se zahazuje jen řádek.
    @Test("Neplatné číslo PR položí celý výpis")
    func aBrokenNumberFailsTheWholeListing() async throws {
        let runner = FakeProcessRunner(
            exitCode: 0,
            standardOutput: #"""
            [{"number":0,"title":"t","author":{"login":"a"},"url":"https://github.com/cli/cli/pull/0",
              "updatedAt":"2026-09-02T10:56:48Z","state":"OPEN","isDraft":false}]
            """#
        )

        await #expect(throws: GitHubError.self) {
            _ = try await gateway(runner).pullRequests(in: cli)
        }
    }

    /// Repo, na které účet nevidí, musí dát **větu z odpovědi**. Text je skutečný výstup
    /// `gh pr list` nad neexistujícím repem.
    @Test("Nedostupné repo vrátí chybu s větou od gh")
    func reportsTheSentenceFromGh() async throws {
        let runner = FakeProcessRunner(
            exitCode: 1,
            standardError: "could not determine base repository: resolve owner: GraphQL: Could not resolve to a Repository with the name 'cli/neexistuje-xyz'."
        )

        do {
            _ = try await gateway(runner).pullRequests(in: cli)
            Issue.record("Nedostupné repo mělo skončit chybou.")
        } catch let error as GitHubError {
            #expect(error.userDescription.contains("Could not resolve"))
        }
    }
}
