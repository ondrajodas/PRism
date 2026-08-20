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
}
