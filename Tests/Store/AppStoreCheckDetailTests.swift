import Foundation
import Testing

@testable import PRism

/// Detail spadlého checku ve store (#214).
///
/// Nejcennější testy téhle sady tvrdí, že se něco **NEstalo**: že se nešlo pro log dopředu, že se
/// nešlo pro log nad stropem, že se stahování při sbalení **zrušilo** a že se nic z toho neuložilo.
@Suite("AppStore — detail checku")
@MainActor
struct AppStoreCheckDetailTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "keboola", name: "job-queue-daemon"), number: 858)

    private func check(
        _ name: String = "Tests (aws)",
        job: Int? = 90_007_149_348
    ) -> PullRequestCheck {
        PullRequestCheck(
            name: name,
            outcome: .failed,
            link: job.map {
                URL(string: "https://github.com/keboola/job-queue-daemon/actions/runs/1/job/\($0)")!
            },
            startedAt: nil,
            completedAt: nil
        )
    }

    private func store(_ gateway: FakeGitHubGateway) -> AppStore {
        AppStore(gateway: gateway, time: FakeTimeSource())
    }

    private func gateway() -> FakeGitHubGateway {
        FakeGitHubGateway(always: .success([]))
    }

    /// Nechá doběhnout úlohu, kterou `toggleCheck` pustil.
    private func settle(_ store: AppStore, check: PullRequestCheck) async {
        await store.checkTasks[CheckKey(pullRequest: pr, check: check.name)]?.value
    }

    // MARK: - Nikdy dopředu

    /// **Nejcennější test téhle sady.** Log se nesmí tahat, dokud se na check neklikne — jinak je
    /// to N+1 past o tři řády dražší než u detailu PR.
    @Test("Bez kliknutí se pro log ani anotace nejde")
    func fetchesNothingUpfront() async {
        let gateway = gateway()
        gateway.checks = [check()]
        let store = store(gateway)

        await store.loadChecks(for: pr)

        #expect(store.checks[pr]?.count == 1)
        #expect(gateway.logsAsked.isEmpty, "log se stáhl, aniž by o něj kdo řekl")
        #expect(gateway.logSizesAsked.isEmpty)
        #expect(gateway.annotationsAsked.isEmpty)
        #expect(store.expandedCheck(in: pr) == nil)
    }

    // MARK: - Rozbalení

    @Test("Rozbalení dotáhne anotace i konec logu")
    func loadsDetailOnExpand() async throws {
        let gateway = gateway()
        gateway.annotations = CheckAnnotations(items: [
            CheckAnnotation(path: "src/Cart.php", line: 41, level: .failure, message: "expects array"),
        ])
        gateway.jobLog = "2026-08-11T16:09:11.2636913Z [ERROR] Found 2 errors"
        gateway.logSize = 4_096
        let store = store(gateway)
        let check = check()

        store.toggleCheck(check, in: pr)
        await settle(store, check: check)

        #expect(store.expandedCheck(in: pr) == check.name)
        let detail = try #require(store.checkDetail(of: check.name, in: pr))
        #expect(detail.annotations == .loaded(gateway.annotations))
        guard case .loaded(let full, let tail) = detail.log else {
            Issue.record("log se nenačetl: \(detail.log)")
            return
        }
        // Ocas je připravený (bez timestampu), celý text zůstává pro `Ukázat celý log`.
        #expect(tail.text == "[ERROR] Found 2 errors")
        #expect(full == gateway.jobLog)
        // Číslo jobu z odkazu — a **totéž** číslo jde na anotace jako check-run ID.
        #expect(gateway.logsAsked == [90_007_149_348])
        #expect(gateway.annotationsAsked == [90_007_149_348])
    }

    /// Bez čísla jobu se detail **nenabízí**, takže se přes store nesmí dát otevřít ani omylem —
    /// jinak by se stahovalo z odkazu, ze kterého se stahovat nedá.
    @Test("Check bez job ID se nerozbalí")
    func refusesChecksWithoutAJobID() async {
        let gateway = gateway()
        let store = store(gateway)

        store.toggleCheck(check("bors", job: nil), in: pr)

        #expect(store.expandedCheck(in: pr) == nil)
        #expect(gateway.logSizesAsked.isEmpty)
        #expect(gateway.annotationsAsked.isEmpty)
    }

    /// Rozbalený je **jen jeden na PR**: dva otevřené konce logu znamenají dvě sady megabajtů
    /// v paměti.
    @Test("Druhé rozbalení první zavře a jeho text zahodí")
    func keepsOnlyOneExpanded() async {
        let gateway = gateway()
        gateway.jobLog = "log"
        let store = store(gateway)
        let first = check("Tests (aws)", job: 1)
        let second = check("Tests (gcp)", job: 2)

        store.toggleCheck(first, in: pr)
        await settle(store, check: first)
        store.toggleCheck(second, in: pr)
        await settle(store, check: second)

        #expect(store.expandedCheck(in: pr) == second.name)
        #expect(store.checkDetail(of: first.name, in: pr) == nil, "text prvního zůstal v paměti")
    }

    // MARK: - Sbalení zahodí a zruší

    /// **Log nemá přežít ani sbalení checku** — výslovné přání u #214. Po rozbalení se stahuje znovu.
    @Test("Sbalení stažený log zahodí")
    func collapsingThrowsTheLogAway() async {
        let gateway = gateway()
        gateway.jobLog = "log"
        let store = store(gateway)
        let check = check()

        store.toggleCheck(check, in: pr)
        await settle(store, check: check)
        store.toggleCheck(check, in: pr)

        #expect(store.expandedCheck(in: pr) == nil)
        #expect(store.checkDetail(of: check.name, in: pr) == nil)
        #expect(store.checkTasks.isEmpty, "úloha po sbalení zůstala")
    }

    /// Zrušení je podmínka, ne úklid: stahování osmimegového logu trvá vteřiny a bez zrušení by
    /// doběhlo do stavu, který už nikdo nečte.
    @Test("Sbalení běžící stahování zruší")
    func collapsingCancelsTheDownload() async {
        let gateway = gateway()
        let store = store(gateway)
        let check = check()
        store.toggleCheck(check, in: pr)
        let task = store.checkTasks[CheckKey(pullRequest: pr, check: check.name)]

        store.collapseCheck(in: pr)

        #expect(task?.isCancelled == true)
        await task?.value
        // A po zrušení se nic nedopsalo — stav je pryč, ne „načteno prázdno“.
        #expect(store.checkDetail(of: check.name, in: pr) == nil)
    }

    // MARK: - Strop

    /// **Nad stropem se nestahuje vůbec.** Jinak by se stáhlo 8,78 MB (4 s) jen proto, aby se
    /// zjistilo, že se nemají ukazovat.
    @Test("Nad stropem se pro log vůbec nejde")
    func doesNotFetchLogsOverTheLimit() async throws {
        let gateway = gateway()
        // Nad stropem, který od #292 stojí na 10 MB — největší log na našich repech (8,78 MB) se
        // dneska **vejde**, takže se na něj tenhle test už nedá postavit.
        gateway.logSize = 12_000_000
        gateway.jobLog = "tohle se nemá stáhnout"
        let store = store(gateway)
        let check = check()

        store.toggleCheck(check, in: pr)
        await settle(store, check: check)

        #expect(gateway.logSizesAsked.count == 1, "velikost se má zjistit")
        #expect(gateway.logsAsked.isEmpty, "log se stáhl, i když je nad stropem")
        let detail = try #require(store.checkDetail(of: check.name, in: pr))
        guard case .tooLarge(let reason) = detail.log else {
            Issue.record("nad stropem má být .tooLarge, je \(detail.log)")
            return
        }
        #expect(reason.contains("MB"), "věta má nést konkrétní velikost")
    }

    // MARK: - Selhání se nesmí tvářit jako prázdno

    /// **Selhané stažení nesmí v UI vypadat jako „log je prázdný“.**
    @Test("Selhaný log je vlastní stav, ne prázdný text")
    func failedLogIsNotAnEmptyLog() async throws {
        let gateway = gateway()
        gateway.jobLogFailure = GitHubError.timedOut
        let store = store(gateway)
        let check = check()

        store.toggleCheck(check, in: pr)
        await settle(store, check: check)

        let detail = try #require(store.checkDetail(of: check.name, in: pr))
        guard case .failed = detail.log else {
            Issue.record("selhání se zapsalo jako \(detail.log)")
            return
        }
    }

    /// Anotace **prázdné být běžně mohou** (workflow je neemituje), takže se selhání a prázdno
    /// nesmí slít — jinak by z chyby vyšlo tvrzení o CI.
    @Test("Selhané anotace jsou vlastní stav, ne žádné anotace")
    func failedAnnotationsAreNotNoAnnotations() async throws {
        let gateway = gateway()
        gateway.annotationsFailure = GitHubError.notFound("nic")
        gateway.jobLog = "log"
        let store = store(gateway)
        let check = check()

        store.toggleCheck(check, in: pr)
        await settle(store, check: check)

        let detail = try #require(store.checkDetail(of: check.name, in: pr))
        guard case .failed = detail.annotations else {
            Issue.record("selhání anotací se zapsalo jako \(detail.annotations)")
            return
        }
        // A log se kvůli spadlým anotacím **nezahodil** — jsou to dvě samostatné cesty.
        guard case .loaded = detail.log else {
            Issue.record("log spadl s anotacemi: \(detail.log)")
            return
        }
    }

    // MARK: - Neznámá velikost (#292)

    /// **Nejcennější test téhle sady.** Do #292 tady stálo, že se bez velikosti **nestahuje** — a
    /// protože rozbor hlaviček velikost nikdy nevydal, byl konec logu vypnutý u každého checku, ne
    /// v krajním případě. `HEAD` je ochrana proti obřímu logu, ne podmínka toho, že se log ukáže.
    @Test("Bez zjištěné velikosti se log přesto stáhne")
    func fetchesTheLogEvenWithoutTheSize() async throws {
        let gateway = gateway()
        gateway.logSize = nil
        gateway.jobLog = "assertace spadla"
        let store = store(gateway)
        let check = check()

        store.toggleCheck(check, in: pr)
        await settle(store, check: check)

        #expect(gateway.logsAsked.count == 1, "log se nestáhl, i když ho nic nezakazovalo")
        let detail = try #require(store.checkDetail(of: check.name, in: pr))
        guard case .loaded(let full, let tail) = detail.log else {
            Issue.record("mělo být .loaded, je \(detail.log)")
            return
        }
        #expect(full == "assertace spadla")
        #expect(tail.text == "assertace spadla")
    }

    /// A totéž, když dotaz na velikost rovnou **spadne**: chybu `HEAD`u nahradí chyba stažení,
    /// pokud vůbec nějaká bude. Jinak by na vypnutou funkci stačil jeden neúspěšný dotaz navíc.
    @Test("Spadlý dotaz na velikost log nezruší")
    func fetchesTheLogEvenWhenTheProbeFails() async throws {
        let gateway = gateway()
        gateway.logSizeFailure = GitHubError.timedOut
        gateway.jobLog = "log"
        let store = store(gateway)
        let check = check()

        store.toggleCheck(check, in: pr)
        await settle(store, check: check)

        #expect(gateway.logsAsked.count == 1)
        let detail = try #require(store.checkDetail(of: check.name, in: pr))
        guard case .loaded = detail.log else {
            Issue.record("mělo být .loaded, je \(detail.log)")
            return
        }
    }

    /// **Mezistav, ne jen výsledek** (#292): dokud se stahuje, drží se velikost z `HEAD`u, aby se
    /// dala napsat do hlášky. Se stropem na 10 MB se čeká vteřiny až desítky vteřin, takže spinner
    /// bez čísla je k nerozeznání od zamrznutí.
    @Test("Dokud se stahuje, drží se velikost z HEADu")
    func keepsTheKnownSizeWhileDownloading() async throws {
        let gateway = gateway()
        gateway.logSize = 8_777_952
        gateway.jobLog = "log"
        let gate = AsyncGate()
        gateway.jobLogGate = gate
        let store = store(gateway)
        let check = check()

        store.toggleCheck(check, in: pr)
        try await gate.waitUntilReached()

        let detail = try #require(store.checkDetail(of: check.name, in: pr))
        guard case .loading(let bytes) = detail.log else {
            Issue.record("během stahování má být .loading, je \(detail.log)")
            return
        }
        #expect(bytes == 8_777_952)

        await gate.release()
        await settle(store, check: check)
        guard case .loaded = store.checkDetail(of: check.name, in: pr)?.log else {
            Issue.record("po uvolnění závory se log nenačetl")
            return
        }
    }

    /// Strop se tím ale **nezahazuje** — jen se uplatní později, na tom, co doopravdy přišlo.
    /// `Ukázat celý log` by jinak nabídl sazbu, kterou strop zakazuje.
    @Test("Bez velikosti rozhodne strop až podle stažených bajtů")
    func appliesTheLimitToWhatArrived() async throws {
        let gateway = gateway()
        gateway.logSize = nil
        gateway.jobLog = String(repeating: "x", count: Policy.logSizeLimit + 1)
        let store = store(gateway)
        let check = check()

        store.toggleCheck(check, in: pr)
        await settle(store, check: check)

        let detail = try #require(store.checkDetail(of: check.name, in: pr))
        guard case .tooLarge(let reason) = detail.log else {
            Issue.record("nad stropem má být .tooLarge, je \(detail.log)")
            return
        }
        #expect(reason.contains("MB"), "věta má nést konkrétní velikost")
    }

    /// Když se nepovede ani stažení, je vidět **jeho** chyba — ta nese kód a výstup `gh`, kdežto
    /// chyba dotazu na velikost mluví o hlavičkách, o které uživateli nejde.
    @Test("Bez velikosti a bez logu je vidět chyba stažení")
    func reportsTheDownloadFailureWhenBothFail() async throws {
        let gateway = gateway()
        gateway.logSizeFailure = GitHubError.malformedOutput("hlavičky")
        gateway.jobLogFailure = GitHubError.notFound("job 90007149348 neexistuje")
        let store = store(gateway)
        let check = check()

        store.toggleCheck(check, in: pr)
        await settle(store, check: check)

        let detail = try #require(store.checkDetail(of: check.name, in: pr))
        guard case .failed(let reason) = detail.log else {
            Issue.record("mělo být .failed, je \(detail.log)")
            return
        }
        #expect(reason.contains("neexistuje"), "má být vidět chyba stažení, ne chyba HEADu")
        #expect(!reason.contains("hlavičky"))
    }

    // MARK: - Úklid

    /// Detail se drží v paměti, takže musí zmizet s PR — a jeho stahování se **zruší**.
    @Test("PR mimo seznam si detail ani stahování neponechá")
    func forgetsDetailOfGonePullRequests() async {
        let summary = PullRequestSummary(
            id: pr,
            title: "t",
            author: "a",
            url: URL(string: "https://github.com/keboola/job-queue-daemon/pull/858")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
        let gateway = FakeGitHubGateway([.success([summary]), .success([])])
        let store = store(gateway)
        await store.refresh()
        let check = check()
        store.toggleCheck(check, in: pr)
        let task = store.checkTasks[CheckKey(pullRequest: pr, check: check.name)]

        await store.refresh()

        #expect(store.expandedChecks.isEmpty)
        #expect(store.checkDetails.isEmpty)
        #expect(store.checkTasks.isEmpty)
        #expect(task?.isCancelled == true)
    }
}
