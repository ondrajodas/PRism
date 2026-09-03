import Foundation

/// Pruh na desce (#515) — **jeden tah**, ne stav a ne množina podle autora.
///
/// Do #515 byl domov uspořádaný podle **autora** (cizí fronta, moje PR) a podle **počtů** (pět
/// karet). Otázka, se kterou se aplikace otevírá, je ale „co udělám teď“ — a na tu odpovídalo
/// jedině řazení podle závažnosti uvnitř jedné z těch dvou front. Deska je proto **třetí pohled,
/// ne třetí množina**: bere tytéž řádky a skládá je podle toho, čí je tah.
///
/// **Rozřazení podle autora se tím neruší** (#331 platí dál): drží ho rail (`RailSection.queue`,
/// `RailSection.mine`) a všechno, co čte jen cizí PR (#332) — hromadné spuštění review,
/// notifikace, automat. Deska je nad tím jen jiné čtení.
enum WorkLane: String, CaseIterable, Hashable, Sendable {
    /// Cizí PR, na kterém review **doběhlo** — i to čisté, protože schválit je taky rozhodnutí.
    ///
    /// Patří sem i selhání, neprůkazný běh a zastaralé nálezy: i tam je tahem podívat se a
    /// rozhodnout, co dál (pustit znovu, nebo to tak nechat). **Ne do `read`** — ten je vázaný
    /// na `neběželo`, a to je přesně to, co hromadná akce pruhu pustí.
    case decide
    /// Cizí PR, na kterém review **neběželo** (`ReviewState.notStarted`).
    ///
    /// Je to **tatáž množina, jakou pouští `AppStore.startReviewsForNotReviewed()`**, a je to
    /// podmínka, ne shoda: počet v hlavičce pruhu je to, co akce udělá, takže běžící review sem
    /// nesmí — jinak by z akce byla ruleta a poznalo by se to jedině účtem za session.
    case read
    /// Vlastní PR, na kterém něco zbývá **předat agentovi** (`HandoffReport.pending > 0`).
    case handOff
    /// Vlastní PR **bez známé překážky k merge**.
    ///
    /// „Známé“ je tu podstatné: bez načteného detailu se o slévatelnosti nedá tvrdit nic, takže
    /// takový PR spadne do `waiting`. Nad nenačtenými daty je to ta bezpečná strana — deska
    /// nabídne o jeden tah **méně**, ne o jeden neexistující víc.
    case merge
    /// Zbytek: běžící review, vlastní PR, o kterém se nedá tvrdit ani `handOff`, ani `merge`.
    ///
    /// **Tichý pruh** — je to jediný, ve kterém se nic nedělá, takže se tak i kreslí (ztlumený,
    /// s nižším stropem, bez akce).
    case waiting
    /// Leží tu **rozdělané review** (neprázdný draft).
    ///
    /// **Přebíjí všechny ostatní**, protože je to ručně psaná práce: nedopsané review je můj tah
    /// bez ohledu na to, co se na PR mezitím stalo. Na vlastním PR draft od #333 nevzniká, ale
    /// starší tam být může — a zmizet nesmí (tatáž úvaha jako u karty `Rozdělaná review`).
    case finishReview

    /// Pořadí na obrazovce. **Zapsané tady, ne ve view** — je to rozhodnutí o tom, v jakém pořadí
    /// se otázky kladou, a takové rozhodnutí patří do `Policy`, kde se dá projít testem.
    ///
    /// **Osa je „jak blízko je ten řádek k tomu, aby míč nebyl u mě“, ne „čí to je“** (změna
    /// proti kresbě, z proklikání #515). Deck kreslil pořadí od cizí práce k vlastní
    /// (*rozhodnout · přečíst · předat · k merge · čeká · dopsat*) a `K merge` v něm bylo čtvrté;
    /// nad hotovou obrazovkou vyhrálo, že **mergnout je nejlevnější tah** a je jediný, po kterém
    /// řádek z desky rovnou zmizí — takže patří první.
    ///
    /// Tím se osa změnila, a s ní **jedna další věc, ne žádná**: `Dopsat a odeslat` jde z konce
    /// na druhé místo, protože je to tentýž druh „skoro hotovo“ — text už je napsaný, chybí ho
    /// odeslat. Zbylé čtyři si **relativní pořadí drží beze změny** (`decide` → `read` →
    /// `handOff` → `waiting`), protože v nové ose vycházejí stejně: u `Rozhodnout` už review
    /// doběhlo a kolega čeká na verdikt, u `Přečíst` to ještě nezačalo, `Předat agentovi` je
    /// vlastní práce, na kterou nečeká nikdo než já, a v tichém pruhu **míč u mě není vůbec**.
    ///
    /// **Tohle je pořadí kresby, ne přednost při rozřazování.** Že `finishReview` „přebíjí
    /// všechno“ (viz `lane(of:…)`) je věta o tom, do kterého pruhu PR **spadne**; že se kreslí
    /// druhý, je věta o tom, kde ten pruh na obrazovce **stojí**. Kdyby se ty dvě věci spletly,
    /// bylo by to čtení pořadí jako přednosti — a to je přesně ten druh záměny, kvůli které tu
    /// stojí tenhle odstavec.
    static let order: [WorkLane] = [.merge, .finishReview, .decide, .read, .handOff, .waiting]

    /// Nadpis pruhu.
    var title: String {
        switch self {
        case .decide: "Rozhodnout"
        case .read: "Přečíst"
        case .handOff: "Předat agentovi"
        case .merge: "K merge"
        case .waiting: "Čeká na ostatní"
        case .finishReview: "Dopsat a odeslat"
        }
    }

    /// Věta v prázdném pruhu.
    ///
    /// **Na pruh jiná**, jako u prázdných sekcí railu: prázdné `Rozhodnout` znamená „nic
    /// nedoběhlo“, kdežto prázdné `Dopsat a odeslat` znamená „nic jsi nezačal“ — a to je dobře.
    /// Jedna společná věta by u některého z nich lhala.
    var emptyExplanation: String {
        switch self {
        case .decide: "Nic nedoběhlo — není o čem rozhodovat."
        case .read: "Všechno ve frontě už review mělo."
        case .handOff: "Na vlastních PR nezbývá nic k předání."
        case .merge: "Nic se zrovna nedá mergnout."
        case .waiting: "Nic nečeká na ostatní."
        case .finishReview: "Nic rozepsaného."
        }
    }

    /// Je to ten tichý pruh? **Vlastnost pruhu, ne `if` ve view** — visí na tom ztlumení, strop
    /// řádků i to, že místo akce stojí popisek.
    var isQuiet: Bool { self == .waiting }

    /// Počítá se pruh do „věcí na tahu“? Tichý ne — o tom celá jeho existence je.
    var isOnMove: Bool { !isQuiet }
}

extension Policy {
    /// Do kterého pruhu pull request patří (#515).
    ///
    /// **Právě jeden pruh na PR**, a je to celý kontrakt téhle funkce: `switch` je vyčerpávající
    /// a návratový typ není optional, takže se nedá skončit nikde. Testuje se výčtem
    /// (`WorkLaneTests`) — rozřazení je věc, kterou se dá pokazit potichu.
    ///
    /// Pořadí rozhodování je pořadí odstavců níž a **není libovolné**:
    ///
    /// 1. **Rozdělané review přebíjí všechno.** Je to ručně psaná práce a ta se neztrácí za
    ///    stavem review ani za autorem.
    /// 2. **Běžící review je čekání.** Dokud session běží, není co udělat — a hlavně: kdyby
    ///    běžící PR zůstal v `read`, hromadná akce pruhu by hlásila víc, než pustí.
    /// 3. **Cizí PR** se dělí jedinou otázkou: *běželo, nebo neběželo.* `notStarted` je `read`
    ///    (tedy přesně to, co pustí `startReviewsForNotReviewed()`), všechno ostatní je `decide`.
    /// 4. **Vlastní PR** se dělí podle toho, co se dá udělat: co zbývá předat (`handOff`), co se
    ///    dá mergnout (`merge`), zbytek čeká.
    ///
    /// - Parameters:
    ///   - pending: kolik zbývá předat agentovi (`HandoffReport.pending`). Na cizím PR se nečte —
    ///     volající ho tam ani nemá odkud vzít, protože zadání se skládá jedině z vlastních.
    ///   - isMergeReady: je vlastní PR **bez známé překážky**? Rozhoduje `isMergeReady(_:)` nad
    ///     `MergeOffer`, tedy tatáž funkce, ze které se kreslí sekce `Větev` — druhé místo by
    ///     znamenalo dvě odpovědi na jednu otázku.
    static func lane(
        of entry: QueueEntry,
        ownership: PullRequestOwnership,
        pending: Int,
        isMergeReady: Bool
    ) -> WorkLane {
        if entry.hasDraft { return .finishReview }
        switch entry.state {
        case .queued, .cloning, .running: return .waiting
        case .notStarted, .clean, .completed, .dismissed, .inconclusive,
             .failed, .checkoutFailed, .timedOut, .interrupted, .stale:
            break
        }
        guard ownership == .mine else {
            return entry.state == .notStarted ? .read : .decide
        }
        if pending > 0 { return .handOff }
        return isMergeReady ? .merge : .waiting
    }

    /// Je vlastní PR **bez známé překážky k merge** (#515)?
    ///
    /// Staví na `mergeOffer(…)`, tedy na tom jediném místě, které o překážkách rozhoduje — deska
    /// si vlastní seznam podmínek neskládá. Přebírá z něj ale **jednu výjimku**: překážka
    /// `notAllowed` mluví o **bráně odesílání**, tedy o tom, co smí *aplikace*, ne o tom, jak
    /// stojí *pull request*. S výchozím (vypnutým) odesíláním by jinak pruh `K merge` byl
    /// navždycky prázdný, a to je tvrzení o nastavení, ne o práci.
    ///
    /// `absent` je **`false`**: to je cizí PR, kde se merge nekreslí vůbec — a i kdyby se sem
    /// takový dostal, „nevím“ je na desce vždycky odpověď `waiting`.
    static func isMergeReady(_ offer: MergeOffer) -> Bool {
        switch offer {
        case .absent: false
        case .allowed: true
        case .blocked(let obstacles): obstacles.allSatisfy(\.isPublishingGate)
        }
    }
}

extension Policy.MergeObstacle {
    /// Mluví ta překážka o **bráně odesílání**, ne o pull requestu (#515)?
    ///
    /// Existuje kvůli desce: pruh `K merge` se ptá „jak stojí PR“, kdežto tahle jedna překážka
    /// odpovídá na „smí aplikace odeslat“. Sekce `Větev` je nerozlišuje schválně — tam se
    /// vypisují všechny důvody, proč tlačítko nejde zmáčknout.
    var isPublishingGate: Bool {
        if case .notAllowed = self { return true }
        return false
    }
}
