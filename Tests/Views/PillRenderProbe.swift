import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#404): vykreslí **všech pět míst na jedno plátno** v obou režimech, aby se
/// sjednocená sazba dala **vidět** vedle výřezu z mockupu.
///
/// Existuje vedle `PillTypesettingTests` proto, že měření odpovídá na „vejde se to a je to
/// čitelné“, kdežto otázka #404 je „vypadá to jako jedna rodina prvků“. Na tu se dá odpovědět
/// jedině obrázkem — a musí být na jednom plátně: pět snímků pod sebou se porovnává po paměti,
/// což je zrovna to, čemu se tady vyhýbáme.
///
/// Na plátně je i dvojice, která se sjednotit **nemá**: `Bot` z konverzace (návrh ho kreslí jako
/// `.botchip`, tedy nemono) a `otevřený` z hlavičky PR (`.state-chip`). Bez nich by se z obrázku
/// nedalo poznat, jestli je nemono chip vada, nebo záměr.
///
/// **`NSHostingView`, ne `ImageRenderer`** — tatáž cesta jako `FindingActionColourProbe`, viz
/// `docs/testovani.md`.
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda sazby kapslí (#404)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct PillRenderProbe {
    /// Šířka, ve které má tabulka nálezů **všech šest sloupců**
    /// (`Policy.findingTableReviewerBreakpoint`) — pod ní odpadá reviewer a na sazbu kapsle je to
    /// táž otázka.
    private let width: CGFloat = 980

    @Test("Vyrendrovat všech pět míst s kapslemi")
    func rendersEveryPillPlace() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
        for dark in [false, true] {
            let url = directory.appending(path: "kapsle-\(dark ? "tmavy" : "svetly").png")
            let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
            var thrown: (any Error)?
            appearance.performAsCurrentDrawingAppearance {
                do {
                    try capture(scene(dark: dark), to: url)
                } catch {
                    thrown = error
                }
            }
            if let thrown { throw thrown }
            print("SONDA \(url.path)")
        }
    }

    /// **Barevný režim se nastavuje dvakrát**: `NSAppearance` kvůli paletě (dynamické `NSColor`)
    /// a `colorScheme` kvůli `.primary`/`.secondary`. S jedním z toho vyjde tmavý text na tmavém.
    private func scene(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label("1 — řádek fronty: odznak stavu (`.pill.crit`/`run`/`ok`/`stale`/`idle`)")
            queueRows
            label("2 — karta nálezu v panelu: `vyřešeno`, `irelevantní` a odznak kontroly")
            cards
            label("3 — řádek tabulky nálezů: `blokuje`, `irelevantní`, `2×`")
            tableRows
            label("4 — bublina u kódu: `blokuje`, `mimo diff`, `kontrola: …`")
            bubbles
            label("5 — vlákno a karta konverzace: `vyřešeno`, `zastaralé`, `+12`, `já`, `schválil`")
            conversation
            label("kontrola: co se sjednotit **nemá** — `Bot` (`.botchip`) a stav PR (`.state-chip`)")
            exceptions
        }
        .frame(width: width, alignment: .topLeading)
        .background(Palette.surface)
        // `tint` nese skutečné okno na kořeni (`ContentView`), a odznak `já` na něm visel do #404.
        .tint(Palette.accent)
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    // MARK: - Pět míst

    private var queueRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.queue, id: \.summary.id) { entry in
                PullRequestRow(
                    pullRequest: entry.summary,
                    reviewState: entry.state,
                    row: entry.row
                )
                .padding(.trailing, 13)
                .padding(.vertical, 5)
            }
        }
        .padding(.horizontal, FindingTableLayout.inset)
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Self.cardRows) { row in
                FindingCardView(row: row, findingActions: Self.actions) {}
            }
        }
        // Panel je 300 bodů (#294) — v něm se karta o místo pere, takže se v širokém plátně
        // kreslit nemá.
        .frame(width: 300)
        .padding(.horizontal, FindingTableLayout.inset)
    }

    private var tableRows: some View {
        let layout = Policy.findingTableLayout(availableWidth: width)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.tableRowModels, id: \.id) { row in
                FindingTableRowView(
                    row: row,
                    layout: layout,
                    findingActions: Self.actions,
                    draft: Self.draft,
                    toggle: {},
                    jump: {}
                )
            }
        }
    }

    private var bubbles: some View {
        VStack(alignment: .leading, spacing: 0) {
            FindingBubbleView(group: Self.blockingGroup, actions: Self.actions, indent: 0, toggle: {})
            FindingBubbleView(group: Self.agreedGroup, actions: Self.actions, indent: 0, toggle: {})
            // Nezakotvená bublina nese `mimo diff` — jinak by na plátně chyběla zrovna ta kapsle,
            // která je v návrhu nejdelší.
            FindingBubbleView(
                group: Self.unanchoredGroup,
                isAnchored: false,
                actions: Self.actions,
                indent: 0,
                toggle: {}
            )
        }
        .padding(.horizontal, FindingTableLayout.inset)
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThreadBubbleView(thread: Self.resolvedThread, viewer: Self.viewer, indent: 0, placement: .timeline)
            ThreadBubbleView(thread: Self.outdatedThread, viewer: Self.viewer, indent: 0, placement: .timeline)
            ConversationEntryView(entry: .review(Self.approval), viewer: Self.viewer)
            ConversationEntryView(entry: .review(Self.changes), viewer: Self.viewer)
        }
        .padding(.horizontal, FindingTableLayout.inset)
        .padding(.bottom, 8)
    }

    private var exceptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            ConversationEntryView(entry: .event(Self.botEvent))
            PullRequestHeaderView(pullRequest: Self.queue[0].summary)
        }
        .padding(.horizontal, FindingTableLayout.inset)
        .padding(.bottom, 14)
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption2)
            .foregroundStyle(Palette.ink3)
            .padding(.horizontal, FindingTableLayout.inset)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    // MARK: - Materiál

    private static let viewer = "ondrajodas"
    private static let actions = FindingActions()
    private static let draft = FileDraftActions(canCompose: true)
    private static let headSha = "4f2ac91"

    private struct QueueEntry {
        let summary: PullRequestSummary
        let state: ReviewState
        let row: QueueRow
    }

    /// Pět stavů fronty — a mezi nimi ty **nejdelší** popisky, protože o šířku se pere jen ten
    /// nejdelší.
    private static let queue: [QueueEntry] = [
        QueueEntry(
            summary: summary(3, "fix: nesahat na secret, když ve Vaultu není"),
            state: .completed(findings: 3),
            row: QueueRow(blocking: 1, spectrum: [])
        ),
        QueueEntry(
            summary: summary(4, "feat: přepsat frontu tak, aby snesla tři sloty naráz"),
            state: .timedOut(findings: 2),
            row: QueueRow(blocking: 1, spectrum: [])
        ),
        QueueEntry(
            summary: summary(5, "chore: bump phpunit to 11.4"),
            state: .running(finished: 2, total: 3),
            row: QueueRow(blocking: 0, spectrum: [])
        ),
        QueueEntry(summary: summary(6, "docs: doplnit README"), state: .clean, row: QueueRow(blocking: 0, spectrum: [])),
        QueueEntry(summary: summary(7, "refactor: rozdělit store"), state: .stale, row: QueueRow(blocking: 0, spectrum: [])),
        QueueEntry(
            summary: summary(8, "test: pokrýt překlad nálezů"),
            state: .inconclusive(reason: .droppedFindings),
            row: QueueRow(blocking: 0, spectrum: [])
        ),
    ]

    private static func summary(_ number: Int, _ title: String) -> PullRequestSummary {
        PullRequestSummary(
            id: PRIdentifier(repo: RepoID(owner: "keboola", name: "platform"), number: number),
            title: title,
            author: "odinuv",
            url: URL(string: "https://github.com/keboola/platform/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_754_000_000),
            state: .open
        )
    }

    private static func finding(
        _ summary: String,
        reviewer: String,
        category: String,
        file: String? = "src/Vault/Encryptor.php",
        line: Int? = 41
    ) -> Finding {
        Finding(
            reported: ReportedFinding(
                file: file,
                line: line,
                category: category,
                verdict: .confirmed,
                shortSummary: nil,
                summary: summary,
                failureScenario: "V logu skončí šifrovací klíč a podpis se spočítá z prázdné hodnoty."
            ),
            reviewer: reviewer,
            headSha: headSha
        )
    }

    private static let blocking = finding(
        "`?? ''` schová chybějící secret jako prázdnou hodnotu",
        reviewer: "php-review",
        category: "correctness"
    )
    private static let agreed = finding(
        "Timeout se nastavuje až po vytvoření klienta, takže první dotaz jde bez něj",
        reviewer: "php-review",
        category: "correctness",
        line: 44
    )
    private static let agreedSecond = finding(
        "Timeout se nastavuje až po vytvoření klienta, takže první dotaz jde bez něj",
        reviewer: "security-review",
        category: "correctness",
        line: 44
    )
    private static let dismissed = finding(
        "Nová výjimka `SecretNotFound` nemá test",
        reviewer: "test-coverage",
        category: "test-coverage",
        file: nil,
        line: nil
    )
    private static let unanchored = finding(
        "Migrace nemá `down()`, takže rollback skončí na půl cesty",
        reviewer: "php-review",
        category: "data-loss",
        file: "db/migrations/2026_08_01.php",
        line: 9_000
    )

    private static let blockingGroup = FindingGroup(file: blocking.file, line: blocking.line, findings: [blocking])
    private static let agreedGroup = FindingGroup(
        file: agreed.file,
        line: agreed.line,
        findings: [agreed, agreedSecond]
    )
    private static let unanchoredGroup = FindingGroup(
        file: unanchored.file,
        line: unanchored.line,
        findings: [unanchored]
    )

    private static let dismissals: [FindingKey: FindingDismissal] = [
        Policy.key(of: dismissed): FindingDismissal(
            reason: .irrelevant,
            dismissedAt: Date(timeIntervalSince1970: 1_754_000_000)
        ),
    ]
    private static let rechecks: [FindingKey: RecheckStatus] = [
        Policy.key(of: blocking): RecheckStatus(verdict: .stillApplies, note: "Řádek 41 se nezměnil."),
        Policy.key(of: agreed): RecheckStatus(verdict: .resolved),
    ]

    private static let cardRows = FindingRow.rows(
        of: [blocking, agreed, dismissed],
        dismissals: dismissals,
        rechecks: rechecks
    )
    private static let tableRowModels = FindingTableRow.rows(
        of: [blocking, agreed, agreedSecond, dismissed],
        sort: nil,
        dismissals: dismissals
    )

    private static func comment(_ id: String, _ author: String, _ body: String) -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: body,
            createdAt: Date(timeIntervalSince1970: 1_754_000_000),
            url: URL(string: "https://github.com/keboola/platform/pull/3#discussion_\(id)")!
        )
    }

    /// Vyřešené vlákno s **mým** komentářem: naráz `vyřešeno` i `já`.
    private static let resolvedThread = ReviewThread(
        id: "PRRT_1",
        path: "src/Vault/Encryptor.php",
        line: 41,
        originalLine: 41,
        side: .right,
        isResolved: true,
        isOutdated: false,
        comments: ConversationPage(
            items: [
                comment("1", "odinuv", "Tady chybí test na chybějící klíč."),
                comment("2", viewer, "Doplněno v abc123."),
            ],
            total: 2,
            hasNextPage: false
        )
    )

    /// Zastaralé a **useknuté** vlákno: `zastaralé` i `+12`.
    private static let outdatedThread = ReviewThread(
        id: "PRRT_2",
        path: "src/Queue/Worker.php",
        line: nil,
        originalLine: 128,
        side: .right,
        isResolved: false,
        isOutdated: true,
        comments: ConversationPage(
            items: [comment("3", "vondrous", "Retry logiku to nemění, za mě OK.")],
            total: 13,
            hasNextPage: true
        )
    )

    private static let approval = SubmittedReview(
        id: "PRR_1",
        author: viewer,
        state: .approved,
        body: "Z pohledu fronty OK, retry logiku to nemění.",
        submittedAt: Date(timeIntervalSince1970: 1_754_000_000)
    )
    private static let changes = SubmittedReview(
        id: "PRR_2",
        author: "odinuv",
        state: .changesRequested,
        body: "Ta mez by měla být pojmenovaná na jednom místě, ne dvakrát.",
        submittedAt: Date(timeIntervalSince1970: 1_754_000_000)
    )

    private static let botEvent = TimelineEvent(
        id: "PRE_1",
        kind: .reviewRequested(reviewer: "keboola/platform"),
        actor: EventActor(login: "github-actions", avatarURL: nil, isBot: true),
        at: Date(timeIntervalSince1970: 1_754_000_000)
    )

    // MARK: - Kreslení

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG — tatáž cesta jako
    /// `FindingActionColourProbe`, viz `docs/testovani.md`.
    private func capture(_ scene: some View, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: hosting.fittingSize.height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — vedle sebe běží víc slotů.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}
