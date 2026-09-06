import Foundation
import Testing

@testable import PRism

/// Měření, ne test (#509). Nic netvrdí — říká, **co stojí dráha v každém řádku seznamu**.
///
/// **Proč vůbec.** U #508 dráha stála v hlavičce **jednoho** PR, takže zdvojený `Policy.handoff`
/// (bere si ho i panel `Zadání`) byl konstanta a v `AppStore+OwnLoop.swift` je to tak zapsané —
/// i s větou, že se to u #509 bude muset změřit, protože tam poběží nad **každým** řádkem.
/// Tohle je to měření.
///
/// **Měří se oba konce** (#275): zlevnění, které práci jen přesune jinam, není zlevnění. Arm `C`
/// je proto ta naivní podoba (dráha si `Policy.handoff` spočítá sama), aby bylo vidět, kolik se
/// ušetřilo — bez ní by číslo z `B` netvrdilo nic.
///
/// - **A** — co seznam dělal **před** #509: `handoffReport(for:)` na každý vlastní řádek.
/// - **B** — co dělá **teď**: tentýž report **plus dráha z něj** (`ownLoopRow(for:handoff:)`).
/// - **C** — naivní podoba: tentýž report **plus dráha, která si report spočítá znovu**
///   (`ownLoop(for:)`).
///
/// **Série se prokládá A/B/C/A/B/C uvnitř jednoho běhu** (#274) — vedle běží další sloty a mezi
/// samostatnými běhy stroj driftuje. Měří se **CPU hlavního vlákna**, ne hodiny, ze stejného
/// důvodu.
///
/// Časy se **netvrdí** `#expect`em: na jiném stroji vyjdou jinak. Pouští se ručně,
/// `TEST_RUNNER_PRISM_MEASURE=1`.
@Suite(
    "Měření dráhy v řádku seznamu (#509)",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
@MainActor
struct OwnLoopRowMeasurement {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Kolik vlastních PR. **23 je skutečná fronta téhle instalace** (změřeno u #572), 60 je
    /// hlava dolů — kdyby cena rostla jinak než lineárně, bylo by to vidět zrovna tam.
    private static let sizes = [5, 23, 60]

    @Test("Co stojí dráha na každém vlastním řádku")
    func rowLoopCost() async {
        for count in Self.sizes {
            let store = await store(ownPullRequests: count)
            let rows = store.pullRequests

            // Zahřátí — první průchod platí za líné inicializace ve Foundation a za první
            // dotažení hodnot z map.
            _ = pass(store, rows, arm: .baseline)
            _ = pass(store, rows, arm: .reusedReport)
            _ = pass(store, rows, arm: .recomputedReport)

            var samples: [Arm: [TimeInterval]] = [:]
            for _ in 0..<5 {
                for arm in Arm.allCases {
                    samples[arm, default: []].append(pass(store, rows, arm: arm))
                }
            }
            for arm in Arm.allCases {
                let times = samples[arm] ?? []
                let median = times.sorted()[times.count / 2]
                print(
                    "MĚŘENÍ \(count) vlastních PR · \(arm.label): "
                        + "\(String(format: "%.3f", median * 1000)) ms na průchod seznamem "
                        + "(\(String(format: "%.4f", median * 1000 / Double(count))) ms na řádek)"
                )
            }
        }
    }

    /// Jeden průchod seznamem tak, jak ho dělá `PullRequestListView` — vrací **CPU hlavního
    /// vlákna**, ne uplynulý čas.
    private func pass(_ store: AppStore, _ rows: [PullRequestSummary], arm: Arm) -> TimeInterval {
        let before = mainThreadCPUSeconds()
        for summary in rows {
            let ownership = store.ownership(of: summary)
            let handoff = ownership == .mine ? store.handoffReport(for: summary.id) : .never
            switch arm {
            case .baseline:
                blackHole(handoff.pending)
            case .reusedReport:
                blackHole(handoff.pending)
                blackHole(ownership == .mine ? store.ownLoopRow(for: summary, handoff: handoff) : nil)
            case .recomputedReport:
                blackHole(handoff.pending)
                blackHole(ownership == .mine ? Policy.ownLoopRow(store.ownLoop(for: summary)) : nil)
            }
        }
        return mainThreadCPUSeconds() - before
    }

    /// Aby optimalizátor průchod nevyhodil. `@inline(never)` schválně — bez něj by se dal
    /// výsledek zahodit a měřilo by se prázdno (#478: měřidlo, které vydá totéž pro „funguje“
    /// i „nefunguje“).
    @inline(never)
    private func blackHole(_ value: some Any) {
        _ = String(describing: type(of: value)).isEmpty
    }

    private enum Arm: CaseIterable {
        /// Stav před #509.
        case baseline
        /// Stav po #509 — dráha z už spočítaného reportu.
        case reusedReport
        /// Naivní podoba — dráha si report spočítá znovu.
        case recomputedReport

        var label: String {
            switch self {
            case .baseline: "A · jen report předání (před #509)"
            case .reusedReport: "B · report + dráha z něj (#509)"
            case .recomputedReport: "C · report + dráha, která ho počítá znovu"
            }
        }
    }

    // MARK: - Materiál

    /// Store s `count` vlastními PR, na kterých **něco leží** — bez nálezů a bez konverzace by
    /// `Policy.handoff` neměl co skládat a měřilo by se prázdno.
    private func store(ownPullRequests count: Int) async -> AppStore {
        let summaries = (1...count).map { index in
            PullRequestSummary(
                id: PRIdentifier(repo: RepoID(owner: "ondrajodas", name: "PRism"), number: index),
                title: "feat(diff): find in the diff with ⌘F (#\(index))",
                author: "ondrajodas",
                url: URL(string: "https://github.com/ondrajodas/PRism/pull/\(index)")!,
                updatedAt: start,
                state: .open
            )
        }
        let gateway = FakeGitHubGateway(always: .success(summaries))
        gateway.viewer = "ondrajodas"
        var configuration = Configuration.standard
        configuration.global.sources = [Source(name: "Moje", query: "author:@me is:open")]
        configuration.global.ownLogins = ["ondrajodas"]
        let store = AppStore(
            gateway: gateway,
            configuration: configuration,
            time: FakeTimeSource(stopAfter: 1),
            visits: VisitLedger(preferences: InMemoryPreferences()),
            activityNotices: ActivityNoticeLedger(preferences: InMemoryPreferences()),
            activityVisits: ActivityVisitLedger(preferences: InMemoryPreferences())
        )
        await store.keepFresh()
        for summary in summaries {
            // Osm nálezů a čtyři komentáře na PR — nad tím `Policy.handoff` doopravdy pracuje.
            store.reviewRecords[summary.id] = makeRecord(
                runs: [
                    makeStoredRun(
                        findings: (1...8).map {
                            makeReported(
                                file: "App/Policy/DiffFind\($0).swift",
                                line: $0 * 7,
                                summary: "Chybějící kontrola návratové hodnoty číslo \($0)"
                            )
                        }
                    )
                ]
            )
            store.conversationStates[summary.id] = .loaded(
                Conversation(
                    viewer: "ondrajodas",
                    reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
                    threads: ConversationPage(items: [], total: 0, hasNextPage: false),
                    comments: ConversationPage(
                        items: (1...4).map { index in
                            ThreadComment(
                                id: "c\(summary.id.number)-\(index)",
                                author: "odinuv",
                                body: "opravdu to potřebuje ten mutex?",
                                createdAt: start,
                                url: summary.url
                            )
                        },
                        total: 4,
                        hasNextPage: false
                    )
                ),
                updatedAt: summary.updatedAt
            )
        }
        return store
    }
}
