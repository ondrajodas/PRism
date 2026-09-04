import Foundation
import Testing

@testable import PRism

/// Mezerník jako další zastávka a průběh ve stavovém řádku (#507).
///
/// **Nejcennější tvrzení tady jsou ta, že se NIC nestane**: mezerník si klávesu nesmí vzít, když
/// se do pole píše, když je ještě kam scrollovat a když se konec obsahu vůbec neměří. Rozbilo by
/// se to potichu — vypadalo by to jako „scroll občas přeskočí“.
@Suite("Policy — mezerník po itineráři (#507)")
struct ItineraryWalkTests {
    /// Dráha o pěti zastávkách: dvě hotové, aktuální jsou soubory.
    private var stops: [ItineraryStop] {
        Policy.itinerary(
            ItineraryFacts(
                hasVisitRecord: true,
                commitsSinceVisit: 3,
                sawChangesSinceVisit: true,
                descriptionKnown: true,
                hasDescription: true,
                descriptionScrolled: true,
                fileCount: 7,
                readFileCount: 2,
                unreadLineCount: 210,
                checks: ChecksSummary(passed: 12, failed: 1, running: 0, skipped: 0),
                openedFailedChecks: 0,
                verdictSubmitted: false,
                verdict: .requestChanges
            )
        )
    }

    /// Dráha, na které je hotové všechno — `current` v ní žádná není.
    private var finished: [ItineraryStop] {
        Policy.itinerary(
            ItineraryFacts(
                descriptionKnown: true,
                hasDescription: true,
                descriptionScrolled: true,
                fileCount: 4,
                readFileCount: 4,
                unreadLineCount: 0,
                verdictSubmitted: true
            )
        )
    }

    // MARK: - Kam mezerník posune

    @Test("Dráha ke zkoušení má zastávky v pořadí z návrhu")
    func theWalkUnderTestHasTheStopsFromTheDesign() {
        #expect(stops.map(\.kind) == [.sinceLastVisit, .description, .files, .checks, .verdict])
        #expect(stops.map(\.state) == [.done, .done, .current, .todo, .todo])
        #expect(finished.allSatisfy { $0.state == .done })
    }

    /// První stisk jde tam, kde dráha podle **dat** stojí — ne na začátek k tomu, co je hotové.
    @Test("Bez kurzoru se jde na aktuální zastávku")
    func withoutACursorTheKeyGoesToTheCurrentStop() {
        #expect(Policy.nextItineraryStop(after: nil, in: stops)?.kind == .files)
    }

    @Test("S kurzorem se jde na následující zastávku v pořadí")
    func withACursorTheKeyGoesToTheNextStopInOrder() {
        let expected: [(ItineraryStop.Kind, ItineraryStop.Kind?)] = [
            (.sinceLastVisit, .description),
            (.description, .files),
            (.files, .checks),
            (.checks, .verdict),
            // Poslední zastávka: **není kam**, takže klávesa propadne scrollu.
            (.verdict, nil),
        ]

        for (cursor, next) in expected {
            #expect(Policy.nextItineraryStop(after: cursor, in: stops)?.kind == next)
        }
    }

    /// Zastávky se skládají z dat, takže `Kontroly` ze seznamu zmizí (PR přestal mít CI, nebo se
    /// kurzor nese z jiného stavu). Hledat další za zastávkou, která tam není, nemá odpověď —
    /// vrací se aktuální.
    @Test("Kurzor mimo dráhu se bere jako žádný")
    func aCursorOutsideTheWalkCountsAsNone() {
        let withoutChecks = stops.filter { $0.kind != .checks }

        #expect(Policy.nextItineraryStop(after: .checks, in: withoutChecks)?.kind == .files)
    }

    /// Hotová dráha nemá `current`, takže se nemá kam posunout — a mezerník zůstane klávesou
    /// scrollu místo toho, aby cyklil dokola.
    @Test("Na hotové dráze bez kurzoru není kam jít")
    func aFinishedWalkHasNowhereToGo() {
        #expect(Policy.nextItineraryStop(after: nil, in: finished) == nil)
        #expect(Policy.nextItineraryStop(after: nil, in: []) == nil)
        #expect(Policy.nextItineraryStop(after: .files, in: []) == nil)
    }

    // MARK: - Kdy si klávesu vzít

    /// **Vyčerpávající matice tří vstupů.** Klávesa se bere jedině v jediné kombinaci ze šesti.
    @Test("Mezerník se bere jen mimo pole a jen na konci obsahu")
    func theKeyIsTakenOnlyOutsideAFieldAndOnlyAtTheEnd() {
        for isEditing in [true, false] {
            for atEnd in [nil, false, true] as [Bool?] {
                let step = Policy.itineraryStep(
                    stops: stops,
                    cursor: nil,
                    isEditing: isEditing,
                    atEnd: atEnd
                )
                let taken = !isEditing && atEnd == true
                #expect((step != nil) == taken, "psaní \(isEditing), konec \(String(describing: atEnd))")
            }
        }
    }

    /// Neměřený konec (`nil`) je **totéž rozhodnutí** jako „není na konci“: tvrdit něco o obsahu,
    /// který nikdo nezměřil, nese víc, než data unesou.
    @Test("Neměřený konec obsahu klávesu nedá")
    func anUnmeasuredEndDoesNotHandOverTheKey() {
        #expect(Policy.itineraryStep(stops: stops, cursor: nil, isEditing: false, atEnd: nil) == nil)
    }

    /// I na konci obsahu se klávesa nebere, když není kam jít — poslední zastávka.
    @Test("Na poslední zastávce se klávesa nebere ani na konci obsahu")
    func theLastStopKeepsTheKeyForScrolling() {
        #expect(
            Policy.itineraryStep(stops: stops, cursor: .verdict, isEditing: false, atEnd: true) == nil
        )
        #expect(
            Policy.itineraryStep(stops: stops, cursor: .files, isEditing: false, atEnd: true)?.kind
                == .checks
        )
    }

    // MARK: - Je výřez na konci obsahu

    @Test("Obsah, který se vejde celý, je na konci")
    func contentThatFitsIsAtTheEnd() {
        #expect(Policy.contentAtEnd(offset: 0, visible: 600, content: 400))
        #expect(Policy.contentAtEnd(offset: 0, visible: 600, content: 600))
    }

    @Test("Dokud je kam scrollovat, na konci to není")
    func whileThereIsRoomToScrollItIsNotTheEnd() {
        #expect(!Policy.contentAtEnd(offset: 0, visible: 600, content: 2000))
        #expect(!Policy.contentAtEnd(offset: 1000, visible: 600, content: 2000))
    }

    /// Rovnost na bod po rozvržení nevyjde, proto vůle — a ta musí být menší než řádek, jinak by
    /// se „na konci“ hlásilo o řádek dřív.
    @Test("Vůle dvou bodů se ještě počítá za konec")
    func theSlackStillCountsAsTheEnd() {
        #expect(Policy.contentAtEnd(offset: 1400, visible: 600, content: 2000))
        #expect(Policy.contentAtEnd(offset: 1398.5, visible: 600, content: 2000))
        #expect(!Policy.contentAtEnd(offset: 1390, visible: 600, content: 2000))
        #expect(Policy.contentEndSlack == 2)
    }

    // MARK: - Stavový řádek

    private var progress: ItineraryProgress {
        ItineraryProgress(done: 4, total: 9, minutes: 12)
    }

    @Test("Průběh se píše jako Krok 4 z 9 · 12 min")
    func theStatusReadsAsTheDesignHasIt() {
        let opened = Date(timeIntervalSince1970: 1_000_000)

        #expect(
            Policy.itineraryStatus(
                progress: progress,
                openedAt: opened,
                now: opened.addingTimeInterval(12 * 60 + 30)
            ) == "Krok 4 z 9 · 12 min"
        )
    }

    /// Minuty v pruhu jsou **uplynulé**, ne odhad z hlavičky — a to je vidět právě tady: hlavička
    /// téhož počítadla říká `10 min` (`ItineraryProgress.minutes`), pruh `1 min`.
    @Test("Minuty v pruhu jsou uplynulé, ne zbývající")
    func theMinutesInTheBarAreElapsedNotRemaining() {
        let opened = Date(timeIntervalSince1970: 1_000_000)
        let progress = ItineraryProgress(done: 4, total: 9, minutes: 10)

        #expect(
            Policy.itineraryStatus(
                progress: progress,
                openedAt: opened,
                now: opened.addingTimeInterval(90)
            ) == "Krok 4 z 9 · 1 min"
        )
    }

    @Test("Bez počítadla se nepíše nic")
    func withoutACounterNothingIsWritten() {
        let empty = ItineraryProgress(done: 0, total: 0, minutes: nil)

        #expect(Policy.itineraryStatus(progress: empty, openedAt: .now, now: .now) == nil)
    }

    /// `0 min` v první minutě je šum a záložka bez záznamu o otevření o čase netvrdí nic.
    @Test("Do první minuty a bez času otevření se minuty nepíšou")
    func minutesAreOmittedUntilTheFirstOneAndWithoutAnOpeningTime() {
        let opened = Date(timeIntervalSince1970: 1_000_000)

        #expect(Policy.minutesInTab(openedAt: nil, now: opened) == nil)
        #expect(Policy.minutesInTab(openedAt: opened, now: opened) == nil)
        #expect(Policy.minutesInTab(openedAt: opened, now: opened.addingTimeInterval(59)) == nil)
        #expect(Policy.minutesInTab(openedAt: opened, now: opened.addingTimeInterval(60)) == 1)
        #expect(Policy.minutesInTab(openedAt: opened, now: opened.addingTimeInterval(3600)) == 60)
        // Posunuté hodiny: čas, který ještě nezačal, se nedá vypsat.
        #expect(Policy.minutesInTab(openedAt: opened, now: opened.addingTimeInterval(-600)) == nil)

        #expect(
            Policy.itineraryStatus(progress: progress, openedAt: opened, now: opened)
                == "Krok 4 z 9"
        )
    }

    // MARK: - Patka s klávesami

    /// **Popiska se odvozuje z katalogu.** Kdyby se opisovala, změna klávesy by o textu nevěděla
    /// — přesně ta chyba, kvůli které katalog vznikl (#441).
    @Test("Patka itineráře nese klávesy z katalogu")
    func theFooterCarriesTheKeysFromTheCatalogue() {
        let hints = Policy.itineraryKeyHints

        #expect(hints.map(\.key) == ["␣", "⌥↓", "⌥V"])
        #expect(hints.map(\.label) == ["další zastávka", "další nález", "prošlo"])
        // Doslova to, co má návrh.
        #expect(
            hints.map { "\($0.key) \($0.label)" }.joined(separator: " · ")
                == "␣ další zastávka · ⌥↓ další nález · ⌥V prošlo"
        )
    }

    @Test("Nápověda se skládá z téže kombinace jako patka")
    func theHintAndTheHelpAgreeOnTheKey() {
        for action in [WindowShortcut.Action.nextItineraryStop, .nextFinding, .toggleFileRead] {
            let hint = Policy.shortcutHint(action)
            let shortcut = Policy.windowShortcut(action)

            #expect(hint.key == shortcut.display)
            #expect(hint.label == shortcut.title.lowercased())
        }
    }
}
