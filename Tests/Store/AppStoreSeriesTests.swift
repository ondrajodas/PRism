import Foundation
import Testing

@testable import PRism

/// Série PR z tiku (#513) — větve dorazí **týmž** dotazem jako hlavy a fronta se podle nich
/// přeskládá.
///
/// Nejcennější tvrzení jsou dvě a obě jsou o počtu dotazů: **na pohnutý tik jeden dotaz na celou
/// frontu**, **na klidný žádný**. Obojí se rozbije potichu — okno vypadá stejně, jen se každou
/// minutu platí za dotaz, o který si nikdo neřekl.
@Suite("AppStore — série PR z tiku (#513)")
@MainActor
struct AppStoreSeriesTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Skutečná série z veřejného repa (`cli/cli`, *Refreshable tokens*): #14452 stojí na hlavě
    /// #14451, #14453 na hlavě #14452.
    private var base: PRIdentifier { PRIdentifier("cli/cli#14451")! }
    private var middle: PRIdentifier { PRIdentifier("cli/cli#14452")! }
    private var top: PRIdentifier { PRIdentifier("cli/cli#14453")! }
    private var unrelated: PRIdentifier { PRIdentifier("keboola/vault#85")! }

    private func configuration() -> Configuration {
        var configuration = Configuration.standard
        configuration.global.sources = [Source(name: "Moje", query: "review-requested:@me is:open")]
        configuration.global.ownLogins = ["ondrajodas"]
        return configuration
    }

    private func summary(
        _ id: PRIdentifier,
        title: String = "Refreshable tokens",
        updatedAt: Date? = nil
    ) -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: title,
            author: "babakks",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: updatedAt ?? start,
            state: .open
        )
    }

    private func head(_ sha: String, head: String, base: String) -> PullRequestHead {
        PullRequestHead(
            sha: sha,
            committedAt: nil,
            refs: BranchRefs(head: head, base: base, isCrossRepository: false)
        )
    }

    /// Fronta ve **vstupním** pořadí od nejnovějšího: nahoře cizí PR, pak vršek série, pak základ —
    /// tedy přesně to pořadí, které série musí přeskládat.
    private func stack() -> (summaries: [PullRequestSummary], heads: [PRIdentifier: PullRequestHead]) {
        (
            [
                summary(unrelated, title: "chore: modernize dependencies", updatedAt: start),
                summary(top, title: "Refreshable tokens (4/7)", updatedAt: start.addingTimeInterval(-60)),
                summary(middle, title: "Refreshable tokens (3/7)", updatedAt: start.addingTimeInterval(-120)),
                summary(base, title: "Refreshable tokens (2/7)", updatedAt: start.addingTimeInterval(-180)),
            ],
            [
                unrelated: head("aaa1", head: "chore/deps", base: "main"),
                base: head("bbb1", head: "token-b", base: "token-a"),
                middle: head("ccc1", head: "token-c1", base: "token-b"),
                top: head("ddd1", head: "token-c2", base: "token-c1"),
            ]
        )
    }

    private func store(_ gateway: FakeGitHubGateway) -> AppStore {
        AppStore(
            gateway: gateway,
            configuration: configuration(),
            time: FakeTimeSource(start: start)
        )
    }
}

// MARK: - Co tik zjistí

extension AppStoreSeriesTests {
    /// Po tiku aplikace ví, na čem co stojí — **bez otevírání PR a bez detailu**. To je celé #513:
    /// `gh search prs` větve nevrací, takže do téhle chvíle byla cizí série neviditelná.
    @Test("Tik dotáhne větve a složí z nich sérii")
    func buildsTheSeriesFromATick() async {
        let stack = stack()
        let gateway = FakeGitHubGateway(always: .success(stack.summaries))
        gateway.heads = stack.heads
        let store = store(gateway)

        await store.refresh()

        #expect(store.branchRefs(for: middle)?.base == "token-b")
        #expect(store.pullRequestSeries.map(\.members) == [[base, middle, top]])
    }

    /// **Fronta drží skupinu pohromadě na místě nejnovějšího člena a uvnitř jde od základu nahoru.**
    /// Bez toho by řazení podle času poslalo vršek nahoru a základ dolů — tedy přesně opačně, než
    /// v jakém pořadí se to dá mergnout.
    @Test("Fronta přeskládá sérii od základu nahoru")
    func ordersTheQueueBySeries() async {
        let stack = stack()
        let gateway = FakeGitHubGateway(always: .success(stack.summaries))
        gateway.heads = stack.heads
        let store = store(gateway)

        await store.refresh()

        #expect(store.visibleQueuePullRequests.map(\.id) == [unrelated, base, middle, top])
    }

    /// Popisek visí nad **základem** skupiny a je jeden; ostatní řádky ho nedostanou.
    @Test("Popisek je jeden a sedí nad základem")
    func writesOneCaption() async {
        let stack = stack()
        let gateway = FakeGitHubGateway(always: .success(stack.summaries))
        gateway.heads = stack.heads
        let store = store(gateway)

        await store.refresh()

        #expect(store.queueSeriesCaptions.count == 1)
        #expect(store.queueSeriesCaptions[base] == "série · 3 PR · review v pořadí ↓")
    }

    /// Umístění a věta pod hlavičkou — to, co se kreslí v řádku a v detailu.
    @Test("Umístění a věta o vrstvě sedí")
    func describesThePlacement() async {
        let stack = stack()
        let gateway = FakeGitHubGateway(always: .success(stack.summaries))
        gateway.heads = stack.heads
        let store = store(gateway)

        await store.refresh()

        #expect(store.seriesPlacement(for: top)?.position == 3)
        #expect(store.seriesPlacement(for: top)?.standsOn == middle)
        #expect(store.seriesPlacement(for: base)?.standsOn == nil)
        #expect(store.seriesNote(for: base) == nil)
        #expect(store.seriesNote(for: top)?.hasPrefix("Diff je jen tahle vrstva nad #14452.") == true)
    }

    /// **Série zaniká sama**: po mergi spodního PR přepne GitHub base horního na `main`. Druhý tik
    /// se na to zeptá (posunulo se `updatedAt`) a skupina zmizí bez jediného zásahu.
    @Test("Po přepnutí základu série zmizí")
    func dissolvesTheSeries() async {
        let stack = stack()
        // Spodní PR se mergnul a GitHub přepnul base toho nad ním na `main`; `updatedAt` se tím
        // pohnulo, takže se druhý tik zeptá znovu.
        let after = [
            summary(unrelated, updatedAt: start),
            summary(top, updatedAt: start.addingTimeInterval(60)),
            summary(middle, updatedAt: start.addingTimeInterval(60)),
        ]
        let gateway = FakeGitHubGateway([.success(stack.summaries), .success(after)])
        gateway.heads = stack.heads
        let store = store(gateway)
        await store.refresh()
        #expect(store.pullRequestSeries.isEmpty == false)

        gateway.heads[middle] = head("ccc1", head: "token-c1", base: "main")
        await store.refresh()

        #expect(store.pullRequestSeries.map(\.members) == [[middle, top]])
        #expect(store.seriesPlacement(for: middle)?.standsOn == nil)
    }

    /// Větve po PR, který ze seznamu vypadl, se **uklidí** — jinak by mapa rostla celé sezení
    /// a série by držela skupinu kolem řádku, který se nekreslí.
    @Test("Po vypadlém PR se větve uklidí")
    func forgetsBranchesOfGonePullRequests() async {
        let stack = stack()
        let gateway = FakeGitHubGateway([.success(stack.summaries), .success([summary(unrelated)])])
        gateway.heads = stack.heads
        let store = store(gateway)
        await store.refresh()
        #expect(store.probedBranchRefs.count == 4)

        await store.refresh()

        #expect(store.probedBranchRefs.keys.map(\.description) == ["keboola/vault#85"])
    }
}

// MARK: - Kolik to stojí

extension AppStoreSeriesTests {
    /// **Jeden dotaz na celou frontu**, ne jeden na PR ani na repozitář — a je to týž dotaz, jakým
    /// se zjišťují zastaralé nálezy (#420).
    @Test("Pohnutý tik je jeden dotaz na celou frontu")
    func asksOncePerTick() async {
        let stack = stack()
        let gateway = FakeGitHubGateway(always: .success(stack.summaries))
        gateway.heads = stack.heads
        let store = store(gateway)

        await store.refresh()

        #expect(gateway.headRequests.count == 1)
        #expect(gateway.headRequests.first?.count == 4)
    }

    /// **Klidný tik se neptá vůbec.** Větve známe a `updatedAt` se nepohnul, takže se dotaz ani
    /// nespustí — tohle je ta polovina, kvůli které se předfiltr vůbec píše.
    @Test("Klidný tik se neptá")
    func asksNothingOnAQuietTick() async {
        let stack = stack()
        let gateway = FakeGitHubGateway(always: .success(stack.summaries))
        gateway.heads = stack.heads
        let store = store(gateway)
        await store.refresh()

        await store.refresh()

        #expect(gateway.headRequests.count == 1)
    }

    /// **Odpověď bez větví nesmí znamenat dotaz každou minutu.** Fixtury z #420 (a odpověď, kterou
    /// GitHub dá u aliasu, na který nevidíme) větve nenesou — a kdyby se „nevíme“ počítalo za důvod
    /// k dotazu, ptala by se aplikace na takové PR donekonečna. Razítko dostane každé PR, na které
    /// odpověď dorazila, takže druhý klidný tik mlčí.
    @Test("Odpověď bez větví se podruhé neptá")
    func asksOnlyOnceWithoutBranches() async {
        let stack = stack()
        let gateway = FakeGitHubGateway(always: .success(stack.summaries))
        gateway.heads = stack.heads.mapValues { PullRequestHead(sha: $0.sha, committedAt: nil) }
        let store = store(gateway)

        await store.refresh()
        await store.refresh()

        #expect(gateway.headRequests.count == 1)
        #expect(store.pullRequestSeries.isEmpty)
    }

    /// Pohnutý PR se zeptá **jen za sebe**: v dotazu je jeden alias, ne celá fronta znovu.
    @Test("Po změně jednoho PR se zeptá jen na něj")
    func asksOnlyAboutTheMovedPullRequest() async {
        let stack = stack()
        let moved = [
            summary(unrelated, updatedAt: start),
            summary(top, updatedAt: start.addingTimeInterval(120)),
            summary(middle, updatedAt: start.addingTimeInterval(-120)),
            summary(base, updatedAt: start.addingTimeInterval(-180)),
        ]
        let gateway = FakeGitHubGateway([.success(stack.summaries), .success(moved)])
        gateway.heads = stack.heads
        let store = store(gateway)
        await store.refresh()

        await store.refresh()

        #expect(gateway.headRequests.count == 2)
        #expect(gateway.headRequests.last == [top])
    }

    /// **Na vlastní PR se tudy neptá**: jejich větve nese rozhlídka po slévatelnosti (#572), takže
    /// by to bylo druhé volání za tutéž hodnotu.
    @Test("Vlastní PR se do dotazu nedostane")
    func skipsOwnPullRequests() async {
        let mine = PullRequestSummary(
            id: PRIdentifier("ondrajodas/PRism#513")!,
            title: "feat: série PR",
            author: "ondrajodas",
            url: URL(string: "https://github.com/ondrajodas/PRism/pull/513")!,
            updatedAt: start,
            state: .open
        )
        let gateway = FakeGitHubGateway(always: .success([mine]))
        let store = store(gateway)

        await store.refresh()

        #expect(gateway.headRequests.isEmpty)
    }
}
