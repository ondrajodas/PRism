import Foundation
import Testing

@testable import PRism

/// Přepnutí vlastního draftu na *ready for review*, jak ho řídí store (#482).
///
/// **Nic se nepřepíná**: `gh` je podstrčený shell skript v dočasné složce, který zapíše, kolikrát
/// byl spuštěn. Fake publisher by se sem podstrčit nedal — `AppStore` si ho podle tvrdé podmínky
/// č. 1 nesmí držet ani jako továrnu. Počítadlo spuštění je jediný způsob, jak ověřit, že se
/// **nevolalo nic**; tatáž scéna jako u labelů (#392) a u merge (#465).
///
/// Akce **nemá potvrzovací sheet**, takže je store to jediné místo, které stojí mezi kliknutím
/// a `gh` — o důvod víc mít tady kontrolu i tvrzení o ní.
@Suite("AppStore — ready for review")
@MainActor
struct AppStoreReadyForReviewTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier("ondrajodas/prism-review-sandbox#11")!
    private let calls: URL

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
        calls = directory.url.appending(path: "gh-calls.log")
    }

    // MARK: - Prostředí testu

    private func configuration(publishing: Bool, mine: Bool) -> Configuration {
        var configuration = Configuration.standard
        if publishing {
            configuration.setRepository(RepositoryConfig(allowsPublishing: true), for: pr.repo)
        }
        configuration.global.ownLogins = mine ? ["autor"] : []
        return configuration
    }

    private func summary() -> PullRequestSummary {
        PullRequestSummary(
            id: pr,
            title: "chore: ready probe",
            author: "autor",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .draft
        )
    }

    private func detail(state: PullRequestState = .draft) -> PullRequest {
        PullRequest(
            id: pr,
            title: "chore: ready probe",
            author: "autor",
            headSha: "aaaa1111",
            baseSha: "bbbb2222",
            headRef: "prism-ready-probe-482",
            baseRef: "master",
            url: URL(string: "https://github.com/\(pr.repo)/pull/\(pr.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: state,
            isCrossRepository: false
        )
    }

    private func commit() -> PullRequestCommit {
        PullRequestCommit(
            sha: "aaaa1111",
            message: "chore: ready probe",
            authorName: "autor",
            authorLogin: "autor",
            avatarURL: nil,
            committedAt: Date(timeIntervalSince1970: 100),
            isMerge: false
        )
    }

    /// Skript, který se tváří jako `gh`. **Na stdout schválně nic** — `gh pr ready` na něj taky nic
    /// nepíše, takže scéna, ve které by odpověď byla, by testovala něco, co v provozu nenastane.
    private func fakeGh(exitCode: Int32 = 0, error: String = "", delay: Double = 0) throws -> URL {
        let script = directory.url.appending(path: "gh-\(UUID().uuidString).sh")
        let text = """
        #!/bin/sh
        echo "call" >> "\(calls.path(percentEncoded: false))"
        \(delay > 0 ? "sleep \(delay)" : "")
        cat >&2 <<'PRISMERR'
        \(error)
        PRISMERR
        exit \(exitCode)
        """
        try text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path(percentEncoded: false)
        )
        return script
    }

    /// Kolikrát se `gh` doopravdy spustilo. Nula znamená „nepřepínalo se“.
    private func ghCalls() throws -> Int {
        guard let text = try? String(contentsOf: calls, encoding: .utf8) else { return 0 }
        return text.split(whereSeparator: \.isNewline).count
    }

    private func prepared(
        gh: URL? = nil,
        publishing: Bool = true,
        mine: Bool = true,
        state: PullRequestState = .draft,
        /// Co vrátí **druhé** načtení detailu, tedy to po úspěšném přepnutí. `nil` = tentýž draft,
        /// což je zrovna ten scénář, ve kterém se pozná, že se stav načetl znovu **a přesto** se
        /// nezměnil.
        after: PullRequestState? = nil
    ) async -> (AppStore, FakeGitHubGateway) {
        let gateway = FakeGitHubGateway(
            always: .success([summary()]),
            detail: .success(detail(state: state))
        )
        gateway.commits = [commit()]
        gateway.branchStatus = BranchStatus(mergeability: .mergeable, mergeState: .draft)
        let store = AppStore(
            gateway: gateway,
            configuration: configuration(publishing: publishing, mine: mine),
            configStore: ConfigStore(layout: layout),
            time: FakeTimeSource(),
            gh: gh
        )
        // `loadBranchStatus` se tady **nevolá**: `loadDetail` si ho na konci zavolá sám, takže by
        // to bylo volání, které skončí na stráži `hasCurrentBranchStatus`. Že se stav načetl,
        // tvrdí `branchStatusRequests` v testech níž.
        await store.loadDetail(for: summary())
        if let after {
            // Až **po** prvním načtení: `detailFromNowOn` platí od nastavení dál, takže nastavené
            // dřív by novou hodnotu viděl i ten první průchod a scéna by začínala tam, kde má
            // skončit.
            gateway.detailFromNowOn = .success(detail(state: after))
            gateway.branchStatus = BranchStatus(mergeability: .mergeable, mergeState: .clean)
        }
        store.openTab(pr)
        return (store, gateway)
    }

    // MARK: - Nic se neodeslalo

    /// **Na cizím PR se nepřepíná** — a sekce `Větev` se tam nekreslí vůbec, takže se na tlačítko
    /// nedá ani dostat. Kontrola je přesto ve store: jediná kontrola ve view je kontrola, kterou
    /// příští obrazovka obejde.
    @Test("Na cizím PR se nepřepíná")
    func sendsNothingOnAForeignPullRequest() async throws {
        let (store, _) = await prepared(gh: try fakeGh(), mine: false)

        await store.markReadyForReview(on: summary())

        #expect(try ghCalls() == 0)
        #expect(store.metadataActionState(for: pr) == nil)
        #expect(store.branchSection(for: pr) == nil)
    }

    /// **S vypnutou branou se nepřepíná** — a tlačítko je zašedlé s důvodem, ne schované.
    @Test("S vypnutou branou se nepřepíná")
    func sendsNothingWithTheGateOff() async throws {
        let (store, _) = await prepared(gh: try fakeGh(), publishing: false)

        await store.markReadyForReview(on: summary())

        #expect(try ghCalls() == 0)
        #expect(store.metadataActionState(for: pr) == nil)
        let section = try #require(store.branchSection(for: pr))
        #expect(section.ready.isVisible)
        #expect(!section.ready.isAllowed)
    }

    /// **Nad PR, který draft není, se nepřepíná** — a v panelu po té akci není ani tlačítko.
    @Test(
        "Nad nedraftem se nepřepíná",
        arguments: [PullRequestState.open, .closed, .merged]
    )
    func sendsNothingOverANonDraft(state: PullRequestState) async throws {
        let (store, _) = await prepared(gh: try fakeGh(), state: state)

        await store.markReadyForReview(on: summary())

        #expect(try ghCalls() == 0)
        #expect(store.branchSection(for: pr)?.ready == .absent)
    }

    /// **Dvojklik pošle jedno volání.** Kontrola leží před prvním `await`, takže mezi nimi není
    /// mezera, do které by se závod vešel — tatáž konstrukce jako u labelů.
    @Test("Dvojklik odešle jedno volání")
    func sendsOnceOnADoubleClick() async throws {
        let (store, _) = await prepared(gh: try fakeGh(delay: 0.4))

        async let first: Void = store.markReadyForReview(on: summary())
        await TestWait.pause()
        async let second: Void = store.markReadyForReview(on: summary())
        _ = await (first, second)

        #expect(try ghCalls() == 1)
    }

    // MARK: - Když to projde

    /// **Po úspěchu se stav načte znovu** — a je to jediné, z čeho se nový stav dá vzít: odpověď
    /// `gh pr ready` je prázdná.
    ///
    /// Tvrdí se **oba směry té cache**: druhý dotaz na detail **i na slévatelnost** doopravdy
    /// odešel (bez zahození razítka by je stráž z #465 zastavila, protože `updatedAt` shrnutí se
    /// nezměnilo), a v panelu po tom **není** ani tlačítko, ani výstraha o rozpracovanosti.
    @Test("Úspěch načte stav znovu a tlačítko zmizí")
    func reloadsTheStateAfterSuccess() async throws {
        let (store, gateway) = await prepared(gh: try fakeGh(), after: .open)

        await store.markReadyForReview(on: summary())

        #expect(try ghCalls() == 1)
        #expect(store.metadataActionState(for: pr) == nil)
        // **Tři dotazy na detail, ne dva**, a je to vlastnost cesty ven, ne překvapení: první je
        // otevření PR, druhý **pre-flight publisheru** (ten jde taky přes gateway, viz
        // `GhReviewPublisher`) a třetí to nové načtení. Stav větve se ptá dvakrát — při otevření
        // a po přepnutí.
        #expect(gateway.detailRequests == [pr, pr, pr])
        #expect(gateway.branchStatusRequests == [pr, pr])
        let section = try #require(store.branchSection(for: pr))
        #expect(section.ready == .absent)
        #expect(!section.merge.obstacles.contains(.draftPullRequest))
        #expect(section.merge.isAllowed)
    }

    /// **Záložka zůstává otevřená** — opak merge (#465), kde ji zavírá tentýž klik. Přepnutím na
    /// *ready* práce na PR nekončí, začíná.
    @Test("Záložka se nezavírá")
    func keepsTheTabOpen() async throws {
        let (store, _) = await prepared(gh: try fakeGh(), after: .open)

        await store.markReadyForReview(on: summary())

        #expect(store.openTabs == [pr])
    }

    // MARK: - Když to nedopadne

    /// **Chyba je vidět v panelu, a v té sekci, ve které se klikalo.** `readyFailed`, ne `failed`:
    /// druhý by ji nakreslil v bloku labelů, tedy u akce, na kterou nikdo neklikal.
    ///
    /// A **stav PR se nenačítá znovu**: přepnutí se nestalo, takže v panelu má zůstat draft
    /// i s tlačítkem, aby se to dalo zkusit znovu.
    @Test("Selhání se ohlásí v sekci Větev a nic nepřepíše")
    func reportsTheFailureInTheBranchSection() async throws {
        // **`after: .open` je tady schválně, i když se nic nepřepnulo**: bez něj by druhé načtení
        // vrátilo tentýž draft, takže by tvrzení „stav se znovu nenačetl“ prošlo i tehdy, kdyby se
        // načetl. Takhle se ta chyba **dá naměřit** — po zbytečném načtení by sekce ztratila
        // tlačítko.
        let (store, gateway) = await prepared(
            gh: try fakeGh(exitCode: 1, error: "HTTP 403: Resource not accessible by integration"),
            after: .open
        )

        await store.markReadyForReview(on: summary())

        let state = try #require(store.metadataActionState(for: pr))
        #expect(state.noticePlace == .branch)
        #expect(state.readyFailure != nil)
        // **`failure` je `nil` schválně**: to je ta hodnota, kterou čte blok labelů, a chyba
        // přepnutí se tam kreslit nemá.
        #expect(state.failure == nil)
        // Dva dotazy: otevření PR a **pre-flight publisheru**. Třetí by znamenal, že se stav
        // načetl znovu po akci, která se nestala.
        #expect(gateway.detailRequests == [pr, pr], "po selhání se stav znovu nenačítá")
        #expect(gateway.branchStatusRequests == [pr])
        #expect(store.branchSection(for: pr)?.ready == .allowed)
    }

    /// Chybu **zapomene až člověk** — `Zavřít` v panelu. Chyba, která zmizí sama, je chyba, kterou
    /// nikdo nepřečte.
    @Test("Zavřít chybu zahodí")
    func clearsTheFailureOnDemand() async throws {
        let (store, _) = await prepared(gh: try fakeGh(exitCode: 1, error: "HTTP 403"))

        await store.markReadyForReview(on: summary())
        #expect(store.metadataActionState(for: pr)?.noticePlace == .branch)

        store.clearMetadataFailure(for: pr)

        #expect(store.metadataActionState(for: pr) == nil)
    }

    /// **Bez `gh` se nevolá nic** a v panelu je důvod — brána `metadataEditing` na chybějící
    /// nástroj sáhne dřív než akce.
    @Test("Bez gh se nepřepíná")
    func sendsNothingWithoutTheTool() async throws {
        let (store, _) = await prepared(gh: nil)

        await store.markReadyForReview(on: summary())

        #expect(try ghCalls() == 0)
        let section = try #require(store.branchSection(for: pr))
        #expect(section.ready.isVisible)
        #expect(!section.ready.isAllowed)
    }
}
