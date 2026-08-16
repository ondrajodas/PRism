import Foundation
import Testing

@testable import PRism

/// Zastaralé nálezy jako **jeden zdroj** (#284).
///
/// O témže stavu mluví hlavička nad taby (`StaleHeadView`), dlaždice `Nálezy proti` a od #284
/// i okrový odznak v pruhu „od tvé poslední návštěvy“. Do #284 si každé z nich porovnávalo sha
/// samo — tenhle výčet je to, co drží, aby se rozešly.
@Suite("AppStore — zastaralé nálezy (#284)")
@MainActor
struct AppStoreStaleFindingsTests {
    private let repo = RepoID(owner: "cli", name: "cli")
    private var id: PRIdentifier { PRIdentifier(repo: repo, number: 42) }

    @Test("Rozešlá sha dá rozchod i s počtem nálezů")
    func reportsTheMismatch() async {
        let store = await prepared(findingsHead: "4f2ac9188cd", findings: 2)

        let stale = store.staleFindings(for: id)

        #expect(stale?.head == "9c1de0212ab")
        #expect(stale?.findingsHead == "4f2ac9188cd")
        #expect(stale?.hasFindings == true)
    }

    /// **Odznak `nálezy zastaraly` se nesmí ukázat, když žádné nálezy nejsou.** Čisté review proti
    /// staršímu commitu je běžný stav — a je pořád zastaralé, takže hlavička o něm mluvit má; jen
    /// odznak by nad ním tvrdil něco, co data neunesou.
    @Test("Čisté review dá rozchod bez nálezů")
    func separatesTheCleanRun() async {
        let store = await prepared(findingsHead: "4f2ac9188cd", findings: 0)

        #expect(store.staleFindings(for: id) != nil, "hlavička o rozchodu mluvit má")
        #expect(store.staleFindings(for: id)?.hasFindings == false)
    }

    @Test("Shodná sha není rozchod")
    func staysQuietWhenTheyMatch() async {
        let store = await prepared(findingsHead: "9c1de0212ab", findings: 3)

        #expect(store.staleFindings(for: id) == nil)
    }

    /// PR, na kterém review nikdy neběželo, nemá záznam — takže nemá ani co zastarat. Tohle je ten
    /// stav ze zadání #284, ve kterém se v pruhu neukázalo vůbec nic.
    @Test("Bez záznamu review není co zastarat")
    func staysQuietWithoutARecord() async {
        let store = await prepared(findingsHead: nil, findings: 0)

        #expect(store.staleFindings(for: id) == nil)
    }

    /// Bez načteného detailu neznáme dnešní hlavu, takže se o rozchodu nedá říct nic — a „nevím“
    /// se nesmí kreslit jako „zastaralo“.
    @Test("Bez detailu se rozchod netvrdí")
    func staysQuietWithoutTheDetail() async {
        let store = await prepared(findingsHead: "4f2ac9188cd", findings: 2, loadsDetail: false)

        #expect(store.staleFindings(for: id) == nil)
    }

    // MARK: - Materiál

    private var summary: PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: "titulek",
            author: "odinuv",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    private func prepared(
        findingsHead: String?,
        findings: Int,
        loadsDetail: Bool = true
    ) async -> AppStore {
        let detail = PullRequest(
            id: id,
            title: "titulek",
            author: "odinuv",
            headSha: "9c1de0212ab",
            baseSha: "bbbb2222",
            url: summary.url,
            updatedAt: summary.updatedAt,
            state: .open,
            body: ""
        )
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([summary]), detail: .success(detail)),
            time: FakeTimeSource()
        )
        if loadsDetail { await store.loadDetail(for: summary) }
        if let findingsHead {
            store.reviewRecords[id] = ReviewRecord(
                pullRequest: id,
                headSha: findingsHead,
                runs: [
                    makeStoredRun(
                        findings: (0..<findings).map { makeReported(file: "Cart.swift", line: $0 + 1) },
                        headSha: findingsHead
                    )
                ]
            )
        }
        return store
    }
}
