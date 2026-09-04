import Foundation
import Testing

@testable import PRism

/// Mapa PR v řádku fronty (#502) — `AppStore.queueMap(for:)`.
///
/// **Nejcennější polovina téhle sady tvrdí, že se pás NEnakreslí.** Kreslený pás je vidět;
/// pás nakreslený nad daty, která nejsou, vypadá jako údaj — a to je zrovna ta vada, kvůli
/// které se do #502 nekreslilo spektrum u řádku bez běhu. Dva důvody, každý svůj test:
///
/// - **na PR nic neběželo** — barva segmentu je závažnost, takže neutrální pás by byl
///   k nerozeznání od PR, na kterém review doběhlo čisté;
/// - **diff se ještě nenačetl** — ve frontě je to normální stav (diff se tahá až při otevření),
///   ne porucha, a segment bez souboru neexistuje.
///
/// Druhá polovina jsou **čtyři tvrzení o cache**: každé z nich mění jeden vstup a čeká, že se pás
/// přepočítá. Rozbila by se potichu — pás z minula pořád vypadá jako pás, jen tvrdí něco, co
/// v záznamu už není. Otisk vstupů je `QueueMapStamp`.
@Suite("AppStore — mapa PR v řádku fronty (#502)")
@MainActor
struct AppStoreQueueMapTests {
    /// **Tentýž pull request, jaký zakládá `makeRecord`** — záznam nese identitu PR, takže by se
    /// s jiným klíčem testovala mapa nad záznamem cizího PR.
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let updatedAt = Date(timeIntervalSince1970: 2_000_000)

    // MARK: - Kdy se pás nekreslí

    @Test("PR, na kterém nic neběželo, pás nedostane")
    func drawsNothingWithoutARun() {
        let store = store()
        store.diffStates[pr] = .loaded(diff(paths: ["src/A.php", "src/B.php"]), updatedAt: updatedAt)

        // Bez záznamu i se záznamem bez běhů — obojí znamená „nikdo se na to nepodíval“.
        #expect(store.queueMap(for: pr) == nil)
        store.reviewRecords[pr] = makeRecord(runs: [])
        #expect(store.queueMap(for: pr) == nil)
    }

    @Test("Bez načteného diffu se pás nekreslí, i když review běželo")
    func drawsNothingWithoutADiff() {
        let store = store()
        store.reviewRecords[pr] = makeRecord(runs: [makeStoredRun()])

        // Nenačtený diff je ve frontě **normální stav**: dotahuje se při otevření PR, takže
        // většina řádků ho nemá. Rozdělané ani spadlé načtení pás nedostane taky — segment se
        // z chybové hlášky složit nedá.
        #expect(store.queueMap(for: pr) == nil)
        store.diffStates[pr] = .loading
        #expect(store.queueMap(for: pr) == nil)
        store.diffStates[pr] = .failed(.other("gh spadl"))
        #expect(store.queueMap(for: pr) == nil)
        // A prázdný diff (PR beze změn) taky ne — pás o nula segmentech je prázdný obdélník.
        store.diffStates[pr] = .loaded(Diff(files: [], unrecognizedLines: 0), updatedAt: updatedAt)
        #expect(store.queueMap(for: pr) == nil)
    }

    // MARK: - Co pás nese

    @Test("Pás vzniká z načteného diffu a nálezů záznamu")
    func buildsTheStripFromTheDiffAndTheRecord() {
        let store = store()
        store.diffStates[pr] = .loaded(
            diff(paths: ["src/A.php", "src/B.php", "src/C.php"]),
            updatedAt: updatedAt
        )
        store.reviewRecords[pr] = makeRecord(runs: [
            makeStoredRun(findings: [
                makeReported(file: "src/B.php", line: 2, category: "correctness", verdict: .confirmed)
            ])
        ])

        let map = store.queueMap(for: pr)

        #expect(map?.segments.map(\.path) == ["src/A.php", "src/B.php", "src/C.php"])
        #expect(map?.segments.map { Policy.mapFill(of: $0) } == [.clean, .blocking, .clean])
        // Popisek o vláknech **mlčí**, protože se v řádku nemají odkud vzít (konverzace se tahá
        // až v detailu). Nemlčí ale o souborech a nálezech, tedy o tom, co pás kreslí.
        #expect(map?.summary == "3 soubory · 1 nález")
    }

    /// **Mapa se v řádku i pod hlavičkou skládá jednou funkcí** (`Policy.pullRequestMap`), takže
    /// tenhle test tvrdí to jediné, čím se ty dvě podoby liší: v řádku se **nepředávají vlákna**.
    /// Kdyby se předala, čárka by v pásu chyběla právě u zavřeného PR — tedy „žádná diskuze“ tam,
    /// kde je odpověď „nevíme“.
    @Test("Vlákna do pásu v řádku nejdou")
    func leavesThreadsOutOfTheRowStrip() {
        let store = store()
        store.diffStates[pr] = .loaded(diff(paths: ["src/A.php"]), updatedAt: updatedAt)
        store.reviewRecords[pr] = makeRecord(runs: [makeStoredRun()])

        #expect(store.queueMap(for: pr)?.segments.allSatisfy { $0.threads.isEmpty } == true)
    }

    // MARK: - Čtyři vstupy, které cache musí vyprázdnit

    @Test("Nový diff pás přepočítá")
    func aNewDiffRebuildsTheStrip() {
        let store = store()
        store.reviewRecords[pr] = makeRecord(runs: [makeStoredRun()])
        store.diffStates[pr] = .loaded(diff(paths: ["src/A.php"]), updatedAt: updatedAt)
        #expect(store.queueMap(for: pr)?.segments.count == 1)

        store.diffStates[pr] = .loaded(
            diff(paths: ["src/A.php", "src/B.php"]),
            updatedAt: updatedAt.addingTimeInterval(60)
        )

        #expect(store.queueMap(for: pr)?.segments.count == 2)
    }

    @Test("Odmítnutí nálezu segment odbarví")
    func dismissingAFindingRepaintsTheSegment() {
        let store = store()
        store.diffStates[pr] = .loaded(diff(paths: ["src/A.php"]), updatedAt: updatedAt)
        let blocking = makeFinding(file: "src/A.php", line: 2, category: "correctness", verdict: .confirmed)
        var record = makeRecord(runs: [
            makeStoredRun(findings: [
                makeReported(file: "src/A.php", line: 2, category: "correctness", verdict: .confirmed)
            ])
        ])
        store.reviewRecords[pr] = record
        #expect(store.queueMap(for: pr)?.segments.map { Policy.mapFill(of: $0) } == [.blocking])

        record.dismissals = makeDismissals([blocking])
        store.reviewRecords[pr] = record

        // Odmítnutý nález nezbarvuje — právě proto se odmítá. S cache slepou k odmítnutím by
        // řádek svítil červeně napořád.
        #expect(store.queueMap(for: pr)?.segments.map { Policy.mapFill(of: $0) } == [.clean])
        #expect(store.queueMap(for: pr)?.summary == "1 soubor")
    }

    @Test("Zaškrtnutí Prošlo segment ztlumí")
    func markingAFileReadDimsTheSegment() {
        let store = store()
        store.diffStates[pr] = .loaded(diff(paths: ["src/A.php"]), updatedAt: updatedAt)
        store.reviewRecords[pr] = makeRecord(runs: [makeStoredRun()])
        #expect(store.queueMap(for: pr)?.segments.first?.readState.isRead == false)

        store.toggleReadMark("src/A.php", blobs: "aaa..bbb", in: pr)

        #expect(store.queueMap(for: pr)?.segments.first?.readState.isRead == true)
        #expect(store.queueMap(for: pr)?.summary == "1 soubor · 1 prošlý")
    }

    /// Blokující sada je **per repo**, takže pás musí zčervenat i tehdy, když se změnila jen
    /// konfigurace a nálezy zůstaly. **Přepíná se na jednom storu, který si pás už spočítal** —
    /// dva story vedle sebe by tvrdily jen to, že se sada čte, ne že cache o ní ví. Bez kategorií
    /// v otisku by řádek kreslil pás z minula, a to je ta podoba vady, kterou nejde poznat od
    /// „nález neblokuje“.
    @Test("Blokující sada z konfigurace pás přebarví, i když už je v cache")
    func theRepositoryBlockingSetRepaintsTheStrip() async throws {
        let workspace = try TemporaryDirectory()
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configStore: ConfigStore(layout: CacheLayout(root: workspace.url)),
            time: FakeTimeSource()
        )
        store.diffStates[pr] = .loaded(diff(paths: ["src/A.php"]), updatedAt: updatedAt)
        store.reviewRecords[pr] = makeRecord(runs: [
            makeStoredRun(findings: [
                makeReported(file: "src/A.php", line: 2, category: "style", verdict: .confirmed)
            ])
        ])
        #expect(store.queueMap(for: pr)?.segments.map { Policy.mapFill(of: $0) } == [.findings])

        var configuration = Configuration.standard
        configuration.repositories[pr.repo] = RepositoryConfig(blockingCategories: ["style"])
        try await store.updateConfiguration(configuration)

        #expect(store.queueMap(for: pr)?.segments.map { Policy.mapFill(of: $0) } == [.blocking])
    }

    /// **Otisk se mění s každým vstupem, který mapa čte** — vyčerpávající výčet nad `QueueMapStamp`,
    /// pět polí a k tomu tvrzení, že se týmž vstupům otisk **nezmění** (jinak by cache nikdy
    /// netrefila). Testy výš to zkoušejí přes store, tenhle nad hodnotou: kdyby z otisku jedno pole
    /// vypadlo, mají čtyři z nich náhodnou šanci projít, tenhle ne.
    @Test("Otisk vstupů se mění s každým z nich")
    func theStampCoversEveryInput() {
        let base = QueueMapStamp(
            diff: updatedAt,
            files: 2,
            findings: [QueueMapStamp.Mark(makeFinding(file: "src/A.php", line: 2))],
            readStates: ["src/A.php": .unread],
            categories: ["correctness"]
        )
        let variants: [(String, QueueMapStamp)] = [
            ("jiné razítko diffu", QueueMapStamp(
                diff: updatedAt.addingTimeInterval(1), files: base.files,
                findings: base.findings, readStates: base.readStates, categories: base.categories
            )),
            ("jiný počet souborů", QueueMapStamp(
                diff: base.diff, files: 3,
                findings: base.findings, readStates: base.readStates, categories: base.categories
            )),
            ("jiný řádek nálezu", QueueMapStamp(
                diff: base.diff, files: base.files,
                findings: [QueueMapStamp.Mark(makeFinding(file: "src/A.php", line: 9))],
                readStates: base.readStates, categories: base.categories
            )),
            ("jiná značka Prošlo", QueueMapStamp(
                diff: base.diff, files: base.files, findings: base.findings,
                readStates: ["src/A.php": .read(at: updatedAt)], categories: base.categories
            )),
            ("jiná blokující sada", QueueMapStamp(
                diff: base.diff, files: base.files, findings: base.findings,
                readStates: base.readStates, categories: ["style"]
            )),
        ]

        for (what, variant) in variants {
            #expect(variant != base, "otisk se nezměnil: \(what)")
        }
        // A tatáž data dají tentýž otisk — bez toho by se pás skládal při každém dotazu znovu
        // a cache by byla jen mrtvá váha.
        #expect(base == QueueMapStamp(
            diff: updatedAt,
            files: 2,
            findings: [QueueMapStamp.Mark(makeFinding(file: "src/A.php", line: 2))],
            readStates: ["src/A.php": .unread],
            categories: ["correctness"]
        ))
    }

    /// **Cache se opravdu chytá**, jinak by čtyři testy výš nedokazovaly nic: kdyby se mapa
    /// skládala při každém dotazu znovu, byly by zelené i s otiskem, který o vstupech neví nic.
    @Test("Druhý dotaz bere odpověď z cache")
    func theSecondCallComesFromTheCache() {
        let store = store()
        store.diffStates[pr] = .loaded(diff(paths: ["src/A.php"]), updatedAt: updatedAt)
        store.reviewRecords[pr] = makeRecord(runs: [makeStoredRun()])

        _ = store.queueMap(for: pr)
        // Uložená mapa se podstrčí ručně — kdyby se odpověď skládala znovu, přepsala by se
        // a tvrzení by spadlo. Otisk zůstává ten, který si zapsal dotaz výš.
        guard let stamp = store.queueMapCache[pr]?.stamp else {
            Issue.record("dotaz si otisk do cache nezapsal")
            return
        }
        store.queueMapCache[pr] = (stamp, PullRequestMap(segments: [], summary: "z cache"))

        #expect(store.queueMap(for: pr)?.summary == "z cache")
    }

    /// Úklid po tiku (`forget(whatIsNotIn:)`) mapu pouští spolu s diffem, ze kterého vznikla —
    /// bez toho by cache rostla donekonečna o každý PR, který se ve frontě jednou objevil.
    @Test("Úklid po tiku cache pustí")
    func theTickPrunesTheCache() async {
        // **`stopAfter: 1`, jinak `keepFresh()` nikdy nedoběhne** — polling je nekonečná smyčka
        // a ukončí ji jedině hodina, která po zadaném počtu uspání vydá `CancellationError`.
        let store = store(time: FakeTimeSource(stopAfter: 1))
        store.diffStates[pr] = .loaded(diff(paths: ["src/A.php"]), updatedAt: updatedAt)
        store.reviewRecords[pr] = makeRecord(runs: [makeStoredRun()])
        _ = store.queueMap(for: pr)
        #expect(store.queueMapCache[pr] != nil)

        await store.keepFresh()

        #expect(store.queueMapCache[pr] == nil)
    }

    // MARK: - Příprava

    private func store(
        configuration: Configuration = .standard,
        time: FakeTimeSource = FakeTimeSource()
    ) -> AppStore {
        AppStore(
            gateway: FakeGitHubGateway(always: .success([])),
            configuration: configuration,
            time: time
        )
    }

    /// Diff o daných souborech, každý o třech změněných řádcích. Otisk (`blobs`) je u všech
    /// stejný — testům o mapě jde o segmenty, ne o rozlišení souborů podle obsahu.
    private func diff(paths: [String]) -> Diff {
        Diff(
            files: paths.map { path in
                FileDiff(
                    oldPath: path,
                    newPath: path,
                    change: .modified,
                    isBinary: false,
                    hunks: [
                        DiffHunk(
                            oldStart: 1,
                            oldCount: 1,
                            newStart: 1,
                            newCount: 2,
                            heading: "",
                            lines: [
                                DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: "kontext"),
                                DiffLine(kind: .added, oldNumber: nil, newNumber: 2, text: "nové"),
                                DiffLine(kind: .removed, oldNumber: 2, newNumber: nil, text: "staré"),
                            ]
                        )
                    ],
                    blobs: "aaa..bbb"
                )
            },
            unrecognizedLines: 0
        )
    }
}
