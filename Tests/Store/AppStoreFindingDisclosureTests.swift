import Foundation
import Testing

@testable import PRism

/// Rozbalení bublin nálezů drží store, ne bublina (#185) — a proto se testuje na něm:
/// co je výchozí, co udělá překliknutí, co skok a co se uklidí, když PR ze seznamu vypadne.
@Suite("AppStore — rozbalení nálezů")
@MainActor
struct AppStoreFindingDisclosureTests {
    private let pr = PRIdentifier("cli/cli#1")!
    private let repo = RepoID(owner: "cli", name: "cli")

    private var configuration: Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = [Source(name: "Moje", query: "review-requested:@me is:open")]
        return configuration
    }

    private func summary(_ id: PRIdentifier? = nil) -> PullRequestSummary {
        let id = id ?? pr
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: "autor",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func store(
        _ gateway: FakeGitHubGateway = FakeGitHubGateway(always: .success([])),
        configuration: Configuration? = nil
    ) -> AppStore {
        AppStore(
            gateway: gateway,
            configuration: configuration ?? self.configuration,
            time: FakeTimeSource()
        )
    }

    private func group(_ findings: [Finding], dismissed: [Finding] = []) -> FindingGroup {
        FindingGroup(
            file: "Cart.swift",
            line: 13,
            findings: findings + dismissed,
            dismissals: makeDismissals(dismissed)
        )
    }

    private func blocking() -> Finding {
        makeFinding(file: "Cart.swift", line: 13, category: "correctness", verdict: .confirmed)
    }

    private func quiet() -> Finding {
        makeFinding(file: "Cart.swift", line: 13, category: "style", verdict: .confirmed)
    }

    @Test("Blokující je rozbalený, ostatní sbalené")
    func pinsBlockingFindings() {
        let store = store()

        #expect(store.findingDisclosure(of: group([blocking()]), in: pr) == .expanded)
        #expect(store.findingDisclosure(of: group([quiet()]), in: pr) == .collapsed)
    }

    /// Blokující sada je per repo, takže se musí brát z **konfigurace toho repa** — s konstantou
    /// by okno přišpendlilo nález, který v tomhle repu neblokuje.
    @Test("Sada blokujících kategorií se bere z repa")
    func readsTheCategoriesOfTheRepository() {
        var configuration = configuration
        configuration.repositories[repo] = RepositoryConfig(blockingCategories: ["style"])
        let store = store(configuration: configuration)

        #expect(store.findingDisclosure(of: group([quiet()]), in: pr) == .expanded)
        #expect(store.findingDisclosure(of: group([blocking()]), in: pr) == .collapsed)
    }

    @Test("Překliknutí drží odchylku od výchozího stavu")
    func keepsTheDeviation() {
        let store = store()
        let quietGroup = group([quiet()])

        store.toggleFinding(quietGroup, in: pr)
        #expect(store.findingDisclosure(of: quietGroup, in: pr) == .expanded)
        // Blokující se týmž klíčem sbalí — je to jedno místo v kódu, tedy jedna bublina.
        #expect(store.findingDisclosure(of: group([blocking()]), in: pr) == .collapsed)

        store.toggleFinding(quietGroup, in: pr)
        #expect(store.findingDisclosure(of: quietGroup, in: pr) == .collapsed)
        // Prázdná množina se maže, ať v mapě nezůstávají klíče bez obsahu.
        #expect(store.toggledFindings[pr] == nil)
    }

    /// Skok z panelu i z lišty musí sbalenou bublinu otevřít, jinak by ukázal značku místo
    /// nálezu, na který se kliklo.
    @Test("Skok sbalenou bublinu rozbalí")
    func revealExpandsACollapsedBubble() {
        let store = store()
        let quietGroup = group([quiet()])

        store.revealFinding(quietGroup, in: pr)

        #expect(store.findingDisclosure(of: quietGroup, in: pr) == .expanded)
    }

    /// A hlavně: **nesmí sbalit** tu, která už rozbalená je. Kdyby `reveal` jen překlikl, skok na
    /// blokující nález by ho zavřel — tedy pravý opak toho, k čemu je.
    @Test("Skok na rozbalenou bublinu ji nesbalí")
    func revealNeverCollapses() {
        let store = store()
        let blockingGroup = group([blocking()])

        store.revealFinding(blockingGroup, in: pr)
        store.revealFinding(blockingGroup, in: pr)

        #expect(store.findingDisclosure(of: blockingGroup, in: pr) == .expanded)
        #expect(store.toggledFindings[pr] == nil)
    }

    @Test("Skok na odmítnutý nález nedělá nic")
    func revealIgnoresDismissedGroups() {
        let store = store()
        let dismissed = group([], dismissed: [blocking()])

        store.revealFinding(dismissed, in: pr)

        #expect(store.findingDisclosure(of: dismissed, in: pr) == .dismissed)
        #expect(store.toggledFindings[pr] == nil)
    }

    /// Bez úklidu by mapa překliknutých rostla donekonečna — tatáž pojistka jako u vláken.
    @Test("Překliknuté nálezy zmizelého PR se uklidí")
    func forgetsTogglesOfVanishedPullRequests() async {
        let other = PRIdentifier("cli/cli#2")!
        let gateway = FakeGitHubGateway([
            .success([summary(), summary(other)]),
            .success([summary(other)]),
        ])
        let store = store(gateway)

        await store.refresh()
        store.toggleFinding(group([quiet()]), in: pr)
        #expect(store.toggledFindings[pr] == ["Cart.swift|13"])

        await store.refresh()

        #expect(store.toggledFindings[pr] == nil)
    }
}
