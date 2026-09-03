import Foundation

/// Texty dráhy v tabu `Průběh` (#242).
///
/// Vlastní typ, ne metody na `ReviewerLane`: `Policy` počítá **strukturu** (kam se běh dostal),
/// kdežto tohle je česká próza, která se dá zkontrolovat testem bez vykreslení okna — stejný vzor
/// jako `RunUsageText` nebo texty lišty diffu.
enum ReviewerLaneText {
    /// Odznak stavu v hlavičce dráhy.
    ///
    /// `spadlo` a `nedoběhlo` jsou dvě různá slova schválně: první znamená nenulový kód, druhé
    /// zrušený běh. Slít je do jednoho by bylo přesně to, co `CLAUDE.md` u chybových stavů zakazuje.
    /// Totéž platí o `nespuštěno` a `ve frontě`: první znamená „nespustilo se“, druhé „review běží
    /// a tenhle čeká na slot“.
    static func state(_ state: ReviewerLane.State) -> String {
        switch state {
        case .notStarted: "nespuštěno"
        case .missingProgress: "bez průběhu"
        case .queued: "ve frontě"
        case .running: "běží"
        case .finished: "doběhlo"
        case .timedOut: "vypršel čas"
        case .interrupted: "přerušeno aplikací"
        case .failed: "spadlo"
        case .stopped: "nedoběhlo"
        }
    }

    /// Jak dopadla **jedna fáze** — pro čtečku obrazovky, která v chipu vidí jen popisek a značku.
    ///
    /// Musí to být stav té fáze, ne stav celé dráhy: se stavem dráhy by čtečka u všech fází přečetla
    /// totéž, tedy „doběhlo“ i nad fází, na kterou nedošlo. Nálezem Copilota na #258.
    static func phase(_ state: ReviewerLane.PhaseState) -> String {
        switch state {
        case .done: "hotovo"
        case .running: "právě běží"
        case .failed: "selhalo"
        case .stopped: "nedoběhlo"
        case .idle: "nedošlo na ni"
        case .unknown: "neví se"
        }
    }

    /// Věta pod dráhou: co se právě děje, nebo čím to skončilo. `nil` = není co dodat.
    ///
    /// U spadlé session je `nil` schválně — důvod má vlastní blok s koncem logu a dvě věty
    /// o tomtéž pod sebou se přestanou číst obě.
    static func last(of lane: ReviewerLane) -> String? {
        switch lane.state {
        case .notStarted:
            // Nesmí to znít jako čekání ve frontě: nic neběží, takže se na nic nečeká. A nesmí to
            // znít ani jako výsledek — o kódu tenhle reviewer neřekl vůbec nic.
            return "Nespustilo se — je v nastavené sadě, ale na tomhle PR ještě neběželo."
        case .missingProgress:
            // Nesmí to znít jako selhání ani jako čisto: běh proběhl a jeho výsledek uložený je,
            // chybí jen průběh. Věta proto říká, kde se ten výsledek dá přečíst.
            return "Běželo, ale průběh se neuložil — starší záznam osu neobsahuje. Jak to dopadlo, "
                + "je vidět v hlavičce PR a v tabu Nálezy."
        case .queued:
            return "Nezačalo — čeká na volný slot."
        case .running:
            guard let tool = lane.lastTool else { return "Session naběhla, první krok ještě nepřišel." }
            guard let detail = tool.shortened(inside: lane.worktree), !detail.isEmpty else {
                return "Právě: \(tool.name)"
            }
            return "Právě: \(tool.name) \(detail)"
        case .finished:
            return finished(lane)
        case .timedOut:
            return "Vypršel čas a session byla zabita. Nálezy, které do té doby dorazily, zůstaly."
        case .interrupted:
            return "Skončilo s aplikací; nálezy se dotáhly z transcriptu."
        case .stopped:
            return "Nedoběhlo — běh někdo zrušil. Co v ose je, je všechno, co dorazilo."
        case .failed:
            return nil
        }
    }

    /// Doběhlá session. Rozlišuje **tři** stavy, ne dva: nahlásila nálezy, nahlásila prázdný
    /// seznam, nebo nenahlásila nic. To poslední **není čisto** — reviewer, který `ReportFindings`
    /// nezavolal, o kódu neřekl nic, a věta „nic nenašel“ by tvrdila víc, než data unesou.
    private static func finished(_ lane: ReviewerLane) -> String {
        guard let count = lane.reportedFindings else {
            return "Doběhlo, ale nálezy vůbec nenahlásilo — to není totéž jako čisto."
        }
        guard count > 0 else { return "Doběhlo a nahlásilo prázdný seznam, tedy čisto." }
        return "Doběhlo · \(Plural.czech(count, one: "nález", few: "nálezy", many: "nálezů"))."
    }

    /// Popisky obou cest do terminálu (#453).
    ///
    /// **Obě nesou konkrétní příkaz**, a to je podmínka, ne pohodlí: v hlavičce stojí dvě ikony
    /// vedle sebe a nápověda je jediné, čím se od sebe liší. Skládá je `Policy.resumeCommand`,
    /// takže se text v nápovědě nemá čím rozejít s tím, co se zkopíruje nebo pustí.
    static func copyResume(sessionID: String) -> String {
        "Zkopírovat \(Policy.resumeCommand(sessionID: sessionID))"
    }

    /// **Od #460 je cíl zásuvka, ne `Terminal.app`** — a popisek to musí říct, protože je to
    /// jediné, čím se `▶` představuje dřív, než se na něj klikne.
    static let resumeInDrawer = "Pustit session v terminálu"

    /// **Nápověda ukazuje to, co se doopravdy pustí**, tedy včetně režimu povolení — od #460 se
    /// to od textu u `⧉` liší a text, který by ten rozdíl zamlčel, by tvrdil víc, než data unesou.
    /// Skládá to `Policy.drawerResumeCommand`, takže se s tím, co odejde do zásuvky, nemá čím
    /// rozejít.
    static func resumeInDrawerHelp(sessionID: String) -> String {
        "Vytáhne zásuvku s terminálem, přejde v ní do pracovního stromu té session a pustí "
            + "\(Policy.drawerResumeCommand(sessionID: sessionID))."
    }

    /// Odznak v hlavičce dráhy, když zadání pro reviewera nebylo celé (#345).
    ///
    /// **Netvrdí, co v zadání chybělo** — na to je místo v nápovědě a v souboru se zadáním. Krátký
    /// je schválně: hlavička nese už jméno skillu, stav, cenu a případné `mimo sadu` nebo
    /// `běžel …`, a v úzkém panelu se dlouhý popisek ořeže do nesmyslu.
    static let intentGapLabel = "zadání není celé"

    /// Co přesně chybělo, větou. Jde do nápovědy odznaku.
    ///
    /// **Každý důvod má vlastní větu**, protože rozlišit „issue nic neříká“ od „text se nedotáhl“
    /// je celý smysl toho příznaku — jedna souhrnná hláška by ty dva stavy slila zpátky do sebe.
    /// A žádná z nich netvrdí, že review je proto špatné: běželo, jen s menším zadáním.
    static func intentGap(_ gap: IntentGap) -> String {
        switch gap {
        case .toolNotConfigured:
            return "Text issue se netahal — v konfiguraci není jméno nástroje (`issueTextTool`), "
                + "takže reviewer dostal jen odkazy. Nic se nepokazilo, jen se to nezkoušelo."
        // **Věta o tom, že se nepřihlášený server nedá odlišit od chybějícího, tady schválně
        // není** (nález Copilota na #388): platila by jedině u `status == nil`, kdežto u vypsaného
        // stavu si protiřečí — ten stav je zrovna to, čím se ty dva případy **liší**. Že je pro
        // uživatele následek stejný, je úvaha o modelu (`IntentGap`), ne text do nápovědy.
        case .serverUnavailable(let status):
            let detail = status.map { "hlásil stav `\($0)`" } ?? "v session vůbec nebyl"
            return "Text issue se nedotáhl — server trackeru \(detail), takže reviewer dostal "
                + "jen odkazy."
        case .toolDenied:
            return "Text issue se nedotáhl — nástroj se v session odmítl (`permission_denials`). "
                + "Reviewer dostal jen odkazy."
        case .noAnswer:
            return "Text issue se nedotáhl — session doběhla, ale text z odpovědi nevypadl. "
                + "Reviewer dostal jen odkazy."
        case .sessionFailed(let detail):
            return "Text issue se nedotáhl — session se nepustila: \(detail). Reviewer dostal "
                + "jen odkazy."
        case .commentsUnavailable:
            return "Komentáře pod PR se nepodařilo přečíst, takže odkazů na zadání mohlo být víc, "
                + "než kolik jich reviewer dostal — linkback z trackeru chodí zrovna komentářem."
        }
    }

    /// Totéž pár slovy — do výpisu událostí, kde je na řádek jeden.
    static func intentGapReason(_ gap: IntentGap) -> String {
        switch gap {
        case .toolNotConfigured: "nástroj není nastavený"
        case .serverUnavailable(let status): status.map { "server trackeru: \($0)" } ?? "server trackeru chybí"
        case .toolDenied: "nástroj se odmítl"
        case .noAnswer: "bez použitelné odpovědi"
        case .sessionFailed(let detail): "session se nepustila: \(detail)"
        case .commentsUnavailable: "komentáře pod PR se nenačetly"
        }
    }

    /// Co běh stál — vpravo v hlavičce. `nil`, dokud to nedorazí: cenu nese `result` event, takže
    /// běžící reviewer ji nemá a zabitý ji mít nebude. Nula by tvrdila, že běh byl zdarma.
    static func usage(of lane: ReviewerLane) -> String? {
        lane.usage.flatMap(RunUsageText.summary(of:))
    }

    // MARK: - Přírůstek (#517)

    /// Kapsle vedle stavu. Krátká schválně — rozsah stojí hned za ní a věta pod dráhou.
    static let incrementLabel = "přírůstek"

    /// Rozsah, nad kterým běh běžel. **Zkrácená sha, jako všude jinde v okně**: celých čtyřicet
    /// znaků dvakrát by z hlavičky dráhy vytlačilo cenu.
    static func incrementRange(_ range: IncrementalDiffRange) -> String {
        "proti \(range.seen.prefix(7)) → \(range.head.prefix(7))"
    }

    /// Rozhodnutí o rozsahu do **výpisu kroků** — jeden řádek osy (#517).
    ///
    /// Ve výpisu je na řádek jedna věc, takže se sem vejde celá věta: u přírůstku rozsah, u celého
    /// diffu **důvod**. Do osy se přitom dostane jedině rozhodnutí, které má co říct
    /// (`ReviewScope.belongsInTimeline`), takže věta „celý diff, protože je to první kolo“ tady
    /// nikdy nestojí.
    static func scope(_ scope: ReviewScope) -> String {
        switch scope {
        case .increment(let range): "jen přírůstek — \(incrementRange(range))"
        case .whole(let reason): "celý diff — \(wholeReason(reason))"
        }
    }

    /// Proč se šlo na celý diff, i když by se čekal přírůstek (#517).
    ///
    /// **Každý důvod má vlastní věty**, jako u `intentGap`: „nedoběhlo minule“ a „přepsala se
    /// historie“ vedou na tentýž běh, ale znamenají něco jiného — a jedna souhrnná hláška by je
    /// slila zpátky do sebe. Věty o vypnutém nastavení, prvním kole a téže hlavě jsou tu jen kvůli
    /// úplnosti výčtu; do okna se nedostanou (`ReviewScope.saysWhyWhole`).
    static func wholeReason(_ reason: ReviewScope.WholeReason) -> String {
        switch reason {
        case .disabled: "přírůstek je v nastavení vypnutý"
        case .firstReview: "první kolo na tomhle PR, takže není od čeho odpočítávat"
        case .sameHead: "hlava se od minulého review nezměnila"
        case .noFinishedRun: "minule nedoběhlo, takže není od čeho odpočítávat"
        case .rewroteHistory: "historie se přepsala (force push), společná část není"
        case .unknownAncestry: "společnou historii se nepodařilo zjistit"
        }
    }

    /// Nápověda ke kapsli. Musí říct, **co běh nečetl** — bez toho se `přírůstek` čte jako
    /// vlastnost výsledku, kdežto je to vlastnost zadání.
    static func incrementHelp(_ range: IncrementalDiffRange) -> String {
        "Reviewer prošel jen to, co se pushlo od minulého review (`git diff "
            + "\(range.seen.prefix(7))...\(range.head.prefix(7))`) — ne celý diff PR. Nálezy "
            + "z minula dostal jako materiál a řekl o nich, jestli trvají."
    }

    /// Nápověda k té větě. Musí říct, **co to znamená pro výsledek** — samotné „celý diff“ se dá
    /// přečíst jako porucha, přitom je to stav, ve kterém aplikace běžela do #517.
    static func wholeReasonHelp(_ reason: ReviewScope.WholeReason) -> String {
        "Reviewer prošel **celý** diff PR, ne jen to, co se pushlo od minula: "
            + "\(wholeReason(reason)). Nálezy z minula se tedy nepřenášely — tenhle běh je "
            + "nahlásí sám, pokud pořád platí."
    }

    /// Jak přírůstek dopadl — věta pod dráhou. `nil` = běh ještě neskončil, takže se netvrdí nic.
    ///
    /// **Nesčítá se do jednoho čísla.** „3 staré trvají“ a „1 nový“ jsou různá tvrzení: první je
    /// o kódu, který nikdo znovu nečetl, druhé o tom, co se pushlo. Jedno číslo „4 nálezy“ by ten
    /// rozdíl zahodilo — a on je celý smysl přírůstku.
    ///
    /// Co běh **neposoudil**, se přiznává (`bez odpovědi`), a `vyřešený pushem` se píše jako
    /// odznak, ne jako ubraný nález: sundat nález smí jedině odmítnutí člověkem (#113).
    static func increment(_ tally: Policy.IncrementalTally) -> String? {
        var parts: [String] = []
        if tally.new > 0 {
            parts.append(Plural.czech(tally.new, one: "nový nález", few: "nové nálezy", many: "nových nálezů")
                + " v přírůstku")
        }
        if tally.stillApplies > 0 { parts.append("\(tally.stillApplies) starých trvá") }
        if tally.resolved > 0 { parts.append("\(tally.resolved) vyřešených pushem") }
        if tally.unclear > 0 { parts.append("\(tally.unclear) nejasných") }
        // **„Nezeptali jsme se“ je jiná věta než „neodpověděl“** (#517): první tvrdí něco o nás,
        // druhá o modelu. Slít je do jedné by znamenalo, že se selhání zápisu materiálu čte jako
        // mlčení revieweera.
        if tally.unanswered > 0 {
            parts.append(tally.askedForVerdicts
                ? "\(tally.unanswered) bez odpovědi"
                : "\(tally.unanswered) neposouzených — materiál se nepodařilo uložit")
        }
        // Prázdný souhrn není „čisto“: znamená, že běh nic nenahlásil a z minula nebylo co nést.
        // Věta o tom už stojí výš (`finished(_:)`), takže se tady mlčí.
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ") + "."
    }

    /// Cena přírůstku proti ceně celého běhu z prvního kola. `nil` = jedna z nich není známá,
    /// a **dohadovat se nesmí**: nula by tvrdila, že běh byl zdarma.
    static func incrementSaving(of lane: ReviewerLane) -> String? {
        guard let whole = lane.increment?.tally?.wholeUsage?.cost,
              let increment = lane.usage?.cost
        else { return nil }
        return "Přírůstek \(RunUsageText.cost(increment)) proti \(RunUsageText.cost(whole)) "
            + "za celý běh v 1. kole."
    }

    // MARK: - Krok v ose (#326)

    /// Odznak odmítnutého kroku. **Verzálky a mono jako v návrhu** — je to štítek, ne věta.
    static let deniedStep = "ODMÍTNUTO"

    /// Co stojí na konci řádku kroku. `nil` = nevíme (krok bez `id`, tedy osa uložená před #326).
    ///
    /// `běží…`, ne trvání: krok, na který ještě nepřišel `tool_result`, se nesmí tvářit jako
    /// hotový — je to totéž pravidlo, jaké dělí `čisté` od `nálezy se nemají kde vzít`.
    static func step(_ mark: ToolStepMark) -> String? {
        switch mark {
        case .none: nil
        case .pending: "běží…"
        case .duration(let value): RunUsageText.duration(value)
        case .denied: deniedStep
        }
    }

    /// Nápověda k řádku kroku — proč se odmítl, nebo co za chybu nástroj vrátil. `nil` u kroku,
    /// který dopadl dobře nebo o sobě nic neříká.
    ///
    /// Hláška je anglická, protože ji píše `claude`, a je to schválně: přeložit cizí chybu
    /// znamená hádat, co v ní bylo. České je to, co k ní aplikace dodává.
    static func stepHelp(of tool: ToolAttempt) -> String? {
        guard let outcome = tool.outcome, let label = stepFailure(outcome.kind) else { return nil }
        return [label, outcome.reason].compactMap { $0 }.joined(separator: " ")
    }

    /// Jak se o kroku, který nedopadl dobře, mluví. `nil` u toho, který dopadl.
    private static func stepFailure(_ kind: ToolAttempt.Outcome.Kind) -> String? {
        switch kind {
        case .passed: nil
        case .denied: "Odmítnuto — nástroj se nespustil."
        case .failed: "Nástroj vrátil chybu."
        }
    }

    // MARK: - Výpis kroků (#325)

    /// Kolik kroků výpis nese — v hlavičce i ve sbaleném řádku.
    static func stepCount(_ count: Int) -> String {
        Plural.czech(count, one: "krok session", few: "kroky session", many: "kroků session")
    }

    /// Zkrácení v hlavičce výpisu. `nil` u neořezané osy: hlavička, která tvrdí ořez tam, kde
    /// žádný není, je horší než žádná — tatáž úmluva jako u `Policy.logTailNotice`.
    ///
    /// **Přiznává se dvakrát** (v hlavičce a řezem na začátku výpisu), a je to schválně: hlavička
    /// je vidět i sbalená, kdežto řez stojí na místě, kde ta useknutá část byla.
    static func stepShortfall(_ dropped: Int) -> String? {
        guard dropped > 0 else { return nil }
        return "· \(dropped) starších se nevešlo"
    }

    /// Řez na začátku výpisu.
    ///
    /// **Skloňuje se i sloveso**, ne jen podstatné jméno: `1 starší krok se nevešlo` je věta, která
    /// v okně praští do očí hned, a jednička je tady běžný stav — ořez přibývá po jedné.
    static func stepCut(_ dropped: Int) -> String? {
        guard dropped > 0 else { return nil }
        let steps = Plural.czech(
            dropped,
            one: "starší krok se nevešel",
            few: "starší kroky se nevešly",
            many: "starších kroků se nevešlo"
        )
        return "\(steps) do stropu"
    }

    /// Přepínač sledování konce. **Není to akce, ale stav**, takže sloveso v infinitivu a barva
    /// běžícího kroku (`find`), ne akcentová.
    static let followTail = "Sledovat konec"

    static let followTailHelp = "Výpis se drží u nejnovějšího kroku. Vypne se odrolováním nahoru "
        + "i klikem; na konci se zapne zpátky. Neukládá se — je to gesto v jednom běhu."

    /// Pilulka u spodní hrany, když se konec nesleduje a mezitím něco přišlo.
    static func stepArrivals(_ count: Int) -> String {
        "↓ \(Plural.czech(count, one: "nový", few: "nové", many: "nových"))"
    }

    /// Co dělá klik na sbalený řádek. Slovo je v řádku schválně — samotná šipka neřekne, že se dá
    /// kliknout, a je to jediné místo, odkud se výpis doběhlé dráhy otevře.
    static let expandFeed = "rozbalit"
}
