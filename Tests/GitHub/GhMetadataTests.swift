import Foundation
import Testing

@testable import PRism

/// Rozbor `gh pr view --json labels,reviewRequests,latestReviews` (#392).
///
/// **Fixtures jsou skutečné výstupy z veřejných repozitářů**, ne vymyšlené: `cli/cli#14119` (tři
/// labely, jeden vyžádaný reviewer, jedno schválení) a `cli/cli#14136` (bez labelů, review od bota
/// bez verdiktu a jedno `CHANGES_REQUESTED`). Dvojice je schválně — první ukazuje sloučení
/// vyžádaných s odpovědmi, druhá to, že review **bez verdiktu** do sekce nepatří.
@Suite("Labely a reviewery z gh")
struct GhMetadataTests {
    @Test("Labely přijdou i s barvou z repozitáře")
    func decodesLabelsWithColour() throws {
        let metadata = try Self.decoded("gh/pr-metadata-labels.json")

        #expect(metadata.labels.map(\.name) == ["dependencies", "go", "ready-for-review"])
        // Barva je **hex bez `#`**, jak ji dává GitHub — a je to hodnota z repozitáře, ne token
        // palety, takže se z ní nic nepřepočítává.
        #expect(metadata.labels.map(\.color) == ["0366d6", "16e2e2", "39d965"])
    }

    /// Sloučení dvou polí do jednoho seznamu tří hodnot: kdo schválil, kdo chce změny, na koho se
    /// čeká.
    @Test("Schválení a vyžádané review se slijí do jednoho seznamu")
    func mergesVerdictsWithPendingRequests() throws {
        let metadata = try Self.decoded("gh/pr-metadata-labels.json")

        #expect(metadata.reviewers == [
            RequestedReviewer(login: "babakks", answer: .approved),
            RequestedReviewer(login: "sergiou87", answer: .waiting),
        ])
    }

    /// **Review bez verdiktu se do sekce nedostane.** Ve fixture je `COMMENTED` od
    /// `copilot-pull-request-reviewer`, tedy od bota, kterého nikdo nevyžádal — nakreslit ho jako
    /// `čeká` by tvrdilo, že se na něj čeká.
    @Test("Komentář bez verdiktu do seznamu reviewerů nepatří")
    func dropsReviewsWithoutAVerdict() throws {
        let metadata = try Self.decoded("gh/pr-metadata-changes-requested.json")

        #expect(metadata.reviewers == [
            RequestedReviewer(login: "babakks", answer: .changesRequested),
        ])
        #expect(!metadata.reviewers.contains { $0.login.contains("copilot") })
    }

    /// Prázdné pole labelů je **platná odpověď**, ne porucha — a musí se poznat od nenačteného
    /// stavu, o čemž rozhoduje `MetadataState`.
    @Test("PR bez labelů dá prázdný snímek, ne chybu")
    func emptyLabelsAreValid() throws {
        let metadata = try Self.decoded("gh/pr-metadata-changes-requested.json")

        #expect(metadata.labels.isEmpty)
        #expect(!metadata.reviewers.isEmpty, "reviewery tam jsou, takže prázdné jsou jen labely")
    }

    /// Labely repozitáře mají **tentýž tvar** jako labely PR, takže se dekódují týmž typem — nabídka
    /// a chip na PR se tím nemůžou rozejít v tom, co je jméno a co barva.
    @Test("Labely repozitáře se dekódují týmž typem")
    func decodesRepositoryLabels() throws {
        let labels = try GhOutput.decoder
            .decode([GhLabel].self, from: try Fixture.data("gh/repo-labels.json"))
            .map(\.label)

        #expect(labels.count > 10)
        #expect(labels.contains { $0.name == "bug" })
        #expect(labels.allSatisfy { !$0.name.isEmpty })
        // Šestimístný hex u každého — z toho se kreslí puntík.
        #expect(labels.allSatisfy { $0.color.count == 6 })
    }

    @Test("Assignable uživatelé se čtou z GraphQL odpovědi")
    func decodesAssignableUsers() throws {
        let logins = try GhOutput.decoder
            .decode(GhAssignableUsersResponse.self, from: try Fixture.data("gh/assignable-users.json"))
            .logins()

        #expect(logins == ["ajbeattie", "audreee", "babakks", "BagToad", "bdehamer"])
    }

    /// **Tým se zahazuje**, protože se z okna vyžádat nedá (nabídka je `assignableUsers`, tedy
    /// lidé) a login nemá. Řádek, se kterým se nedá nic udělat, do sekce nepatří.
    ///
    /// Inline JSON, ne fixture: vyžádání review od týmu se ve veřejných repozitářích nesehnalo
    /// a tvar je z dokumentace `gh` (`__typename: Team`, `slug` místo `login`).
    @Test("Vyžádané review od týmu se do seznamu nedostane")
    func dropsTeamRequests() throws {
        let json = """
        {
          "labels": [],
          "reviewRequests": [
            {"__typename": "Team", "name": "Platform", "slug": "platform"},
            {"__typename": "User", "login": "odinuv"}
          ],
          "latestReviews": []
        }
        """
        let metadata = try GhOutput.decoder
            .decode(GhPullRequestMetadata.self, from: Data(json.utf8))
            .metadata()

        #expect(metadata.reviewers == [RequestedReviewer(login: "odinuv", answer: .waiting)])
    }

    /// Neznámý stav review **nepokládá celý snímek** — stejné pravidlo jako u `SubmittedReview`.
    /// Do seznamu se ale nedostane: verdikt, kterému nerozumíme, není verdikt.
    @Test("Neznámý stav review snímek nepoloží")
    func survivesUnknownReviewState() throws {
        let json = """
        {
          "labels": [{"name": "bug", "color": "d73a4a"}],
          "reviewRequests": [],
          "latestReviews": [{"author": {"login": "odinuv"}, "state": "SOMETHING_NEW"}]
        }
        """
        let metadata = try GhOutput.decoder
            .decode(GhPullRequestMetadata.self, from: Data(json.utf8))
            .metadata()

        #expect(metadata.labels.map(\.name) == ["bug"])
        #expect(metadata.reviewers.isEmpty)
    }

    /// Chybějící barva **nepoloží sekci** — puntík se pak nakreslí neutrální. Inline JSON, protože
    /// GitHub barvu u labelu vždycky dává; jde o odolnost dekódování, ne o skutečný stav.
    @Test("Label bez barvy se dekóduje s prázdným hexem")
    func survivesMissingColour() throws {
        let json = """
        {"labels": [{"name": "bug"}], "reviewRequests": [], "latestReviews": []}
        """
        let metadata = try GhOutput.decoder
            .decode(GhPullRequestMetadata.self, from: Data(json.utf8))
            .metadata()

        #expect(metadata.labels == [PullRequestLabel(name: "bug", color: "")])
    }

    private static func decoded(_ fixture: String) throws -> PullRequestMetadata {
        try GhOutput.decoder
            .decode(GhPullRequestMetadata.self, from: try Fixture.data(fixture))
            .metadata()
    }
}
