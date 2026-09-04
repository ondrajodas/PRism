import Foundation
import Testing

@testable import PRism

/// Co deska ukazuje nad pruhy (#515): strop na řádky, akce nad pruhem a věta pod pozdravem.
///
/// Do kterého pruhu PR patří, se testuje ve `WorkLaneTests`. Tady jsou tři věci, které se dají
/// pokazit potichu a **nejsou vidět z kódu**: že se počet v hlavičce nezúží stropem, že text
/// akce odpovídá tomu, co akce udělá, a že věta pod pozdravem nezmiňuje nuly.
@Suite("Deska — strop, akce, věta")
struct BoardTests {
    private func summary(_ number: Int, author: String = "kolega") -> PullRequestSummary {
        PullRequestSummary(
            id: PRIdentifier(repo: RepoID("cli/cli")!, number: number),
            title: "titulek \(number)",
            author: author,
            url: URL(string: "https://github.com/cli/cli/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: Double(number)),
            state: .open
        )
    }

    private func entries(_ count: Int, author: String = "kolega", from: Int = 1) -> [QueueEntry] {
        (from..<(from + count)).map {
            QueueEntry(pullRequest: summary($0, author: author), state: .notStarted, row: .empty, hasDraft: false)
        }
    }

    private func lane(_ lane: WorkLane, in board: Board) -> Board.Lane {
        board.lanes.first { $0.lane == lane }!
    }
}

// MARK: - Strop na řádky

extension BoardTests {
    /// **Strop je o kresbě, ne o množině** (#371). Pruh hlásí třináct, kreslí pět a patka říká
    /// `+8`; kdyby strop sestoupil do počítání, začala by deska tvrdit, že práce je méně, než jí
    /// je — a to je regrese, která se pozná až za týden.
    @Test("Strop řeže kresbu, ne počet v hlavičce")
    func capsTheDrawingNotTheCount() {
        let board = Policy.board(entries: entries(13))
        let read = lane(.read, in: board)

        let slice = Policy.laneSlice(read.rows, of: .read, expanded: false)

        #expect(read.count == 13)
        #expect(slice.rows.count == 5)
        #expect(slice.hidden == 8)
    }

    /// **Tichý pruh má dva řádky, ne pět** — je to jediný pruh, ve kterém se nic nedělá, takže
    /// nemá plnit obrazovku, na které je šest pruhů pod sebou (návrh, sekce 45).
    @Test("Tichý pruh má nižší strop než ostatní")
    func capsTheQuietLaneLower() {
        #expect(Policy.laneRowLimit(.waiting) == 2)
        for lane in WorkLane.allCases where !lane.isQuiet {
            #expect(Policy.laneRowLimit(lane) == 5, "\(lane)")
        }
    }

    /// Patka nad pruhem, který je celý vidět, by byla akce, po které se nic nezmění.
    /// **Ani při přesně stropu**: `hidden` se rozhoduje o jedničku, takže je to ten případ,
    /// na kterém se `>=` proti `>` pozná.
    @Test("Pod stropem a přesně na stropu se nic neschovává")
    func hidesNothingUpToTheLimit() {
        #expect(Policy.laneSlice(entries(4), of: .read, expanded: false).hidden == 0)
        #expect(Policy.laneSlice(entries(5), of: .read, expanded: false).hidden == 0)
        #expect(Policy.laneSlice(entries(6), of: .read, expanded: false).hidden == 1)
    }

    /// Rozbalený pruh ukáže **všechno** a nic neschovává — patka se pak přepne na `Zobrazit
    /// méně`, což view pozná právě z toho, že `hidden` je nula a pruh je v rozbalených.
    @Test("Rozbalený pruh ukáže všechno")
    func showsEverythingWhenExpanded() {
        let slice = Policy.laneSlice(entries(13), of: .read, expanded: true)

        #expect(slice.rows.count == 13)
        #expect(slice.hidden == 0)
    }
}

// MARK: - Akce nad pruhem

extension BoardTests {
    /// **Počet v akci je to, co akce udělá.** `Pustit review na 2` pustí ta dvě a nic jiného —
    /// kdyby se ta dvě čísla rozešla, byla by z akce ruleta.
    @Test("Akce nese počet z vlastního pruhu")
    func carriesTheLaneCount() {
        let board = Policy.board(entries: entries(3))

        #expect(lane(.read, in: board).action == .runReviews(count: 3))
        #expect(lane(.read, in: board).action.title == "Pustit review na 3")
    }

    /// **Prázdný pruh akci nedostane** — otevřít první z ničeho ani pustit review na nic není
    /// akce, je to tlačítko, po kterém se nic nestane.
    @Test("Prázdný pruh akci nemá")
    func hasNoActionWhenEmpty() {
        let board = Policy.board(entries: [])

        for lane in WorkLane.order where !lane.isQuiet {
            #expect(self.lane(lane, in: board).action == LaneAction.none, "\(lane)")
            #expect(self.lane(lane, in: board).action.title == nil, "\(lane)")
        }
    }

    /// **Tichý pruh akci nemá nikdy**, ani s řádky: místo tlačítka v něm stojí popisek
    /// `nic k udělání`. Zašedlé tlačítko by tvrdilo „tady se to dělá, jen teď ne“.
    @Test("Tichý pruh má popisek, ne akci")
    func showsANoteInsteadOfAnAction() {
        let board = Policy.board(entries: entries(2, author: "ondrajodas"), mine: ["ondrajodas"])
        let quiet = lane(.waiting, in: board)

        #expect(quiet.count == 2)
        #expect(quiet.action == .quiet)
        #expect(quiet.action.title == nil)
        #expect(quiet.action.note == "nic k udělání")
    }

    /// **Potvrzení má jedině akce, která utratí víc než jednu session.** Je to tatáž hranice,
    /// podle které má sheet merge a nemá ho label — vratnost, ne složitost.
    @Test("Potvrzení se ptá jen hromadné spuštění review")
    func confirmsOnlyTheBulkRun() {
        let actions: [LaneAction] = [
            .openFirst(count: 3, isPrimary: true),
            .runReviews(count: 3),
            .buildPrompts(count: 3),
            .finishDraft(count: 3),
            .quiet,
            .none,
        ]

        #expect(actions.filter(\.needsConfirmation) == [.runReviews(count: 3)])
    }

    /// **Nejvýš jedna akce na kombinaci kláves** — dvě tlačítka s jednou klávesou znamenají, že
    /// vyhraje to zaregistrované později (#151, #184), a poznalo by se to jedině tím, že jedna
    /// „nefunguje“. Katalog na kolize hlídá `WindowShortcutsTests`; tady se tvrdí, že si je deska
    /// nerozdala dvakrát.
    @Test("Každý pruh má jinou zkratku, nebo žádnou")
    func handsOutDistinctShortcuts() {
        let shortcuts = WorkLane.order.compactMap { Policy.laneAction(of: $0, count: 2).shortcut }

        #expect(shortcuts.count == 3)
        #expect(Set(shortcuts).count == shortcuts.count)
        // `K merge` má tutéž akci jako `Rozhodnout`, ale **bez klávesy** — `⏎` je rozdané.
        #expect(Policy.laneAction(of: .decide, count: 2).shortcut == .openFirstOnBoard)
        #expect(Policy.laneAction(of: .merge, count: 2).shortcut == nil)
        #expect(Policy.laneAction(of: .handOff, count: 2).shortcut == nil)
    }

    /// Popisek se mění s počtem tam, kde na tom záleží: `Otevřít` u jednoho řádku (otevře se
    /// **jeden**, ať jich v pruhu leží kolik chce) proti `Otevřít první` u víc.
    @Test("Popisek akce se mění s počtem")
    func namesTheActionByCount() {
        #expect(LaneAction.openFirst(count: 1, isPrimary: true).title == "Otevřít")
        #expect(LaneAction.openFirst(count: 4, isPrimary: false).title == "Otevřít první")
        #expect(LaneAction.buildPrompts(count: 1).title == "Sestavit zadání")
        #expect(LaneAction.buildPrompts(count: 2).title == "Sestavit 2 zadání")
        #expect(LaneAction.finishDraft(count: 1).title == "Dopsat")
        #expect(LaneAction.finishDraft(count: 3).title == "Dopsat nejstarší")
    }

    /// `⏎` je jediná zkratka desky **bez modifikátoru**, takže musí ustoupit překryvu, který si
    /// ji bere sám — nad otevřenou paletou ⌘K se zakáže a klávesa propadne dál.
    @Test("Holé ⏎ ustupuje otevřené paletě a prázdnému pruhu")
    func yieldsTheBareReturn() {
        #expect(Policy.canOpenFirstOnBoard(count: 3, isPaletteOpen: false))
        #expect(!Policy.canOpenFirstOnBoard(count: 3, isPaletteOpen: true))
        #expect(!Policy.canOpenFirstOnBoard(count: 0, isPaletteOpen: false))
    }
}

// MARK: - Věta pod pozdravem

extension BoardTests {
    /// `8 věcí na tahu · 4 čekají na ostatní · 1 se dá mergnout` — přesně ta věta, kterou kreslí
    /// návrh (sekce 45). „Na tahu“ je součet **všech pruhů kromě tichého**.
    @Test("Věta sčítá pruhy na tahu a jmenuje tiché i merge")
    func composesTheSentence() {
        var board = Policy.board(entries: [])
        board = Board(
            lanes: [
                Board.Lane(lane: .decide, rows: entries(3), action: .openFirst(count: 3, isPrimary: true)),
                Board.Lane(lane: .read, rows: entries(2, from: 10), action: .runReviews(count: 2)),
                Board.Lane(lane: .handOff, rows: entries(2, from: 20), action: .buildPrompts(count: 2)),
                Board.Lane(lane: .merge, rows: entries(1, from: 30), action: .openFirst(count: 1, isPrimary: false)),
                Board.Lane(lane: .waiting, rows: entries(4, from: 40), action: .quiet),
                Board.Lane(lane: .finishReview, rows: [], action: .none),
            ],
            activity: board.activity
        )

        #expect(Policy.boardSentence(board) == "8 věcí na tahu · 4 čekají na ostatní · 1 se dá mergnout")
    }

    /// **Nuly se nepíšou** — „0 čeká na ostatní“ je hlášení o ničem a pozdrav má být krátký.
    @Test("Prázdné části věty vypadnou")
    func dropsEmptyParts() {
        let board = Policy.board(entries: entries(2))

        #expect(Policy.boardSentence(board) == "2 věci na tahu")
    }

    /// Prázdná deska je **nejlepší možný stav** a nesmí vypadat jako porucha, takže se to řekne
    /// slovem, ne nulou — tatáž úvaha jako u prázdné fronty do #515.
    @Test("Prázdná deska mluví slovem, ne nulou")
    func speaksAboutTheEmptyBoard() {
        #expect(
            Policy.boardSentence(Policy.board(entries: []))
                == "Nic na tahu — fronta je vyřízená a nic vlastního nečeká."
        )
    }

    /// Když je na tahu nula a přitom něco čeká, musí věta říct **obojí**: „nic na tahu“ samo by
    /// zamlčelo, že venku něco leží, a věta o čekání sama by neřekla, že se nemá co dělat.
    @Test("Nic na tahu vedle čekajících se řekne obojí")
    func mentionsBothWhenNothingIsOnMove() {
        var board = Policy.board(entries: [])
        board = Board(
            lanes: WorkLane.order.map { lane in
                Board.Lane(
                    lane: lane,
                    rows: lane == .waiting ? entries(2) : [],
                    action: lane == .waiting ? .quiet : LaneAction.none
                )
            },
            activity: board.activity
        )

        #expect(Policy.boardSentence(board) == "Nic na tahu · 2 čekají na ostatní")
    }
}

// MARK: - Pořadí pruhů a skrývání prázdných (z proklikání #515)

extension BoardTests {
    private func board(counts: [WorkLane: Int]) -> Board {
        var next = 1
        return Board(
            lanes: WorkLane.order.map { lane in
                let count = counts[lane] ?? 0
                let rows = entries(count, from: next)
                next += max(count, 1)
                return Board.Lane(lane: lane, rows: rows, action: Policy.laneAction(of: lane, count: count))
            },
            activity: Policy.board(entries: []).activity
        )
    }

    /// **`K merge` je první a `Dopsat a odeslat` druhé** — obojí z prvního proklikání #515, tedy
    /// změna proti kresbě z decku (*rozhodnout · přečíst · předat · k merge · čeká · dopsat*).
    ///
    /// **Celé pořadí plyne z osy** („jak blízko je řádek k tomu, aby míč nebyl u mě“), a je to
    /// jediné rozhodnutí, které v něm je. Druhé proklikání z něj na jedno kolo `handOff` vyvázalo
    /// a posadilo ho na konec desky; byl to ale **špatně přeložený pokyn** — mluvil o posledním
    /// *pravidle* v `Policy.lane` (viz `WorkLaneTests.handOffIsTheLastRuleThatClaimsAnything`), ne
    /// o posledním *pruhu* v kresbě —, takže je od třetího proklikání zpátky na **pátém** místě.
    ///
    /// Tvrdí se tu **celé pořadí literálem**, ne jen první položka: kdyby se osa změnila znovu,
    /// má spadnout tenhle test a ne render.
    @Test("Pořadí pruhů začíná tím, co je hotové, a končí tichým pruhem")
    func putsTheFinishedWorkFirst() {
        #expect(WorkLane.order == [.merge, .finishReview, .decide, .read, .handOff, .waiting])
        #expect(Set(WorkLane.order) == Set(WorkLane.allCases))
        #expect(WorkLane.order.count == WorkLane.allCases.count)
        // Tichý pruh je **poslední**, a tvrdí se to zvlášť: je to konec osy — míč u mě není vůbec —,
        // takže za něj nesmí spadnout pruh, ve kterém se něco dělá.
        #expect(WorkLane.order.last == .waiting)
        // Zbylé čtyři si drží **relativní** pořadí z kresby; přesunuly se jedině `merge`
        // a `finishReview`. Kdyby se přeskládaly i ony, je to jiné rozhodnutí a chce vlastní
        // záznam — `handOff` na konci už jedno takové mělo a byl to špatně přeložený pokyn.
        #expect(WorkLane.order.filter { $0 != .merge && $0 != .finishReview }
            == [.decide, .read, .handOff, .waiting])
        // Deska pořadí **nepřeskládává** — bere ho z `WorkLane.order`.
        #expect(Policy.board(entries: entries(2)).lanes.map(\.lane) == WorkLane.order)
    }

    /// **Prázdný pruh se nekreslí** (z proklikání #515), ale v `lanes` zůstane: věta pod
    /// pozdravem mluví o celé desce, ne o tom, co je zrovna vidět.
    @Test("Prázdné pruhy se nekreslí, ale z desky nezmizí")
    func hidesEmptyLanesFromTheDrawingOnly() {
        let two = board(counts: [.read: 3, .waiting: 1])

        #expect(two.lanes.count == 6)
        #expect(two.visibleLanes.map(\.lane) == [.read, .waiting])
        #expect(!two.isEverythingDone)
        // Pořadí se skrýváním nemíchá: `visibleLanes` je filtr nad `order`, ne nové řazení.
        #expect(board(counts: [.waiting: 1, .merge: 2]).visibleLanes.map(\.lane) == [.merge, .waiting])
    }

    /// **Tichý pruh se skrývá jako každý jiný** — ale jen když je prázdný, takže se věta pod
    /// pozdravem a deska nemají čím rozejít: „4 čekají na ostatní“ a nakreslený pruh mají
    /// **tutéž podmínku**, totiž nenulový počet.
    @Test("Skrytí tichého pruhu a nula ve větě je jedna podmínka")
    func keepsTheSentenceAndTheDrawingInAgreement() {
        let waiting = board(counts: [.waiting: 4])

        #expect(waiting.visibleLanes.map(\.lane) == [.waiting])
        #expect(Policy.boardSentence(waiting) == "Nic na tahu · 4 čekají na ostatní")

        let none = board(counts: [.read: 1])
        #expect(none.visibleLanes.map(\.lane) == [.read])
        #expect(!Policy.boardSentence(none).contains("čeká"))
    }

    /// **Zkratka visí na pruhu, ne na pozici**, a je to to nejcennější tvrzení celého skrývání:
    /// „první pruh“ je od proklikání #515 pokaždé jiný, takže kdyby se `⏎` vázalo na pozici,
    /// byla by to kolize z #151 a #184 — jen v čase, tedy nezachytitelná pohledem do katalogu.
    ///
    /// Prochází se **všech 64 podmnožin** neprázdných pruhů. Tvrdí se dvě věci naráz: `⏎` nikdy
    /// nevydá jiný pruh než `Rozhodnout`, a když je `Rozhodnout` skryté, **nevydá ji nikdo** —
    /// nepřevezme ji ani pruh, který zbyl nahoře.
    @Test("Skrytý pruh svou zkratku nepředá sousedovi")
    func neverRebindsAShortcutToAnotherLane() {
        for mask in 0..<(1 << WorkLane.order.count) {
            let present = WorkLane.order.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            let visible = board(counts: Dictionary(uniqueKeysWithValues: present.map { ($0, 2) }))
                .visibleLanes

            #expect(visible.map(\.lane) == present)
            let holders = visible.filter { $0.action.shortcut == .openFirstOnBoard }.map(\.lane)
            #expect(holders == (present.contains(.decide) ? [.decide] : []))
            // A žádná kombinace neumí rozdat jednu klávesu dvakrát.
            let shortcuts = visible.compactMap { $0.action.shortcut }
            #expect(Set(shortcuts).count == shortcuts.count)
        }
    }

    /// **Prázdná deska má vlastní věty, ne prázdnou plochu.** Je to stav, který skrývání teprve
    /// vyrábí — do proklikání #515 na obrazovce stálo šest rámečků s nulou.
    ///
    /// A **nenačtená fronta není vyřízená fronta**: to je ta nebezpečná strana, protože
    /// „všechno vyřízené“ nad nestaženým seznamem je tvrzení o ničem.
    @Test("Prázdná deska řekne, že je vyřízeno — a nad nenačtenou frontou to neřekne")
    func explainsTheEmptyBoard() {
        #expect(board(counts: [:]).isEverythingDone)
        #expect(board(counts: [.waiting: 1]).isEverythingDone == false)

        let done = Policy.boardEmpty(isLoaded: true)
        #expect(done.title == "Všechno vyřízené")
        #expect(done.explanation.contains("objeví jako pruh samy"))
        // **Neopakuje větu pod pozdravem** — ta mluví o stavu, tahle o tom, co bude dál. Dvě
        // věty o tomtéž nad prázdnou obrazovkou znamenají, že si jedna z nich nevěří.
        #expect(!done.explanation.contains("Nic na tahu"))

        let loading = Policy.boardEmpty(isLoaded: false)
        #expect(loading.title == "Načítám frontu")
        #expect(!loading.explanation.contains("vyřízen"))
        #expect(loading.title != done.title)
    }
}

// MARK: - Merge přebíjí předání (z proklikání #515)

extension BoardTests {
    private func own(_ number: Int) -> QueueEntry {
        QueueEntry(
            pullRequest: summary(number, author: "ondrajodas"),
            state: .clean,
            row: .empty,
            hasDraft: false
        )
    }

    /// **Mergnutelný vlastní PR s nevyřízeným předáním je v `K merge`**, ne v `Předat agentovi` —
    /// a pilulka `N k předání` mu zůstane v řádku.
    ///
    /// Tohle je to tvrzení, které pinuje nález z proklikání: schválený PR se všemi checky
    /// zelenými (`keboola/job-queue-daemon#934`) ležel v `Předat agentovi`, protože `pending > 0`
    /// rozhodovalo dřív než merge. Tvrdí se **obojí naráz** — pruh i obsah řádku —, protože
    /// samotný přesun by informaci o předání ztratil, a to je horší vada než špatný pruh.
    @Test("Mergnutelný PR s nevyřízeným předáním je v K merge, ale pilulku si nese")
    func putsAMergeableOwnPullRequestIntoMergeAndKeepsThePill() {
        let board = Policy.board(
            entries: [own(1)],
            mine: ["ondrajodas"],
            handoff: { _ in WorkLaneTests.handoff(pending: 2, stage: .never) },
            isMergeReady: { _ in true }
        )

        #expect(lane(.merge, in: board).rows.map(\.pullRequest.number) == [1])
        #expect(lane(.handOff, in: board).rows.isEmpty)
        #expect(board.visibleLanes.map(\.lane) == [.merge])
        // **Pilulka visí na řádku, ne na pruhu**, takže jde s PR do kteréhokoli z nich. Kdyby
        // záležela na pruhu, zmizela by právě tímhle přesunem jediná zmínka o tom, že něco zbývá.
        let row = PullRequestRow(
            pullRequest: own(1).pullRequest,
            reviewState: .clean,
            ownership: .mine,
            pending: 2
        )
        #expect(row.pendingHandoff == 2)
        #expect(row.showsPromptAction == false)  // bez `openPrompt` se tlačítko nekreslí
    }

    /// **Ani nevyřízené předání merge nepřebíjí** (druhé proklikání #515 — ruší výjimku, kterou
    /// tady stálo tvrzení přesně naopak).
    ///
    /// `changed` je stav, ve kterém je něco **nevyřízeného** — nepředaná položka, nová položka,
    /// nebo cizí odpověď v předaném vlákně. Po prvním proklikání to PR drželo v `Předat agentovi`
    /// i nad slévatelnou větví; pokyn zní, že **mergnutelný PR patří do `K merge`, tečka**.
    ///
    /// Tvrdí se to **s obsahem řádku v jednom testu**, a je to ta cennější polovina: kdyby se
    /// s přesunem ztratila zmínka o předání, byla by to horší vada než špatný pruh. Pilulka
    /// `1 k předání` na stavu předání **nezávisí vůbec** (`PullRequestRow.pendingHandoff` se ptá
    /// jedině na autora a na počet), takže `changed` je v `K merge` vidět stejně jako `never`.
    @Test("Nevyřízené předání (changed) jde do K merge a pilulku si nese")
    func putsAChangedHandoffIntoMergeToo() {
        let board = Policy.board(
            entries: [own(1)],
            mine: ["ondrajodas"],
            handoff: { _ in WorkLaneTests.handoff(pending: 1, stage: .changed) },
            isMergeReady: { _ in true }
        )

        #expect(lane(.merge, in: board).rows.map(\.pullRequest.number) == [1])
        #expect(lane(.handOff, in: board).rows.isEmpty)
        #expect(board.visibleLanes.map(\.lane) == [.merge])

        let row = PullRequestRow(
            pullRequest: own(1).pullRequest,
            reviewState: .clean,
            ownership: .mine,
            pending: 1
        )
        #expect(row.pendingHandoff == 1)

        // A **nemergnutelný `changed` zůstává v `Předat agentovi`** — je to ta polovina pravidla,
        // kterou by plošné „merge vyhrává“ rozbilo potichu.
        let blocked = Policy.board(
            entries: [own(1)],
            mine: ["ondrajodas"],
            handoff: { _ in WorkLaneTests.handoff(pending: 1, stage: .changed) },
            isMergeReady: { _ in false }
        )
        #expect(lane(.handOff, in: blocked).rows.map(\.pullRequest.number) == [1])
    }

    /// A **akce nad `K merge` se tím nezměnila**: `Otevřít` bez klávesy, protože `⏎` patří
    /// `Rozhodnout`. Nová obsazenost pruhu nesmí rozdat druhou zkratku na tutéž klávesu.
    @Test("K merge s řádky nedostane ⏎")
    func doesNotHandTheBareReturnToMerge() {
        let board = Policy.board(
            entries: [own(1)],
            mine: ["ondrajodas"],
            handoff: { _ in WorkLaneTests.handoff(pending: 2, stage: .never) },
            isMergeReady: { _ in true }
        )

        let visible = board.visibleLanes
        #expect(visible.compactMap { $0.action.shortcut } == [])
        #expect(lane(.merge, in: board).action == .openFirst(count: 1, isPrimary: false))
    }
}
