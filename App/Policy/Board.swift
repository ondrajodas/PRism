import Foundation

/// Co domácí záložka ukazuje (#515) — **deska pruhů podle mého tahu**.
///
/// Nahradila `Dashboard` z #181, a je to výměna otázky, ne přeskládání týchž kusů: karty
/// odpovídaly na „kolik toho je“, deska odpovídá na „co udělám teď“. Čísla, která nesly karty,
/// zůstávají v railu (`AppStore.railQueueCount`, `railMineCount`, `activityBadge`) a ve stavovém
/// řádku (`Policy.summary`) — tedy tam, kde jsou vidět **ze všech obrazovek**, ne jen z téhle.
///
/// **Jeden snímek na překreslení.** Deska prochází celý seznam a u vlastních PR se ptá na
/// předání; getter na jeden pruh by tu práci udělal šestkrát za sebou a byl by to druhý zdroj
/// pravdy o jedné obrazovce. Ze stejného důvodu je uvnitř i blok `Dění` — tak to bylo
/// i u `Dashboard` (#443).
struct Board: Hashable, Sendable {
    /// Pruhy **v pořadí, ve kterém se kreslí**, a vždycky všechny (`WorkLane.order`).
    ///
    /// **Prázdný pruh se nevypouští**: mizející pruh by desku při každém tiku přeskládal a
    /// `Rozhodnout` by pod rukou skočilo tam, kde bylo `Přečíst`. Prázdno je navíc odpověď a je
    /// na pruh jiná (`WorkLane.emptyExplanation`).
    let lanes: [Lane]
    /// Blok `Dění` v pravém sloupci. Součást téhož snímku — viz doc komentář typu.
    let activity: DashboardActivity

    /// Jeden pruh: co v něm leží a co se s tím dá udělat naráz.
    struct Lane: Hashable, Sendable, Identifiable {
        let lane: WorkLane
        /// **Celý** pruh, seřazený podle závažnosti (`Policy.byUrgency`). Strop na kresbu řeší
        /// `Policy.laneSlice(_:of:expanded:)` — strop je o kresbě, ne o množině (#371).
        let rows: [QueueEntry]
        /// Akce nad pruhem. Skládá ji `Policy.laneAction(of:count:)`, takže se počet v hlavičce
        /// a to, co akce udělá, nemají čím rozejít.
        let action: LaneAction

        var id: WorkLane { lane }
        var count: Int { rows.count }
    }
}

/// Akce nad celým pruhem (#515).
///
/// **Výčet, ne uzávěr s popiskem**: rozhoduje se u ní trojice *co je na tlačítku · jakou má
/// klávesu · ptá se potvrzení*, a všechny tři musí vyjít z jednoho místa. Do #515 byla jediná
/// hromadná akce v okně `Pustit review na vše, co neběželo` v bloku `Co teď`; ta se sem
/// přestěhovala k pruhu, kterého se týká.
enum LaneAction: Hashable, Sendable {
    /// Otevřít první řádek pruhu (`decide`, `merge`). Nic to neutratí a jde to vzít zpět.
    ///
    /// **`isPrimary` rozhoduje o klávese, ne o kresbě.** `⏎` smí patřit **jedinému** pruhu —
    /// dvě tlačítka s jednou kombinací znamenají, že vyhraje to zaregistrované později (#151,
    /// #184), a poznalo by se to tím, že jedna „nefunguje“. Dostane ji `Rozhodnout`, protože je
    /// první a je to ten pruh, na který návrh (sekce 45) klávesu kreslí; `K merge` má tutéž akci
    /// bez klávesy.
    case openFirst(count: Int, isPrimary: Bool)
    /// Pustit review na všechno, co v pruhu leží (`read`).
    ///
    /// **Jediná akce desky, která utratí víc než jednu session** — a proto jediná s potvrzením.
    case runReviews(count: Int)
    /// Otevřít každý PR pruhu s rozloženým panelem `Zadání` (`handOff`).
    case buildPrompts(count: Int)
    /// Dopsat rozdělané review (`finishReview`) — otevře to nejstarší.
    case finishDraft(count: Int)
    /// Tichý pruh: místo akce popisek `nic k udělání`.
    case quiet
    /// Prázdný pruh: v hlavičce nestojí nic, věta je v těle.
    case none

    /// Text tlačítka. `nil` = tlačítko se nekreslí.
    ///
    /// **Počet je v popisku u akcí, které pracují s celým pruhem** (`Pustit review na 2`,
    /// `Sestavit 2 zadání`) — u nich je to to, co se stane. U `Otevřít` je počet naopak jen
    /// v hlavičce: otevře se **jeden** PR, ať jich v pruhu leží kolik chce.
    var title: String? {
        switch self {
        case .openFirst(let count, _): count == 1 ? "Otevřít" : "Otevřít první"
        case .runReviews(let count): "Pustit review na \(count)"
        case .buildPrompts(let count):
            count == 1 ? "Sestavit zadání" : "Sestavit \(count) zadání"
        case .finishDraft(let count): count == 1 ? "Dopsat" : "Dopsat nejstarší"
        case .quiet, .none: nil
        }
    }

    /// Popisek místo tlačítka. `nil` = v hlavičce nestojí nic.
    var note: String? {
        if case .quiet = self { return "nic k udělání" }
        return nil
    }

    /// Klávesová zkratka z katalogu (#441). `nil` = akce klávesu nemá.
    ///
    /// **Nejvýš jedna akce na kombinaci**, protože dvě tlačítka s jednou klávesou znamenají, že
    /// vyhraje to zaregistrované později (#151, #184). Deska proto rozdává tři různé:
    /// `⏎` pruhu `Rozhodnout`, `⌘⇧R` review a `⌘⇧D` draftu — ty dvě posledně jmenované jsou
    /// tytéž, jaké měly akce v bloku `Co teď`. `K merge` má `Otevřít` **bez klávesy**, protože
    /// `⏎` je už rozdané.
    var shortcut: WindowShortcut.Action? {
        switch self {
        case .openFirst(_, let isPrimary): isPrimary ? .openFirstOnBoard : nil
        case .runReviews: .runAllReviews
        case .finishDraft: .openDraft
        case .buildPrompts, .quiet, .none: nil
        }
    }

    /// Ptá se ta akce potvrzení?
    ///
    /// **Jedině tam, kde se utratí víc než jedna session.** Otevřít záložku nestojí nic a jde to
    /// vzít zpátky; sestavit zadání taky ne (panel skládá text z toho, co store už má). Je to
    /// tatáž hranice, podle které má sheet merge a nemá ho label — vratnost, ne složitost.
    var needsConfirmation: Bool {
        if case .runReviews = self { return true }
        return false
    }
}

/// Kolik řádků pruhu se kreslí a kolik se nevešlo (#515).
struct LaneSlice: Hashable, Sendable {
    let rows: [QueueEntry]
    /// Kolik řádků zbylo pod stropem. `0` = pruh je celý vidět, takže se patka **nekreslí**.
    let hidden: Int
}

extension Policy {
    /// Kolik řádků se z pruhu kreslí (#515).
    ///
    /// Pět je z #371 a je to horní hranice toho, co se dá přejet očima. **Tichý pruh má dva**, a
    /// je to celá jeho kresba spolu se ztlumením: je to jediný pruh, ve kterém se nic nedělá,
    /// takže nemá plnit obrazovku, na které je šest pruhů pod sebou. Návrh (sekce 45) ho kreslí
    /// se dvěma řádky ze čtyř.
    static func laneRowLimit(_ lane: WorkLane) -> Int {
        lane.isQuiet ? 2 : 5
    }

    /// Řez pruhu na to, co se nakreslí (#515).
    ///
    /// **Rozbaluje se na místě, nepřepíná se do sekce.** Patka pruhu nemá kam vést: pruh míchá
    /// cizí a vlastní PR, takže žádná sekce railu nemá tutéž množinu — a odkaz na sekci, ve které
    /// leží něco jiného, je horší než rozbalení. Proto `expanded` a ne `BlockFooter`.
    static func laneSlice(_ rows: [QueueEntry], of lane: WorkLane, expanded: Bool) -> LaneSlice {
        let limit = laneRowLimit(lane)
        guard !expanded, rows.count > limit else { return LaneSlice(rows: rows, hidden: 0) }
        return LaneSlice(rows: Array(rows.prefix(limit)), hidden: rows.count - limit)
    }

    /// Akce nad pruhem podle toho, co v něm leží (#515).
    ///
    /// **Prázdný pruh akci nedostane** — otevřít první z ničeho ani pustit review na nic není
    /// akce, je to tlačítko, po kterém se nic nestane. Tichý pruh ji nedostane nikdy.
    static func laneAction(of lane: WorkLane, count: Int) -> LaneAction {
        guard !lane.isQuiet else { return .quiet }
        guard count > 0 else { return .none }
        return switch lane {
        case .decide: .openFirst(count: count, isPrimary: true)
        case .merge: .openFirst(count: count, isPrimary: false)
        case .read: .runReviews(count: count)
        case .handOff: .buildPrompts(count: count)
        case .finishReview: .finishDraft(count: count)
        case .waiting: .quiet
        }
    }

    /// Deska celá (#515) — všech šest pruhů a blok `Dění`.
    ///
    /// Bere **plný** seznam, ne zúžený filtrem (#117): domov je tvrzení o tom, co je na tahu, ne
    /// o tom, co je zrovna vidět v seznamu — tatáž úvaha jako u souhrnu ve stavovém řádku.
    /// Rozřazení podle autora se dělá **jednou** (`ownership(of:mine:)` na řádek), ne u každého
    /// pruhu.
    ///
    /// - Parameters:
    ///   - pending: kolik na vlastním PR zbývá předat (`HandoffReport.pending`). Uzávěrem, ne
    ///     mapou: čte se jen u vlastních PR a skládat pro desku kopii všech načtených konverzací
    ///     při každém průchodu tělem by byla práce za odpověď, kterou nikdo nepřečte (tatáž
    ///     úvaha jako u `ownPullRequestsAwaitingMove`).
    ///   - isMergeReady: je vlastní PR bez známé překážky? Taky uzávěrem, a s předfiltrem na
    ///     straně storu — bez načteného detailu se `mergeOffer` neskládá vůbec.
    static func board(
        entries: [QueueEntry],
        mine: Set<String> = [],
        pending: (PRIdentifier) -> Int = { _ in 0 },
        isMergeReady: (PRIdentifier) -> Bool = { _ in false },
        activity: [ActivityEvent] = [],
        lastVisit: Date? = nil,
        activityEmpty: ActivityEmptyState? = nil
    ) -> Board {
        var grouped: [WorkLane: [QueueEntry]] = [:]
        for entry in byUrgency(entries) {
            let ownership = self.ownership(of: entry.pullRequest, mine: mine)
            // U cizího PR se na předání ani na merge neptáme — obojí je otázka o **mojí** větvi
            // a uzávěr by kvůli ní sáhl na data, která se u cizího PR nenačítají.
            let lane = lane(
                of: entry,
                ownership: ownership,
                pending: ownership == .mine ? pending(entry.id) : 0,
                isMergeReady: ownership == .mine && isMergeReady(entry.id)
            )
            grouped[lane, default: []].append(entry)
        }
        return Board(
            lanes: WorkLane.order.map { lane in
                let rows = grouped[lane] ?? []
                return Board.Lane(lane: lane, rows: rows, action: laneAction(of: lane, count: rows.count))
            },
            activity: dashboardActivity(activity, since: lastVisit, empty: activityEmpty)
        )
    }

    /// Věta pod pozdravem (#515) — `8 věcí na tahu · 4 čekají na ostatní · 1 se dá mergnout`.
    ///
    /// **Mluví o pruzích, ne o počtech PR**, protože o tom je celá deska: „osm věcí na tahu“ je
    /// součet všech pruhů kromě tichého. Čísla, která nesly karty (kolik čeká ve frontě, kolik
    /// blokuje), zůstávají v railu a ve stavovém řádku.
    ///
    /// **Části, které by byly nulou, se nepíšou** — „0 čeká na ostatní“ je hlášení o ničem a
    /// pozdrav má být krátký. Když není na tahu nic, řekne se to slovem, ne nulou: prázdná deska
    /// je nejlepší možný stav a nesmí vypadat jako porucha.
    static func boardSentence(_ board: Board) -> String {
        let counts = Dictionary(uniqueKeysWithValues: board.lanes.map { ($0.lane, $0.count) })
        let onMove = board.lanes.filter { $0.lane.isOnMove }.reduce(0) { $0 + $1.count }
        let waiting = counts[.waiting] ?? 0
        let merge = counts[.merge] ?? 0

        guard onMove > 0 || waiting > 0 else {
            return "Nic na tahu — fronta je vyřízená a nic vlastního nečeká."
        }
        var parts: [String] = [
            onMove > 0
                ? Plural.czech(onMove, one: "věc na tahu", few: "věci na tahu", many: "věcí na tahu")
                : "nic na tahu"
        ]
        if waiting > 0 {
            parts.append(Plural.czech(
                waiting,
                one: "čeká na ostatní",
                few: "čekají na ostatní",
                many: "čeká na ostatní"
            ))
        }
        if merge > 0 {
            parts.append(Plural.czech(
                merge,
                one: "se dá mergnout",
                few: "se dají mergnout",
                many: "se dá mergnout"
            ))
        }
        // První část začíná velkým písmenem, zbytek ne — je to jedna věta oddělená středníkovými
        // tečkami, ne tři nadpisy.
        return parts.joined(separator: " · ").capitalizedFirst
    }

    /// Smí si deska vzít `⏎` (#515)?
    ///
    /// **Holá klávesa je jediná zkratka desky bez modifikátoru**, takže se musí ustupovat
    /// překryvu, který si ji bere sám: nad otevřenou paletou ⌘K je zkratka **okna** zakázaná a
    /// klávesa propadne dál — tentýž vzorec jako u `⌘⏎` v tabu `Zeptat se`
    /// (`Policy.claimsReturnShortcut`) a u `⎋` nad rozkliknutým commitem (`Policy.canCloseCommit`).
    static func canOpenFirstOnBoard(count: Int, isPaletteOpen: Bool) -> Bool {
        count > 0 && !isPaletteOpen
    }
}

private extension String {
    /// Věta začíná velkým písmenem. `localizedCapitalized` by zvětšilo **každé** slovo.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
