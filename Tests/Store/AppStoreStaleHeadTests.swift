import Foundation
import Testing

@testable import PRism

/// Zastaralé nálezy poznané **tikem** (#420) — jedním dotazem na celou frontu.
///
/// Cenná polovina jsou tvrzení o tom, co se **nestane**: za tik se neposílá dotaz na každý PR
/// zvlášť, detail se kvůli tomu netahá vůbec, klidný tik se neptá a bez záznamu dění se neptá taky.
/// Všechno to se rozbije potichu — výsledek v okně vypadá stejně, jen se každou minutu platí
/// desetinásobek volání.
@Suite("AppStore — hlavy z tiku (#420)")
@MainActor
struct AppStoreStaleHeadTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    /// Kdy vznikla nová hlava — **dva dny** před tikem, který si toho všiml. Na tom rozdílu stojí
    /// tvrzení o čase události.
    private var pushedAt: Date { start.addingTimeInterval(-2 * 24 * 3600) }

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    private func configuration() -> Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = [Source(name: "Moje", query: "review-requested:@me is:open")]
        configuration.global.ownLogins = ["ondrajodas"]
        return configuration
    }

    private func summary(
        _ text: String,
        author: String = "odinuv",
        updatedAt: Date? = nil
    ) -> PullRequestSummary {
        let id = PRIdentifier(text)!
        return PullRequestSummary(
            id: id,
            title: "chore: modernize dependencies",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: updatedAt ?? start,
            state: .open
        )
    }

    /// Store se **záznamem dění** (bez něj se neptá — je jediný konzument) a s uloženými nálezy
    /// proti `findingsHead`.
    private func store(
        _ gateway: FakeGitHubGateway,
        findings: [PRIdentifier: String],
        activityLog: Bool = true
    ) -> AppStore {
        let store = AppStore(
            gateway: gateway,
            configuration: configuration(),
            time: FakeTimeSource(start: start),
            announced: AnnouncedPullRequests(layout: layout),
            activityLog: activityLog ? ActivityLog(layout: layout) : nil
        )
        for (pr, head) in findings {
            store.reviewRecords[pr] = ReviewRecord(
                pullRequest: pr,
                headSha: head,
                runs: [makeStoredRun(findings: [makeReported(file: "Cart.swift", line: 3)], headSha: head)]
            )
        }
        return store
    }
}

// MARK: - Co se stane

extension AppStoreStaleHeadTests {
    /// Řádek je v dění **po tiku**, bez otevírání PR — a to je celé #420. Do té doby se rozchod
    /// zapsal teprve při `loadDetail`, tedy v okamžiku, kdy už ho hlavička nad taby říká sama.
    @Test("Posunutá hlava dá řádek už z tiku")
    func recordsTheStaleFindingsFromATick() async {
        let pr = PRIdentifier("cli/cli#1")!
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        gateway.heads = [pr: PullRequestHead(sha: "9c1de02", committedAt: pushedAt)]
        let store = store(gateway, findings: [pr: "4f2ac91"])

        await store.refresh()

        #expect(store.activityEvents.map(\.kind) == [.staleFindings])
        #expect(store.activityEvents.first?.pullRequest == pr)
        #expect(store.activityEvents.first?.head == "9c1de02")
        // Detail se kvůli tomu **netahá** — o commitech se proto z tiku nemluví.
        #expect(store.activityEvents.first?.detail == "hlava je teď")
    }

    /// **Řádek říká čas události, ne čas zjištění.** Bez toho by po restartu vypadalo, že nálezy
    /// zastaraly dneska — datum by se posunulo pokaždé, když se aplikace spustí.
    @Test("Řádek nese datum commitu, ne okamžik zjištění")
    func datesTheRowByTheEvent() async {
        let pr = PRIdentifier("cli/cli#1")!
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        gateway.heads = [pr: PullRequestHead(sha: "9c1de02", committedAt: pushedAt)]
        let store = store(gateway, findings: [pr: "4f2ac91"])

        await store.refresh()

        #expect(store.activityEvents.first?.at == pushedAt)
        #expect(store.activityEvents.first?.at != start)
    }

    /// Když datum hlavy nedorazí, datuje se řádek okamžikem zjištění — vymyslet datum zpětně by
    /// znamenalo tvrdit, co v datech není.
    @Test("Bez data hlavy se řádek datuje zjištěním")
    func fallsBackToTheMomentOfNotice() async {
        let pr = PRIdentifier("cli/cli#1")!
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        gateway.heads = [pr: PullRequestHead(sha: "9c1de02", committedAt: nil)]
        let store = store(gateway, findings: [pr: "4f2ac91"])

        await store.refresh()

        #expect(store.activityEvents.first?.at == start)
    }

    /// Identita nese hlavu, takže druhé všimnutí téhož rozchodu řádek **nezdvojí a nepředatuje** —
    /// tohle je ta polovina, kvůli které restart nepřepíše datum na dnešek.
    @Test("Druhý tik řádek nezdvojí ani nepředatuje")
    func keepsTheFirstRow() async {
        let pr = PRIdentifier("cli/cli#1")!
        let gateway = FakeGitHubGateway(always: .success([
            summary("cli/cli#1"),
        ]))
        gateway.heads = [pr: PullRequestHead(sha: "9c1de02", committedAt: pushedAt)]
        let first = store(gateway, findings: [pr: "4f2ac91"])
        await first.refresh()

        // Nový store nad **tímtéž** souborem záznamu, tedy restart aplikace. `updatedAt` je
        // posunuté, takže se **ptá znovu** a dozví se totéž.
        let secondGateway = FakeGitHubGateway(always: .success([
            summary("cli/cli#1", updatedAt: start.addingTimeInterval(60)),
        ]))
        secondGateway.heads = gateway.heads
        let restarted = store(secondGateway, findings: [pr: "4f2ac91"])
        await restarted.loadStoredActivity()
        await restarted.refresh()

        #expect(secondGateway.headRequests.count == 1, "po restartu se zeptá — razítka jsou v paměti")
        #expect(restarted.activityEvents.count == 1)
        #expect(restarted.activityEvents.first?.at == pushedAt)
    }
}

// MARK: - Co se nestane

extension AppStoreStaleHeadTests {
    /// **Jeden dotaz na celou frontu, ne na PR.** Tři PR s nálezy v jednom tiku znamenají jedno
    /// volání se třemi identifikátory — a **nula** dotazů na detail, což je ta N+1 past, kvůli
    /// které se rozchod do #420 tikem nepoznal.
    @Test("Za tik jde jeden dotaz, ne dotaz na každé PR")
    func asksOnceForTheWholeQueue() async {
        let ids = ["cli/cli#1", "vercel/next.js#2", "microsoft/terminal#3"].map { PRIdentifier($0)! }
        let gateway = FakeGitHubGateway(always: .success(ids.map { summary("\($0)") }))
        gateway.heads = Dictionary(
            uniqueKeysWithValues: ids.map { ($0, PullRequestHead(sha: "9c1de02", committedAt: pushedAt)) }
        )
        let store = store(
            gateway,
            findings: Dictionary(uniqueKeysWithValues: ids.map { ($0, "4f2ac91") })
        )

        await store.refresh()

        #expect(gateway.headRequests.count == 1, "jedno volání, ne tři")
        #expect(gateway.headRequests.first?.count == 3)
        #expect(Set(gateway.headRequests.first ?? []) == Set(ids))
        #expect(gateway.detailRequests.isEmpty, "detail se kvůli hlavám netahá")
        #expect(store.activityEvents.count == 3)
    }

    /// **Klidný tik se neptá.** `updatedAt` se nepohnul, takže se hlava nemá čím změnit — a tohle
    /// je celá odpověď na „co to přidá na tik“: na klidný den nula volání.
    @Test("Druhý tik bez změny updatedAt se neptá")
    func staysQuietOnACalmTick() async {
        let pr = PRIdentifier("cli/cli#1")!
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        gateway.heads = [pr: PullRequestHead(sha: "9c1de02", committedAt: pushedAt)]
        let store = store(gateway, findings: [pr: "4f2ac91"])

        await store.refresh()
        await store.refresh()
        await store.refresh()

        #expect(gateway.headRequests.count == 1)
        #expect(store.activityEvents.count == 1)
    }

    /// **Bez záznamu dění se na zastaralé nálezy neptá.** Banner za ně nechodí, takže je záznam
    /// jejich jediný konzument — dotaz kvůli nim by byl volání za nic, každou minutu.
    ///
    /// **Od #513 to ale neznamená, že se nepošle dotaz žádný**: týmž dotazem se tahají větve pro
    /// sérii PR a ty mají konzumenta jiného (frontu). Řádek dění z toho nevznikne, a to je ta
    /// polovina, na které tenhle test stojí.
    @Test("Bez záznamu dění řádek nevznikne")
    func recordsNothingWithoutTheLog() async {
        let pr = PRIdentifier("cli/cli#1")!
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        gateway.heads = [pr: PullRequestHead(sha: "9c1de02", committedAt: pushedAt)]
        let store = store(gateway, findings: [pr: "4f2ac91"], activityLog: false)

        await store.refresh()

        #expect(store.activityEvents.isEmpty)
    }

    /// PR bez uložených nálezů do **téhle** rozhlídky nepatří — není co zastarat —, takže z něj
    /// nevznikne řádek. Od #513 se na něj dotaz pošle kvůli větvím, ale to je druhá rozhlídka
    /// v témže dokumentu (viz `SeriesRefsProbeTests`).
    @Test("PR bez nálezů řádek nedá")
    func recordsNothingWithoutFindings() async {
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        let store = store(gateway, findings: [:])

        await store.refresh()

        #expect(store.activityEvents.isEmpty)
    }

    /// **Vlastní PR se neptá a řádek o něm nevznikne** (#332). Z dění se nesmí stát obchvat
    /// pravidla o tom, o čem se nehlásí.
    @Test("Vlastní PR se neptá")
    func asksNothingAboutOwnPullRequests() async {
        let pr = PRIdentifier("cli/cli#1")!
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1", author: "ondrajodas")]))
        gateway.heads = [pr: PullRequestHead(sha: "9c1de02", committedAt: pushedAt)]
        gateway.viewer = "ondrajodas"
        let store = store(gateway, findings: [pr: "4f2ac91"])

        await store.loadViewer()
        await store.refresh()

        #expect(gateway.headRequests.isEmpty)
        #expect(store.activityEvents.isEmpty)
    }

    /// Shodná hlava řádek nedá — a razítko přesto dostane, takže se příští klidný tik neptá.
    @Test("Shodná hlava řádek nedá")
    func recordsNothingWhenTheHeadMatches() async {
        let pr = PRIdentifier("cli/cli#1")!
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        gateway.heads = [pr: PullRequestHead(sha: "4f2ac91", committedAt: pushedAt)]
        let store = store(gateway, findings: [pr: "4f2ac91"])

        await store.refresh()
        await store.refresh()

        #expect(store.activityEvents.isEmpty)
        #expect(gateway.headRequests.count == 1)
    }

    /// **Selhaný dotaz razítko neposune**, takže se příští tik zkusí znovu — tatáž nesymetrie jako
    /// u razítka rozhlídky po diskuzi (#335). Do okna se to nehlásí: nic v něm netvrdí, že hlavy
    /// zná, a stav GitHubu drží stavový řádek z pollingu.
    @Test("Selhaný dotaz se zkusí znovu")
    func retriesAfterAFailure() async {
        let pr = PRIdentifier("cli/cli#1")!
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        gateway.headsFailure = GitHubError.timedOut
        let store = store(gateway, findings: [pr: "4f2ac91"])

        await store.refresh()
        #expect(store.activityEvents.isEmpty)

        gateway.headsFailure = nil
        gateway.heads = [pr: PullRequestHead(sha: "9c1de02", committedAt: pushedAt)]
        await store.refresh()

        #expect(gateway.headRequests.count == 2)
        #expect(store.activityEvents.map(\.kind) == [.staleFindings])
    }

    /// PR, na kterou GitHub neodpoví, razítko **nedostane** — „nevíme“ se nesmí zapsat jako
    /// „zjištěno“, jinak by se na ni nezeptalo, dokud se `updatedAt` nepohne.
    @Test("Chybějící odpověď razítko nedostane")
    func leavesAMissingAnswerUnstamped() async {
        let pr = PRIdentifier("cli/cli#1")!
        let gateway = FakeGitHubGateway(always: .success([summary("cli/cli#1")]))
        let store = store(gateway, findings: [pr: "4f2ac91"])

        await store.refresh()
        await store.refresh()

        #expect(gateway.headRequests.count == 2)
        #expect(store.headProbes.isEmpty)
        #expect(store.activityEvents.isEmpty)
    }
}
