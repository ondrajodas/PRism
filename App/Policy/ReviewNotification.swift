import Foundation

extension Policy {
    /// Notifikace o doběhlém review (#82). `nil` = není o čem dát vědět.
    ///
    /// **Staví na `ReviewState`, ne na běhech.** Ten stav už rozlišuje přesně to, co se má
    /// v notifikaci poznat — nálezy, čisto, spadlou session, timeout s částečnými nálezy
    /// i „nemám co říct“ (reviewer nenahlásil nálezy, nebo se část ztratila). Skládat to
    /// z `record.runs` znovu by znamenalo druhé místo, které o témž výsledku rozhoduje,
    /// a rozejít se v tom znamená, že **řádek seznamu a notifikace řeknou dvě různé věci**.
    ///
    /// Rozhoduje proto výsledek **celého záznamu**, ne jednotlivý běh: reviewery jedou
    /// paralelně a tři notifikace za jedno PR jsou tři vyrušení za jednu věc.
    ///
    /// `nil` vrací u stavů, které nejsou konec běhu (`notStarted`, `queued`, `cloning`,
    /// `running`) a u `stale`. Zastaralý záznam znamená, že během běhu přišel nový commit —
    /// oznamovat výsledek proti kódu, který v PR není, by posílalo číst nálezy, které se
    /// vzápětí zneplatní.
    static func reviewNotification(
        for pr: PRIdentifier,
        state: ReviewState,
        blocking: Int = 0
    ) -> PullRequestNotification? {
        guard let body = notificationBody(state: state, blocking: blocking),
              let event = notificationEvent(for: state)
        else { return nil }
        // Titulek nese **repo a číslo**, ne jen „Review doběhlo“: notifikací může viset víc
        // a bez identifikace se nepozná, které patří ke kterému PR. Číslo se skládá přes
        // `description` identifikátoru, takže se nikde neinterpoluje přes locale — z `#21663`
        // by jinak bylo `#21 663`.
        return PullRequestNotification(
            pullRequest: pr,
            title: pr.description,
            body: body,
            event: event
        )
    }

    /// Do které kategorie stav patří (#86).
    ///
    /// Skládá se **z téhož `ReviewState`** jako text, takže se brána a hláška nemůžou rozejít.
    /// `nil` u stavů, které nejsou konec běhu — a to je stejná množina jako u textu, takže si
    /// obojí musí odpovídat; drží to test.
    private static func notificationEvent(for state: ReviewState) -> NotificationEvent? {
        switch state {
        case .notStarted, .queued, .cloning, .running, .stale:
            nil
        case .completed:
            .findings
        case .timedOut(let findings):
            // **Timeout se rozděluje podle toho, jestli něco dodal.** S nálezy je to o nálezech
            // (jsou k přečtení a čekají na posouzení), bez nich je to selhání: běh nedoběhl
            // a nic z toho není.
            //
            // Do #133 padal celý `timedOut` do `.findings`, což znamenalo, že kdo si vypne
            // `Review se nepovedlo`, dostával notifikaci o běhu, který nedoběhl a nic nenahlásil.
            // Chytil to Copilot na rozporu mezi textem v nastavení a mapováním — a správná
            // oprava byla mapování, ne text.
            findings > 0 ? .findings : .failure
        case .interrupted(let findings):
            // Stejné dělení jako u timeoutu a ze stejného důvodu: nálezy jsou k přečtení,
            // kdežto přerušený běh bez nich je selhání.
            findings > 0 ? .findings : .failure
        case .clean, .dismissed:
            // Odmítnuté nálezy jsou z pohledu vyrušení totéž jako čisto: nezbylo nic, co bych
            // musel řešit. Kdo si vypne „čisté review“, nechce ani tuhle hlášku.
            .clean
        case .failed, .checkoutFailed:
            .failure
        }
    }

    /// Co se v notifikaci píše. `nil` = tenhle stav se neoznamuje.
    private static func notificationBody(state: ReviewState, blocking: Int) -> String? {
        switch state {
        case .notStarted, .queued, .cloning, .running, .stale:
            nil
        case .completed(let findings):
            findingsText(findings, blocking: blocking)
        case .timedOut(let findings):
            // Timeout musí být poznat i tehdy, když nálezy jsou: zabitý běh je mohl mít
            // rozepsané, takže „3 nálezy“ by tvrdilo víc, než se stalo.
            findings > 0
                ? "Review nedoběhlo do limitu. \(findingsText(findings, blocking: blocking))"
                : "Review nedoběhlo do limitu a nic nenahlásilo."
        case .interrupted(let findings):
            // Říká **proč** to nedoběhlo, protože se s tím dělá něco jiného než s timeoutem:
            // limit se dá zvednout, spadlá aplikace ne. A nálezy jsou z transcriptu, takže
            // „3 nálezy“ samo o sobě by tvrdilo, že běh doběhl.
            findings > 0
                ? "Review přerušila aplikace. \(findingsText(findings, blocking: blocking)) Nálezy jsou z transcriptu."
                : "Review přerušila aplikace a nic nenahlásilo."
        case .clean:
            // Kratší a bez detailu — ale poznat se to musí, takže ne prázdné tělo.
            "Reviewer nenašel žádný nález."
        case .dismissed(let count):
            // „Našel a já to zamítl“ je jiné tvrzení než „nic nenašel“ (#113), takže se
            // v textu nesmí slít. Nastane po opakovaném review, kde odmítnutí zůstala.
            //
            // Formulace je schválně taková, aby ji unesl **každý** tvar počtu: „Zbyly jen
            // nálezy, které jsi odmítl (1)“ mluví o jednom nálezu v množném čísle. Je to
            // tatáž třída chyby, jakou u blokujících našel Copilot na #131 — jen tady ji
            // neřeší skloňování slova, ale to, jak je věta postavená.
            "Odmítl jsi \(Plural.czech(count, one: "nález", few: "nálezy", many: "nálezů")) a nic jiného nezbylo."
        case .failed(let detail):
            // Sem spadá i „nemám co říct“ — spadlá session i nereportující běh. Detail
            // z `Policy` je věta, se kterou se dá něco dělat, takže se posílá celá.
            "Review se nepovedlo. \(detail)"
        case .checkoutFailed(let detail):
            "Nepovedlo se připravit pracovní kopii. \(detail)"
        }
    }

    /// „3 nálezy, z toho 1 blokující“ — a `blocking` se do textu dostane jen tehdy, když je
    /// z čeho.
    ///
    /// Skloňuje `Plural.czech`, tedy tentýž helper, jakým se řídí odznak stavu a chipy
    /// reviewerů. Vlastní `switch` tady být nesmí: byla by to čtvrtá kopie téhož pravidla
    /// a rozešly by se — tenhle soubor to zkusil a vyšlo z toho „3 blokujících“ (nález
    /// Copilota na #131). U „blokující“ jsou přitom tvary jen **dva**, protože jednotné číslo
    /// a 2–4 vyjdou stejně; `one` a `few` jsou proto shodné, ne opomenutí.
    private static func findingsText(_ findings: Int, blocking: Int) -> String {
        let found = Plural.czech(findings, one: "nález", few: "nálezy", many: "nálezů")
        guard blocking > 0 else { return "\(found), nic blokujícího." }
        let blocks = Plural.czech(blocking, one: "blokující", few: "blokující", many: "blokujících")
        return "\(found), z toho \(blocks)."
    }

    /// Notifikace o novém PR ve frontě (#85).
    ///
    /// Na rozdíl od té o doběhlém review **nemá `nil` variantu**: co je nové, rozhoduje snímek
    /// v `AnnouncedPullRequests`, a když se na tuhle funkci dojde, je o čem dát vědět.
    ///
    /// Titulek nese repo a číslo (jako u review), tělo **titulek PR** — to je jediné, z čeho
    /// se pozná, jestli se na to jít podívat hned. Chybějící titulek je vlastní stav, ne
    /// prázdný řádek: `gh` ho vždycky vrátí, takže by prázdno znamenalo, že se PR nespároval
    /// se seznamem, a to se nemá tvrdit jako „PR bez názvu“.
    ///
    /// **Re-review se pozná textem** (#137). U PR, který jsem reviewoval minulý týden, není
    /// „Nový PR k review“ pravda — a je to zrovna ten případ, kdy má člověk jiné očekávání:
    /// u nového PR jde o první přečtení, u re-review o to, co se od mého review změnilo.
    /// Vlastní `NotificationEvent` to není schválně: šel by sice vypnout zvlášť (#86), ale
    /// je to pátý přepínač za rozdíl, který zatím nikdo vypínat nechtěl. Přidat se dá potom.
    static func newPullRequestNotification(
        for pr: PRIdentifier,
        title: String?,
        isReReview: Bool = false
    ) -> PullRequestNotification {
        PullRequestNotification(
            pullRequest: pr,
            title: isReReview
                ? "Znovu požádáno o review — \(pr.description)"
                : "Nový PR k review — \(pr.description)",
            body: title ?? "Titulek se nepodařilo přečíst.",
            event: .newPullRequest
        )
    }

    /// Notifikace za **všechna** nová PR z jednoho tiku (#87). `nil` = žádná nejsou.
    ///
    /// Jedno PR dá plnou hlášku s titulkem, víc PR **jeden souhrn**: deset hlášek naráz je
    /// první důvod, proč si člověk notifikace vypne. U jednoho PR se souhrn nedělá schválně —
    /// „1 nový PR k review“ říká **méně** než jeho název.
    ///
    /// **Žádné čekací okno.** Tik pollingu dodá celý seznam naráz, takže se slévá to, co se
    /// stalo mezi dvěma tiky — a to je přesně ten interval, o kterém má smysl mluvit. Držet
    /// vlastní okno by znamenalo stav, zdržení hlášky a druhé místo, kde se rozhoduje, co
    /// patří k čemu. Proto se to testuje **bez čekání v reálném čase**, jak chce zadání.
    /// `reviewed` jsou PR, u kterých už někdy review běželo (#137) — viz `isReReview` výš.
    static func newPullRequestsNotification(
        for pullRequests: [PRIdentifier],
        titles: [PRIdentifier: String] = [:],
        reviewed: Set<PRIdentifier> = []
    ) -> PullRequestNotification? {
        guard let first = pullRequests.first else { return nil }
        guard pullRequests.count > 1 else {
            return newPullRequestNotification(
                for: first,
                title: titles[first],
                isReReview: reviewed.contains(first)
            )
        }
        return PullRequestNotification(
            // Klik vybere **první**, tedy naposledy změněný (seznam je řazený `Policy.sorted`).
            // Nevybrat nic by znamenalo kliknutí, po kterém se nestane nic; a vybrat něco ze
            // středu seznamu by bylo losování.
            pullRequest: first,
            title: summaryTitle(
                count: pullRequests.count,
                reReviews: pullRequests.count { reviewed.contains($0) }
            ),
            body: summary(of: pullRequests),
            event: .newPullRequest,
            // Vlastní vlákno: souhrn není o tom jednom PR, který v něm stojí první.
            threadIdentifier: newPullRequestsThread
        )
    }

    /// Titulek souhrnu. Kolik z nich je re-review, se řekne **jen když nějaké jsou** (#137).
    ///
    /// Nerozpadá se to na dvě notifikace (jednu za nové, druhou za re-review), i když by každá
    /// řekla svoje: doručení je jedno, takže je jeden výsledek — a na tom stojí, že se při
    /// selhání zkusí celá dávka znovu jako celek (#87). Dvě notifikace by vrátily částečný
    /// zápis snímku, tedy tu past, kterou u #132 našel Copilot a #87 odstranil.
    ///
    /// U jednoho PR se souhrn nedělá vůbec, takže se tam rozdíl pozná plným textem — a to je
    /// ten případ, kde na něm záleží nejvíc.
    private static func summaryTitle(count: Int, reReviews: Int) -> String {
        guard reReviews > 0 else {
            return Plural.czech(
                count,
                one: "nový PR k review",
                few: "nové PR k review",
                many: "nových PR k review"
            )
        }
        // Zkratka `PR` se v češtině neskloňuje, takže jsou všechny tři tvary shodné záměrně —
        // tatáž situace jako u „blokující“. `Plural` se přesto použije, protože formátuje
        // číslo přes locale; holá interpolace je ten vzor, kvůli kterému z `#21663` vyjde
        // `#21 663`.
        let all = Plural.czech(count, one: "PR k review", few: "PR k review", many: "PR k review")
        let again = Plural.czech(reReviews, one: "znovu", few: "znovu", many: "znovu")
        return "\(all) (\(again))"
    }

    /// Vlákno, do kterého patří souhrn za víc nových PR (#87).
    static let newPullRequestsThread = "new-pull-requests"

    /// Které PR souhrn jmenuje. Delší seznam se zkrátí — notifikace má dva řádky.
    ///
    /// **Titulky se sem nepředávají schválně.** Vypisují se identifikátory, protože tři názvy
    /// PR se do dvou řádků banneru nevejdou a `owner/repo#číslo` řekne, čeho se to týká. Do
    /// #134 tu parametr `titles` byl a nepoužíval se — mrtvá větev, kterou našel Copilot.
    private static func summary(of pullRequests: [PRIdentifier]) -> String {
        let listed = pullRequests.prefix(summaryLimit).map(\.description).joined(separator: ", ")
        let rest = pullRequests.count - summaryLimit
        guard rest > 0 else { return listed }
        // „a 4 další“ — ne jen „…“, protože počet je ta informace, podle které se pozná, jestli
        // se do fronty jít podívat hned.
        return "\(listed) a \(Plural.czech(rest, one: "další", few: "další", many: "dalších"))"
    }

    /// Kolik PR se v souhrnu vypíše jménem.
    ///
    /// Tři, protože `owner/repo#číslo` je dlouhé a macOS ukáže v banneru dva řádky — čtvrtý
    /// identifikátor už se do nich nevejde a zbytek stejně řekne počet.
    private static let summaryLimit = 3

    /// Kolik z platných nálezů záznamu blokuje.
    ///
    /// Počítají se **platné** (`activeFindings`), tedy bez odmítnutých (#113) — blokující
    /// nález, kterému nevěřím, není důvod k vyrušení.
    static func blockingCount(
        in record: ReviewRecord,
        categories: Set<String> = defaultBlockingCategories
    ) -> Int {
        record.activeFindings.count { isBlocking($0, categories: categories) }
    }
}
