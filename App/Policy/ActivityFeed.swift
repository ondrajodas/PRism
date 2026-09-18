import Foundation

/// Jeden řádek sekce `Dění` (#414) — položka plus to, co se o ní musí vědět **před** kreslením.
///
/// Existuje ze stejných dvou důvodů jako `ConversationRow` (#361): **identita je uložená**, ne
/// počítaná při každém dotazu líného seznamu, a **značka poslední návštěvy je rozhodnutí**, ne
/// `if` nad sousedním prvkem ve view.
struct ActivityFeedRow: Identifiable, Hashable, Sendable {
    /// Identita položky. Tatáž hodnota jako `event.id` — jen přečtená z pole, ne skládaná.
    let id: String
    let event: ActivityEvent
    /// Kreslí se **před** tímhle řádkem pruh `Tady jsem skončil`?
    ///
    /// Řadí se od nejnovějšího (#316), takže pruh stojí **pod** novinkami a popisek se proti
    /// konverzaci obrací: `Nové od tvé poslední návštěvy` by v obráceném pořadí ukazovalo na to,
    /// co už jsem viděl.
    let isFirstSeen: Bool
}

/// Blok jednoho dne v sekci `Dění` (#414).
///
/// Den je nadpis bloku, ne oddělovač uvnitř seznamu: obrazovka nemá filtry (poznámka 94 v návrhu),
/// takže den a strop 200 položek jsou celé členění, které má.
struct ActivityFeedDay: Identifiable, Hashable, Sendable {
    /// `yyyy-MM-dd` toho dne — stabilní klíč, ne pořadí v poli.
    let id: String
    /// `Dnes`, `Včera`, jinak `čtvrtek 20. srpna`.
    let title: String
    /// Co stojí v nadpisu za tečkou: **počet nepřečtených** v tom dni, a když žádné nejsou, celé
    /// datum u relativních titulků. `nil` = nic.
    ///
    /// Počet patří do nadpisu, i když odznak v railu od #526 svítí i na aktivní sekci: nadpis
    /// počítá nepřečtené **v tom dni**, odznak v **celém záznamu**. Přes půlnoc se ta dvě čísla
    /// rozejdou, a je to tak správně — každé odpovídá na jinou otázku. (Do #526 tu stálo, že na
    /// aktivní položce se odznak nekreslí; ten důvod odpadl s pruhem na hraně railu.)
    let note: String?
    let rows: [ActivityFeedRow]
}

/// Jak se u řádku dění napíše čas (#443).
///
/// **Rozhodnutí, ne hotový text u obou podob.** Relativní stáří se v okně přepočítává samo
/// (`Text(_:format:)`), takže řetězec z `Policy` by zamrzl na tom, kdy se poskládal — kdežto
/// u hodin je den součástí rozhodnutí a skládat ho ve view by znamenalo dvě místa, která si to
/// počítají sama.
enum ActivityTimeLabel: Hashable, Sendable {
    /// `před 2 min` — text skládá view, protože se sám přepočítává.
    case relative
    /// Hotový text: `v 7:58`, `včera v 7:58`, `20. srpna v 7:58`.
    case absolute(String)
}

/// Kde řádek dění stojí (#443) — a co z toho pro něj plyne.
///
/// **Jeden příznak, ne dva.** Obě věci, kterými se ty dvě podoby liší, plynou z **místa**, ne
/// z události: kolik je na řádek místa (sekce má celou šířku okna, blok na dashboardu 456 bodů)
/// a kdo nese den u času (v sekci hlavička dne, na dashboardu nikdo). Dva nezávislé booleany by
/// šlo nastavit křížem a vznikla by z toho třetí podoba, kterou návrh nekreslí.
enum ActivityRowPlace: Hashable, Sendable {
    /// Sekce `Dění` (#414) — celá událost na celé šířce okna, den nese hlavička dne.
    case section
    /// Blok `Dění` na dashboardu (#443) — úzký tvar (`.tl-line.slim`) a den u času.
    case dashboard
}

/// Co se ukáže, když v dění nic není (#414).
///
/// **Čtyři prázdna, která se nesmí slít**, ze stejného důvodu jako `čisté review` a `review se
/// nepovedlo`: první znamená klid, druhé ztracenou historii a poslední dvě „bannery nechodí“ —
/// a každé se spravuje jinde.
///
/// `CaseIterable` je od #443 a je to tvrzení, ne pohodlí: blok na dashboardu z každého z nich dělá
/// **jednu větu** a test se ptá, jestli je těch vět tolik, kolik je případů. Bez výčtu by pátý stav
/// mohl tiše splynout s klidem.
enum ActivityEmptyState: Hashable, CaseIterable, Sendable {
    /// Nic se nestalo. Klid, ne porucha.
    case calm
    /// Soubor se záznamem byl, ale nepřečetl se — **historie je ztracená**. Vlastní stav proto, že
    /// klidné „nic se nestalo“ by nad ním tvrdilo víc, než data unesou.
    case unreadable
    /// Systém notifikace zakázal. Spravit se to dá **jedině v Nastavení systému**.
    case notificationsDenied
    /// Notifikace jsou vypnuté v nastavení aplikace. **Zápis to nezastaví** — proto to má vlastní
    /// stav a vlastní východ; návrh kreslil jen ten zakázaný, tenhle je rozhodnutý při
    /// implementaci (jinak by vypnutý přepínač vypadal jako odmítnuté oprávnění).
    case notificationsOff
}

extension Policy {
    // MARK: - O čem se hlásí

    /// O čem se v dění **hlásí vůbec** (#414) — tatáž pravidla jako u notifikací (#332).
    ///
    /// Je to **jediná brána** a je tady schválně: dění čte tytéž události jako notifikace, takže
    /// bez ní by z něj byl obchvat pravidla „o vlastním PR se nehlásí“ — hláška, která se
    /// v banneru nesmí objevit, by na obrazovce zůstala navěky.
    ///
    /// Pravidlo se láme podle druhu, ne plošně, a je to totéž lámání jako u notifikací:
    ///
    /// - výsledky review, nový PR, znovu k review, zastaralé nálezy a odchod z fronty jsou
    ///   odpověď na **review request**, takže platí jen o **cizím** PR (`Policy.reviewNotification`
    ///   vlastní PR nevydá, `Policy.pullRequests(_:ownedBy:mine:)` je do fronty nepustí);
    /// - **cizí aktivita** je opačný směr — na **mém** PR se ozval někdo jiný —, takže platí jen
    ///   o vlastním (`Policy.activitySweep` sahá jen na `.mine`).
    ///
    /// Zastaralé nálezy patří k cizím PR proto, že na vlastním je push obvykle **můj** a hláška
    /// o vlastní práci je ten druh šumu, po kterém si člověk obrazovku přestane otevírat — tatáž
    /// úvaha, kvůli které `ForeignActivity` schválně nenese commity.
    static func isReported(_ kind: ActivityEvent.Kind, on ownership: PullRequestOwnership) -> Bool {
        switch kind {
        case .newPullRequest, .reReview, .findings, .clean, .failure, .staleFindings, .leftQueue,
             .returnedFromSnooze, .replyRound:
            // **Druhé kolo (#523) patří k cizím PR**: „odpověď na tvoje review“ je otázka o cizí
            // práci a na vlastním PR by z ní byl řádek o tom, že jsem si odpověděl sám.
            ownership == .theirs
        case .foreignActivity, .agentFix:
            // **Agent běží jedině na vlastním PR** (`Policy.agentFix` vrací `notMine` jako první
            // odpověď), takže řádek o něm nad cizím PR by byl záznam o něčem, co se nestalo.
            ownership == .mine
        }
    }

    /// Který druh dění odpovídá notifikační události.
    ///
    /// Existuje proto, aby se druh **neodvozoval z textu** — tatáž úvaha jako u `NotificationEvent`
    /// samotné. `isReReview` se předává zvlášť, protože banner o novém PR a o re-review nese jednu
    /// událost a liší se jen titulkem (#137): vypnout se to má jedním přepínačem, ale na ose jsou
    /// to dva různé glyfy.
    static func activityKind(of event: NotificationEvent, isReReview: Bool = false) -> ActivityEvent.Kind {
        switch event {
        case .newPullRequest: isReReview ? .reReview : .newPullRequest
        case .findings: .findings
        case .clean: .clean
        case .failure: .failure
        case .activity: .foreignActivity
        case .agentFix: .agentFix
        case .replies: .replyRound
        }
    }

    // MARK: - Kresba řádku

    /// Kam řádek vede (#414). Cíl se **píše do řádku**, ne kreslí jako holá šipka.
    static func destination(of kind: ActivityEvent.Kind) -> ActivityDestination {
        switch kind {
        // Nový PR a re-review vedou na `Přehled`: rozhodnutí „jdu do toho“ se dělá z popisu
        // a z faktů, ne z výsledků, které ještě nejsou.
        case .newPullRequest, .reReview: .tab(.overview)
        case .findings: .tab(.findings)
        // Čisté i spadlé review vede na `Průběh` — je to záznam běhu a u obojího je to jediné
        // místo, kde se dá poznat, co reviewer doopravdy dělal.
        case .clean, .failure: .tab(.progress)
        case .foreignActivity: .tab(.conversation)
        // **Na `Přehled`, protože nad tabem je dráha** (#508) a pod ní sekce `Větev` (#465, #510) —
        // tedy obojí, co o běhu agenta něco říká. Zadání #511 mluví o „kliku na dráhu“; dráha
        // žádný vlastní tab nemá, kreslí se **nad** pruhem záložek, takže ji `Přehled` otevře
        // stejně jako kterýkoli jiný — a `Přehled` k ní přidá to, co se o PR ví.
        case .agentFix: .tab(.overview)
        // **Druhé kolo vede na `Přehled`** (#523), protože tam je karta `Odpověď na tvoje review`
        // — tedy celý ten rozpis, o kterém řádek mluví. `Konverzace` by ukázala vlákna, ale ne to,
        // co s nimi udělaly commity.
        case .replyRound: .tab(.overview)
        // Zastaralé nálezy vedou na `Commity`, ne na `Nálezy`: rozhodnutí, co s nimi, se dělá
        // podle toho, co v těch commitech přišlo.
        case .staleFindings: .tab(.commits)
        // Jediný řádek, který do okna nevede — PR z fronty odešel, takže v seznamu není.
        case .leftQueue: .gitHub
        // Návrat z odložení vede na `Přehled`, jako příchod do fronty: je to tentýž okamžik —
        // PR je zpátky na stole a rozhodnutí „jdu do toho“ se dělá z popisu, ne z výsledků.
        case .returnedFromSnooze: .tab(.overview)
        }
    }

    /// Barva puntíku na ose.
    static func tone(of kind: ActivityEvent.Kind) -> ActivityTone {
        switch kind {
        case .newPullRequest, .reReview, .foreignActivity: .accent
        // **Jedna barva na celý druh, ne podle toho, jak běh dopadl.** Puntík odpovídá na „co to
        // je“, ne na „jak to dopadlo“ — to nese věta v řádku. Zeleně by se spadlý běh tvářil jako
        // úspěch, červeně by se hotová oprava tvářila jako porucha, a akcent je to, co obojí
        // spojuje: **na tomhle PR na tebe něco čeká**.
        case .agentFix: .accent
        // Tentýž důvod jako u agenta: puntík odpovídá na „co to je“, ne „jak to dopadlo“.
        // Zeleně by se řádek s jedním zbývajícím bodem tvářil jako hotovo.
        case .replyRound: .accent
        case .findings, .failure: .critical
        case .clean: .ok
        case .staleFindings: .stale
        // Odchod z fronty není dobrá ani zlá zpráva, takže nedostane barvu žádnou — řádek je
        // navíc celý ztlumený, protože nikam do okna nevede.
        case .leftQueue: .neutral
        // Návrat z odložení taky ne: je to změna pohledu, ne zpráva o PR. Zeleně by se tvářil
        // jako úspěch, červeně jako porucha, a je to ani jedno.
        case .returnedFromSnooze: .neutral
        }
    }

    /// Glyf v puntíku. Jména z SF Symbols proti znakům z návrhu (`⟲ 💬 ! ↓ ✓ − ✕ ↻`) — v okně se
    /// kreslí symbolem, ať se písmo puntíku nerozchází se zbytkem ikon.
    static func symbol(of kind: ActivityEvent.Kind) -> String {
        switch kind {
        case .newPullRequest: "arrow.down"
        case .reReview: "arrow.clockwise"
        case .findings: "exclamationmark"
        case .clean: "checkmark"
        case .failure: "xmark"
        case .foreignActivity: "bubble.left"
        case .agentFix: "wand.and.stars"
        case .replyRound: "arrowshape.turn.up.left"
        case .staleFindings: "clock.arrow.circlepath"
        case .leftQueue: "minus"
        case .returnedFromSnooze: "alarm"
        }
    }

    /// Kreslí se u řádku chip **bez banneru**?
    ///
    /// Jen u druhů, které banner **umí** — u dopočítaných (zastaralé nálezy, odchod z fronty) by
    /// tvrdil, že něco nedorazilo, přitom za ně banner nechodí nikdy a schválně: vyrušovat nemají,
    /// dohledat se mají. To je celý důvod, proč tahle obrazovka unese věci, které banner ne.
    static func showsSilentChip(_ kind: ActivityEvent.Kind, announced: Bool) -> Bool {
        guard !announced else { return false }
        switch kind {
        case .newPullRequest, .reReview, .findings, .clean, .failure, .foreignActivity,
             .agentFix, .replyRound:
            return true
        case .staleFindings, .leftQueue, .returnedFromSnooze: return false
        }
    }

    // MARK: - Skládání položek

    /// Řádek o novém PR ve frontě (#85) nebo o re-review (#137). `nil` = nehlásí se.
    ///
    /// **Titulek PR jde do detailu, ne do headline.** Banner nese `owner/repo#85` v titulku, protože
    /// v něm není kde jinde identifikaci napsat; v řádku se PR kreslí samostatně, takže by se
    /// zopakovalo.
    static func newPullRequestActivity(
        for pr: PRIdentifier,
        title: String?,
        author: String? = nil,
        isReReview: Bool = false,
        ownership: PullRequestOwnership = .theirs,
        at: Date,
        announced: Bool
    ) -> ActivityEvent? {
        let kind = activityKind(of: .newPullRequest, isReReview: isReReview)
        guard isReported(kind, on: ownership) else { return nil }
        return ActivityEvent(
            id: identity(kind, pr, at: at),
            kind: kind,
            pullRequest: pr,
            at: at,
            headline: isReReview ? "Znovu k review" : "Nový PR k review",
            // Chybějící titulek je vlastní stav, ne prázdný řádek — tatáž úvaha jako u banneru.
            detail: title,
            wasAnnounced: announced,
            // Autor jen u příchodu do fronty (návrh, sekce 27): je to „kdo na mě čeká“. Prázdný
            // se zahazuje, ať za `owner/repo#85` nezůstane visící tečka.
            author: author.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    /// Řádek o doběhlém review (#82). `nil` = není o čem psát.
    ///
    /// **Staví na `reviewNotification`**, ne na vlastním rozboru stavu: co je konec běhu a jak se
    /// jmenuje, je jedno rozhodnutí a druhá odpověď na něj by se s první rozešla — pak by banner
    /// a řádek dění nad tímtéž během řekly dvě různé věci.
    static func reviewActivity(
        for pr: PRIdentifier,
        ownership: PullRequestOwnership = .theirs,
        state: ReviewState,
        blocking: Int = 0,
        topFinding: Finding? = nil,
        at: Date,
        announced: Bool
    ) -> ActivityEvent? {
        guard let notification = reviewNotification(
            for: pr,
            ownership: ownership,
            state: state,
            blocking: blocking,
            topFinding: topFinding
        ) else { return nil }
        let kind = activityKind(of: notification.event)
        guard isReported(kind, on: ownership) else { return nil }
        return ActivityEvent(
            id: identity(kind, pr, at: at),
            kind: kind,
            pullRequest: pr,
            at: at,
            headline: notification.title,
            detail: reviewActivityDetail(state: state, topFinding: topFinding),
            wasAnnounced: announced
        )
    }

    /// Druhá půlka řádku o review. `nil` = titulek řekl všechno.
    ///
    /// Bere se **totéž tělo jako v banneru** (`notificationDetail`), jen u `clean` se zahazuje:
    /// „Čisté review · Reviewer nenašel žádný nález“ je jedna věta dvakrát. Kolik skillů běželo
    /// a co to stálo (návrh sekce 27 to v řádku kreslí) se sem nedává — to je záznam běhu a je
    /// v tabu `Průběh`, kam ten řádek vede.
    private static func reviewActivityDetail(state: ReviewState, topFinding: Finding?) -> String? {
        if case .clean = state { return nil }
        return notificationDetail(state: state, topFinding: topFinding)
    }

    /// Řádek o cizí aktivitě na **vlastním** PR (#335). `nil` = nehlásí se.
    ///
    /// **Nejnovější věta je headline, počet je detail** — obráceně než u banneru, a je to
    /// z návrhu (sekce 27): v seznamu je to věta, podle které se řádek pozná, kdežto banner se čte
    /// odshora a nahoru patří „kolik a čeho“. Počet se přitom kreslí jen tehdy, když je položek
    /// **víc než jedna**: „odinuv: …“ a za tím „1 nový komentář“ je totéž dvakrát.
    static func foreignActivityEvent(
        for pr: PRIdentifier,
        ownership: PullRequestOwnership = .mine,
        activity: ForeignActivity,
        at: Date,
        announced: Bool
    ) -> ActivityEvent? {
        guard isReported(.foreignActivity, on: ownership) else { return nil }
        guard let summary = activityHeadline(activity) else { return nil }
        let sentence = activityDetail(activity)
        return ActivityEvent(
            id: identity(.foreignActivity, pr, at: at),
            kind: .foreignActivity,
            pullRequest: pr,
            at: at,
            headline: sentence ?? summary,
            detail: sentence == nil || activity.count < 2 ? nil : summary,
            wasAnnounced: announced
        )
    }

    /// Řádek o tom, že doběhl agent na **vlastním** PR (#511). `nil` = nehlásí se.
    ///
    /// **Headline je tentýž text jako titulek banneru** (`Policy.agentRunHeadline`), na rozdíl od
    /// cizí aktivity, kde se ty dva obracejí. Důvod je v tom, čím se ta položka pozná: u cizí
    /// aktivity je to **věta, kterou někdo napsal**, kdežto tady je to **jak to dopadlo** — a to
    /// je zrovna to, co se do titulku vejde celé. Druhé skládání téhož by se s bannerem rozešlo.
    ///
    /// **Detail je celá věta o výsledku**, tedy ta z panelu (`Policy.agentRunSentence`) — v řádku
    /// je na ni místo a je to jediné místo, kde se to, co agent nechal být, dá po týdnu dohledat:
    /// stav v `AppStore` se zavřením aplikace ztratí a záznam běhu se k PR neukládá.
    static func agentFixEvent(
        for pr: PRIdentifier,
        ownership: PullRequestOwnership = .mine,
        outcome: AgentRunOutcome,
        worktree: String?,
        at: Date,
        announced: Bool
    ) -> ActivityEvent? {
        guard isReported(.agentFix, on: ownership) else { return nil }
        return ActivityEvent(
            id: identity(.agentFix, pr, at: at),
            kind: .agentFix,
            pullRequest: pr,
            at: at,
            headline: agentRunHeadline(outcome),
            detail: agentRunSentence(outcome, worktree: worktree),
            wasAnnounced: announced
        )
    }

    /// Řádek o tom, že nálezy zastaraly (tvrdá podmínka č. 5). `nil` = nehlásí se.
    ///
    /// Klíčem položky je **hlava**, ne okamžik — téhož rozchodu si aplikace všimne při každém
    /// dalším dotažení detailu i při každém dotazu na hlavy, a druhý řádek o téže věci by byl šum.
    ///
    /// `commits` je `nil`, když se počet spočítat nedá — buď hlava nálezů v seznamu commitů není
    /// (typicky po force-pushi), nebo se o rozchodu ví z tiku a seznam commitů se kvůli němu
    /// **netahá** (#420). Pak se o commitech **nemluví**; vymyslet číslo by bylo horší než ho
    /// neuvést.
    ///
    /// **Řádek nese čas události, ne čas zjištění** (#420). Nálezy zastaraly ve chvíli, kdy hlava
    /// vznikla, takže se datuje `headAt`. Datum zjištění by po restartu tvrdilo, že práce
    /// z minulého týdne zastarala dneska — a je to schválně **rozhodnutí `Policy`**, ne `??` na
    /// volajícím: obě cesty (dotažený detail, dávkový dotaz z tiku) musí datovat stejně, jinak by
    /// tentýž rozchod měl dvě data podle toho, kdo si ho všiml první.
    ///
    /// Cena je, že řádek nalezený se zpožděním padne do **svého** dne, tedy pod značku poslední
    /// návštěvy, a nepočítá se jako nepřečtený. Druhé razítko (událost pro kresbu, zjištění pro
    /// nepřečtené) by rozbilo invariant, na kterém stojí pruh `Tady jsem skončil` — nové položky
    /// jsou **předpona** seznamu (`Policy.activityFeed`).
    ///
    /// - Parameters:
    ///   - headAt: kdy vznikla hlava, na kterou se PR posunul. `nil` = nevíme (force-push, commit
    ///     mimo seznam, odpověď bez data). **Bez výchozí hodnoty schválně**: zapomenutý parametr by
    ///     tiše vrátil datování okamžikem zjištění, tedy přesně tu chybu, kvůli které #420 vzniklo.
    ///   - noticedAt: kdy si toho aplikace všimla. Použije se **jedině** bez `headAt` — tvrdit
    ///     datum, které v datech není, je horší než datum zjištění.
    static func staleFindingsActivity(
        for pr: PRIdentifier,
        ownership: PullRequestOwnership = .theirs,
        head: String,
        commits: Int?,
        headAt: Date?,
        noticedAt: Date
    ) -> ActivityEvent? {
        guard isReported(.staleFindings, on: ownership) else { return nil }
        return ActivityEvent(
            // Hlava, ne čas: viz doc komentář výš.
            id: "\(ActivityEvent.Kind.staleFindings.rawValue)|\(pr)|\(head)",
            kind: .staleFindings,
            pullRequest: pr,
            at: headAt ?? noticedAt,
            headline: "Nálezy zastaraly",
            detail: staleCommitsPhrase(commits),
            head: head
        )
    }

    /// `přišly 3 commity, hlava je teď` — sha se kreslí jako pilulka za tím, takže tady není.
    ///
    /// Sloveso se skloňuje **zvlášť** (`Plural.word`), jako u blokujících nálezů: „přišly 1 commit“
    /// je ta třída chyby, kterou u #131 našel Copilot.
    private static func staleCommitsPhrase(_ commits: Int?) -> String {
        guard let commits, commits > 0 else { return "hlava je teď" }
        let verb = Plural.word(commits, one: "přišel", few: "přišly", many: "přišlo")
        let noun = Plural.czech(commits, one: "commit", few: "commity", many: "commitů")
        return "\(verb) \(noun), hlava je teď"
    }

    /// Kolik commitů přišlo **po** téhle sha. `nil` = z těch dat se to říct nedá.
    ///
    /// Seznam commitů PR přijde od nejstaršího, takže se počítá zbytek za nalezeným commitem.
    /// `nil` u sha, která v seznamu **není**: po force-pushi tam hlava nálezů být nemusí a číslo
    /// dopočítané odjinud by tvrdilo, co se nestalo. Volání navíc to nestojí — commity si tahá
    /// `loadDetail` tak jako tak (#316).
    static func commitsAfter(_ sha: String, in commits: [PullRequestCommit]) -> Int? {
        guard let index = commits.firstIndex(where: { $0.sha == sha }) else { return nil }
        return commits.count - index - 1
    }

    /// Kdy vznikl commit s touhle sha. `nil` = v seznamu není, nebo u něj datum nepřišlo.
    ///
    /// Tím se datuje řádek o zastaralých nálezech u cesty přes dotažený detail (#420) — je to
    /// **tatáž hodnota**, jakou u dávkového dotazu na hlavy nese `PullRequestHead.committedAt`,
    /// jen z druhého zdroje. Dvě různá data pod jedním rozchodem by znamenala, že se řádek mění
    /// podle toho, kdo si ho všiml první.
    static func commitDate(of sha: String, in commits: [PullRequestCommit]) -> Date? {
        commits.first { $0.sha == sha }?.committedAt
    }

    /// Řádek o tom, že PR odešel z fronty. `nil` = nehlásí se.
    ///
    /// **Proč odešel, se neříká** (poznámka 92 v návrhu): mergnuto, zavřeno, zrušený review request
    /// nebo moje odeslané review se ze samotného snímku fronty rozlišit nedá — a dotahovat kvůli
    /// jednomu řádku detail je volání za nic.
    static func departureActivity(
        for pr: PRIdentifier,
        ownership: PullRequestOwnership = .theirs,
        at: Date
    ) -> ActivityEvent? {
        guard isReported(.leftQueue, on: ownership) else { return nil }
        return ActivityEvent(
            id: identity(.leftQueue, pr, at: at),
            kind: .leftQueue,
            pullRequest: pr,
            at: at,
            headline: "Už není ve frontě",
            detail: "mergnuto, nebo zrušený request — z fronty se to nepozná"
        )
    }

    /// Řádek o tom, že se PR vrátil z odložení (#512). `nil` = nehlásí se.
    ///
    /// **Bez tohohle řádku by se PR ve frontě objevil odnikud** — a to je zrovna ta vlastnost,
    /// kvůli které je odložení riskantní věc: schová práci a pak ji tiše vrátí. Řádek říká
    /// **proč** se vrátil (`došel čas`, `přišel push`, `přišel komentář`, `vrátil jsem ho ručně`),
    /// protože to je jediné, co z fronty samotné vidět není.
    ///
    /// **Banner za něj nechodí** (`showsSilentChip(_:announced:)` u něj chip nekreslí): návrat je
    /// splnění mé vlastní objednávky, ne novinka zvenčí. Že PR leží ve frontě, řekne fronta.
    static func snoozeReturnActivity(
        for pr: PRIdentifier,
        ownership: PullRequestOwnership = .theirs,
        reason: SnoozeReturn,
        at: Date
    ) -> ActivityEvent? {
        guard isReported(.returnedFromSnooze, on: ownership) else { return nil }
        return ActivityEvent(
            id: identity(.returnedFromSnooze, pr, at: at),
            kind: .returnedFromSnooze,
            pullRequest: pr,
            at: at,
            headline: "Vrátil se z odložení",
            detail: snoozeReturnDetail(reason)
        )
    }

    /// Adresa pull requestu na GitHubu. `nil` = nesložila se (nemá se stát, `RepoID` je platná
    /// cesta).
    ///
    /// **Skládá se z identity, ne ze shrnutí**, a to je celý důvod, proč to existuje: řádek
    /// `už není ve frontě` mluví o PR, který ze seznamu **odešel**, takže žádné shrnutí s `url`
    /// v paměti není. Přes `URLComponents` jako permalink v těle review, ať se nic neescapuje ručně.
    static func gitHubURL(of pr: PRIdentifier) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(pr.repo)/pull/\(pr.number)"
        return components.url
    }

    /// Identita položky: druh, PR a okamžik.
    ///
    /// **Deterministická**, aby přežila uložení a načtení a aby se dvě všimnutí téže věci slila.
    /// Okamžik se píše jako počet sekund od referenčního data, ne přes locale — je to klíč, ne text
    /// pro člověka.
    /// **Není `private` od #523**: skládá ji i `replyRoundActivity`, která bydlí ve vlastním
    /// souboru (druhé kolo má vlastní notifikaci i vlastní řádek). Druhé skládání téhož klíče by
    /// znamenalo dvě pravidla, podle kterých se položky slévají.
    static func identity(_ kind: ActivityEvent.Kind, _ pr: PRIdentifier, at: Date) -> String {
        "\(kind.rawValue)|\(pr)|\(at.timeIntervalSinceReferenceDate)"
    }

    // MARK: - Záznam

    /// Kolik položek se v dění pamatuje.
    ///
    /// **Strop na položky, ne na dny** (návrh, poznámka 93): dění odpovídá na „co jsem prošvihl“,
    /// a to je omezené pozorností, ne kalendářem — týdenní okno jako u `SpendLedger` by usekávalo
    /// přesně tu dovolenou, kvůli které se sem chodí. Mez je vidět v typu schválně: cache bez
    /// vyjmenované meze je únik paměti s odkladem (#224).
    static let activityLimit = 200

    /// Uložený záznam po přidání nových položek — **od nejnovějšího, bez duplicit, se stropem**.
    ///
    /// Jedno místo pro obojí (disk i paměť), takže se nemají čím rozejít. Při překročení stropu
    /// odcházejí **nejstarší** položky: dění je o tom, co jsem prošvihl, a to nejstarší jsem
    /// prošvihl nejdřív.
    ///
    /// Řadí se podle času a při shodě podle identity, aby bylo pořadí stabilní — jinak by se
    /// seznam mezi dvěma načteními přehazoval a líný seznam by přerovnával obsah bez důvodu.
    static func activityLog(
        _ stored: [ActivityEvent],
        adding: [ActivityEvent],
        limit: Int = activityLimit
    ) -> [ActivityEvent] {
        guard limit > 0 else { return [] }
        var known = Set(stored.map(\.id))
        var merged = stored
        for event in adding where known.insert(event.id).inserted {
            merged.append(event)
        }
        return merged
            .sorted { ($0.at, $0.id) > ($1.at, $1.id) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Co je nové

    /// Kolik položek je nepřečtených — proti značce poslední návštěvy.
    ///
    /// **Bez značky je nové všechno**, a je to opačná volba než u konverzace (#173), kde `nil`
    /// znamená prázdno. Důvod je v tom, co ta data jsou: záznam dění vzniká teprve za běhu
    /// aplikace, takže „nikdy jsem tu nebyl“ znamená, že jsem opravdu nic z toho neviděl — kdežto
    /// u PR by to znamenalo vypsat celou jeho historii.
    static func unreadActivity(_ events: [ActivityEvent], since: Date?) -> Int {
        guard let since else { return events.count }
        return events.count { $0.at > since }
    }

    /// Odznak sekce `Dění` v railu. `nil` = nekreslí se.
    ///
    /// **Počítá nepřečtené**, ne všechno: počítadlo nad celým záznamem by svítilo navěky a to, co
    /// otravuje, se spravuje **posunem značky**, ne bledší barvou.
    ///
    /// **Kreslí se i na aktivní sekci** (#526, mění rozhodnutí z #414). Do #526 rozhodovalo i to,
    /// jestli v `Dění` zrovna stojím: odznak seděl **na** ikoně a překryl ji, takže by na aktivní
    /// položce zbyl červený puntík bez identity (poznámka 95 v návrhu). Od #526 je odznak
    /// v **rohu** ikony a aktivní sekci značí **pruh na hraně railu** (`SidebarRail`), takže ten
    /// důvod odpadl — a `Dění` ukazuje počet nepřečtených i zevnitř, což je zrovna to místo, kde
    /// na něj člověk kouká.
    ///
    /// Argument o viditelnosti proto **zmizel celý**, ne že by se ignoroval: parametr, o kterém se
    /// nerozhoduje, je jen místo, kam se dá omylem sáhnout.
    static func activityBadge(unread: Int) -> Int? {
        unread > 0 ? unread : nil
    }

    // MARK: - Řádky a bloky

    /// Sekce `Dění` po dnech (#414) — co se kreslí, v jakém pořadí a kde je pruh poslední návštěvy.
    ///
    /// **Od nejnovějšího** jako seznam commitů (#316), takže pruh stojí **pod** novinkami. Kreslí
    /// se před první **už viděnou** položkou, a jen když nad ním něco nového je: pruh úplně nahoře
    /// by říkal „všechno pod tebou znáš“, tedy nic.
    static func activityFeed(
        _ events: [ActivityEvent],
        since: Date? = nil,
        now: Date,
        calendar: Calendar = .current
    ) -> [ActivityFeedDay] {
        // **Pořadí se srovná znovu, i když ho volající drží.** Hranice pruhu se počítá z toho, že
        // nové položky jsou **předpona** seznamu (jedno číslo místo hledání souseda), takže mlčky
        // věřit vstupu znamená, že by špatné pořadí nakreslilo pruh na cizí místo. Cena je jedno
        // seřazení nejvýš dvou set položek na průchod tělem — strop je právě to, co ji ohraničuje.
        let ordered = activityLog([], adding: events, limit: max(events.count, 1))
        let unread = unreadActivity(ordered, since: since)
        let rows = ordered.enumerated().map { index, event in
            ActivityFeedRow(
                id: event.id,
                event: event,
                // Pořadí je od nejnovějšího a „nové“ je `at > since`, takže nové položky jsou
                // vždycky **předpona** seznamu — hranice je proto jedno číslo, ne hledání souseda.
                isFirstSeen: unread > 0 && index == unread
            )
        }
        return days(of: rows, since: since, now: now, calendar: calendar)
    }

    private static func days(
        of rows: [ActivityFeedRow],
        since: Date?,
        now: Date,
        calendar: Calendar
    ) -> [ActivityFeedDay] {
        var order: [String] = []
        var grouped: [String: [ActivityFeedRow]] = [:]
        for row in rows {
            let key = dayKey(of: row.event.at, calendar: calendar)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(row)
        }
        return order.compactMap { key in
            guard let rows = grouped[key], let first = rows.first else { return nil }
            let distance = dayDistance(from: first.event.at, to: now, calendar: calendar)
            let fresh = rows.count { row in since.map { row.event.at > $0 } ?? true }
            return ActivityFeedDay(
                id: key,
                title: dayTitle(of: first.event.at, distance: distance),
                note: dayNote(of: first.event.at, distance: distance, unread: fresh),
                rows: rows
            )
        }
    }

    /// `yyyy-MM-dd` z komponent, ne z `DateFormatter`: klíč se nemá měnit s nastavením systému
    /// a `Policy` je bez I/O i bez sdíleného stavu.
    private static func dayKey(of date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Kolik dní zpátky ten den je. Přes `Calendar`, ne odečítáním sekund — letní čas dělá dny
    /// o hodinu kratší a delší, takže by se den občas přeskočil (tatáž úvaha jako v `SpendLedger`).
    private static func dayDistance(from date: Date, to now: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: date)
        let to = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    private static func dayTitle(of date: Date, distance: Int) -> String {
        switch distance {
        case 0: "Dnes"
        case 1: "Včera"
        default: longDay(date)
        }
    }

    /// Za tečkou v nadpisu bloku: počet nepřečtených, a když žádné nejsou, celé datum u `Dnes`
    /// a `Včera` — u nich je to jediné místo, kde se datum dá přečíst.
    private static func dayNote(of date: Date, distance: Int, unread: Int) -> String? {
        guard unread == 0 else {
            return Plural.czech(unread, one: "nová", few: "nové", many: "nových")
        }
        return distance <= 1 ? longDay(date) : nil
    }

    /// `čtvrtek 20. srpna`. Formátuje se přes locale — bundle deklaruje `cs`, takže se den
    /// nepojmenuje anglicky vedle českých popisků.
    private static func longDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    // MARK: - Čas a hlavička

    /// Jak dlouho zpátky se čas píše relativně (`před 2 min`) a odkdy hodinami (`v 07:58`).
    ///
    /// Dvě hodiny, protože blok už den nese v nadpisu: `před 14 hodinami` je nad hlavičkou `Dnes`
    /// horší než `v 07:58`, ze kterého se pozná, jestli to bylo před schůzkou nebo po ní. Relativní
    /// čas má hodnotu jen u toho, co se stalo teď — tam je zase `v 09:10` k ničemu.
    static let relativeActivityWindow: TimeInterval = 2 * 60 * 60

    /// Píše se u řádku relativní čas, nebo hodiny?
    ///
    /// Rozhodnutí, ne formátování: samotný text skládá view (`Text(_:format:)`), protože relativní
    /// čas se v okně **přepočítává sám** a řetězec z `Policy` by zamrzl na tom, kdy se poskládal.
    static func showsRelativeTime(of date: Date, now: Date) -> Bool {
        now.timeIntervalSince(date) < relativeActivityWindow
    }

    /// Čas u řádku dění — a jestli si k němu řádek nese **den** (#443).
    ///
    /// Den nese řádek jedině na **dashboardu**. V sekci ho nese **hlavička dne** (`Dnes`, `Včera`,
    /// `čtvrtek 20. srpna`), takže se u řádku píše jen `v 7:58`; blok na dashboardu je jeden
    /// a bez dělení po dnech, takže by tam včerejší událost vypadala jako dnešní ráno.
    ///
    /// **Jedno rozhodnutí pro obě obrazovky.** Dvě místa, která si to počítají sama, se rozejdou
    /// právě v tom, co je vidět jen jeden den v roce; formát je proto tentýž jako u `visitLabel`
    /// (`v 7:58`, `včera v 7:58`, `20. srpna v 7:58`) a jde o **totéž** čtení dne, takže se ty
    /// dva popisky na jedné obrazovce nemají čím rozejít.
    static func activityTime(
        of date: Date,
        now: Date,
        at place: ActivityRowPlace,
        calendar: Calendar = .current
    ) -> ActivityTimeLabel {
        if showsRelativeTime(of: date, now: now) { return .relative }
        // Výčtem, ne `if`em: třetí místo, kde se dění kreslí, si tím vynutí rozhodnutí, jestli si
        // den nese samo — tichý default by u něj znamenal `v 7:58` u včerejška.
        switch place {
        case .section: return .absolute("v \(date.formatted(.dateTime.hour().minute()))")
        case .dashboard: return .absolute(visitLabel(date, now: now, calendar: calendar))
        }
    }

    /// Věta pod nadpisem sekce. Druhá půlka mluví o **značce poslední návštěvy**, protože ta
    /// rozhoduje o tom, co je nad pruhem `Tady jsem skončil` — bez ní by pruh nebyl vysvětlený.
    ///
    /// `nil` značka dostane vlastní věty: „naposledy nikdy“ by nešlo napsat a mlčet o tom nejde,
    /// protože tehdy je nové **všechno** a odznak v railu ukazuje celý záznam.
    static func activityHeaderSentence(
        lastVisit: Date?,
        hasEvents: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let opening = "Co se stalo na pull requestech, když jsem se nekoukal."
        guard let lastVisit else {
            return hasEvents ? "\(opening) Ještě jsi tu nebyl, takže je nové všechno." : opening
        }
        let when = visitLabel(lastVisit, now: now, calendar: calendar)
        return "\(opening) Naposledy jsem tu byl \(when)."
    }

    /// Kdy jsem tu byl naposledy — `v 08:12`, `včera v 22:10`, `20. srpna v 18:20`.
    ///
    /// Čte to **věta v hlavičce i pruh** `Tady jsem skončil`, takže je to jedno místo: dvě různá
    /// formátování téhož okamžiku na jedné obrazovce by vypadala jako dva různé okamžiky.
    ///
    /// Den se dopisuje, jen když **není dnešní**. `v 08:12` u značky staré tři dny je ta chyba,
    /// kterou nikdo nepozná — a zrovna tady na tom záleží, protože pruh dělí seznam.
    static func visitLabel(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let clock = date.formatted(.dateTime.hour().minute())
        switch dayDistance(from: date, to: now, calendar: calendar) {
        case 0: return "v \(clock)"
        case 1: return "včera v \(clock)"
        default: return "\(date.formatted(.dateTime.day().month(.wide))) v \(clock)"
        }
    }

    // MARK: - Prázdno

    /// Co se ukáže, když v dění nic není. `nil` = něco tam je, takže se prázdný stav nekreslí.
    ///
    /// **Ztracený záznam má přednost před všemi**: nad rozbitým souborem se o notifikacích nedá
    /// tvrdit nic, protože prázdno není jejich vina. **Zakázané oprávnění pak před vypnutým
    /// přepínačem**, protože je to ten stav, ve kterém je aplikace úplně mlčící a člověk o tom
    /// nemusí vědět — kdežto přepínač si vypnul sám.
    static func activityEmptyState(
        hasEvents: Bool,
        isUnreadable: Bool = false,
        notificationsDenied: Bool,
        notificationsEnabled: Bool
    ) -> ActivityEmptyState? {
        guard !hasEvents else { return nil }
        if isUnreadable { return .unreadable }
        if notificationsDenied { return .notificationsDenied }
        return notificationsEnabled ? .calm : .notificationsOff
    }
}
