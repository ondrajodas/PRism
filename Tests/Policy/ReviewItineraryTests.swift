import Foundation
import Testing

@testable import PRism

/// Zastávky itineráře review (#506) — **matice vstupů**, protože je to čistá funkce a je to
/// jediné místo, kde se rozhoduje, co má člověk dělat dřív.
///
/// Testuje se **přítomnost** zastávky (která v seznamu je a která ne) a **hotovost** (kdy je ✓).
/// Ty dvě otázky se schválně nemíchají: zastávka může být v seznamu a nehotová, ale nikdy hotová
/// a mimo seznam — a právě to druhé by tiše snížilo jmenovatele počítadla `4 z 9`.
@Suite("Policy — itinerář review (#506)")
struct ReviewItineraryTests {
    /// Fakta o PR, který má všechno: návštěvu s commity, popis, sedm souborů, zelené CI.
    private var full: ItineraryFacts {
        ItineraryFacts(
            hasVisitRecord: true,
            commitsSinceVisit: 3,
            sawChangesSinceVisit: false,
            descriptionKnown: true,
            hasDescription: true,
            descriptionScrolled: false,
            fileCount: 7,
            readFileCount: 0,
            unreadLineCount: 210,
            checks: ChecksSummary(passed: 12, failed: 0, running: 0, skipped: 0),
            openedFailedChecks: 0,
            verdictSubmitted: false,
            verdict: .approve
        )
    }

    private func kinds(_ facts: ItineraryFacts) -> [ItineraryStop.Kind] {
        Policy.itinerary(facts).map(\.kind)
    }

    private func stop(_ kind: ItineraryStop.Kind, in facts: ItineraryFacts) -> ItineraryStop? {
        Policy.itinerary(facts).first { $0.kind == kind }
    }

    // MARK: - Které zastávky v seznamu jsou

    /// Pořadí je pevné a je to pořadí čtení, ne důležitosti.
    @Test("Plné PR má pět zastávek v pořadí z návrhu")
    func fullPullRequestHasAllFiveStops() {
        #expect(kinds(full) == [.sinceLastVisit, .description, .files, .checks, .verdict])
    }

    /// **Tohle je to tvrzení ze zadání**: bez záznamu návštěvy zastávka `Od minule` v itineráři
    /// není, i když commity „od minule“ nějaké přišly. Bez záznamu není proti čemu měřit —
    /// „od tvé poslední návštěvy“ nad prvním otevřením by znamenalo „od začátku věků“.
    @Test("Bez záznamu návštěvy Od minule v itineráři není")
    func withoutAVisitRecordThereIsNoSinceLastVisitStop() {
        var facts = full
        facts.hasVisitRecord = false
        #expect(!kinds(facts).contains(.sinceLastVisit))
        #expect(kinds(facts) == [.description, .files, .checks, .verdict])
    }

    /// A druhá polovina téže podmínky (#171): záznam je, ale nic nepřišlo.
    @Test("Bez commitů od minule Od minule v itineráři není")
    func withoutNewCommitsThereIsNoSinceLastVisitStop() {
        var facts = full
        facts.commitsSinceVisit = 0
        #expect(!kinds(facts).contains(.sinceLastVisit))
    }

    /// **Force push se počítá jako commit** — je to změna kódu, kterou jsem neviděl, a navíc ta
    /// nejzávažnější. Store ho proto sčítá s commity a itinerář ho pak nemůže přeskočit.
    @Test("Od minule vznikne i nad samotným force pushem")
    func forcePushAloneIsEnoughForTheStop() {
        var facts = full
        facts.commitsSinceVisit = 1
        #expect(kinds(facts).contains(.sinceLastVisit))
    }

    /// #306: bez CI se `Kontroly` nekreslí. Prázdná zastávka by navíc **zvedla jmenovatele**
    /// počítadla o práci, která na tomhle PR není.
    @Test("PR bez CI nemá zastávku Kontroly")
    func pullRequestWithoutChecksHasNoChecksStop() {
        var facts = full
        facts.checks = ChecksSummary(passed: 0, failed: 0, running: 0, skipped: 0)
        #expect(!kinds(facts).contains(.checks))
        #expect(kinds(facts) == [.sinceLastVisit, .description, .files, .verdict])
    }

    /// **Přeskočené checky jsou pořád CI.** `gh` u velkých PR vrací většinu checků přeskočených
    /// (změřeno u #209: 28 checků, 22 přeskočených) a zastávka nad nimi má co říct — přeskočený
    /// build znamená, že se nic neověřilo.
    @Test("Samé přeskočené checky zastávku Kontroly udrží")
    func skippedChecksStillCount() {
        var facts = full
        facts.checks = ChecksSummary(passed: 0, failed: 0, running: 0, skipped: 22)
        #expect(kinds(facts).contains(.checks))
        #expect(stop(.checks, in: facts)?.detail == "přeskočeno")
    }

    /// Popis, soubory a verdikt jsou vždycky — i nad PR, který nemá nic.
    @Test("Prázdné PR má tři zastávky")
    func emptyPullRequestKeepsTheThreeUnconditionalStops() {
        #expect(kinds(ItineraryFacts()) == [.description, .files, .verdict])
    }

    // MARK: - Kdy je zastávka hotová

    @Test("Od minule je hotové, až když jsem přírůstek viděl")
    func sinceLastVisitIsDoneOnlyAfterSeeingTheChanges() {
        var facts = full
        #expect(stop(.sinceLastVisit, in: facts)?.state == .current)
        facts.sawChangesSinceVisit = true
        #expect(stop(.sinceLastVisit, in: facts)?.state == .done)
    }

    @Test("Popis je hotový po odscrollování na konec")
    func descriptionIsDoneAfterScrollingToTheEnd() {
        var facts = full
        #expect(stop(.description, in: facts)?.state != .done)
        facts.descriptionScrolled = true
        #expect(stop(.description, in: facts)?.state == .done)
    }

    /// **Chybějící popis se neodškrtne odscrollováním.** Prázdná karta se doroluje na konec
    /// hned, takže bez téhle podmínky by PR bez popisu vypadalo, že jsem záměr přečetl — a jediné,
    /// co se s chybějícím záměrem dá udělat, je zeptat se autora.
    @Test("PR bez popisu má zastávku nehotovou i po odscrollování")
    func missingDescriptionIsNeverDone() {
        var facts = full
        facts.hasDescription = false
        facts.descriptionScrolled = true
        #expect(stop(.description, in: facts)?.state != .done)
        #expect(stop(.description, in: facts)?.detail == "bez popisu")
    }

    /// **Nenačtený detail o popisu netvrdí nic** — `bez popisu` nad obrazovkou, kterou si
    /// aplikace zrovna stahuje, je text, který data neunesou.
    @Test("Nenačtený detail nepíše bez popisu")
    func unknownDescriptionSaysNothing() {
        var facts = full
        facts.descriptionKnown = false
        facts.hasDescription = false
        #expect(stop(.description, in: facts)?.detail == nil)
    }

    @Test("Soubory jsou hotové, až když jsou prošlé všechny")
    func filesAreDoneWhenEveryFileIsRead() {
        var facts = full
        facts.readFileCount = 6
        #expect(stop(.files, in: facts)?.state != .done)
        facts.readFileCount = 7
        #expect(stop(.files, in: facts)?.state == .done)
    }

    /// **Nenačtený diff hotový není**, i když je prošlých nula ze nuly: nula souborů znamená
    /// „ještě nevím, kolik jich je“, ne „nic ke čtení“.
    @Test("Nenačtený diff nechává zastávku Soubory otevřenou")
    func unloadedDiffLeavesTheFilesStopOpen() {
        var facts = full
        facts.fileCount = 0
        facts.readFileCount = 0
        #expect(stop(.files, in: facts)?.state != .done)
        #expect(stop(.files, in: facts)?.detail == nil)
    }

    @Test("Zelené CI je hotové rovnou")
    func passingChecksAreDoneRightAway() {
        #expect(stop(.checks, in: full)?.state == .done)
        #expect(stop(.checks, in: full)?.detail == "12 prošlo")
    }

    /// **Spadlý check je hotový, teprve když se rozbalí** — a to je ta věc, kterou se u červeného
    /// buildu přeskakuje. `1 spadl` přebíjí `11 prošlo`: podle nejhoršího, ne podle většiny.
    @Test("Spadlý check je hotový až po rozbalení")
    func failedChecksNeedToBeOpened() {
        var facts = full
        facts.checks = ChecksSummary(passed: 11, failed: 1, running: 0, skipped: 0)
        #expect(stop(.checks, in: facts)?.state != .done)
        #expect(stop(.checks, in: facts)?.detail == "1 spadl")
        facts.openedFailedChecks = 1
        #expect(stop(.checks, in: facts)?.state == .done)
    }

    /// Dva spadlé a jeden otevřený je pořád nehotovo.
    @Test("Rozbalit jeden ze dvou spadlých nestačí")
    func openingOneOfTwoFailedChecksIsNotEnough() {
        var facts = full
        facts.checks = ChecksSummary(passed: 0, failed: 2, running: 0, skipped: 0)
        facts.openedFailedChecks = 1
        #expect(stop(.checks, in: facts)?.state != .done)
    }

    /// **Běžící CI hotové není, ani když nic nespadlo**: není co uzavřít, výsledek se ještě
    /// nezná.
    @Test("Běžící CI zastávku neuzavře")
    func runningChecksAreNeverDone() {
        var facts = full
        facts.checks = ChecksSummary(passed: 5, failed: 0, running: 2, skipped: 0)
        #expect(stop(.checks, in: facts)?.state != .done)
        #expect(stop(.checks, in: facts)?.detail == "2 běží")
    }

    @Test("Verdikt je hotový po odeslání a píše odesláno")
    func verdictIsDoneOnceSubmitted() {
        var facts = full
        #expect(stop(.verdict, in: facts)?.detail == "návrh: schválit")
        facts.verdictSubmitted = true
        #expect(stop(.verdict, in: facts)?.state == .done)
        #expect(stop(.verdict, in: facts)?.detail == "odesláno")
    }

    /// **Bez návrhu se u verdiktu nepíše nic.** `suggestedVerdict` vrací `nil` tehdy, když není
    /// z čeho soudit (spadlý reviewer, ztracený nález), a napsat tam `Schválit` je ta nejdražší
    /// chyba, kterou tahle aplikace umí udělat.
    @Test("Bez návrhu verdikt mlčí")
    func verdictWithoutASuggestionSaysNothing() {
        var facts = full
        facts.verdict = nil
        #expect(stop(.verdict, in: facts)?.detail == nil)
    }

    // MARK: - Aktuální zastávka

    /// `current` je **první nehotová**, ostatní nehotové jsou `todo`. Itinerář je dráha, takže
    /// „kde jsem“ má jednu odpověď.
    @Test("Aktuální je právě jedna, a to první nehotová")
    func exactlyOneStopIsCurrent() {
        var facts = full
        facts.sawChangesSinceVisit = true
        let stops = Policy.itinerary(facts)
        #expect(stops.count { $0.state == .current } == 1)
        #expect(stops.first { $0.state == .current }?.kind == .description)
        #expect(stops.first?.state == .done)
    }

    /// **Hotový itinerář nemá aktuální zastávku** — dráha došla do konce a nemá kde stát.
    @Test("Hotový itinerář nemá aktuální zastávku")
    func finishedItineraryHasNoCurrentStop() {
        var facts = full
        facts.sawChangesSinceVisit = true
        facts.descriptionScrolled = true
        facts.readFileCount = facts.fileCount
        facts.verdictSubmitted = true
        let stops = Policy.itinerary(facts)
        #expect(stops.allSatisfy { $0.state == .done })
    }

    /// Zastávka **za** aktuální je `todo`, i když je sama hotová jako data — hotová je hotová,
    /// takže `Kontroly` nad zeleným CI zůstanou ✓ i uprostřed nedokončeného itineráře. Právě
    /// proto se `current` počítá z pořadí a ne z „poslední hotové“.
    @Test("Hotová zastávka za aktuální zůstává hotová")
    func doneStopsAfterTheCurrentOneStayDone() {
        let stops = Policy.itinerary(full)
        #expect(stops.first { $0.kind == .sinceLastVisit }?.state == .current)
        #expect(stops.first { $0.kind == .checks }?.state == .done)
        #expect(stops.first { $0.kind == .description }?.state == .todo)
    }

    // MARK: - Počítadlo a čas

    /// **Jednotkou počítadla je soubor, ne zastávka.** `4 z 9` má být počet věcí, které se
    /// doopravdy čtou: 7 souborů + `Od minule` + `Popis` + `Kontroly` + `Verdikt` = 11.
    @Test("Počítadlo počítá soubory, ne zastávky")
    func progressCountsFilesNotStops() {
        var facts = full
        facts.sawChangesSinceVisit = true
        facts.readFileCount = 3
        let progress = Policy.itineraryProgress(of: Policy.itinerary(facts), facts: facts)
        // Hotovo: `Od minule`, `Kontroly` (zelené CI) a tři prošlé soubory.
        #expect(progress.done == 5)
        #expect(progress.total == 11)
        #expect(Policy.itineraryHeading(progress).hasPrefix("Itinerář · 5 z 11 · "))
    }

    /// Nenačtený diff do počítadla soubory nepřináší — a čas se pak neodhaduje vůbec.
    @Test("Nad nenačteným diffem se čas neodhaduje")
    func withoutFilesThereIsNoTimeEstimate() {
        var facts = full
        facts.fileCount = 0
        facts.unreadLineCount = 0
        let progress = Policy.itineraryProgress(of: Policy.itinerary(facts), facts: facts)
        #expect(progress.minutes == nil)
        #expect(progress.total == 4)
        #expect(Policy.itineraryHeading(progress) == "Itinerář · 1 z 4")
    }

    /// Odhad je **z neprošlých řádků**: 210 řádků při 30 na minutu je 7 minut, a k tomu minuta
    /// za každou nehotovou zastávku, která soubory nečte (`Od minule`, `Popis`, `Verdikt`).
    @Test("Odhad času vychází z neprošlých řádků a nehotových zastávek")
    func timeEstimateComesFromUnreadLines() {
        let progress = Policy.itineraryProgress(of: Policy.itinerary(full), facts: full)
        #expect(progress.minutes == 10)
    }

    /// **Hotový itinerář čas nepíše**: `0 min` nad hotovou prací je šum a nad nehotovou lež.
    @Test("Hotový itinerář čas nepíše")
    func finishedItineraryShowsNoTime() {
        var facts = full
        facts.sawChangesSinceVisit = true
        facts.descriptionScrolled = true
        facts.readFileCount = facts.fileCount
        facts.unreadLineCount = 0
        facts.verdictSubmitted = true
        let stops = Policy.itinerary(facts)
        let progress = Policy.itineraryProgress(of: stops, facts: facts)
        #expect(progress.minutes == nil)
        #expect(Policy.itineraryHeading(progress) == "Itinerář · 11 z 11")
    }

    /// Odhad nikdy nevyjde nula: soubor se dvěma řádky je pořád práce na chvíli.
    @Test("Odhad je nejmíň minuta")
    func timeEstimateIsAtLeastOneMinute() {
        var facts = ItineraryFacts()
        facts.fileCount = 1
        facts.readFileCount = 1
        facts.unreadLineCount = 0
        facts.descriptionKnown = true
        facts.hasDescription = true
        facts.descriptionScrolled = true
        let stops = Policy.itinerary(facts)
        // Nehotový zůstává jen `Verdikt`, tedy jedna zastávka bez řádků.
        #expect(Policy.itineraryProgress(of: stops, facts: facts).minutes == 1)
    }

    /// Proužek se **nekreslí, dokud není hotové nic** — prázdná linka nad nezapočatou prací je
    /// stálý prvek bez informace (tatáž úvaha jako `readFileShare`, #500).
    @Test("Proužek podílu se nad nezapočatou prací nekreslí")
    func shareIsNilBeforeAnythingIsDone() {
        #expect(ItineraryProgress(done: 0, total: 9, minutes: 12).share == nil)
        #expect(ItineraryProgress(done: 0, total: 0, minutes: nil).share == nil)
        #expect(ItineraryProgress(done: 3, total: 9, minutes: 12).share == 1.0 / 3.0)
    }

    // MARK: - Kam zastávka vede

    /// Klik na zastávku přepíná tab, takže musí být z čeho ten tab vzít — a `Verdikt` míří do
    /// `Změněných souborů`, protože se vybírá v panelu vpravo, který je vidět v nich.
    @Test("Každá zastávka vede do svého tabu")
    func everyStopPointsAtATab() {
        let tabs: [ItineraryStop.Kind: PullRequestTab] = [
            .sinceLastVisit: .overview,
            .description: .overview,
            .files: .filesChanged,
            .checks: .checks,
            .verdict: .filesChanged,
        ]
        for stop in Policy.itinerary(full) {
            #expect(stop.tab == tabs[stop.kind])
            #expect(Policy.itineraryStopHelp(stop) == "\(stop.title) — přepne na \(stop.tab.czechLabel)")
        }
    }

    // MARK: - Konec popisu

    /// Krátký popis, který se vejde celý, je přečtený rovnou: neviditelný konec nemá.
    @Test("Obsah, který se vejde, je přečtený rovnou")
    func contentThatFitsIsReadImmediately() {
        #expect(Policy.overviewAtEnd(offset: 0, visible: 800, content: 400, isLoaded: true))
        #expect(Policy.overviewAtEnd(offset: 0, visible: 800, content: 800, isLoaded: true))
    }

    @Test("Nahoře nad dlouhým popisem to konec není")
    func topOfALongDescriptionIsNotTheEnd() {
        #expect(!Policy.overviewAtEnd(offset: 0, visible: 800, content: 4_000, isLoaded: true))
    }

    /// Tolerance: pod dolní hranou je vnitřní odsazení karty, takže „poslední bod obsahu“
    /// a „poslední řádek je vidět“ nejsou totéž.
    @Test("Konec se pozná i s tolerancí od dolní hrany")
    func theEndIsRecognisedWithinTheSlack() {
        #expect(Policy.overviewAtEnd(offset: 3_200, visible: 800, content: 4_000, isLoaded: true))
        #expect(Policy.overviewAtEnd(offset: 3_180, visible: 800, content: 4_000, isLoaded: true))
        #expect(!Policy.overviewAtEnd(offset: 3_100, visible: 800, content: 4_000, isLoaded: true))
    }

    /// **Nenačtený popis konec není, i když se obsah vejde** (nález Copilota na #506).
    ///
    /// Je to tvrzení o tom, že se něco **nestane**, a rozbije se potichu: ve stavu
    /// `Načítám popis…` je obsah krátký, takže by `content <= visible` vydalo `true` — a store
    /// tu značku ukládá **jednosměrně** (`noteOverviewReadToEnd` ji nikdy nesundá), takže by
    /// zastávka `Popis a záměr` byla hotová u PR, jehož popis nikdo neviděl.
    ///
    /// Výčet je úplný: dvě šířky obsahu (vejde se / nevejde) a k tomu vršek i konec dlouhého,
    /// protože nenačtený popis musí vydat `false` **ve všech** polohách scrollu.
    @Test("Nenačtený popis není konec v žádné poloze")
    func anUnloadedDescriptionIsNeverTheEnd() {
        for content in [400.0, 800, 4_000] {
            for offset in [0.0, 3_180, 3_200] {
                #expect(
                    !Policy.overviewAtEnd(
                        offset: offset, visible: 800, content: content, isLoaded: false
                    ),
                    "obsah \(content), posun \(offset): nenačtený popis vyšel jako přečtený"
                )
            }
        }
    }

    /// **A PR bez popisu se odškrtnout musí.** Kdyby rozhodovalo „je neprázdný“ místo
    /// „je načtený“, počítadlo itineráře by u takového PR nikdy nedošlo na konec — proto je to
    /// `description != nil`, ne `!description.isEmpty`.
    @Test("PR bez popisu je přečtený, jakmile je načtený")
    func aPullRequestWithoutADescriptionCountsAsRead() {
        #expect(Policy.overviewAtEnd(offset: 0, visible: 800, content: 120, isLoaded: true))
    }

    /// Neprošlé řádky se počítají jen ze souborů, které prošlé nejsou — a `changed` (#500)
    /// je **neprošlý**: je to práce, která se vrátila.
    ///
    /// Počítá se z **hlaviček hunků** (`newCount`), ne procházením řádků: `FileDiff.additions`
    /// iteruje každý řádek každého hunku a tahle funkce běží při každém průchodu tělem detailu.
    /// Fixture má `newCount` rovné počtu přidaných řádků, takže vyjde 20 + 3 = **23** (a bez
    /// značek 10 + 20 + 3 = **33**), ne součet `+/−`.
    @Test("Neprošlé řádky vynechají prošlé soubory, změněné ne")
    func unreadLinesSkipReadFilesButNotChangedOnes() {
        let at = Date(timeIntervalSince1970: 1_000)
        let files = [
            ItineraryFileFactory.file("a.php", additions: 10, deletions: 5),
            ItineraryFileFactory.file("b.php", additions: 20, deletions: 0),
            ItineraryFileFactory.file("c.php", additions: 3, deletions: 2),
        ]
        let states: [String: FileReviewState] = [
            "a.php": .read(at: at),
            "b.php": .changed(readAt: at),
        ]
        #expect(Policy.unreadLineCount(of: files, states: states) == 23)
        #expect(Policy.unreadLineCount(of: files, states: [:]) == 33)
        // A **soubor bez hunků nepřinese nic** — binárka ani přejmenování beze změny obsahu
        // (`similarity index 100%`) žádné řádky ke čtení nemají.
        #expect(
            Policy.unreadLineCount(
                of: [
                    FileDiff(
                        oldPath: "logo.png",
                        newPath: "logo.png",
                        change: .modified,
                        isBinary: true,
                        hunks: []
                    )
                ],
                states: [:]
            ) == 0
        )
    }
}
