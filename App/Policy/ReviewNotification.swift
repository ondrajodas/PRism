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
    ///
    /// Rozvržení je **titulek → nález → PR** (#200), protože banner se čte odshora a dolní
    /// řádek se ořízne. Nahoře je proto to, podle čeho se člověk rozhoduje, jestli jde
    /// k počítači hned (kolik nálezů a kolik z nich blokuje), pod tím **ten nejzávažnější
    /// z nich** a teprve na třetím řádku identifikace PR.
    static func reviewNotification(
        for pr: PRIdentifier,
        state: ReviewState,
        blocking: Int = 0,
        topFinding: Finding? = nil
    ) -> PullRequestNotification? {
        guard let title = notificationTitle(state: state, blocking: blocking),
              let event = notificationEvent(for: state)
        else { return nil }
        return PullRequestNotification(
            pullRequest: pr,
            title: title,
            body: notificationBody(state: state, pr: pr, topFinding: topFinding),
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

    /// Titulek — první řádek banneru, a proto ten, který rozhoduje (#200).
    ///
    /// `nil` = tenhle stav se neoznamuje; množina musí odpovídat `notificationEvent(for:)`
    /// a drží to test.
    ///
    /// **Do #200 tu bylo `owner/repo#číslo`.** Identifikace se přesunula na třetí řádek, protože
    /// jméno PR neříká, jestli se má jít k počítači hned — kdežto „3 nálezy · 1 blokuje“ ano.
    /// Ztratit se tím nemá: v banneru je PR pořád vidět (změřeno), notifikace o témž PR řadí
    /// systém k sobě podle `threadIdentifier` a klik se řídí typem, ne textem.
    private static func notificationTitle(state: ReviewState, blocking: Int) -> String? {
        switch state {
        case .notStarted, .queued, .cloning, .running, .stale:
            nil
        case .completed(let findings):
            findingsHeadline(findings, blocking: blocking)
        // Nedoběhlý běh s nálezy má v titulku **taky počty**: nálezy jsou k přečtení a to
        // rozhoduje o naléhavosti stejně jako u doběhlého. Že to nedoběhlo, řekne detail
        // hned pod ním — v banneru je vidět, takže se ty dva stavy neslijí.
        case .timedOut(let findings):
            findings > 0 ? findingsHeadline(findings, blocking: blocking) : "Review nedoběhlo do limitu"
        case .interrupted(let findings):
            findings > 0 ? findingsHeadline(findings, blocking: blocking) : "Review přerušila aplikace"
        case .clean:
            "Čisté review"
        case .dismissed:
            // „Našel a já to zamítl“ je jiné tvrzení než „nic nenašel“ (#113) a nesmí se
            // s ním slít ani v titulku. Počet je v detailu pod ním.
            "Zbyly jen odmítnuté nálezy"
        case .failed:
            "Review se nepovedlo"
        case .checkoutFailed:
            "Nepovedlo se připravit pracovní kopii"
        }
    }

    /// Tělo: **detail a pod ním PR**, každé na svém řádku (#200).
    ///
    /// Jméno PR se skládá přes `description` identifikátoru, takže se číslo nikde
    /// neinterpoluje přes locale — z `#21663` by jinak bylo `#21 663`.
    ///
    /// Detail smí chybět (nálezy jsou, ale volající je nedodal); pak zbude samotné PR. Prázdný
    /// řádek navíc by tam nebyl k ničemu a odsunul by identifikaci ještě níž.
    private static func notificationBody(state: ReviewState, pr: PRIdentifier, topFinding: Finding?) -> String {
        [notificationDetail(state: state, topFinding: topFinding), pr.description]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    /// Druhý řádek — co se stalo. `nil` = není co dodat.
    private static func notificationDetail(state: ReviewState, topFinding: Finding?) -> String? {
        switch state {
        case .notStarted, .queued, .cloning, .running, .stale:
            nil
        case .completed:
            findingLine(topFinding)
        case .timedOut(let findings):
            // Timeout musí být poznat i tehdy, když nálezy jsou: zabitý běh je mohl mít
            // rozepsané, takže samotné „3 nálezy“ v titulku by tvrdilo víc, než se stalo.
            findings > 0
                ? sentence("Nedoběhlo do limitu.", followedBy: findingLine(topFinding))
                : "Reviewer nic nenahlásil."
        case .interrupted(let findings):
            // Říká **proč** to nedoběhlo, protože se s tím dělá něco jiného než s timeoutem:
            // limit se dá zvednout, spadlá aplikace ne. A že jsou nálezy z transcriptu, taky —
            // jinak by titulek tvrdil, že běh doběhl.
            findings > 0
                ? sentence(
                    "Přerušila to aplikace, nálezy jsou z transcriptu.",
                    followedBy: findingLine(topFinding)
                )
                : "Reviewer nic nenahlásil."
        case .clean:
            // Kratší a bez detailu — ale poznat se to musí, takže ne prázdný řádek.
            "Reviewer nenašel žádný nález."
        case .dismissed(let count):
            // Formulace je schválně taková, aby ji unesl **každý** tvar počtu: „Zbyly jen
            // nálezy, které jsi odmítl (1)“ mluví o jednom nálezu v množném čísle. Je to
            // tatáž třída chyby, jakou u blokujících našel Copilot na #131 — jen tady ji
            // neřeší skloňování slova, ale to, jak je věta postavená.
            "Odmítl jsi \(Plural.czech(count, one: "nález", few: "nálezy", many: "nálezů")) a nic jiného nezbylo."
        case .failed(let detail):
            // Sem spadá i „nemám co říct“ — spadlá session i nereportující běh. Detail
            // z `Policy` je věta, se kterou se dá něco dělat, takže se posílá celá.
            //
            // **Na jeden řádek**, a není to kosmetika: `CheckoutError.userDescription` lepí
            // výstup `gitu` za prázdný řádek, takže by se PR z třetího řádku propadlo o půl
            // obrazovky níž. Chytil to test, ne úvaha.
            detail.singleLine
        case .checkoutFailed(let detail):
            detail.singleLine
        }
    }

    /// „3 nálezy · 1 blokuje“ — a když neblokuje nic, řekne se i to.
    ///
    /// Že **nic neblokuje**, patří do titulku ze stejného důvodu jako do těla před #200:
    /// „3 nálezy“ bez druhé půlky vypadají stejně vážně jako tři blokující, a rozhodnutí,
    /// jestli jít k počítači hned, se dělá právě podle toho.
    ///
    /// Skloňuje `Plural.czech`, tedy tentýž helper, jakým se řídí odznak stavu a chipy
    /// reviewerů. Vlastní `switch` tady být nesmí: byla by to čtvrtá kopie téhož pravidla
    /// a rozešly by se — tenhle soubor to zkusil a vyšlo z toho „3 blokujících“ (nález
    /// Copilota na #131).
    ///
    /// **Skloňuje se i sloveso** (#200): „1 blokuje“, „3 blokují“, ale od pěti zase
    /// „5 blokuje“ — čeština u pěti a výš přechází zpátky na jednotné číslo. `one` a `many`
    /// jsou proto shodné **záměrně**, ne překlepem; do #200 tu bylo přídavné jméno
    /// („blokující“), u kterého se shodovaly naopak `one` a `few`. Je na to tabulka v testu.
    private static func findingsHeadline(_ findings: Int, blocking: Int) -> String {
        let found = Plural.czech(findings, one: "nález", few: "nálezy", many: "nálezů")
        guard blocking > 0 else { return "\(found) · nic neblokuje" }
        let blocks = Plural.czech(blocking, one: "blokuje", few: "blokují", many: "blokuje")
        return "\(found) · \(blocks)"
    }

    /// Nejzávažnější nález jako jeden řádek: `correctness: ?? '' schová chybějící secret`.
    ///
    /// Kategorie je před dvojtečkou, protože v ní je ta půlka informace, kterou souhrn
    /// neopakuje (a je to totéž, čím se nálezy dělí do sekcí v panelu). Text je
    /// `shortSummary`, protože přesně na tohle je — s `summary` jako záložkou, když ho
    /// reviewer ani překladatel nedodal.
    ///
    /// **Řádkové zlomy se slévají a text se krátí.** Na třetím řádku těla je jméno PR, takže
    /// by ho jeden `\n` v souhrnu — nebo dost dlouhá věta — odsunul mimo to, co je vidět.
    private static func findingLine(_ finding: Finding?) -> String? {
        guard let finding else { return nil }
        let text = summaryLine(of: finding)
        guard let category = finding.category.map(normalized(category:)), !category.isEmpty else {
            return text.isEmpty ? nil : shortened(text)
        }
        // Prázdný souhrn nechá samotnou kategorii: visící dvojtečka vypadá jako uříznutý text.
        return text.isEmpty ? category : shortened("\(category): \(text)")
    }

    /// Souhrn nálezu na jeden řádek. Prázdný `shortSummary` se bere jako nedodaný — jinak by
    /// z něj byl prázdný řádek pod titulkem.
    private static func summaryLine(of finding: Finding) -> String {
        let short = finding.shortSummary?.singleLine ?? ""
        return short.isEmpty ? finding.summary.singleLine : short
    }

    /// Kolik znaků unese řádek s nálezem, než se z banneru vytlačí PR pod ním.
    ///
    /// **Změřeno v běžící aplikaci**, ne odhadnuto: do banneru se vejdou **čtyři řádky těla
    /// po zhruba 43 znacích** a co se nevejde, macOS uřízne třemi tečkami — včetně řádku
    /// s identifikací. Se 140 znaky dlouhým `summary` z banneru zmizelo `ondrajodas/PRism#200`
    /// úplně. Sto znaků nechá nálezu tři řádky a PR ten čtvrtý.
    ///
    /// Krátí se **jen nález**, ne detail u selhání: tam je věta z `Policy` nebo z `gitu`
    /// a rozhoduje spíš její začátek, který se vejde tak jako tak.
    static let notificationFindingLimit = 100

    /// Text zkrácený na `notificationFindingLimit`, na hranici slova.
    ///
    /// Vlastní tři tečky, i když macOS umí ořezat sám: systémový ořez sebere **celý zbytek
    /// notifikace**, tedy i řádek, na kterém je PR. Tohle je řez, po kterém zbytek přežije.
    private static func shortened(_ text: String) -> String {
        guard text.count > notificationFindingLimit else { return text }
        let cut = text.prefix(notificationFindingLimit)
        // Poslední slovo se zahazuje jedině tehdy, když ho řez **rozpůlil**. Když `cut` končí
        // na hranici slova, vešlo se celé — a `dropLast()` na slepo by ho sebral zbytečně,
        // takže by z banneru zmizel kus textu, na který bylo místo (nález Copilota na #248).
        let kept = splitsAWord(cut, in: text)
            ? cut.split(separator: " ").dropLast().joined(separator: " ")
            : String(cut)
        // Mezera před třemi tečkami vypadá jako překlep, a zbýt tam po řezu může.
        let trimmed = kept.trimmingCharacters(in: .whitespaces)
        // Jediné dlouhé slovo (cesta, hash) hranici nemá, takže se řeže natvrdo — jinak by
        // nezbylo nic.
        return "\(trimmed.isEmpty ? String(cut) : trimmed)…"
    }

    /// Rozpůlil řez slovo? Ano jedině tehdy, když na obou stranách hranice stojí něco jiného
    /// než mezera.
    private static func splitsAWord(_ cut: Substring, in text: String) -> Bool {
        guard let last = cut.last, !last.isWhitespace else { return false }
        guard let next = text.dropFirst(cut.count).first else { return false }
        return !next.isWhitespace
    }

    /// Věta a za ní detail, když nějaký je.
    private static func sentence(_ text: String, followedBy detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return text }
        return "\(text) \(detail)"
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

    /// Které PR souhrn jmenuje. Delší seznam se zkrátí — do banneru se vejde pár řádků.
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
    /// Tři, protože `owner/repo#číslo` je dlouhé a v banneru je místa na pár řádků — čtvrtý
    /// identifikátor už se do nich nevejde a zbytek stejně řekne počet. (Kolik řádků přesně,
    /// je změřené u #200: titulek a pod ním čtyři.)
    private static let summaryLimit = 3

}
