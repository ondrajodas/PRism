import Foundation
import Testing

@testable import PRism

@Suite("Vydání z gh")
struct GhReleaseTests {
    private let gh = URL(filePath: KnownPath.gh)

    private func gateway(_ runner: ProcessRunning) -> GhGateway {
        GhGateway(gh: gh, runner: runner)
    }

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    /// Adresa je kontrakt s `gh` stejně jako seznam `--json` polí u ostatních volání:
    /// `per_page` drží celou historii na jedné stránce a repo je konstanta, ne parametr.
    @Test("Ptá se na vlastní repo jedním voláním na celou stránku")
    func asksOwnRepositoryInOneCall() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "[]")

        _ = try await gateway(runner).fetchReleases()

        #expect(runner.invocations == [
            .init(executable: gh, arguments: [
                "api", "repos/ondrajodas/PRism/releases?per_page=100",
            ]),
        ])
    }

    @Test("Skutečný výstup gh se přečte na vydání")
    func decodesRealOutput() async throws {
        let runner = try FakeProcessRunner(exitCode: 0, standardOutput: Fixture.text("gh/releases.json"))

        let releases = try await gateway(runner).fetchReleases()

        #expect(releases.count == 3)
        let newest = try #require(releases.first)
        #expect(newest.tag == "v1.1.23")
        #expect(newest.name == "v1.1.23 — notifikace o re-review")
        #expect(newest.publishedAt == (try date("2026-08-05T19:42:42Z")))
        #expect(newest.url == URL(string: "https://github.com/ondrajodas/PRism/releases/tag/v1.1.23"))
        // Tělo je **rovnou v seznamu**, takže se na jednotlivé vydání nechodí zvlášť.
        #expect(newest.body.contains("re-review"))
        #expect(releases.last?.tag == "v1.1.21")
    }

    @Test("Prázdná historie není chyba")
    func emptyHistoryIsNotAnError() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "[]")

        #expect(try await gateway(runner).fetchReleases().isEmpty)
    }

    @Test("Rozbitý JSON skončí rozlišitelnou chybou, ne pádem")
    func malformedOutputThrows() async {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: "{ tohle není pole")

        await #expect(throws: GitHubError.self) {
            try await gateway(runner).fetchReleases()
        }
    }

    @Test("Selhání gh se zařadí jako u ostatních volání")
    func classifiesFailure() async {
        let runner = FakeProcessRunner(
            exitCode: 1,
            standardError: "error connecting to api.github.com"
        )

        await #expect(throws: GitHubError.network("error connecting to api.github.com")) {
            try await gateway(runner).fetchReleases()
        }
    }

    // MARK: - Mapování

    /// Draft je vidět jen tomu, kdo má do repa zápis — tedy zrovna mně. Kdyby prošel, stal by
    /// se z něj „nejnovější release“ a značka by se posunula na něco, co nikdy nevyšlo.
    @Test("Rozdělané vydání se do seznamu nedostane")
    func skipsDrafts() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: """
            [
              {
                "tag_name": "v9.9.9",
                "name": "rozdělané",
                "published_at": null,
                "body": "zatím nic",
                "html_url": "https://github.com/ondrajodas/PRism/releases/tag/v9.9.9",
                "draft": true
              },
              {
                "tag_name": "v1.0.0",
                "name": "v1.0.0",
                "published_at": "2026-08-01T10:00:00Z",
                "body": "notes",
                "html_url": "https://github.com/ondrajodas/PRism/releases/tag/v1.0.0",
                "draft": false
              }
            ]
            """)

        let releases = try await gateway(runner).fetchReleases()

        #expect(releases.map(\.tag) == ["v1.0.0"])
    }

    @Test("Vydání bez názvu a bez popisu se jmenuje svým tagem")
    func fallsBackToTag() async throws {
        let runner = FakeProcessRunner(exitCode: 0, standardOutput: """
            [
              {
                "tag_name": "v1.0.0",
                "name": null,
                "published_at": "2026-08-01T10:00:00Z",
                "body": null,
                "html_url": "https://github.com/ondrajodas/PRism/releases/tag/v1.0.0",
                "draft": false
              }
            ]
            """)

        let release = try #require(try await gateway(runner).fetchReleases().first)

        #expect(release.name == "v1.0.0")
        #expect(release.body.isEmpty)
    }
}
