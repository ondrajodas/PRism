import Foundation
import Testing

@testable import PRism

/// Anotace hunků ze strany store (#524) — spouštěč, brána a to, co se s výsledkem stane.
///
/// **Nejcennější tvrzení téhle sady jsou ta, která říkají, že se něco NEstalo**: že z anotace
/// nikdy nevznikne nález, že se automat bez zapnuté brány nespustí a že zrušený běh neuloží nic.
/// Ta se rozbijí potichu — porušení není chyba, ale věta, která se v okně počítá jinam, než patří.
@Suite("AppStore — anotace hunků (#524)")
@MainActor
struct AppStoreAnnotationsTests {
    private let directory: TemporaryDirectory
    private let layout: CacheLayout
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let time = FakeTimeSource()

    init() throws {
        directory = try TemporaryDirectory()
        layout = CacheLayout(root: directory.url)
    }

    // MARK: - Scéna

    private func detail(headSha: String = "aaaa1111") -> PullRequest {
        PullRequest(
            id: pr,
            title: "titulek",
            author: "autor",
            headSha: headSha,
            baseSha: "bbbb2222",
            url: URL(string: "https://github.com/cli/cli/pull/42")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open,
            body: "popis"
        )
    }

    /// Překladač nálezů, který si jen pamatuje, že ho někdo zavolal (#592).
    ///
    /// Je tu kvůli **negativnímu tvrzení**: anotace se nepřekládá, takže tenhle fake má po celém
    /// běhu zůstat nedotčený. Kdyby se překlad k anotacím jednou přilepil, byla by to druhá
    /// session na tutéž věc — a zaplacená by byla dvakrát.
    final class FakeTranslator: FindingTranslating, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [FindingsLanguage] = []

        var languages: [FindingsLanguage] { lock.withLock { recorded } }

        func translate(
            _ findings: [ReportedFinding],
            to language: FindingsLanguage
        ) async throws -> [FindingTranslation?] {
            lock.withLock { recorded.append(language) }
            return findings.map { _ in nil }
        }
    }

    private func store(
        annotator: FakeHunkAnnotator? = FakeHunkAnnotator(),
        annotatesHunks: Bool = false,
        headSha: String = "aaaa1111",
        annotationStore: AnnotationStore? = nil,
        findingsLanguage: FindingsLanguage = .czech,
        translator: FakeTranslator? = nil
    ) -> AppStore {
        var configuration = Configuration.standard
        configuration.global.annotatesHunks = annotatesHunks
        configuration.global.findingsLanguage = findingsLanguage
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([]), detail: .success(detail(headSha: headSha))),
            configuration: configuration,
            time: time,
            checkout: FakeRepoCheckout(),
            reviewer: FakeReviewRunner(),
            translator: translator,
            annotator: annotator,
            annotationStore: annotationStore ?? AnnotationStore(layout: layout),
            cacheLayout: layout
        )
        // **Detail se nasadí rovnou.** Anotace se v provozu pouští nad otevřeným diffem, takže
        // hlava je známá — a bez ní by `Policy.annotations(of:head:)` neměla proti čemu platnost
        // posoudit a nevydala by nic (zákaz, ne povolení).
        store.detailStates[pr] = .loaded(detail(headSha: headSha), updatedAt: time.now)
        return store
    }

    private func run(
        hunks: [HunkAnnotation] = [HunkAnnotation(file: "a.swift", hunk: 1, why: "věta", source: nil)],
        files: [FileAnnotation] = [FileAnnotation(file: "a.swift", kind: .behaviour)],
        outcome: ReviewRunOutcome = .finished,
        answered: Bool = true,
        usage: RunUsage? = nil
    ) -> AnnotationRun {
        AnnotationRun(
            hunks: hunks,
            files: files,
            outcome: outcome,
            sessionID: "s1",
            answered: answered,
            dropped: 0,
            usage: usage
        )
    }

    private func waitUntilDone(_ store: AppStore) async {
        await waitUntil("anotace doběhnou") { !store.isAnnotating(pr) }
        #expect(!store.isAnnotating(pr))
    }

    // MARK: - Ruční spuštění

    /// Základní směr: kliknutí → jedna session nad **hlavou z detailu** → uložený záznam, který
    /// pro tu hlavu platí.
    @Test("Kliknutí popíše změny a záznam se uloží")
    func manualStartStoresTheAnnotations() async throws {
        let annotator = FakeHunkAnnotator(runs: [run()])
        let store = store(annotator: annotator)

        store.startAnnotating(for: pr)
        await waitUntilDone(store)

        #expect(annotator.requests.count == 1)
        #expect(annotator.requests.first?.headSha == "aaaa1111")
        #expect(annotator.requests.first?.baseSha == "bbbb2222")
        #expect(store.annotations(for: pr)?.hunks.count == 1)
        #expect(store.annotations(for: pr)?.files.first?.kind == .behaviour)
        #expect(try await AnnotationStore(layout: layout).load(for: pr)?.headSha == "aaaa1111")
    }

    // MARK: - Jazyk vět (#592)

    /// **Zadání jazyk nenese, a to je to tvrzení** (#592, po proklikání). Anotace se kreslí v diffu
    /// vedle českých popisků, takže je to text v okně — česky vždycky. `findingsLanguage` je volba
    /// o obsahu review, který může odejít na GitHub anglicky, a do téhle cesty nepatří.
    ///
    /// Tenhle test hlídá **spodní konec** cesty: ať je `Jazyk nálezů` nastavený jakkoli, session
    /// dostane totéž zadání. Že o jazyku neví ani prompt, tvrdí `AnnotateCommandTests` nad
    /// zdrojáky — za běhu není co proměnit, protože konstanta parametr nemá.
    @Test("Jazyk nálezů zadáním session nehýbe", arguments: FindingsLanguage.allCases)
    func theFindingsLanguageNeverReachesTheRequest(_ language: FindingsLanguage) async {
        let annotator = FakeHunkAnnotator(runs: [run()])
        let store = store(annotator: annotator, findingsLanguage: language)

        store.startAnnotating(for: pr)
        await waitUntilDone(store)

        #expect(
            annotator.requests == [
                AnnotationRequest(
                    pullRequest: pr,
                    headSha: "aaaa1111",
                    worktree: annotator.requests.first?.worktree ?? URL(filePath: "/"),
                    baseSha: "bbbb2222",
                    timeout: Configuration.standard.resolved(for: pr.repo).reviewTimeout
                )
            ]
        )
    }

    /// **Kvůli jazyku se nespouští druhá session, a to je to tvrzení.** U nálezů překlad je (#94),
    /// protože jich je hodně a `category` u nich musí zůstat anglickým slugem; anotace se píše
    /// ve svém jazyce rovnou.
    ///
    /// Test tvrdí obojí naráz: překladač zůstal **nedotčený** a věta se uložila **doslova tak, jak
    /// dorazila** — tedy že po ní nikdo nešel ani potichu. Rozbilo by se to bez hlesu: přeložená
    /// anotace vypadá správně, jen je dvakrát zaplacená.
    @Test("Anotace se nepřekládá a druhá session kvůli jazyku nenaběhne")
    func annotationsAreNeverTranslated() async throws {
        let translator = FakeTranslator()
        let annotator = FakeHunkAnnotator(
            runs: [
                run(hunks: [HunkAnnotation(file: "a.php", hunk: 1, why: "věta z běhu", source: nil)])
            ]
        )
        let store = store(annotator: annotator, findingsLanguage: .czech, translator: translator)

        store.startAnnotating(for: pr)
        await waitUntilDone(store)

        #expect(translator.languages.isEmpty)
        #expect(store.annotations(for: pr)?.hunks.map(\.why) == ["věta z běhu"])
        #expect(try await AnnotationStore(layout: layout).load(for: pr)?.hunks.map(\.why) == ["věta z běhu"])
    }

    /// **Přepnutí jazyka na uloženou anotaci nesáhne.** Přepsat se bez nového běhu nedá (a ten
    /// stojí peníze), takže stará věta v cizím jazyce **dožije** do příští hlavy. Nesmí se ale
    /// stát, že ji přepnutí potichu zahodí nebo že si aplikace kvůli němu pustí session sama.
    @Test("Anotace uložená v jiném jazyce přepnutím nezmizí ani nepřeběhne")
    func storedAnnotationsSurviveALanguageSwitch() async throws {
        let annotator = FakeHunkAnnotator(
            runs: [run(hunks: [HunkAnnotation(file: "a.php", hunk: 1, why: "Временно указывает", source: nil)])]
        )
        let store = store(annotator: annotator, findingsLanguage: .english)

        store.startAnnotating(for: pr)
        await waitUntilDone(store)

        // Druhý store nad **tou samou cache**, jen s přepnutým jazykem — tak to vypadá po změně
        // v nastavení a restartu.
        let secondAnnotator = FakeHunkAnnotator(runs: [run()])
        let after = self.store(annotator: secondAnnotator, findingsLanguage: .czech)
        await after.loadAnnotations(for: pr)

        #expect(after.annotations(for: pr)?.hunks.map(\.why) == ["Временно указывает"])
        // A **nikdo nic nepustil**: přečtení uložených anotací session nespouští, takže ruská věta
        // se nepřepíše ani potichu. Bez tohohle tvrzení by komentář výš říkal víc než test.
        #expect(secondAnnotator.requests.isEmpty)
        #expect(!after.isAnnotating(pr))
    }

    /// **Ruční spuštění bránu nečte**, a je to tatáž dělba jako u routingu (#518) s `Pustit přesto`:
    /// brána rozhoduje o tom, co si vybírá aplikace, ne o tom, o co si člověk řekne kliknutím.
    @Test("Kliknutí popíše změny i u repa, kde je brána vypnutá")
    func manualStartIgnoresTheGate() async {
        let annotator = FakeHunkAnnotator(runs: [run()])
        let store = store(annotator: annotator, annotatesHunks: false)

        store.startAnnotating(for: pr)
        await waitUntilDone(store)

        #expect(annotator.requests.count == 1)
    }

    /// Druhé kliknutí, dokud běží, nepustí druhou session — jinak by nad jednou hlavou běžely dvě
    /// a zaplatily se obě.
    @Test("Dvě kliknutí za sebou pustí jednu session")
    func doubleClickStartsOnce() async {
        let annotator = FakeHunkAnnotator(runs: [run()], holdsUntilRelease: true)
        let store = store(annotator: annotator)

        store.startAnnotating(for: pr)
        await waitUntil("session naběhne") { !annotator.requests.isEmpty }
        store.startAnnotating(for: pr)
        annotator.releaseAll()
        await waitUntilDone(store)

        #expect(annotator.requests.count == 1)
    }

    /// Bez zapojené session se tlačítko v liště **nekreslí**. Zašedlé by slibovalo akci, která se
    /// zapíná jinde — tatáž úvaha jako u `Otevřít v editoru` (#530).
    ///
    /// **Spuštění se přesto nesmí vrátit potichu** (oprava k #524): tudy se z lišty projít nedá,
    /// ale kdyby ano, tichý návrat je přesně ten tvar, kterým „tlačítko nic nedělá“ vzniká. Test
    /// tvrdí obojí — že nic neběží **a** že se o tom dá číst.
    @Test("Bez zapojené session se nenabízí, ale mlčky se nevrací")
    func withoutAnAnnotatorTheAttemptIsReported() async {
        let store = store(annotator: nil)

        #expect(!store.canAnnotate(pr))
        store.startAnnotating(for: pr)

        #expect(!store.isAnnotating(pr))
        #expect(store.annotationFailure(for: pr) == AppStore.unwiredAnnotationFailure)
        // A je to vidět tam, kde se o běhu čte: dráha `anotace` v tabu `Průběh`.
        if case .failed = store.annotationLane(for: pr)?.state {} else {
            Issue.record("dráha se má nakreslit i tehdy, když běh vůbec nevznikl")
        }
        #expect(store.annotationControl(for: pr) == .failed(detail: AppStore.unwiredAnnotationFailure))
    }

    /// Ovladač v liště má **tři stavy**, ne dva — a po každém kliknutí se musí některý z nich
    /// změnit. Kdyby se běh od klidu nepoznal, je kliknutí k nerozeznání od tlačítka, které nic
    /// nedělá; přesně to #524 předvedl.
    @Test("Ovladač v liště rozlišuje klid, běh a selhání")
    func theToolbarControlHasThreeStates() async {
        let annotator = FakeHunkAnnotator(runs: [run()], holdsUntilRelease: true)
        let store = store(annotator: annotator)

        #expect(store.annotationControl(for: pr) == .idle)

        store.startAnnotating(for: pr)
        await waitUntil("session naběhne") { !annotator.requests.isEmpty }
        #expect(store.annotationControl(for: pr) == .running)

        annotator.releaseAll()
        await waitUntilDone(store)
        // Doběhlý běh vrací ovladač do klidu — „popsat znovu“ je tatáž akce jako poprvé.
        #expect(store.annotationControl(for: pr) == .idle)
    }

    /// Zrušení z lišty musí běh **doopravdy** zastavit a ovladač vrátit do klidu. Tlačítko, které
    /// se po kliknutí nezmění, je totéž jako tlačítko, které nic nedělá — jen o obrazovku dál.
    @Test("Zrušení z lišty běh zastaví a ovladač vrátí do klidu")
    func cancellingFromTheToolbarStopsTheRun() async {
        let annotator = FakeHunkAnnotator(runs: [run()], holdsUntilRelease: true)
        let store = store(annotator: annotator)

        store.startAnnotating(for: pr)
        await waitUntil("session naběhne") { !annotator.requests.isEmpty }
        store.cancelAnnotating(for: pr)
        await waitUntilDone(store)

        #expect(store.annotationControl(for: pr) == .idle)
        #expect(store.annotations(for: pr) == nil)
    }

    // MARK: - Brána automatu

    /// **Výchozí stav je vypnuto** a automat se bez něj nespustí: je to session navíc na každou
    /// hlavu, tedy peníze, o které si nikdo neřekl.
    @Test("Automat bez zapnuté brány nepopisuje")
    func theAutomatDoesNothingWithoutTheGate() async {
        let annotator = FakeHunkAnnotator(runs: [run()])
        let store = store(annotator: annotator, annotatesHunks: false)
        store.automaticReviews.insert(pr)

        store.annotateAfterAutomaticReview(of: pr)
        await waitUntilDone(store)

        #expect(annotator.requests.isEmpty)
    }

    /// **Ruční `Spustit review` anotace nespouští.** Brána platí jen na automat — kdo si o popis
    /// řekne, má na to položku v nabídce nad diffem.
    @Test("Ruční review anotace nespustí, ani se zapnutou branou")
    func aManualReviewDoesNotAnnotate() async {
        let annotator = FakeHunkAnnotator(runs: [run()])
        let store = store(annotator: annotator, annotatesHunks: true)

        store.annotateAfterAutomaticReview(of: pr)
        await waitUntilDone(store)

        #expect(annotator.requests.isEmpty)
    }

    @Test("Automat se zapnutou branou popíše změny")
    func theAutomatAnnotatesBehindTheGate() async {
        let annotator = FakeHunkAnnotator(runs: [run()])
        let store = store(annotator: annotator, annotatesHunks: true)
        store.automaticReviews.insert(pr)

        store.annotateAfterAutomaticReview(of: pr)
        await waitUntilDone(store)

        #expect(annotator.requests.count == 1)
    }

    // MARK: - Anotace není nález

    /// **Z anotace nikdy nevznikne nález.** Je to hranice, kvůli které má tahle session vlastní
    /// typ výsledku, vlastní store a vlastní schéma bez pole pro závažnost — a tenhle test je to
    /// jediné místo, kde se dá tvrdit naráz o všech třech vrstvách.
    @Test("Popsané změny nevyrobí ani jeden nález")
    func annotationsNeverBecomeFindings() async throws {
        let annotator = FakeHunkAnnotator(runs: [run(hunks: [
            HunkAnnotation(file: "a.swift", hunk: 1, why: "přidává bránu", source: nil),
            HunkAnnotation(file: "a.swift", hunk: 2, why: "a test k ní", source: nil),
        ])])
        let store = store(annotator: annotator)

        store.startAnnotating(for: pr)
        await waitUntilDone(store)

        #expect(store.annotations(for: pr)?.hunks.count == 2)
        // Ani záznam review, ani jediný nález, ani chip nad tabem.
        #expect(store.reviewRecords[pr] == nil)
        #expect(store.reviewRecord(for: pr) == nil)
        #expect(Policy.chips(for: store.reviewRecord(for: pr), skills: [], running: []).isEmpty)
        // A na disku leží soubor **jedině** pod `annotations/`, ne v `reviews/`.
        #expect(FileManager.default.fileExists(atPath: layout.annotationFile(for: pr).path()))
        #expect(!FileManager.default.fileExists(atPath: layout.reviews.path()))
    }

    // MARK: - Když to nedopadne

    /// **Zrušení neuloží nic**: věty, které si nikdo nevyžádal, by po zrušení zůstaly ležet nad
    /// hunky — a rozdělaný průběh by v dráze navěky „běžel“.
    @Test("Zrušený běh neuloží nic a průběh po sobě uklidí")
    func cancellationStoresNothing() async throws {
        let annotator = FakeHunkAnnotator(runs: [run()], holdsUntilRelease: true)
        let store = store(annotator: annotator)

        store.startAnnotating(for: pr)
        await waitUntil("session naběhne") { !annotator.requests.isEmpty }
        store.cancelAnnotating(for: pr)
        await waitUntilDone(store)

        #expect(store.annotations(for: pr) == nil)
        #expect(store.annotationProgress[pr] == nil)
        #expect(try await AnnotationStore(layout: layout).load(for: pr) == nil)
    }

    /// **Doběhlý běh bez čitelné odpovědi se uloží.** Bez souboru by se „zkusilo se to a nevyšlo“
    /// nedalo odlišit od „nikdy neběželo“ — a příští otevření PR by session zaplatilo znovu.
    @Test("Zabitá session se uloží jako běh bez odpovědi")
    func aTimedOutRunIsStoredAsUnanswered() async {
        let annotator = FakeHunkAnnotator(runs: [
            run(hunks: [], files: [], outcome: .timedOut, answered: false)
        ])
        let store = store(annotator: annotator)

        store.startAnnotating(for: pr)
        await waitUntilDone(store)

        let stored = store.annotations(for: pr)
        #expect(stored?.answered == false)
        #expect(stored?.outcome == .timedOut)
        #expect(stored?.isEmpty == true)
    }

    /// Spadlý běh **nese důvod dál**. `try?` by z chybějící binárky udělal „diff nemá co popsat“.
    @Test("Spadlý běh se ohlásí, nezamlčí")
    func aFailedRunIsReported() async {
        let annotator = FakeHunkAnnotator(failing: ProcessError.launchFailed("claude se nenašel"))
        let store = store(annotator: annotator)

        store.startAnnotating(for: pr)
        await waitUntilDone(store)

        #expect(store.annotationFailure(for: pr)?.contains("Popis změn neproběhl") == true)
        #expect(store.annotations(for: pr) == nil)
        // Dráha zůstane a **řekne, že to spadlo** — zmizet by znamenalo, že se nic nestalo.
        if case .failed = store.annotationLane(for: pr)?.state {} else {
            Issue.record("dráha spadlého běhu má být `failed`")
        }
    }

    // MARK: - Platnost proti hlavě

    /// Uložený záznam se po pushi **neukáže**, a je to tvrdá podmínka č. 5: anotace se páruje
    /// pořadím hunku, takže by po pushi ukazovala na cizí kód, ne na starý.
    @Test("Po pushi se uložené anotace přestanou vydávat")
    func aPushInvalidatesTheAnnotations() async {
        let annotator = FakeHunkAnnotator(runs: [run()])
        let store = store(annotator: annotator, headSha: "aaaa1111")

        store.startAnnotating(for: pr)
        await waitUntilDone(store)
        #expect(store.annotations(for: pr) != nil)

        store.detailStates[pr] = .loaded(detail(headSha: "cccc3333"), updatedAt: time.now)

        #expect(store.annotations(for: pr) == nil)
        // **Dráha zmizí spolu s nimi**, i když je běh z tohohle sezení: jinak by tab `Průběh`
        // tvrdil „popsáno“ o diffu, ze kterého se nic nekreslí.
        #expect(store.annotationLane(for: pr) == nil)
        // **Z paměti ani z disku se přitom nic nemaže** — rozhoduje `Policy`, ne store.
        #expect(store.hunkAnnotations[pr] != nil)
        #expect(store.annotationProgress[pr] != nil)
    }

    /// Načtení z disku se děje **až při otevření PR**, a **jen jednou**: chybějící klíč v mapě
    /// znamená „ještě se nečetlo“.
    @Test("Anotace se z disku načtou při otevření PR")
    func loadsFromDiskOnOpen() async throws {
        let annotationStore = AnnotationStore(layout: layout)
        try await annotationStore.save(
            StoredAnnotations(
                pullRequest: pr,
                headSha: "aaaa1111",
                hunks: [HunkAnnotation(file: "a.swift", hunk: 1, why: "z disku", source: nil)],
                files: [],
                outcome: .finished,
                sessionID: nil,
                answered: true,
                dropped: 0,
                finishedAt: Date(timeIntervalSince1970: 7),
                usage: nil
            )
        )
        let store = store(annotationStore: annotationStore)

        await store.loadAnnotations(for: pr)

        #expect(store.annotations(for: pr)?.hunks.first?.why == "z disku")
    }
}
