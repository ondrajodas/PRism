import Foundation

/// Notifikace (#82, #85, #87) — co se ohlásí, když se do okna nikdo nedívá.
///
/// Rozhodování, **jestli** se má hlásit, je v `Policy`; tady je jen to, kdy se na ni store
/// zeptá a co si o odeslání zapíše.
extension AppStore {
    /// Pošle notifikaci a zapamatuje si, když nešla.
    ///
    /// Vrstva bez konzumenta: první, kdo tuhle cestu použije, je #82 (doběhlé review), pak
    /// #85 (nové PR). Volání bez nastaveného centra (testy) neudělá nic a **nic si ani
    /// nezapíše** — „odsud se neposílá“ není porucha, o které by se mělo hlásit.
    /// Vrací, **jak** doručení dopadlo — volající se podle toho může rozhodnout, jestli to
    /// zkusit znovu (#85 na tom stojí). `nil` = odsud se neposílá.
    @discardableResult
    func notify(_ notification: PullRequestNotification) async -> NotificationDelivery? {
        guard let notifications else { return nil }
        // Brána z nastavení (#86) je **tady**, v jediném místě, kterým jde všechno — jako
        // `PublishScope` u odesílání. Kdyby se ptal každý volající, jeden by to zapomněl.
        //
        // Vrátit se to musí **před** `deliver(_:)`: ten si říká o oprávnění, a dialog za
        // něco, co je vypnuté, je dialog za nic. Je to zadání #86 a je na to test.
        guard configuration.global.notifications.allows(notification.event) else { return nil }
        let delivery = await notifications.deliver(notification)
        notificationFailure = message(for: delivery)
        // Čas se posouvá **jen po doručení** (#138). Odmítnuté oprávnění ani selhání systému
        // z toho „ohlášeno“ neudělá — řádek by pak tvrdil, že notifikace fungují, zrovna když
        // nefungují.
        if case .delivered = delivery {
            lastDeliveredNotification = DeliveredNotification(at: time.now, title: notification.title)
        }
        return delivery
    }

    /// Proč notifikace nedorazila, jako věta pro okno. `nil` = dorazila.
    ///
    /// Úspěch hlášku **maže**: oprávnění se dá povolit v Nastavení systému a příští
    /// doručení už projde — věta, která by po něm zůstala, by posílala hledat vyřešený
    /// problém.
    private func message(for delivery: NotificationDelivery) -> String? {
        switch delivery {
        case .delivered:
            nil
        case .notAuthorized:
            // Říká, co se kvůli tomu neděje, a kde se to dá spravit. Aplikace tam nedosáhne,
            // takže samotné „nemám oprávnění“ by nedávalo další krok.
            //
            // Schválně **nejmenuje konkrétní událost**: tahle vrstva je základ pro víc druhů
            // notifikací (doběhlé review #82, nové PR #85), takže „o doběhlém review nedám
            // vědět“ by u těch ostatních tvrdilo něco jiného, než se stalo.
            """
            Notifikace nemají povolení, takže se o dění v PR nedozvíš, dokud se do aplikace \
            nepodíváš. Povolit se dá v Nastavení systému → Oznámení → PRism.
            """
        case .failed(let detail):
            "Notifikaci se nepodařilo doručit. \(detail)"
        }
    }

    /// Klik na notifikaci **otevře záložku** PR, kterého se týká (#409).
    ///
    /// Okno dopředu dává `SystemNotificationCenter` — aktivace aplikace je přístup ke stroji
    /// jako doručení samotné, takže store zůstává bez AppKitu.
    ///
    /// **Otevírá se `openTab(_:in:)`, ne `selection`** — a to je celé #409. Do té doby tady stálo
    /// jedno přiřazení do `selection`, tedy do stavu, který od záložek (#180) v domácí záložce
    /// nikdo nekreslí: `activeTab` zůstal na `.home`, žádná záložka nevznikla a z kliknutí bylo
    /// „aplikace naskočila a nic“. Byla to regrese od #180 (obsluha je z #82–#88, kdy výběr řádku
    /// otevření byl) a **testy ji nechytily**, protože tvrdily přesně to `selection`.
    ///
    /// **Tab se nejmenuje.** Proud kliknutí nese `PRIdentifier`, ne událost, takže by se vybíral
    /// naslepo — a volba tabu je per PR (`detailTab(for:)`), tedy odpověď na „kam se v tomhle PR
    /// koukám“. Otevřít člověka tam, kde skončil, je nejmenší překvapení; jmenovat tab umí ten,
    /// kdo ví, o čem klik je (paleta ⌘K, řádek dění z #414).
    ///
    /// **Na čí PR klik dopadne, se nerozlišuje.** Notifikace se o vlastních PR hlásí jedině
    /// o cizí aktivitě (#335), ale klik na starší notifikaci může přijít i na PR, který se mezitím
    /// do sekce `Moje PR` (#331) přesunul — a záložka je na sekci railu nezávislá, protože si detail
    /// bere z **plného** seznamu (`summary(for:)`). Rozřazení podle autora by tady tedy znamenalo
    /// zahozený klik za nic.
    ///
    /// Co udělat, rozhoduje `Policy.notificationClick(on:listed:visible:status:)` — včetně toho, že
    /// PR mimo seznam se neotevírá naslepo a že filtr, který ho schoval (#117), se ruší.
    func handleNotificationClicks() async {
        guard let notifications else { return }
        for await pr in notifications.clicks() {
            let click = Policy.notificationClick(
                on: pr,
                listed: pullRequests,
                visible: visiblePullRequests,
                status: status
            )
            guard case .open(let clearsFilter) = click else { continue }
            // Filtr se ruší **dřív** než se otevírá záložka: `clearFilter()` jde přes `setFilter`,
            // který výběr srovnává s filtrem — v opačném pořadí by srovnal i ten výběr, který
            // právě nastavilo otevření.
            if clearsFilter { clearFilter() }
            openTab(pr)
        }
    }

    /// Dá vědět, jak review dopadlo (#82).
    ///
    /// Volá se **až tam, kde se review uzavírá**, ne u ukládání jednotlivého běhu: jinak by
    /// u tří skillů přišlo „čisté“ a za minutu „3 nálezy“ za totéž PR. Rozhoduje proto
    /// `reviewState(for:)`, tedy tentýž stav, jaký ukazuje řádek seznamu — druhý výpočet by
    /// se s prvním mohl rozejít.
    ///
    /// Stavy, které nejsou konec běhu, a zastaralý záznam si `Policy` odfiltruje sama.
    func notifyAboutFinishedReview(of pr: PRIdentifier) async {
        guard notifications != nil else { return }
        // Počet blokujících i nejzávažnější nález se berou z **téhož** záznamu jako stav, takže
        // se titulek („3 nálezy · 1 blokuje“) a řádek pod ním nemají jak rozejít. Bez záznamu
        // vyjde nula a `nil` — není to spolknuté selhání, ale odpověď: když review nedoběhlo
        // (selhal checkout, spadlo volání GitHubu), nemá co blokovat ani co ukázat.
        let record = reviewRecords[pr]
        let categories = resolved(for: pr.repo).blockingCategories
        guard let notification = Policy.reviewNotification(
            for: pr,
            // Čí PR to je (#332). Rozhoduje `Policy.reviewNotification`, ne tenhle guard: o vlastním
            // PR se touhle cestou nehlásí nic, protože všechny tři události jsou odpověď na review
            // request. Bere se `ownership(of:)` nad identitou — shrnutí tu po ruce být nemusí.
            ownership: ownership(of: pr),
            state: reviewState(for: pr),
            blocking: record.map { Policy.blockingCount(in: $0, categories: categories) } ?? 0,
            topFinding: record.flatMap { Policy.mostSevereFinding(in: $0, categories: categories) }
        ) else { return }
        await notify(notification)
    }

    /// Dá vědět o PR, která se v seznamu objevila (#85).
    ///
    /// **Zapisuje se až po doručení.** Opačné pořadí znamená, že se PR zapíše jako ohlášené,
    /// notifikace se nepovede a už nikdy nepřijde — a je to zadání #85. Zapisuje se přitom
    /// **celý** aktuální seznam, ne jen to, co se doručilo: snímek má odpovídat frontě, takže
    /// se do něj musí dostat i PR, která tam byla už minule.
    ///
    /// **Přechodná chyba snímek nepřepíše** (příští tik to zkusí znovu), kdežto **odmítnuté
    /// oprávnění ano**: opakovat každou minutu něco, co je zakázané, nemá cenu a po povolení
    /// se ta PR ve frontě přečtou v okně. Že notifikace nechodí, je vidět ve stavovém řádku.
    ///
    /// Zápis je od #87 **všechno nebo nic**, a vyplývá to ze slévání: za tik jde jedna
    /// notifikace, takže je jedno doručení a jeden výsledek. Nedoručený souhrn proto nechá
    /// všechna nová PR mimo snímek a příští tik je zkusí znovu jako celek.
    ///
    /// Do #87 se zapisovalo **po jednotlivých PR** (fronta bez těch, u kterých doručení
    /// selhalo), protože se i po jednotlivých posílalo — bez toho by při opakovaném selhání
    /// jedné notifikace chodily ty ostatní každou minutu (nález Copilota na #132). Se souhrnem
    /// ta situace nastat nemůže: buď odešel celý, nebo vůbec.
    ///
    /// **Hlásí se jedině cizí PR** (#332). „Nový PR k review“ o pull requestu, který jsem sám
    /// otevřel, je hláška o vlastním pushi — a `Znovu požádáno o review` u něj neplatí vůbec.
    ///
    /// Zúžení je **na vstupu, ne až u doručení**, takže se vlastní PR nedostane ani do snímku
    /// ohlášených: v něm mají být právě ta PR, proti kterým se příště hledají novinky. Vypadnou
    /// z něj sami (`newcomers(in:)` odebírá, co v seznamu není), takže nic neroste.
    ///
    /// **Dokud se neví, kdo se dívá**, je podle `Policy.ownership` všechno cizí, takže vlastní PR,
    /// které dorazí v prvním tiku po startu (než doběhne `gh api user`), se ohlásit **může**. Je to
    /// vědomá volba: druhá strana by byla mlčet, dokud login nedorazí, a to znamená u selhaného
    /// `gh api user` ztracené notifikace o cizích PR — tedy o té práci, kvůli které aplikace je.
    func announceNewPullRequests(in summaries: [PullRequestSummary]) async {
        guard notifications != nil, let announced else { return }
        let listed = Policy.pullRequests(summaries, ownedBy: .theirs, mine: ownLogins).map(\.id)
        let newcomers = await announced.newcomers(in: listed)
        guard !newcomers.isEmpty else { return }

        // Jedna notifikace za celý tik (#87), ne jedna na PR: deset hlášek naráz je první
        // důvod, proč si člověk notifikace vypne. Čekací okno na to potřeba není — tik dodá
        // celý seznam naráz, takže se slévá právě to, co se stalo mezi dvěma tiky.
        guard let notification = Policy.newPullRequestsNotification(
            for: newcomers,
            titles: titles(from: summaries),
            reviewed: reviewedPullRequests
        ) else { return }

        let delivery = await notify(notification)
        // Nedoručený souhrn nechá **všechna** nová PR mimo snímek, takže se příští tik zkusí
        // znovu jako jeden celek. Do #87 se zapisovalo po jednotlivých PR, protože se i po
        // jednotlivých posílalo; teď je doručení jedno, takže i výsledek je jeden.
        guard delivery?.isWorthRetrying != true else { return }
        await announced.remember(listed)
    }

    /// PR, u kterých už někdy review běželo (#137). Podle nich se pozná re-review od novinky.
    ///
    /// Zdrojem jsou **uložené nálezy**, ne rozdělaný draft: draft může existovat u PR, které
    /// se nikdy nereviewovalo (stačí napsat komentář), kdežto záznam vzniká jedině doběhlým
    /// během. Čte se z paměti — `reviewRecords` se plní při startu z disku a `forget` je na
    /// rozdíl od diffu nebo konverzace **neuklízí**, takže PR, který z fronty odešel po mém
    /// review, tam zůstane. To je zrovna ten případ, kvůli kterému #137 vzniklo.
    ///
    /// Zahozený záznam (#81) z PR udělá zase novinku, a je to tak schválně: zahození znamená
    /// „tenhle výsledek je k ničemu“, takže chovat se k tomu PR jako k nedotčenému je poctivé.
    private var reviewedPullRequests: Set<PRIdentifier> { Set(reviewRecords.keys) }

    /// Titulky PR pro text notifikace, klíčované identifikátorem.
    private func titles(from summaries: [PullRequestSummary]) -> [PRIdentifier: String] {
        Dictionary(summaries.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    }
}
