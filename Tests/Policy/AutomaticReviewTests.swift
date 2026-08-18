import Foundation
import Testing

@testable import PRism

/// Koho automat vybere. Čistá funkce — rozpočet ani spouštění sem nepatří.
@Suite("Policy — automatický režim")
struct AutomaticReviewTests {
    private let cli = RepoID(owner: "cli", name: "cli")

    private func summary(
        _ identifier: String,
        updatedAt: TimeInterval = 100,
        state: PullRequestState = .open,
        author: String = "autor"
    ) -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: state
        )
    }

    private func configuration(automatic: Bool) -> Configuration {
        var configuration = Configuration.standard
        configuration.repositories = [cli: RepositoryConfig(mode: automatic ? .automatic : .manual)]
        return configuration
    }

    private func pick(
        _ summaries: [PullRequestSummary],
        automatic: Bool = true,
        mine: Set<String> = [],
        considered: [PRIdentifier: Date] = [:],
        running: Set<PRIdentifier> = []
    ) -> [PRIdentifier] {
        Policy.automaticallyReviewable(
            in: summaries,
            configuration: configuration(automatic: automatic),
            mine: mine,
            considered: considered,
            running: running
        )
    }

    @Test("Repo v automatickém režimu se vybere")
    func picksAutomaticRepositories() {
        #expect(pick([summary("cli/cli#1")]) == [PRIdentifier("cli/cli#1")])
    }

    /// Neznámé repo nesmí bez dozoru spálit panel session — proto je výchozí `manual`.
    @Test("Manuální repo se nevybere")
    func skipsManualRepositories() {
        #expect(pick([summary("cli/cli#1")], automatic: false).isEmpty)
    }

    /// Stejný stav podruhé znamená, že se od minula nic nezměnilo.
    @Test("Už zvážený PR se stejným updatedAt se nevybere")
    func skipsWhatWasAlreadyConsidered() {
        let considered = [PRIdentifier("cli/cli#1")!: Date(timeIntervalSince1970: 100)]

        #expect(pick([summary("cli/cli#1", updatedAt: 100)], considered: considered).isEmpty)
    }

    @Test("Změněný PR se vybere znovu")
    func picksUpAChange() {
        let considered = [PRIdentifier("cli/cli#1")!: Date(timeIntervalSince1970: 100)]

        #expect(pick([summary("cli/cli#1", updatedAt: 200)], considered: considered).count == 1)
    }

    @Test("PR, nad kterým už něco běží, se nevybere")
    func skipsRunningPullRequests() {
        #expect(pick([summary("cli/cli#1")], running: [PRIdentifier("cli/cli#1")!]).isEmpty)
    }

    /// Autor na draftu ještě pracuje a každý push by stál session. Ruční spuštění zůstává.
    @Test("Draft se sám nereviewuje")
    func skipsDrafts() {
        #expect(pick([summary("cli/cli#1", state: .draft)]).isEmpty)
    }

    /// Vybírá se z posledního tiku, takže zavřený PR vypadne tím, že v seznamu není.
    @Test("Prázdný seznam nevybere nic")
    func picksNothingFromAnEmptyList() {
        #expect(pick([]).isEmpty)
    }

    // MARK: - Vlastní PR (#332)

    /// **Nejcennější test téhle sady.** Automat na vlastním PR znamená útratu bez upozornění —
    /// a protože se vlastní PR mění pod rukama, je to útrata za nálezy proti kódu, který za deset
    /// minut nebude. Repo je přitom v automatickém režimu, takže by to bez pravidla prošlo.
    @Test("Vlastní PR se nevybere ani při globálním automatickém režimu")
    func neverPicksOwnPullRequests() {
        var configuration = Configuration.standard
        // Globální default, ne override per repo: tohle je ta cesta, kterou by vlastní PR prošlo
        // i v repu, o kterém se nikdy nic nenastavovalo.
        configuration.global.mode = .automatic

        let picked = Policy.automaticallyReviewable(
            in: [summary("cli/cli#1", author: "OndraJodas")],
            configuration: configuration,
            mine: ["ondrajodas"],
            considered: [:],
            running: []
        )

        #expect(picked.isEmpty)
    }

    /// Druhá cesta k témuž: repo si o automat řekne samo. Pravidlo je **pravidlo, ne výchozí
    /// hodnota**, takže se nedá přebít ani per repo — přepínač do nastavení se zamítl (viz
    /// `Policy.automaticallyReviewable`).
    @Test("Vlastní PR se nevybere ani když si o automat řekne repo")
    func neverPicksOwnPullRequestsForAnAutomaticRepository() {
        #expect(pick([summary("cli/cli#1", author: "ondrajodas")], mine: ["ondrajodas"]).isEmpty)
    }

    /// Cizí PR v témže seznamu projít **musí** — jinak by test výš platil i tehdy, kdyby se
    /// automat vypnul celý.
    @Test("Cizí PR ve stejném seznamu projde dál")
    func stillPicksTheirPullRequests() {
        let picked = pick(
            [summary("cli/cli#1", author: "ondrajodas"), summary("cli/cli#2", author: "kolega")],
            mine: ["ondrajodas"]
        )

        #expect(picked == [PRIdentifier("cli/cli#2")])
    }

    /// Bez loginu je podle `Policy.ownership` všechno cizí, takže se automat chová jako do #332.
    /// Je to ta bezpečná strana jen na jednu stranu — a proto `mine` nemá výchozí hodnotu.
    @Test("Bez znalosti loginu se nevyřazuje nic")
    func picksEverythingWithoutAViewer() {
        #expect(pick([summary("cli/cli#1", author: "ondrajodas")], mine: []).count == 1)
    }
}
