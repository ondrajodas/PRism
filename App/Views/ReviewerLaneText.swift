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

    /// Co běh stál — vpravo v hlavičce. `nil`, dokud to nedorazí: cenu nese `result` event, takže
    /// běžící reviewer ji nemá a zabitý ji mít nebude. Nula by tvrdila, že běh byl zdarma.
    static func usage(of lane: ReviewerLane) -> String? {
        lane.usage.flatMap(RunUsageText.summary(of:))
    }
}
