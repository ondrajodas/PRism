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
    /// Vlastní PR, na kterém něco zbývá **předat agentovi** (`HandoffReport.awaitsMove`) — a který
    /// se přitom **nedá mergnout**: slévatelnost je silnější signál a přebíjí předání vždycky
    /// (viz `lane(of:…)`).
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
    /// odeslat. Zbylé tři si **relativní pořadí drží beze změny** (`decide` → `read` →
    /// `waiting`), protože v nové ose vycházejí stejně: u `Rozhodnout` už review doběhlo a kolega
    /// čeká na verdikt, u `Přečíst` to ještě nezačalo a v tichém pruhu **míč u mě není vůbec**.
    ///
    /// **`Předat agentovi` je poslední, a to je pokyn, ne výsledek té osy** (druhé proklikání
    /// #515 — ruší jeho páté místo, které tu stálo předtím). V ose vycházel pátý, tedy **nad**
    /// tichým pruhem: je to vlastní práce, na kterou nikdo nečeká. Nad hotovou obrazovkou ale
    /// vyhrálo, že **návrhy od agenta jsou nejnižší priorita** — je to nabídka, kterou si můžu
    /// vzít, kdežto v tichém pruhu se aspoň dozvím, na co se čeká.
    ///
    /// **Osa se tím nemění**, a je to tady napsané schválně: kdo bude příště pořadí posuzovat
    /// podle osy, dostane u `handOff` páté místo — a **nesmí ho podle toho „opravit“**. Z osy
    /// plyne jedině to, že `handOff` je za `read`; že je až za `waiting`, je rozhodnutí člověka
    /// a mění se jedině dalším rozhodnutím člověka.
    ///
    /// **Tohle je pořadí kresby, ne přednost při rozřazování.** Že `finishReview` „přebíjí
    /// všechno“ (viz `lane(of:…)`) je věta o tom, do kterého pruhu PR **spadne**; že se kreslí
    /// druhý, je věta o tom, kde ten pruh na obrazovce **stojí**. Kdyby se ty dvě věci spletly,
    /// bylo by to čtení pořadí jako přednosti — a to je přesně ten druh záměny, kvůli které tu
    /// stojí tenhle odstavec.
    static let order: [WorkLane] = [.merge, .finishReview, .decide, .read, .waiting, .handOff]

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

    // **Věta na prázdný pruh tu do proklikání #515 byla a odešla s ním** (`Nic nedoběhlo — není
    // o čem rozhodovat.` a spol.). Prázdný pruh se od té doby nekreslí (`Board.visibleLanes`),
    // takže by ji nikdo nepřečetl — a držet text, který se nemá kde ukázat, je mrtvá váha, která
    // svádí spolehnout se na ni. Co říct, když není ani jeden pruh, skládá
    // `Policy.boardEmpty(isLoaded:)`, a je to **jedna** věta o celé desce, ne šest o pruzích.

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
    /// 4. **Vlastní PR** se dělí podle toho, co se dá udělat — a **slévatelnost vyhrává vždycky**
    ///    (druhé proklikání #515): mergnutelný PR je `merge`, i když na něm něco zbývá předat,
    ///    a **výjimka z toho žádná není**. Nemergnutelný PR se dělí jako dřív: co zbývá předat
    ///    je `handOff`, zbytek čeká.
    ///
    ///    **Ruší se tím výjimka pro `HandoffReport.Stage.changed`**, která tu stála po prvním
    ///    proklikání: nevyřízené předání (typicky cizí odpověď v předaném vlákně) drželo PR
    ///    v `handOff` i nad slévatelnou větví. **Pokyn zní, že mergnutelný PR patří do `K merge`,
    ///    tečka** — takže po `outranksMerge` nezůstalo ani prázdné `false`, protože stav, který
    ///    nikdo nečte, svádí spolehnout se na něj.
    ///
    ///    Ještě dřív to bylo obráceně (`pending > 0` přebíjelo merge) a projevilo se to na
    ///    schváleném PR se všemi checky zelenými, který ležel v `Předat agentovi`
    ///    ([`keboola/job-queue-daemon#934`](https://github.com/keboola/job-queue-daemon/pull/934)).
    ///
    ///    **Informace o předání se tím neztrácí, a nebylo pro to potřeba nic přidávat**: pilulka
    ///    `N k předání` i `Prompt →` visí na **řádku** (`PullRequestRow.pendingHandoff`), ne na
    ///    pruhu, takže jdou s PR do kteréhokoli pruhu — a **na stavu předání nezávisí ani jedna
    ///    z nich**, takže `changed` je v `K merge` vidět stejně jako kdekoli jinde. Jedna podoba
    ///    řádku, ne třetí (#172).
    ///
    /// - Parameters:
    ///   - handoff: v jakém stavu je předání agentovi. Čte se z něj **jedině `awaitsMove`**, tedy
    ///     tatáž otázka, jakou odpovídá odznak `Moje PR` v railu — dvě odpovědi na „zbývá tu něco?“
    ///     by se dala rozejít, a je na to tvrzení. `stage` se do rozřazování **nedostane vůbec**
    ///     (od druhého proklikání #515). Na cizím PR se report nečte — volající ho tam ani nemá
    ///     odkud vzít, protože zadání se skládá jedině z vlastních.
    ///   - isMergeReady: je vlastní PR **bez známé překážky**? Rozhoduje `isMergeReady(_:)` nad
    ///     `MergeOffer`, tedy tatáž funkce, ze které se kreslí sekce `Větev` — druhé místo by
    ///     znamenalo dvě odpovědi na jednu otázku.
    static func lane(
        of entry: QueueEntry,
        ownership: PullRequestOwnership,
        handoff: HandoffReport,
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
        if isMergeReady { return .merge }
        return handoff.awaitsMove ? .handOff : .waiting
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
