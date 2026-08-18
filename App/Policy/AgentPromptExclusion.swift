import Foundation

/// Proč položka **není** v textu zadání (#377) — a co se o tom napíše k jejímu řádku.
///
/// Šest důvodů, a je to celý výčet toho, co aplikace umí vypnout sama. Dva z nich jsou volby
/// panelu z #333 (`odmítl jsi ho`, `vyřešeno`), jeden je hrubý filtr po druzích a tři se poznají
/// **z dat** — vlastní autorství, prázdný souhrn a souhrn, který jen převypráví diff.
///
/// **U každé vypnuté položky musí být důvod vidět**, protože bez něj je předvybrání aplikace
/// k nerozeznání od chyby: čtyřicet položek, z nichž pět je odškrtnutých bez vysvětlení, se
/// neprochází, ale odklikne.
enum AgentPromptExclusion: String, Hashable, Sendable, CaseIterable, Identifiable {
    /// Odmítnutý nález (#113) — dokud se volba `Odmítnuté nálezy` nezapne.
    case dismissed
    /// Vyřešené vlákno — dokud se volba `Vyřešená vlákna` nezapne.
    case resolved
    /// Celý druh je v panelu vypnutý. Hrubý filtr, tedy **moje** rozhodnutí, ne aplikace.
    case kindOff
    /// Napsal jsem to já (`Conversation.isMine`).
    case mine
    /// Souhrn review bez obsahu — prázdné tělo, nebo tělo bez čehokoli kromě nadpisů.
    case empty
    /// Souhrn, který jen převypráví diff (`Policy.summarizesDiff`) — jediná heuristika.
    case summarizesDiff

    var id: String { rawValue }

    /// Popisek u řádku položky (`.pick .why` z návrhu, sekce 23).
    var label: String {
        switch self {
        case .dismissed: "odmítl jsi ho"
        case .resolved: "vyřešeno"
        case .kindOff: "druh vypnutý"
        case .mine: "napsal jsi to ty"
        case .empty: "bez obsahu"
        case .summarizesDiff: "shrnuje diff"
        }
    }

    /// Předvybrala to aplikace **z dat**, nebo je to moje volba v panelu?
    ///
    /// Rozděluje to věta pod seznamem: `Vypnuté jsem předvybral: …` mluví jen o tom, co aplikace
    /// poznala sama. `odmítl jsi ho`, `vyřešeno` ani `druh vypnutý` do ní nepatří — to jsou
    /// zaškrtávátka, která jsem vypnul já, a vysvětlovat mi vlastní rozhodnutí je šum.
    var isPreselected: Bool {
        switch self {
        case .mine, .empty, .summarizesDiff: true
        case .dismissed, .resolved, .kindOff: false
        }
    }

    /// Počet s podstatným jménem — `1 vlastní`, `2 souhrny bez obsahu`.
    ///
    /// Krátké tvary, ne `label`: odznaků nad textem je vedle sebe až šest, takže
    /// `2 souhrny review, které jen shrnují diff` by z nich udělalo dva řádky.
    func countLabel(_ count: Int) -> String {
        switch self {
        case .dismissed:
            Plural.czech(count, one: "odmítnutý", few: "odmítnuté", many: "odmítnutých")
        case .resolved:
            Plural.czech(count, one: "vyřešené", few: "vyřešená", many: "vyřešených")
        case .kindOff:
            Plural.czech(count, one: "položka", few: "položky", many: "položek")
        case .mine:
            Plural.czech(count, one: "vlastní", few: "vlastní", many: "vlastních")
        case .empty:
            Plural.czech(count, one: "souhrn bez obsahu", few: "souhrny bez obsahu", many: "souhrnů bez obsahu")
        case .summarizesDiff:
            Plural.czech(count, one: "souhrn diffu", few: "souhrny diffu", many: "souhrnů diffu")
        }
    }

    /// Odznak nad textem — `1 vlastní vynechán`, `2 souhrny bez obsahu vynechány`.
    ///
    /// `nil` u `kindOff`: tam se odznak skládá z **volby**, ne z důvodu (`vynecháno: 2 komentáře
    /// pod PR`), protože „2 položky vynechány“ by neřeklo, které — a zrovna u hrubého filtru je
    /// druh ta informace, kterou hledám.
    ///
    /// Sloveso se skloňuje s podstatným jménem: `vyřešené vlákno` je střední rod, ostatní mužský.
    /// Jedna tabulka tvarů by z `1 vyřešené vynechán` udělala češtinu, které si nikdo nevšimne
    /// dřív, než se na obrazovku podívá.
    func omittedLabel(_ count: Int) -> String? {
        guard self != .kindOff else { return nil }
        let verb = self == .resolved
            ? Plural.word(count, one: "vynecháno", few: "vynechána", many: "vynecháno")
            : Plural.word(count, one: "vynechán", few: "vynechány", many: "vynecháno")
        return "\(countLabel(count)) \(verb)"
    }
}

extension Policy {
    /// Proč tahle položka není v zadání (#377). `nil` = je v něm.
    ///
    /// **Pořadí případů je pořadí rozhodování a záleží na něm.** Nejdřív ty dva stavy, které mají
    /// vlastní volbu v panelu od #333 (`odmítl jsi ho`, `vyřešeno`) — jsou to pravdivější popisky
    /// než „druh vypnutý“ a přesně tak je kreslí návrh. Pak hrubý filtr po druzích, protože to je
    /// **moje** rozhodnutí a má přebít cokoli, co aplikace pozná z dat. Až nakonec předvybrání
    /// z dat.
    ///
    /// Vlákna a nálezy z dat vypnout **nejde**: vlákno, které jsem si na vlastním PR založil sám,
    /// je poznámka „tady se musím vrátit“, tedy práce (`Policy.agentPromptItems`), a nález sundá
    /// jedině odmítnutí (#113). Předvybrat se proto dá jen to, co je próza bez místa v kódu —
    /// komentář pod PR a souhrn review.
    static func agentPromptExclusion(
        of item: AgentPromptItem,
        options: AgentPromptOptions,
        conversation: Conversation?
    ) -> AgentPromptExclusion? {
        switch item {
        case .finding(_, let dismissal) where dismissal != nil && !options.includes(.dismissedFindings):
            return .dismissed
        case .thread(let thread) where thread.isResolved && !options.includes(.resolvedThreads):
            return .resolved
        default:
            break
        }
        guard options.includes(item.choice) else { return .kindOff }
        switch item {
        case .comment(let comment):
            return conversation?.isMine(comment) == true ? .mine : nil
        case .review(let review):
            if conversation?.isMine(review) == true { return .mine }
            if hasNoContent(review.body) { return .empty }
            return summarizesDiff(review.body) ? .summarizesDiff : nil
        case .finding, .thread:
            return nil
        }
    }

    /// Je položka v textu zadání (#377)?
    ///
    /// **Jediné místo, kde se to rozhoduje** — text i seznam v sheetu se ptají tudy, jinak by se
    /// počet v hlavičce rozešel s tím, co se zkopíruje. Je to tentýž důvod, proč #334 svedlo „co je
    /// nové“ na jednu funkci.
    ///
    /// Drží se **odchylka, ne seznam vybraných** (jako `Policy.disclosure` u bublin, #185): výchozí
    /// stav se odvozuje z dat a z voleb, takže seznam vybraných by se musel plnit při každém
    /// přeskládání zadání — a nový běh review nebo dotažená konverzace by uživateli zahodily, co si
    /// naklikal. `!=` je tady xor: předvybraná položka se kliknutím vypne, vypnutá zapne, a obojí
    /// jednou hodnotou v množině.
    static func agentPromptIncludes(
        _ item: AgentPromptItem,
        options: AgentPromptOptions,
        conversation: Conversation?,
        toggled: Set<String> = []
    ) -> Bool {
        let excluded = agentPromptExclusion(of: item, options: options, conversation: conversation) != nil
        return excluded == toggled.contains(item.id)
    }
}
