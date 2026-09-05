import Foundation

/// Jedna položka nabídky `Odložit` (#512).
///
/// **Pojmenovaný typ, ne dvojice `(String, SnoozeCondition)`**: nese k tomu klávesu, a ta se
/// v `App/` rozhoduje v `Policy`, ne v kresbě (#441). Kresba z něj skládá tlačítko a popisku
/// **odvozuje**, takže se nedá napsat `⌥1` vedle jiné klávesy.
struct SnoozeOffer: Hashable, Sendable, Identifiable {
    let title: String
    let condition: SnoozeCondition
    /// Klávesa **uvnitř otevřené nabídky**, ne zkratka okna. Do katalogu `WindowShortcut` proto
    /// nepatří: ten registruje kombinace, které platí kdykoli je okno vpředu, a `⌥1` musí platit
    /// jedině nad rozbalenou nabídkou — jinak by přebila psaní v každém textovém poli.
    let key: Character
    /// Glyfy modifikátoru do popisky. Jediná hodnota (`⌥`), ale bere se z téhož typu jako zbytek
    /// okna, aby se `⌥` nekreslilo jednou takhle a podruhé jako `alt`.
    let modifiers: ShortcutModifiers = .option

    var id: String { title }
    /// `⌥1` — **odvozeno**, ne opsáno vedle klávesy (#441).
    var shortcutLabel: String { "\(modifiers.glyphs)\(key)" }
}

extension Policy {
    // MARK: - Nabídka

    /// Co nabídnout v `Odložit` (#512) — čtyři hotové volby; `Vlastní datum…` si sáhne na
    /// kalendář, takže do výčtu nepatří.
    ///
    /// **Klávesy jsou `⌥1`–`⌥4` v pořadí nabídky.** Nejsou v katalogu zkratek okna schválně (viz
    /// `SnoozeOffer.key`); rozhodnuté jsou přesto tady, protože kresba o kombinacích rozhodovat
    /// nemá.
    ///
    /// - Parameter now: „teď“, ze kterého se počítá zítřejší ráno a týden. Parametr, ne
    ///   `Date.now` — jinak by se nabídka nedala projít výčtem.
    static func snoozeOffers(now: Date, calendar: Calendar = .current) -> [SnoozeOffer] {
        [
            SnoozeOffer(
                title: snoozeMorningTitle(after: now, calendar: calendar),
                condition: .until(snoozeMorning(after: now, calendar: calendar)),
                key: "1"
            ),
            // **Měřidlo se sem nedosazuje**, i když by hlava někdy po ruce byla: nabídka je čistá
            // funkce nad časem a doplnit základ umí rozhlídka u všech odložení jedním způsobem
            // (`snoozeBaseline`). Dvě cesty k jedné hodnotě by znamenaly dvě odpovědi na otázku
            // „od čeho se měří“.
            SnoozeOffer(title: "do dalšího pushe", condition: .nextPush(head: nil), key: "2"),
            SnoozeOffer(title: "do dalšího komentáře", condition: .nextComment(count: nil), key: "3"),
            SnoozeOffer(
                title: "na týden",
                condition: .until(now.addingTimeInterval(snoozeWeek)),
                key: "4"
            ),
        ]
    }

    /// **Nejbližší** ráno v devět — okamžik, na který míří první volba nabídky.
    ///
    /// **Devátá hodina, ne „za 24 hodin“.** Odložení do rána je o pracovním dni, ne o intervalu:
    /// zadané v jednu v noci má vrátit PR za osm hodin, ne za dvaatřicet. Proto se hledá **příští
    /// výskyt** té hodiny, ne zítřejší den — a proto se titulek volby odvozuje (`snoozeMorningTitle`)
    /// místo toho, aby se do něj slovo `zítra` napsalo natvrdo.
    ///
    /// **Kalendář je parametr.** `Calendar.current` nese časové pásmo stroje, takže by se test
    /// v jiné zóně rozešel s tím, co se počítá v okně — a je to tentýž kořen jako globální stav
    /// procesu v `Tests/` (#367).
    static func snoozeMorning(after now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.date(bySettingHour: snoozeMorningHour, minute: 0, second: 0, of: now)
        guard let today else { return now.addingTimeInterval(86_400) }
        guard today <= now else { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    }

    /// Titulek první volby — `do zítra 9:00`, nebo `do rána 9:00`, když je devátá ještě dneska.
    ///
    /// **Odvozený z okamžiku, ne napsaný vedle něj.** Kdyby se `zítra` psalo natvrdo, lhala by
    /// nabídka pokaždé, když si někdo odloží PR ve dvě v noci — a byl by to zrovna ten vzor, který
    /// Copilot v tomhle repu nachází: text tvrdí víc, než data unesou.
    static func snoozeMorningTitle(after now: Date, calendar: Calendar = .current) -> String {
        let morning = snoozeMorning(after: now, calendar: calendar)
        let isToday = calendar.isDate(morning, inSameDayAs: now)
        return isToday ? "do rána \(snoozeMorningLabel)" : "do zítra \(snoozeMorningLabel)"
    }

    /// Hodina, na kterou míří `do zítra`. Jedna konstanta pro **výpočet i popisku** — dvě by
    /// znamenaly nabídku, která slibuje jiný čas, než nastaví.
    static let snoozeMorningHour = 9
    static var snoozeMorningLabel: String { "\(snoozeMorningHour):00" }
    /// Týden ve vteřinách. Volba `na týden` je jediné místo, které ho potřebuje.
    static let snoozeWeek: TimeInterval = 7 * 24 * 60 * 60

    // MARK: - Vypršení

    /// Skončilo odložení? (#512)
    ///
    /// **Jediné místo, kde se ta otázka rozhoduje** — čas, hlava i počet příspěvků. Tři volající
    /// (rozhlídka po tiku, blok `Odložené` a zúžení fronty) by si ji jinak zodpověděli každý po
    /// svém a rozešli by se potichu, protože odložený PR není vidět.
    ///
    /// **Neznámé měřidlo nikdy nevrací `true`.** `nil` u hlavy i u počtu znamená *ještě nevím, od
    /// čeho měřit* (viz `SnoozeCondition`), a odložení, které se zruší samo dřív, než mělo, je
    /// horší než odložení, které chvíli trvá navíc: první z nich vrátí PR do fronty a vypadá jako
    /// porucha odložení, druhý se dá kdykoli ukončit tlačítkem `Vrátit teď`.
    ///
    /// **Nedoručená odpověď se od nezměněné hodnoty musí lišit**, proto jsou `head` a `comments`
    /// volitelné i na vstupu: PR, na který se rozhlídka nedostala (strop dotazu, chybějící alias
    /// v odpovědi), o svém stavu neříká nic — a „nevíme“ nesmí vyjít jako „vypršelo“ ani jako
    /// „trvá dál na základě dnešního měření“.
    ///
    /// - Parameters:
    ///   - head: hlava, na které PR stojí **teď**. `nil` = nezjištěno.
    ///   - comments: počet příspěvků pod PR **teď** (`SnoozeSignal.comments`). `nil` = nezjištěno.
    ///   - now: „teď“ pro časovou podmínku.
    static func snoozeExpired(
        _ snooze: Snooze,
        head: String?,
        comments: Int?,
        now: Date
    ) -> Bool {
        switch snooze.condition {
        // `>=` schválně: odložení `do 9:00` má v devět skončit, ne v 9:00:01. Vteřina navíc je
        // neviditelná, ale výčtem se testuje hranice, ne okolí.
        case .until(let deadline): return now >= deadline
        case .nextPush(let baseline):
            guard let baseline, let head else { return false }
            return head != baseline
        case .nextComment(let baseline):
            guard let baseline, let comments else { return false }
            // **`>`, ne `!=`.** Smazaný komentář počet sníží, a to není „přišel komentář“ —
            // odložení by skončilo tím, že někdo něco vzal zpátky. Že se základ smazáním posune
            // dolů, řeší `snoozeBaseline`, jinak by se od té chvíle nedalo dopočítat nic.
            return comments > baseline
        }
    }

    /// Odložení s **doplněným nebo srovnaným měřidlem** (#512). `nil` = není co měnit.
    ///
    /// Dvě různé situace, jedna funkce, protože obě odpovídají na „od čeho se má měřit“:
    ///
    /// 1. **Doplnění.** Odložení vzniklo nad řádkem fronty, kde se hlava ani počet příspěvků
    ///    neznají (`gh search prs` ani jedno nevrací). Základ dosadí první rozhlídka, která se na
    ///    to PR zeptá — do té doby odložení `snoozeExpired` neukončí.
    /// 2. **Srovnání dolů u komentářů.** Když je dnešní počet **nižší** než základ (někdo
    ///    komentář smazal), musí základ klesnout s ním. Jinak by se příští komentář vrátil jen na
    ///    původní číslo, `comments > baseline` by nevyšlo a odložení „do dalšího komentáře“ by
    ///    trvalo navždycky.
    ///
    /// **Vrací se `nil`, ne nezměněná kopie**, aby volající poznal, že nemá co zapisovat: zápis
    /// odložení sahá na disk, a rozhlídka běží každý tik.
    static func snoozeBaseline(_ snooze: Snooze, head: String?, comments: Int?) -> Snooze? {
        var updated = snooze
        switch snooze.condition {
        case .until:
            return nil
        case .nextPush(let baseline):
            // Základ se **nepřepisuje**, jen doplňuje: přepsat ho dnešní hlavou by u PR, na kterém
            // se mezitím pushlo, znamenalo odložení, které se nikdy neukončí.
            guard baseline == nil, let head else { return nil }
            updated.condition = .nextPush(head: head)
        case .nextComment(let baseline):
            guard let comments else { return nil }
            if let baseline, comments >= baseline { return nil }
            updated.condition = .nextComment(count: comments)
        }
        return updated
    }

    /// Proč se PR vrátil — do řádku dění (#512).
    ///
    /// Volá se jedině nad odložením, o kterém `snoozeExpired` řeklo `true`, takže je to překlad
    /// podmínky na důvod, ne druhé rozhodování. `Vrátit teď` sem nechodí: ruční návrat zná svůj
    /// důvod sám (`SnoozeReturn.manual`).
    static func snoozeReturn(of condition: SnoozeCondition) -> SnoozeReturn {
        switch condition {
        case .until: .time
        case .nextPush: .push
        case .nextComment: .comment
        }
    }

    // MARK: - Zúžení fronty

    /// Smí se tenhle PR odložit? (#512)
    ///
    /// **Jen cizí.** Odložit se dá to, co po mně někdo chce; u vlastního PR rozhoduje o tom, kdy
    /// se na něj podívám, to, kdy pushnu. Rozhodující důvod je ale kreslený: blok `Odložené` visí
    /// **pod frontou**, takže odložené vlastní PR by ze sekce `Moje PR` zmizelo a nikde by se
    /// neobjevilo — tedy přesně ta tichá díra, kvůli které tohle issue existuje.
    ///
    /// **Brána, ne zašedlá položka**: na vlastním řádku se nabídka `Odložit` nekreslí vůbec, jako
    /// se na cizím PR nekreslí merge (tvrdá podmínka č. 1).
    static func canSnooze(_ ownership: PullRequestOwnership) -> Bool {
        ownership == .theirs
    }

    /// Seznam **bez odložených** (#512) — další zúžení nad tím, co seznam už má.
    ///
    /// Tatáž škola jako `Policy.pullRequests(_:ownedBy:mine:)` (#332): je to **pohled**, ne nový
    /// zdroj pravdy. Čte to všechno, co tvrdí něco o práci, která na mě čeká — fronta a její
    /// odznak, deska, souhrn ve stavovém řádku, odznak v Docku, notifikace a automat.
    ///
    /// **Nikdy z něj neuklízej.** Úklid (`forget(whatIsNotIn:)`, `CacheEviction`,
    /// `ReviewStore.cleanUp`) bere plný seznam z tiku — odložený PR má na disku klon, nálezy
    /// i rozdělané review stejně jako každý jiný, a uklidit mu je jen proto, že ho zrovna nechci
    /// vidět, by znamenalo, že se po návratu z odložení začíná od nuly. Stejně tak nesmí mizet
    /// z **nabídky filtru** a z **nastavení**: repo, jehož jediné PR je odložené, se pořád sleduje.
    ///
    /// **Nesahá na řazení** — jako `filtered(_:by:)` a `pullRequests(_:ownedBy:mine:)`.
    static func pullRequests(
        _ pullRequests: [PullRequestSummary],
        withoutSnoozed isSnoozed: (PRIdentifier) -> Bool
    ) -> [PullRequestSummary] {
        pullRequests.filter { !isSnoozed($0.id) }
    }

    /// Odložené PR z toho seznamu — obsah bloku `Odložené` (#512).
    ///
    /// Doplněk k `pullRequests(_:withoutSnoozed:)` nad **tímtéž** vstupem: kdyby si blok skládal
    /// množinu po svém, uměly by se rozejít a PR by zmizel z fronty, aniž by se objevil v bloku.
    /// Přesně to je stav, kterému se tohle issue vyhýbá.
    static func snoozedPullRequests(
        in pullRequests: [PullRequestSummary],
        isSnoozed: (PRIdentifier) -> Bool
    ) -> [PullRequestSummary] {
        pullRequests.filter { isSnoozed($0.id) }
    }

    // MARK: - Rozhlídka

    /// Na které odložené PR se **v tomhle tiku** zeptáme (#512).
    ///
    /// Tatáž škola jako `staleHeadProbe` (#420) a `activitySweep` (#335), a ze stejného důvodu —
    /// dotaz na PR nesmí být `N+1` na tik:
    ///
    /// 1. **Jedno dávkové volání, ne jedno na PR** (`SnoozeProbeQuery`).
    /// 2. **Časová podmínka se neptá vůbec.** `do zítra 9:00` se pozná z hodin, takže dotaz na
    ///    GitHub by byl dotaz za nic (`SnoozeCondition.needsSignal`).
    /// 3. **`updatedAt` ze searche je předfiltr a je zadarmo.** Ptáme se jedině na PR, jehož
    ///    `updatedAt` se posunul od chvíle, kdy jsme se ptali naposledy — hlava se ani počet
    ///    příspěvků bez posunu `updatedAt` změnit nemá čím. Na klidný den **nula volání**.
    ///    Výjimka je PR, u kterého základ ještě neznáme: ten se musí zeptat i bez posunu, jinak
    ///    by odložení „do dalšího pushe“ nemělo od čeho měřit, dokud se na PR něco nestane.
    /// 4. **Strop na jeden dotaz** (`snoozeProbeLimit`) — ohraničuje velikost dokumentu; co se
    ///    nevejde, se zeptá příští tik, protože razítko dostane jedině PR, na které se ptalo.
    ///
    /// **Bere seznam z tiku, ne uložená odložení.** Odložení může v cache ležet i po PR, které se
    /// mezitím zavřelo a ze seznamu vypadlo — a ptát se na hlavu zavřeného PR znamená platit za
    /// odpověď, kterou nikdo nepřečte.
    ///
    /// - Parameters:
    ///   - snoozed: odložení toho PR, nebo `nil`, když odložené není.
    ///   - probedAt: `updatedAt`, se kterým se na to PR ptalo naposledy. `nil` = nikdy.
    static func snoozeProbe(
        of pullRequests: [PullRequestSummary],
        snoozed: (PRIdentifier) -> Snooze?,
        probedAt: (PRIdentifier) -> Date?,
        limit: Int = snoozeProbeLimit
    ) -> [PRIdentifier] {
        pullRequests
            .filter { summary in
                guard let snooze = snoozed(summary.id), snooze.condition.needsSignal else { return false }
                return snoozeNeedsBaseline(snooze.condition) || probedAt(summary.id) != summary.updatedAt
            }
            // Pořadí ze **vstupu**, jako u `staleHeadProbe`: seznam je od naposledy změněného,
            // takže strop uřízne to nejstarší — a to je zrovna to, co snese počkat na příští tik.
            .prefix(limit)
            .map(\.id)
    }

    /// Chybí téhle podmínce základ, od kterého se má měřit?
    ///
    /// Vlastní funkce, protože se na to ptá `snoozeProbe` (koho se zeptat) i `snoozeBaseline`
    /// (co doplnit) — dvě `switch` nad týmž výčtem by se rozešly první změnou.
    static func snoozeNeedsBaseline(_ condition: SnoozeCondition) -> Bool {
        switch condition {
        case .until: false
        case .nextPush(let head): head == nil
        case .nextComment(let count): count == nil
        }
    }

    /// Kolik odložených PR nejvíc se vejde do jednoho dotazu (#512).
    ///
    /// **Dvacet, jako u `staleHeadProbeLimit`, a ze stejného důvodu**: je to strop na velikost
    /// dokumentu, ne na cenu — dávkový GraphQL dotaz stojí jeden bod bez ohledu na počet aliasů
    /// (změřeno u #420). Odložených PR bývá jednotky; dvacet je s rezervou nad tím, co má smysl
    /// mít odložené naráz.
    static let snoozeProbeLimit = 20

    // MARK: - Věty

    /// `vrátí se zítra 9:00` / `vrátí se s dalším pushem` (#512) — poznámka u řádku v bloku
    /// `Odložené`.
    ///
    /// **Slibuje se podmínka, ne odhad.** U času se píše okamžik, u pushe a komentáře událost;
    /// „vrátí se asi zítra“ nad podmínkou, která na čase nestojí, by tvrdilo víc, než data unesou.
    ///
    /// **Blízké datum se píše dnem, vzdálené i datem.** `vrátí se zítra 9:00` je čitelnější než
    /// `vrátí se 6. 9. 9:00`, ale u odložení na týden je den v týdnu k ničemu.
    static func snoozeNote(_ snooze: Snooze, now: Date, calendar: Calendar = .current) -> String {
        switch snooze.condition {
        case .until(let deadline):
            "vrátí se \(snoozeDeadlineLabel(deadline, now: now, calendar: calendar))"
        case .nextPush:
            "vrátí se s dalším pushem"
        case .nextComment:
            "vrátí se s dalším komentářem"
        }
    }

    /// Termín slovy — `dnes 17:00`, `zítra 9:00`, `12. 9. 9:00`.
    ///
    /// **„Zítra“ se počítá proti `now`, ne proti systémovým hodinám.** `Calendar.isDateInTomorrow`
    /// se ptá na **skutečný** dnešek, takže by se poznámka v bloku rozešla s okamžikem, ze kterého
    /// se počítá zbytek odložení — a v testu s pevnými hodinami by vycházela náhodně podle toho,
    /// kdy test běží. Je to tentýž kořen jako globální stav procesu v `Tests/` (#367).
    static func snoozeDeadlineLabel(_ deadline: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = deadline.formatted(date: .omitted, time: .shortened)
        switch calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: deadline)
        ).day {
        case 0: return "dnes \(time)"
        case 1: return "zítra \(time)"
        default: return "\(deadline.formatted(date: .abbreviated, time: .omitted)) \(time)"
        }
    }

    /// Nadpis bloku `Odložené · 2` (#512). `nil` = blok se **nekreslí**.
    ///
    /// Prázdný blok by byl rámeček s nulou — tatáž úvaha, kvůli které deska prázdné pruhy
    /// nekreslí (#515). Odložení je stav, který něco skrývá, takže blok musí být vidět **právě
    /// tehdy**, když je co skrývat.
    ///
    /// **`hidden` je počet odložených, které z bloku vyřadil filtr** (oprava po proklikání).
    /// Blok pod frontou stojí nad **zafiltrovaným** seznamem, kdežto deska nad plným — takže
    /// bez téhle části nadpisu vede `do fronty →` z desky na jiné číslo, než jaké nabídlo,
    /// a nic to nevysvětlí. Nula se **nepíše**, jako u ostatních částí.
    static func snoozedBlockTitle(count: Int, hidden: Int = 0) -> String? {
        guard count > 0 || hidden > 0 else { return nil }
        guard hidden > 0 else { return "Odložené · \(count)" }
        return "Odložené · \(count) · \(hidden) schoval filtr"
    }

    /// Kolik odložených se na desce nakreslí (oprava po proklikání).
    ///
    /// **Strop, ne množina.** Nadpis bloku počítá dál všechny; patka říká, kolik se nevešlo, a vede
    /// do fronty. Bez stropu by dvacet odložených roztáhlo pravý sloupec desky přes celou
    /// obrazovku — tatáž úvaha jako u `laneRowLimit` a `activityRowLimit`, a **pět** proto, že blok
    /// je v tom sloupci třetí a má být tichý.
    static let snoozedBoardRowLimit = 5

    /// Věta do řádku dění, když se PR vrátil z odložení (#512).
    ///
    /// **Skládá se tady, ne v kresbě**, protože se ukládá — řádek dění je záznam toho, co se
    /// stalo tehdy (viz `ActivityEvent`).
    static func snoozeReturnDetail(_ reason: SnoozeReturn) -> String {
        switch reason {
        case .time: "došel čas"
        case .push: "přišel push"
        case .comment: "přišel komentář"
        case .manual: "vrátil jsem ho ručně"
        }
    }
}
