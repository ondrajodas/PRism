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
