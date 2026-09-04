import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sonda, ne test (#291): vykreslí **desku** (#515) s blokem `Dění` (#443), aby se dala
/// **vidět** a položit vedle sekce 45 návrhu.
///
/// Existuje proto, že `BoardSeparatorTests` odpovídá na „kolik je čar a jsou stejně silné“
/// a `ActivityRowShapeTests` na „vejde se úzký řádek na jednu řádku a co v něm není“, kdežto
/// otázka *jak to vedle sebe vypadá* se z čísla nepozná. Od #515 je ta otázka ostřejší: vpravo
/// v hlavičce pruhu stojí **akce s počtem a kapslí klávesy**, a to je první věc, která se do
/// zúženého pruhu nevejde.
///
/// **`NSHostingView` a `cacheDisplay`, ne `ImageRenderer`**: deska je `ScrollView` a ten se
/// offscreen nerasterizuje (změřeno u #237).
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`, cesta ven přes `TEST_RUNNER_PRISM_RENDER_DIR`.
@MainActor
@Suite(
    "Sonda desky podle mého tahu (#515)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct BoardRenderProbe {
    /// Šířka okna z návrhu (deska má v mockupu 1134 bodů obsahu), k ní užší okno, ve kterém
    /// pravý sloupec spadne pod 456 bodů — právě tam se pozná, jestli se ořezává titulek, nebo
    /// souřadnice — a od #515 **nejužší povolené okno**: podlaha je 700 bodů (`RootView`)
    /// a rail z ní ubere 64, takže na desku zbývá kolem 636. Akce v hlavičce pruhu
    /// (`Pustit review na 6 ⌘⇧R`) je nejdelší prvek desky, takže se právě tady pozná, jestli
    /// z ní ustoupí nadpis, počet, nebo ona sama.
    private let widths: [CGFloat] = [1240, 900, 636]

    /// Šest scén, a **dvě z nich vyrábí až skrývání prázdných pruhů** (z proklikání #515):
    /// ke stavu, na kterém není ani jeden pruh, ani k tomu s jediným se klikáním nedostaneš,
    /// protože fronta si o svůj obsah neřekne.
    private enum Scenario: String, CaseIterable {
        /// Tři pruhy ze šesti: draft, doběhlé review a zbytek `neběželo`. Vidět je na ní
        /// **nové pořadí** (`Dopsat a odeslat` nad `Rozhodnout` nad `Přečíst`) a to, že tři
        /// prázdné pruhy na obrazovce nejsou.
        case lanes = "pruhy"
        /// Jediný neprázdný pruh — na tomhle se pozná, jestli deska s jedním blokem není spíš
        /// oznámení než seznam.
        case single = "jediny-pruh"
        /// Není ani jeden pruh: místo šesti rámečků s nulou jedna věta, že je vyřízeno.
        case everythingDone = "hotovo"
        /// Prázdný blok `Dění`: jediné místo, kde z celé sekce zbude jedna věta, a věta pod
        /// hlavičkou vypadá jinak než nakreslený seznam.
        case activityEmpty = "prazdne-deni"
        /// **Vlastní PR, který je slévatelný a přitom na něm zbývá něco nevyřízeného předat** —
        /// tedy stav předání `changed`. Otázka, na kterou scéna odpovídá, je „je v `K merge`
        /// pořád vidět, že něco zbývá?“; klikáním se k ní člověk dostane jedině nad vlastním PR
        /// se zeleným CI.
        ///
        /// **Právě `changed`, ne `never`** (druhé proklikání #515): `never` byl případ z prvního
        /// proklikání a do `K merge` chodil i předtím, kdežto `changed` je ten, který v pruhu
        /// `Předat agentovi` **zůstával** — takže je to jediná scéna, na které je změna vidět.
        case mergeWithHandoff = "k-merge-s-predanim"
        /// **Všech šest pruhů neprázdných** — jediná scéna, na které je vidět **pořadí**.
        ///
        /// Přidaná u druhého proklikání #515, a je to odpověď na druhou otázku z #478: scéna
        /// `pruhy` má `Předat agentovi` i `Čeká na ostatní` prázdné, takže by přesunem jednoho
        /// z nich **nenaměřila nic** — vypadala by stejně před i po. Tady se `Předat agentovi`
        /// musí kreslit **nad** tichým pruhem, tedy jako **pátý** (třetí proklikání ho vrátilo
        /// z konce; poslední místo bylo špatně přeložený pokyn o posledním *pravidle*).
        case allLanes = "vsechny-pruhy"
    }

    @Test("Vyrendrovat desku do PNG")
    func rendersTheBoard() async throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["PRISM_RENDER_DIR"] ?? NSTemporaryDirectory())
        for width in widths {
            for dark in [false, true] {
                for scenario in Scenario.allCases {
                    let store = await store(scenario)
                    let url = directory.appending(
                        path: "deska-\(Int(width))-\(dark ? "tmavy" : "svetly")-\(scenario.rawValue).png"
                    )
                    try write(store: store, width: width, dark: dark, to: url)
                    print("SONDA \(url.path)")
                }
            }
        }
    }

    /// Scéna do okna mimo obrazovku a odtud `cacheDisplay` do PNG.
    ///
    /// **Barevný režim se nastavuje dvakrát**: `NSAppearance` kvůli paletě (dynamické `NSColor`)
    /// a `colorScheme` kvůli `.primary`/`.secondary`. S jedním z toho vyjde tmavý text na tmavém.
    private func write(store: AppStore, width: CGFloat, dark: Bool, to url: URL) throws {
        let scene = BoardView(store: store, open: { _ in })
            .frame(width: width, height: Self.height)
            .environment(\.colorScheme, dark ? .dark : .light)
            .tint(Palette.accent)
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var thrown: Error?
        appearance.performAsCurrentDrawingAppearance {
            do {
                try capture(scene, width: width, to: url)
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
    }

    private func capture(_ scene: some View, width: CGFloat, to url: URL) throws {
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: Self.height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        // Mimo obrazovku, ať sonda nikomu neskočí před oči — vedle sebe běží víc instancí aplikace.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontUnanimated()
        defer { window.orderOut(nil) }
        // Hierarchie se doskládá až za pár koly smyčky; sonda nic netvrdí, takže stačí odmlka.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    /// Store s frontou a se záznamem dění, jak ho kreslí sekce 31 — od #515 osm řádků a patka
    /// `+34` (do #515 pět a `+37`; položek je pořád dvaačtyřicet).
    ///
    /// Fronta má sedm PR schválně: levý sloupec je pak vysoký jako v mockupu, takže je na obrázku
    /// vidět i to, kvůli čemu se blok stěhoval — kolik prázdna pod `Co teď` zbývalo.
    private func store(_ scenario: Scenario) async -> AppStore {
        let count = switch scenario {
        case .everythingDone: 0
        case .single, .mergeWithHandoff: 1
        case .allLanes: 6
        case .lanes, .activityEmpty: 7
        }
        let queue = (1..<(1 + count)).map { number in
            PullRequestSummary(
                id: PRIdentifier(repo: RepoID("keboola/vault")!, number: number),
                title: "chore: modernize dependencies (Symfony 8-ready)",
                // U scény `k-merge-s-predanim` musí být PR **můj**, jinak se do vlastních pruhů
                // nedostane vůbec (#332). U `vsechny-pruhy` je vlastní **první, pátý a šestý**
                // (`K merge`, `Předat agentovi`, `Čeká na ostatní`) — kdo je čí, rozhoduje
                // o polovině pruhů.
                author: Self.author(of: number, in: scenario),
                url: URL(string: "https://github.com/keboola/vault/pull/\(number)")!,
                updatedAt: Date(timeIntervalSince1970: Double(number) * 100),
                state: .open
            )
        }
        // **Hodiny musí jít teď**, i když jsou falešné: `Text(_:format: .relative)` se počítá proti
        // skutečnému kalendáři, kdežto `Policy.activityTime` proti `store.time.now`. S výchozím
        // rokem 1970 by ty dvě odpovědi mířily každá jinam a `včera v 7:58` by se v renderu
        // ukázalo jako `včera` — tedy zrovna to, kvůli čemu sonda vznikla.
        var configuration = Configuration.standard
        // **Bez mých loginů je všechno cizí** (`ownership(ofAuthor:mine:)`), takže scéna
        // o vlastních pruzích je musí nastavit — jinak by vyrendrovala `Přečíst`.
        configuration.global.ownLogins = ["ondrajodas"]
        let store = AppStore(
            gateway: FakeGitHubGateway(always: .success(queue)),
            configuration: configuration,
            time: FakeTimeSource(start: Date())
        )
        await store.refresh()
        if scenario == .lanes, let first = queue.first?.id, let second = queue.dropFirst().first?.id {
            // Draft posadí PR do `Dopsat a odeslat` (přebíjí všechno), uložený běh do
            // `Rozhodnout` — zbytek zůstane v `Přečíst`. Tři pruhy tedy stojí a tři chybí,
            // což je přesně to, co má být na obrázku vidět.
            // **Draft se sází přímo do `drafts`**, ne přes `setDraftBody`: ta cesta si bere
            // `headSha` z **načteného** detailu (`mutateDraft`), a sonda detail nenačítá — bez
            // toho by draft tiše nevznikl a pruh `Dopsat a odeslat` by na obrázku chyběl.
            store.drafts[first] = ReviewDraft(
                pullRequest: first,
                headSha: "aaaa1111",
                body: "Zbytek vypadá dobře, jen ta jedna kontrola."
            )
            store.reviewRecords[second] = ReviewRecord(
                pullRequest: second,
                headSha: "aaaa1111",
                runs: [makeStoredRun(findings: [], headSha: "aaaa1111")]
            )
        }
        if scenario == .mergeWithHandoff, let id = queue.first?.id {
            // **Slévatelnost se skládá ze čtyř vstupů** (`Policy.mergeOffer`), takže se sázejí
            // všechny — jinak by z předfiltru vyšlo `factsMissing` a PR by spadl do `Čeká na
            // ostatní`. Brána odesílání zapnutá být nemusí: `notAllowed` není překážka
            // pull requestu (`MergeObstacle.isPublishingGate`).
            store.detailStates[id] = .loaded(Self.mergeableDetail(id), updatedAt: Date())
            store.branchStatuses[id] = .loaded(
                BranchStatus(mergeability: .mergeable, mergeState: .clean),
                updatedAt: Date()
            )
            store.checks[id] = []
            store.commits[id] = []
            // Dva aktivní nálezy a k nim razítko **proti dnešní hlavě, ale bez předaných
            // identit** — z toho `Policy.handoff` složí `2 k předání` ve stavu `changed`, tedy
            // „něco je nevyřízené“. Ten stav do druhého proklikání #515 držel PR v `Předat
            // agentovi` i nad slévatelnou větví; od té doby vyhrává merge a pilulka řádku
            // zůstane, protože visí na autorovi a počtu, ne na stavu předání.
            //
            // **Ani jeden z nich nesmí být blokující** (`Policy.defaultBlockingCategories`:
            // `correctness`, `security`, `data-loss`) — blokující nález je **skutečná** překážka
            // merge (`MergeObstacle.blockingFindings`), takže by scéna neukázala nový případ, ale
            // starý. Přesně tak vypadal i PR z proklikání: `2 k předání` bez odznaku `blokuje`.
            store.reviewRecords[id] = ReviewRecord(
                pullRequest: id,
                headSha: Self.mergeableHead,
                runs: [makeStoredRun(
                    findings: [
                        makeReported(category: "clarity", summary: "Ta věta v komentáři mluví o starém názvu."),
                        makeReported(category: "docs", summary: "Popis nemluví o novém příznaku.")
                    ],
                    headSha: Self.mergeableHead
                )]
            )
            // **Razítko se sází přímo do `handoffStamps`**, ne přes `noteHandoff(of:)`: ta cesta
            // si bere hlavu i identity ze složeného zadání, a sonda žádné neskládá. `handed: []`
            // je záměr — kdyby v něm ty dvě položky byly, vyšel by z toho `delivered`, tedy
            // „předáno a nic nového“, a scéna by ukazovala prázdnou pilulku.
            store.handoffStamps[id] = Handoff(at: Date(), headSha: Self.mergeableHead, handed: [])
        }
        if scenario == .allLanes {
            setUpAllLanes(in: store, ids: queue.map(\.id))
        }
        guard scenario != .activityEmpty else { return store }
        store.activityEvents = Self.events
        return store
    }

    /// Autor pull requestu ve scéně. **U `vsechny-pruhy` rozhoduje o polovině pruhů**, protože
    /// vlastní PR se do `Rozhodnout` ani `Přečíst` nedostane a cizí do zbylých tří ne (#332).
    private static func author(of number: Int, in scenario: Scenario) -> String {
        switch scenario {
        case .mergeWithHandoff: "ondrajodas"
        case .allLanes: [1, 5, 6].contains(number) ? "ondrajodas" : "odinuv"
        case .lanes, .single, .everythingDone, .activityEmpty: "odinuv"
        }
    }

    /// Šest PR do šesti pruhů, po jednom řádku — scéna, na které je vidět **pořadí**.
    ///
    /// Rozřazuje je `Policy.lane`, ne sonda, takže se sází jedině vstupy: (1) můj PR se vším,
    /// co si žádá slévatelnost → `K merge`; (2) cizí s draftem → `Dopsat a odeslat` (draft
    /// přebíjí všechno); (3) cizí s uloženým čistým během → `Rozhodnout`; (4) cizí, na kterém se
    /// nic nestalo → `Přečíst`; (5) můj s aktivním nálezem a **bez načteného detailu** →
    /// `Předat agentovi`; (6) můj bez detailu i bez nálezů → `Čeká na ostatní` („nevím“ je
    /// `waiting`).
    private func setUpAllLanes(in store: AppStore, ids: [PRIdentifier]) {
        store.detailStates[ids[0]] = .loaded(Self.mergeableDetail(ids[0]), updatedAt: Date())
        store.branchStatuses[ids[0]] = .loaded(
            BranchStatus(mergeability: .mergeable, mergeState: .clean),
            updatedAt: Date()
        )
        store.checks[ids[0]] = []
        store.commits[ids[0]] = []
        // **Draft se sází přímo do `drafts`** — `setDraftBody` si bere `headSha` z načteného
        // detailu a ten scéna u tohohle PR nemá.
        store.drafts[ids[1]] = ReviewDraft(
            pullRequest: ids[1],
            headSha: Self.mergeableHead,
            body: "Zbytek vypadá dobře, jen ta jedna kontrola."
        )
        store.reviewRecords[ids[2]] = ReviewRecord(
            pullRequest: ids[2],
            headSha: Self.mergeableHead,
            runs: [makeStoredRun(findings: [], headSha: Self.mergeableHead)]
        )
        // ids[3] zůstává, jak přišel z fronty: `neběželo`, tedy `Přečíst`.
        // ids[5] je můj PR, o kterém se nedá tvrdit ani předání, ani merge — tichý pruh.
        store.reviewRecords[ids[4]] = ReviewRecord(
            pullRequest: ids[4],
            headSha: Self.mergeableHead,
            runs: [makeStoredRun(
                findings: [makeReported(category: "clarity", summary: "Ten komentář mluví o starém názvu.")],
                headSha: Self.mergeableHead
            )]
        )
    }

    private static let mergeableHead = "aaaa1111"

    /// Detail vlastního PR **bez jakékoli překážky**: otevřený, ne draft, ne fork, s větví.
    private static func mergeableDetail(_ id: PRIdentifier) -> PullRequest {
        PullRequest(
            id: id,
            title: "[AJDA-3077] Deduplicate shared logic across task-scoping operators",
            author: "ondrajodas",
            headSha: mergeableHead,
            baseSha: "bbbb2222",
            headRef: "ondra/AJDA-3077",
            baseRef: "main",
            url: URL(string: "https://github.com/keboola/vault/pull/\(id.number)")!,
            updatedAt: Date(),
            state: .open,
            isCrossRepository: false
        )
    }

    /// Položky ze sekce 31 doslova — a pátá **ze včerejška**, protože právě na ní je vidět den
    /// u času (`včera v 7:58`). Podrobnost, sha, chip `bez banneru` i autor v nich zůstávají
    /// schválně, i když je úzký tvar nekreslí: sonda tím ukazuje, že se **vynechávají při kresbě**,
    /// ne že by v záznamu nebyly.
    private static var events: [ActivityEvent] {
        let now = Date()
        var events = [
            ActivityEvent(
                id: "staleFindings|keboola/vault#85|9c1f0ab",
                kind: .staleFindings,
                pullRequest: PRIdentifier("keboola/vault#85")!,
                at: now.addingTimeInterval(-120),
                headline: "Nálezy zastaraly",
                detail: "přišly 3 commity, hlava je teď",
                head: "9c1f0ab2d4e5f60718293a4b5c6d7e8f90a1b2c3"
            ),
            ActivityEvent(
                id: "foreignActivity|keboola/app-project-restore#91|1",
                kind: .foreignActivity,
                pullRequest: PRIdentifier("keboola/app-project-restore#91")!,
                at: now.addingTimeInterval(-900),
                headline: "odinuv: opravdu to potřebuje ten mutex?",
                detail: "a 1 review od Copilota",
                wasAnnounced: true
            ),
            ActivityEvent(
                id: "findings|keboola/vault#85|2",
                kind: .findings,
                pullRequest: PRIdentifier("keboola/vault#85")!,
                at: now.addingTimeInterval(-1200),
                headline: "3 nálezy · 1 blokuje",
                detail: "php-review, security-review",
                wasAnnounced: true
            ),
            ActivityEvent(
                id: "newPullRequest|keboola/vault#85|3",
                kind: .newPullRequest,
                pullRequest: PRIdentifier("keboola/vault#85")!,
                at: now.addingTimeInterval(-3600),
                headline: "Nový PR k review",
                detail: "chore: modernize dependencies (Symfony 8-ready)",
                wasAnnounced: true,
                author: "odinuv"
            ),
            ActivityEvent(
                id: "clean|keboola/job-queue-api#402|4",
                kind: .clean,
                pullRequest: PRIdentifier("keboola/job-queue-api#402")!,
                at: yesterdayMorning(before: now),
                headline: "Čisté review",
                detail: "3 skilly · 1,04 $",
                wasAnnounced: false
            )
        ]
        // Zbytek záznamu, ať je patka na obrázku vidět. Do #515 z toho vyšlo `+37` jako v sekci
        // 31; od #515 je strop osm řádků, takže z týchž dvaačtyřiceti položek vyjde `+34`.
        events += (0..<37).map { index in
            ActivityEvent(
                id: "reReview|keboola/connection#\(200 + index)|old",
                kind: .reReview,
                pullRequest: PRIdentifier("keboola/connection#\(200 + index)")!,
                at: now.addingTimeInterval(-2 * 86_400 - Double(index) * 60),
                headline: "Znovu k review",
                detail: "fix: rate limiting on the storage API",
                wasAnnounced: true,
                author: "odinuv"
            )
        }
        return events
    }

    /// Včera v 7:58 — ten okamžik z mockupu, ne „o den zpátky“: den se dopisuje podle kalendáře,
    /// takže odečtení 24 hodin by v době kolem půlnoci padlo na dnešek.
    private static func yesterdayMorning(before now: Date) -> Date {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        return calendar.date(bySettingHour: 7, minute: 58, second: 0, of: yesterday) ?? yesterday
    }

    private static let height = 1100.0
}
