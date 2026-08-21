import Foundation
import Testing

@testable import PRism

/// Rozhodnutí o výpisu kroků v tabu `Průběh` (#325) — čistá funkce, tedy vyčerpávající výčet.
///
/// Tři věci, které se dají pokazit potichu a každá znamená, že se na běžící review nedá koukat:
/// **automat přebije klik** (zavřený výpis se při každé události otevře znovu), **doběhnutí zavře
/// výpis** (obrazovka zmizí zrovna ve chvíli, kdy je na ni nejvíc důvodů koukat) a **sledování
/// konce se vypne samo** vůlí v poloze scrollu.
@Suite("Výpis kroků v tabu Průběh")
struct StepFeedTests {
    private func lane(_ skill: String, _ state: ReviewerLane.State, entries: Int = 3) -> ReviewerLane {
        var timeline = ReviewerTimeline(skill: skill)
        let start = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<entries {
            timeline.record(
                .attemptedTool(ToolAttempt(name: "Read", detail: "a\(index).php", id: "t\(index)")),
                at: start + Double(index)
            )
        }
        return ReviewerLane(
            skill: skill,
            state: state,
            phases: [],
            lastTool: nil,
            finishedAt: nil,
            reportedFindings: nil,
            usage: nil,
            sessionID: nil,
            worktree: nil,
            droppedEntries: 0,
            loadedSkill: nil,
            intentGap: nil,
            entries: timeline.entries,
            isConfigured: true
        )
    }

    // MARK: - Co se u dráhy kreslí

    /// Prázdná osa nedostane ani sbalený řádek: `0 kroků session` nabízí rozbalení prázdného okna,
    /// tedy tvrdí, že se něco stalo.
    @Test("Dráha bez osy výpis nemá")
    func laneWithoutEntriesHasNoFeed() {
        let empty = lane("code-review", .notStarted, entries: 0)

        #expect(Policy.stepFeed(of: empty, expansion: StepFeedExpansion()) == .none)
        #expect(Policy.stepFeed(
            of: empty,
            expansion: StepFeedExpansion(expanded: ["code-review"])
        ) == .none)
    }

    @Test("Rozbalení řídí množina na tabu")
    func expansionComesFromTheTab() {
        let running = lane("code-review", .running)

        #expect(Policy.stepFeed(of: running, expansion: StepFeedExpansion()) == .collapsed)
        #expect(Policy.stepFeed(
            of: running,
            expansion: StepFeedExpansion(expanded: ["code-review"])
        ) == .expanded)
    }

    // MARK: - Automatické rozbalení

    /// Výčet přes **všechny** stavy dráhy: rozbalit se má jedině to, co běží.
    @Test("Automat rozbalí jen běžící dráhu", arguments: [
        (ReviewerLane.State.notStarted, false),
        (.missingProgress, false),
        (.queued, false),
        (.running, true),
        (.finished, false),
        (.timedOut, false),
        (.interrupted, false),
        (.failed(detail: "boom"), false),
        (.stopped, false),
    ] as [(ReviewerLane.State, Bool)])
    func opensOnlyRunningLanes(state: ReviewerLane.State, opens: Bool) {
        let next = Policy.stepFeedExpansion(
            StepFeedExpansion(),
            lanes: [lane("code-review", state)]
        )

        #expect(next.expanded.contains("code-review") == opens)
    }

    /// **Nejcennější test téhle sady** (že se něco NEstalo): doběhnutí výpis nezavře.
    @Test("Doběhnutí výpis nezavře")
    func finishingKeepsTheFeedOpen() {
        var state = Policy.stepFeedExpansion(StepFeedExpansion(), lanes: [lane("code-review", .running)])
        #expect(state.expanded == ["code-review"])

        state = Policy.stepFeedExpansion(state, lanes: [lane("code-review", .finished)])

        #expect(state.expanded == ["code-review"])
        // Ale automat už na tom skillu „nevisí“ — příští běh ho dostane znovu.
        #expect(state.opened.isEmpty)
    }

    /// Druhá polovina téhož: **klik automat přebije**. Bez `opened` by se zavřený výpis běžícího
    /// revieweera otevřel příští událostí, tedy do vteřiny.
    @Test("Zavřený výpis běžící dráhy se sám neotevře")
    func closingABusyLaneSticks() {
        let lanes = [lane("code-review", .running)]
        var state = Policy.stepFeedExpansion(StepFeedExpansion(), lanes: lanes)

        state = Policy.toggledStepFeed(state, of: "code-review")
        #expect(state.expanded.isEmpty)

        // Tolik průchodů, kolik jich při běhu proteče za pár sekund.
        for _ in 0..<10 { state = Policy.stepFeedExpansion(state, lanes: lanes) }

        #expect(state.expanded.isEmpty)
    }

    /// Nový běh téhož revieweera (`Pustit znovu`) rozbalení dostane — mezitím z `opened` vypadl.
    @Test("Nový běh rozbalení dostane znovu")
    func aNewRunOpensAgain() {
        var state = Policy.stepFeedExpansion(StepFeedExpansion(), lanes: [lane("code-review", .running)])
        state = Policy.toggledStepFeed(state, of: "code-review")
        state = Policy.stepFeedExpansion(state, lanes: [lane("code-review", .finished)])
        #expect(state.expanded.isEmpty)

        state = Policy.stepFeedExpansion(state, lanes: [lane("code-review", .running)])

        #expect(state.expanded == ["code-review"])
    }

    /// Tři paralelní session se nesmí proplést — každá dráha má vlastní výpis a vlastní rozbalení.
    @Test("Dráhy se neovlivňují")
    func lanesAreIndependent() {
        let state = Policy.stepFeedExpansion(StepFeedExpansion(), lanes: [
            lane("code-review", .running),
            lane("security", .finished),
            lane("tests", .running),
        ])

        #expect(state.expanded == ["code-review", "tests"])
    }

    @Test("Klik otevře a zavře")
    func toggleOpensAndCloses() {
        var state = Policy.toggledStepFeed(StepFeedExpansion(), of: "code-review")
        #expect(state.expanded == ["code-review"])

        state = Policy.toggledStepFeed(state, of: "code-review")
        #expect(state.expanded.isEmpty)
    }

    // MARK: - Sledování konce

    /// Krátký obsah je vždycky „na konci“ — není kam odrolovat, takže by `false` znamenalo, že se
    /// konec nesleduje hned od první události.
    @Test("Obsah kratší než okno je na konci")
    func shortContentCountsAsTheEnd() {
        #expect(Policy.stepFeedAtEnd(offset: 0, visible: 138, content: 40))
        #expect(Policy.stepFeedAtEnd(offset: 0, visible: 138, content: 138))
    }

    @Test("Konec se pozná s vůlí, ne na bod")
    func endHasSlack() {
        // Přesně na konci.
        #expect(Policy.stepFeedAtEnd(offset: 162, visible: 138, content: 300))
        // Zaokrouhlení po rozvržení — pořád konec.
        #expect(Policy.stepFeedAtEnd(offset: 160.5, visible: 138, content: 300))
        // O řádek výš už ne.
        #expect(!Policy.stepFeedAtEnd(offset: 145, visible: 138, content: 300))
        #expect(!Policy.stepFeedAtEnd(offset: 0, visible: 138, content: 300))
    }

    /// Vůle musí být **pod výškou řádku**, jinak se do ní vejde celá událost a „sleduju konec“ by
    /// platilo i nad výpisem, ve kterém poslední krok není vidět.
    @Test("Vůle je menší než řádek výpisu")
    func slackIsSmallerThanARow() {
        #expect(Policy.stepFeedEndSlack < 14)
    }

    // MARK: - Co dělat s tím, co říká geometrie

    /// Vyčerpávající výčet, protože právě tady se dá sledování konce pokazit tak, že se **samo
    /// vypne první událostí** — narostlý obsah je totiž o řádek „mimo konec“.
    @Test("Reakce na geometrii", arguments: [
        // narostlo, poloha, dohání → co se má stát
        (true, true, false, StepFeedReaction.catchUp),
        (true, false, false, .catchUp),
        (true, true, true, .catchUp),
        (true, false, true, .catchUp),
        (false, true, false, .follow(true)),
        (false, false, false, .follow(false)),
        (false, true, true, .ignore),
        (false, false, true, .ignore),
    ] as [(Bool, Bool, Bool, StepFeedReaction)])
    func decidesWhatToDo(grew: Bool, isAtEnd: Bool, isCatchingUp: Bool, expected: StepFeedReaction) {
        #expect(
            Policy.stepFeedReaction(grew: grew, isAtEnd: isAtEnd, isCatchingUp: isCatchingUp) == expected
        )
    }

    /// **Nejcennější dvojice z té tabulky, vypsaná zvlášť:** narostlý obsah sledování konce
    /// **nevypne** (jinak by se vypnulo první událostí) a odrolování **ano** (jinak by se v běžícím
    /// review nedalo přečíst nic, co je o pár kroků výš).
    @Test("Narostlý obsah není odrolování")
    func growthIsNotScrolling() {
        #expect(Policy.stepFeedReaction(grew: true, isAtEnd: false, isCatchingUp: false) == .catchUp)
        #expect(
            Policy.stepFeedReaction(grew: false, isAtEnd: false, isCatchingUp: false) == .follow(false)
        )
    }

    // MARK: - Pilulka „N nových“

    @Test("Se sledovaným koncem se pilulka nekreslí")
    func noPillWhileFollowing() {
        #expect(Policy.stepFeedArrivals(scrolls: true, follows: true, newest: 40, anchor: 10) == nil)
    }

    @Test("Bez kotvy a bez nových událostí taky ne")
    func noPillWithoutArrivals() {
        #expect(Policy.stepFeedArrivals(scrolls: true, follows: false, newest: 40, anchor: nil) == nil)
        #expect(Policy.stepFeedArrivals(scrolls: true, follows: false, newest: nil, anchor: 10) == nil)
        #expect(Policy.stepFeedArrivals(scrolls: true, follows: false, newest: 10, anchor: 10) == nil)
    }

    /// Počítá se z **`id`, ne z počtu událostí**: se stropem počet přestane růst, takže by pilulka
    /// u dlouhého běhu tvrdila, že nepřibylo nic — a to je ta situace, ve které se odroloval nahoru.
    @Test("Pilulka počítá od kotvy")
    func pillCountsFromTheAnchor() {
        #expect(Policy.stepFeedArrivals(scrolls: true, follows: false, newest: 512, anchor: 500) == 12)
    }

    /// **Nekreslí se nad obsahem, který se vejde celý** — pilulka slibuje posun na konec, jenže
    /// v okně bez rolování žádný schovaný konec není. Je to ta samá věc jako schovaný přepínač
    /// `Sledovat konec`, jen na druhém konci výpisu.
    @Test("Bez rolování se pilulka nekreslí ani s nakotvenými událostmi")
    func noPillWithoutScrolling() {
        #expect(Policy.stepFeedArrivals(scrolls: false, follows: false, newest: 512, anchor: 500) == nil)
    }

    // MARK: - Výška okna

    /// Rozměry **schválně kulaté a schválně jiné než v návrhu**: tahle funkce nesmí na konkrétních
    /// číslech záležet a s literály se z výčtu dá přečíst aritmetika — obsah je `10 + 10 × řádky`
    /// a strop padne mezi devátý a desátý řádek. Že strop **není celý počet řádků**, je jako
    /// v návrhu (hrana usekne řádek, takže je poznat, že se roluje); pro samotný výpočet to hraje
    /// roli jen na hranici, a ta má vlastní test.
    ///
    /// Že se ty **skutečné** rozměry shodují s tím, co výpis nakreslí, tvrdí `StepFeedWindowTests`
    /// na hostovaném okně — tady by to byla druhá kopie čísel.
    private let metrics = StepFeedMetrics(row: 10, cut: 20, inset: 5, cap: 105)

    /// Kolik řádků se do stropu ještě vejde. Dopočítané z rozměrů, aby test nedržel třetí číslo.
    private var rowsInsideTheCap: Int {
        Int((metrics.cap - 2 * metrics.inset) / metrics.row)
    }

    /// **Připomínka z proklikání #402**: krátký běh nesmí nakreslit okno s dvěma třetinami prázdna.
    @Test("Krátký běh dostane okno o výšce obsahu")
    func shortRunGetsAShortWindow() {
        let window = Policy.stepFeedWindow(rows: 3, cut: false, metrics: metrics)

        #expect(window.height == 2 * metrics.inset + 3 * metrics.row)
        #expect(window.height < metrics.cap)
        // Vejde se celý, takže není co rolovat — a tím padá i přepínač a pilulka.
        #expect(!window.scrolls)
    }

    @Test("Prázdný výpis je jen vzduch, ne strop")
    func emptyFeedIsJustTheInset() {
        let window = Policy.stepFeedWindow(rows: 0, cut: false, metrics: metrics)

        #expect(window.height == 2 * metrics.inset)
        #expect(!window.scrolls)
    }

    @Test("Řez na začátku se do výšky počítá")
    func theCutCountsTowardsTheHeight() {
        let plain = Policy.stepFeedWindow(rows: 3, cut: false, metrics: metrics)
        let withCut = Policy.stepFeedWindow(rows: 3, cut: true, metrics: metrics)

        #expect(withCut.height == plain.height + metrics.cut)
    }

    @Test("Dlouhý běh se zastaví na stropu")
    func longRunStopsAtTheCap() {
        let window = Policy.stepFeedWindow(rows: 300, cut: true, metrics: metrics)

        #expect(window.height == metrics.cap)
        #expect(window.scrolls)
    }

    /// **Nejcennější test téhle sekce** (že se něco NEstalo): okno na hranici stropu **neposkočí**
    /// o řádek tam a zpět. Roste monotónně, na stropu se zastaví a od té chvíle ho žádná další
    /// událost nezmenší ani nezvětší — proto se výška počítá z **dat**, ne z výšky obsahu hlášené
    /// scrollem, která se při rozvržení mění i naplano (`1825 → 3505 → 1825`).
    @Test("Na hranici stropu okno nekmitá")
    func theWindowDoesNotFlickerAtTheCap() {
        let heights = (0...40).map { Policy.stepFeedWindow(rows: $0, cut: false, metrics: metrics) }

        for (rows, window) in heights.enumerated().dropFirst() {
            let previous = heights[rows - 1]
            #expect(window.height >= previous.height, "výška klesla mezi \(rows - 1) a \(rows) řádky")
            #expect(window.height <= metrics.cap)
            // Jednou dojetý strop se už nemění — a s ním ani odpověď na „je co rolovat“.
            if previous.height == metrics.cap {
                #expect(window.height == metrics.cap)
                #expect(window.scrolls)
            }
        }
        #expect(heights[rowsInsideTheCap].height < metrics.cap)
        #expect(heights[rowsInsideTheCap + 1].height == metrics.cap)
    }

    /// Rolovat se začne přesně tam, kde obsah strop **přeroste** — o řádek dřív ne. Kdyby se
    /// `scrolls` rozešel s výškou, byl by na obrazovce přepínač bez rolování (nebo naopak).
    @Test("Rolování začíná až za stropem")
    func scrollingStartsPastTheCap() {
        #expect(!Policy.stepFeedWindow(rows: rowsInsideTheCap, cut: false, metrics: metrics).scrolls)
        #expect(Policy.stepFeedWindow(rows: rowsInsideTheCap + 1, cut: false, metrics: metrics).scrolls)
    }

    /// Obsah **přesně** na strop se neroluje, a proto je v podmínce `>`, ne `>=`: okno je vysoké
    /// jako obsah, takže je vidět celý — přepínač `Sledovat konec` by nad ním nabízel posun tam,
    /// kde už výpis je.
    @Test("Obsah přesně na strop se neroluje")
    func contentExactlyAtTheCapDoesNotScroll() {
        // Devět řádků a odsazení sedne na strop na bod.
        let exact = StepFeedMetrics(row: 10, cut: 20, inset: 5, cap: 100)

        let window = Policy.stepFeedWindow(rows: 9, cut: false, metrics: exact)

        #expect(window.height == exact.cap)
        #expect(!window.scrolls)
    }
}
