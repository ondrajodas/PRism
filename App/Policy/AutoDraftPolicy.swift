import Foundation

/// Co automat udělá s **jedním** nálezem (#520).
///
/// Tři odpovědi, ne `Bool`. „Vezmu si ho“, „nechám ho na kliknutí a řeknu proč“ a „tenhle už je
/// vyřízený“ jsou tři různé věci — a prostřední z nich je celý smysl issue: sporný nález se
/// nesmí ztratit.
enum AutoDraftPick: Hashable, Sendable {
    /// Převzít do rozdělaného review.
    case adopt
    /// Nechat na kliknutí — a **je vidět proč**.
    case contested(AutoDraftDoubt)
    /// Nezvažovat vůbec: je o něm rozhodnuto.
    case skip(AutoDraftSkip)
}

/// Proč nález do návrhu vůbec nevstoupil (#520).
enum AutoDraftSkip: Hashable, Sendable {
    /// Odmítl jsem ho (#113). **Návrh ho nesmí ani převzít, ani nabídnout jako sporný** —
    /// rozhodnutí člověka je konečné a druhý stav vedle něj by ho zpochybňoval.
    case dismissed
}

/// Složí automat na tomhle PR návrh review? (#520)
///
/// **Dvě odpovědi, a ta druhá nese důvod.** „Nesložil se“ bez důvodu je k nerozeznání od rozbité
/// aplikace — tatáž konstrukce jako u spouštěče agenta (`AgentFixDecision`, #510).
enum AutoDraftDecision: Equatable, Sendable {
    /// Slož návrh podle plánu.
    case compose(AutoDraftPlan)
    /// Nic neskládej, a **je vidět proč**.
    case skip(AutoDraftRefusal)
}

/// Proč se návrh nesložil (#520). **Výčet, ne věta**: rozhodnutí se testuje výčtem.
enum AutoDraftRefusal: Equatable, Sendable {
    /// Brána `autoDraft` je vypnutá — globálně nebo pro tohle repo. **Výchozí stav.**
    case gateClosed
    /// Vlastní PR. Review na něj GitHub nepustí (`APPROVE` i `REQUEST_CHANGES` vrátí 422,
    /// změřeno u #62), takže by návrh byl práce, kterou nejde odeslat — tatáž mez jako
    /// u předvyplnění verdiktu (`Policy.prefillableSuggestion`, #114).
    case ownPullRequest
    /// Nálezy patří jiné hlavě, než na které PR stojí (tvrdá podmínka č. 5). Návrh z nich by
    /// mluvil o kódu, který už neexistuje.
    case staleFindings
    /// Na PR už leží rozdělané review. **Tohle je ta odpověď na „už převzato ručně“**: co jsem
    /// začal psát já (nebo návrh z minulého běhu), automat nepřepíše — ani o jeden komentář.
    case draftExists
    /// Není co navrhnout: čisté review, nebo ze samých odmítnutých nálezů. Verdikt se tím
    /// **neruší** — ten dál navrhuje `Policy.suggestedVerdict` (#114).
    case nothingToPropose
}

/// Co si automat vzal a co nechal (#520).
struct AutoDraftPlan: Equatable, Sendable {
    /// Nálezy k převzetí, **v pořadí ze záznamu** — ať se komentáře v panelu skládají tak, jak by
    /// je naklikal člověk shora dolů.
    var adopt: [Finding]
    /// Nálezy, které zůstávají na kliknutí, a důvod u každého.
    var contested: [FindingKey: AutoDraftDoubt]

    /// Návrh, ve kterém není co ukázat. Takový se **nesklápí do razítka**: razítko bez obsahu by
    /// v okně tvrdilo „návrh je připravený“ nad prázdným panelem.
    var isEmpty: Bool { adopt.isEmpty && contested.isEmpty }
}

extension Policy {
    // MARK: - Kdy se návrh složí

    /// Složí se na tomhle PR návrh review? Čistá funkce, testuje se **vyčerpávajícím výčtem**.
    ///
    /// **Pořadí kontrol je součást odpovědi**, ne detail implementace — vyhrává první, která
    /// zabere, a jde od toho, co se dá zodpovědět bez ostatních dat:
    ///
    /// 1. **Brána.** `autoDraft` z `ResolvedConfig`, globálně i per repo, **ve výchozím stavu
    ///    vypnutá**. Právě to drží vlastnost „samo se nic nepředvyplní“; že se samo nic
    ///    **neodešle**, drží tvrdá podmínka č. 1 a ta se tímhle issue nemění ani o písmeno.
    /// 2. **Vlastnictví.** Na vlastní PR review odeslat nejde, takže se na něm nic nesklápí.
    /// 3. **Hlava.** Zastaralý záznam nebo hlava, která se s ním rozešla, znamená, že nálezy
    ///    mluví o kódu, který v PR není. `nil` hlava je **zákaz, ne povolení**: dokud nevíme,
    ///    na čem PR stojí, nedá se tvrdit, že návrh platí.
    /// 4. **Rozdělané review.** Existující draft se **nepřepisuje**, viz `draftExists`.
    /// 5. **Je co navrhnout.** Prázdný plán se zahazuje, aby v okně nevzniklo razítko nad ničím.
    ///
    /// - Parameters:
    ///   - isAllowed: `ResolvedConfig.autoDraft` toho repa. **Bez výchozí hodnoty** — brána,
    ///     kterou lze zapomenout, není brána (tatáž úvaha jako u `Policy.agentFix`).
    ///   - ownership: čí PR to je (`Policy.ownership(of:mine:)`), taky bez výchozí hodnoty.
    ///   - head: hlava, na které PR stojí **teď**. `nil` = nevíme.
    static func autoDraft(
        record: ReviewRecord?,
        draft: ReviewDraft?,
        ownership: PullRequestOwnership,
        isAllowed: Bool,
        head: String?
    ) -> AutoDraftDecision {
        guard isAllowed else { return .skip(.gateClosed) }
        guard ownership != .mine else { return .skip(.ownPullRequest) }
        guard let record, !record.isStale, let head, record.headSha == head else {
            return .skip(.staleFindings)
        }
        guard draft == nil else { return .skip(.draftExists) }

        let plan = autoDraftPlan(of: record)
        guard !plan.isEmpty else { return .skip(.nothingToPropose) }
        return .compose(plan)
    }

    /// Rozhodnutí nad **všemi** nálezy záznamu — tedy co se převezme a co zůstane sporné.
    ///
    /// Jde se po **skupinách** (`Policy.groups`), protože rozpor je vlastnost místa, ne nálezu:
    /// dva reviewery na jednom řádku, kteří se neshodnou, se nedají posoudit každý zvlášť.
    /// Nález bez `file:line` stojí ve vlastní skupině, takže se u něj rozpor z definice nestane —
    /// a je to správně: „chybí testy“ od dvou reviewerů není spor, je to dvakrát totéž.
    static func autoDraftPlan(of record: ReviewRecord) -> AutoDraftPlan {
        var plan = AutoDraftPlan(adopt: [], contested: [:])
        for group in groups(of: record.findings, dismissals: record.dismissals) {
            let doubt = disagreement(in: group)
            for finding in group.findings {
                switch autoDraftPick(of: finding, dismissal: group.dismissal(of: finding), doubt: doubt) {
                case .adopt:
                    plan.adopt.append(finding)
                case .contested(let reason):
                    plan.contested[key(of: finding)] = reason
                case .skip:
                    continue
                }
            }
        }
        return plan
    }

    /// Co automat udělá s jedním nálezem. **Tady se to rozhoduje a nikde jinde.**
    ///
    /// Pořadí je zase součást odpovědi:
    ///
    /// 1. **Odmítnutý nález** (#113) — o něm je rozhodnuto, takže se ani nepřevezme, ani se
    ///    nenabídne jako sporný. Je to jediná „naučená výjimka“, kterou aplikace dneska zná.
    /// 2. **Rozpor na místě** — přebíjí verdikt: dva `CONFIRMED` proti sobě jsou pořád spor.
    /// 3. **Verdikt.** `CONFIRMED` se převezme, `PLAUSIBLE` zůstává sporný a **chybějící verdikt
    ///    taky** — „neřekl jsem“ není „jsem si jistý“.
    ///
    /// **Shoda dvou reviewerů nález nerozdvojí do jednoho komentáře**: převezmou se oba, protože
    /// každý napsal vlastní větu a slévat cizí texty se v tomhle okně nikde nedělá
    /// (`FindingGroup`). Že z toho na GitHubu vzniknou dvě vlákna, říká panel větou nad seznamem
    /// komentářů (`Policy.linesWithSeveralComments`) — tedy dřív, než se cokoli odešle.
    static func autoDraftPick(
        of finding: Finding,
        dismissal: FindingDismissal?,
        doubt: AutoDraftDoubt?
    ) -> AutoDraftPick {
        guard dismissal == nil else { return .skip(.dismissed) }
        if let doubt { return .contested(doubt) }
        switch finding.verdict {
        case .confirmed: return .adopt
        case .plausible: return .contested(.plausible)
        case nil: return .contested(.noVerdict)
        }
    }

    /// Neshodnou se na tomhle místě reviewery? `nil` = neshoda tam není, nebo o ní nejde mluvit.
    ///
    /// **Rozpor je rozdíl ve verdiktu mezi dvěma různými reviewery na jednom místě** — tedy to,
    /// co se z dat doopravdy pozná. Sémantický spor („jeden chce A, druhý B“) aplikace přečíst
    /// neumí a tvrdit ho z textu by byl odhad, ne údaj.
    ///
    /// Počítá se jen z **platných** nálezů: shoda dvou reviewerů, ze kterých jednomu nevěřím,
    /// není shoda — tatáž úvaha jako u odznaku `2×` (`FindingGroup.agreement`).
    ///
    /// Jména se **řadí**, aby `php-review ↔ security-review` vyšlo pokaždé stejně; v razítku na
    /// disku by pořadí z pole nálezů znamenalo, že se tentýž spor po dalším běhu zapíše jinak.
    static func disagreement(in group: FindingGroup) -> AutoDraftDoubt? {
        let active = group.activeFindings
        let reviewers = Set(active.map(\.reviewer))
        guard reviewers.count > 1 else { return nil }
        guard Set(active.map(\.verdict)).count > 1 else { return nil }
        return .disagreement(reviewers: reviewers.sorted())
    }

    // MARK: - Co je z návrhu vidět

    /// Značky `sporné`, které se u nálezů **smí** nakreslit. Prázdné = nekreslí se nic.
    ///
    /// **Bere razítko, ne záznam**: kdyby se sporné počítalo při každém překreslení, objevila by se
    /// pilulka `PLAUSIBLE` i u člověka, který si automat nikdy nezapnul — tedy tvrzení o něčem,
    /// co se nestalo. Razítko naopak znamená „automat se na tyhle nálezy díval a tohle si nevzal“.
    ///
    /// Zahození návrhu razítko maže, takže tudy zhasne i značka u nálezu.
    static func autoDraftDoubts(of record: ReviewRecord?) -> [FindingKey: AutoDraftDoubt] {
        record?.autoDraft?.contested ?? [:]
    }

    /// Pruh v panelu: `Návrh připravený automatem · 21:52 · z 5 nálezů 3 převzaty, 2 sporné`.
    ///
    /// **Hodiny se předávají naformátované** — jdou přes locale, takže v `Policy` by se nedaly
    /// testovat (tatáž úvaha jako u `Policy.briefMeta`). Co tady zůstává, je rozhodnutí, co se
    /// vypíše, a to je jediné, co se dá pokazit potichu.
    ///
    static func autoDraftNote(at clock: String, adopted: Int, contested: Int) -> String {
        "Návrh připravený automatem · \(clock) · \(autoDraftTally(adopted: adopted, contested: contested))"
    }

    /// `z 5 nálezů 3 převzaty, 2 sporné` — počty samy o sobě.
    ///
    /// **Vlastní funkce, ne kus věty**, protože je čtou dvě místa: pruh v panelu a řádek v `Dění`.
    /// Dvě skládání týchž počtů by znamenala, že osa říká o témž návrhu něco jiného než okno.
    ///
    /// **Obě čísla se píšou vždycky, i když je jedno z nich nula.** Věta „z 3 nálezů 0 převzato,
    /// 3 sporné“ je to jediné, co nad prázdným panelem vysvětlí, proč v něm nic není — a „3
    /// převzaty“ bez druhé půlky by svádělo k tomu, že je hotovo.
    static func autoDraftTally(adopted: Int, contested: Int) -> String {
        let considered = adopted + contested
        let taken = Plural.czech(adopted, one: "převzat", few: "převzaty", many: "převzato")
        return "z \(Plural.czech(considered, one: "nálezu", few: "nálezů", many: "nálezů")) "
            + "\(taken), \(Plural.czech(contested, one: "sporný", few: "sporné", many: "sporných"))"
    }

    /// Pilulka v řádku fronty — `návrh review · 3 + 2 sporné`, u čistého `návrh: schválit`.
    ///
    /// `nil` = **nekreslí se nic**: žádné razítko a žádný verdikt k navržení (nebo vypnutá brána,
    /// viz níž).
    ///
    /// **Razítko má přednost před verdiktem.** Když návrh něco převzal, je to konkrétnější
    /// odpověď než „šlo by schválit“ — a obě pilulky vedle sebe by se praly o týž slot.
    ///
    /// **Brána platí jedině na živý návrh verdiktu, ne na razítko** — a je to rozhodnutí, ne
    /// nedůslednost. Razítko znamená, že návrh **už je složený**, takže v panelu leží komentáře,
    /// které tam někdo nenapsal; schovat o nich zprávu jen proto, že se volba mezitím vypnula, by
    /// z nich udělalo práci bez vysvětlení. Vypnutá volba brání tomu, aby **vznikl další** (to
    /// hlídá `Policy.autoDraft` a `AppStore.materializeAutoDraft`).
    ///
    /// **`návrh: schválit` se kreslí jedině nad `approve`.** `REQUEST_CHANGES` bez jediného
    /// převzatého nálezu znamená, že se všechno nechalo na kliknutí; slíbit u toho hotový verdikt
    /// by tvrdilo, že je co odeslat.
    static func autoDraftPill(
        stamp: StoredAutoDraft?,
        suggestion: ReviewVerdict?,
        isAllowed: Bool
    ) -> AutoDraftPill? {
        if let stamp { return .composed(adopted: stamp.adopted, contested: stamp.contested.count) }
        guard isAllowed else { return nil }
        return suggestion == .approve ? .verdict(.approve) : nil
    }
}

/// Co o návrhu review říká řádek fronty (#520).
///
/// **Typ, ne řetězec**: text i nápověda se z něj odvozují, takže se pilulka a to, co znamená,
/// nemají čím rozejít — a řádek se dá testovat bez kreslení.
enum AutoDraftPill: Hashable, Sendable {
    /// Návrh leží v panelu. Nese obě čísla, protože sporné se nesmí ztratit ani tady.
    case composed(adopted: Int, contested: Int)
    /// Nálezy nejsou (nebo se všechny odmítly) a verdikt jde navrhnout — `návrh: schválit`.
    case verdict(ReviewVerdict)

    var text: String {
        switch self {
        case .composed(let adopted, let contested):
            contested == 0
                ? "návrh review · \(adopted)"
                : "návrh review · \(adopted) + \(contested) sporné"
        case .verdict(let verdict):
            "návrh: \(verdict.choice.czechLabel.lowercased())"
        }
    }

    /// Nápověda říká **co dál**, ne co je vidět — text pilulky se v ní neopakuje (tatáž úvaha
    /// jako u pilulky agenta, #511).
    var help: String {
        switch self {
        case .composed(let adopted, let contested):
            contested == 0
                ? "Automat převzal \(Plural.czech(adopted, one: "nález", few: "nálezy", many: "nálezů")) do rozdělaného review. Odeslat se pořád potvrzuje v okně s celým payloadem."
                : "Automat převzal \(adopted) z nálezů, \(contested) nechal jako sporné. Co je sporné a proč, ukáže panel — odeslat se pořád potvrzuje v okně s celým payloadem."
        case .verdict:
            "Review doběhlo a nezbylo nic k převzetí — verdikt je jen návrh, odesílá se pořád ručně."
        }
    }
}
