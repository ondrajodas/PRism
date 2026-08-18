import Foundation

/// Jedna položka zadání pro agenta (#333) — to, co je na vlastním PR potřeba opravit.
///
/// **Čtyři případy, ne jeden s příznakem.** Nález našel reviewer a odpovídat není komu; vlákno,
/// komentář a souhrn review napsal člověk a dá se mu odpovědět. Agent podle toho pozná, kde se
/// dá zeptat zpátky — a proto se ten původ nese i v textu, ne jen v odznaku v okně.
///
/// Nese **původní modely**, ne opsané řetězce: tatáž úvaha jako u `ConversationEntry`. Kdyby se
/// při sběru přepisovaly do jednoho plochého tvaru, rozhodnutí „co se z položky ukáže“ by spadlo
/// do sběru a text zadání by se nedal změnit bez zásahu do klasifikace.
enum AgentPromptItem: Hashable, Sendable, Identifiable {
    /// Nález mého revieweera. `dismissedAs` nese důvod odmítnutí (#113) — položka s ním se do
    /// zadání dostane jedině tehdy, když se o to v panelu výslovně řekne.
    case finding(Finding, dismissedAs: FindingDismissal.Reason?)
    /// Vlákno u řádku — od kolegy i od Copilota.
    case thread(ReviewThread)
    /// Komentář pod PR. Soubor ani řádek nemá.
    case comment(ThreadComment)
    /// Souhrn odeslaného review. Soubor ani řádek nemá.
    case review(SubmittedReview)

    /// Identita nese **typ**, ne jen `id` z GitHubu: review, komentář a vlákno mají vlastní
    /// číselné řady a shoda mezi nimi by v `ForEach` zahodila jednu z položek. Stejné pravidlo
    /// jako u `ConversationEntry.id`.
    var id: String {
        switch self {
        case .finding(let finding, _): "f\(Policy.key(of: finding).rawValue)"
        case .thread(let thread): "t\(thread.id)"
        case .comment(let comment): "c\(comment.id)"
        case .review(let review): "r\(review.id)"
        }
    }

    /// Do které volby v panelu položka patří — tedy čím se dá zapnout a vypnout.
    ///
    /// Vyřešené vlákno a odmítnutý nález jsou **vlastní volby**, ne příznak na těch ostatních:
    /// `vyřešeno` je stav vlákna na GitHubu, ne důkaz, že je hotovo, takže se musí dát přibrat
    /// zvlášť — a v okně být vidět, i když v textu nejsou.
    var choice: AgentPromptChoice {
        switch self {
        case .finding(_, let dismissal): dismissal == nil ? .findings : .dismissedFindings
        case .thread(let thread): thread.isResolved ? .resolvedThreads : .unresolvedThreads
        case .comment: .comments
        case .review: .reviews
        }
    }

    /// Do sekce kterého souboru položka patří. `nil` = sekce `K celému PR (bez souboru)`.
    ///
    /// Komentář pod PR a souhrn review soubor **nemají** a přišpendlit je k náhodnému by
    /// agentovi lhalo o tom, kde se to řeší. Nález bez souboru (chybějící test, poznámka
    /// k architektuře) je tentýž případ.
    var file: String? {
        switch self {
        case .finding(let finding, _): finding.file
        case .thread(let thread): thread.path
        case .comment, .review: nil
        }
    }

    /// Řádek, u kterého se to řeší. `nil` = položka platí pro celý soubor.
    ///
    /// U zastaralého vlákna je to `originalLine` (`anchorLine`), tedy číslo, které platilo pro
    /// starší commit — že je zastaralé, **musí být napsané v textu** (`Policy.agentPromptHeading`).
    /// Tvrdit dnešní řádek u kotvy, která platila pro starý head, je horší než nic.
    var line: Int? {
        switch self {
        case .finding(let finding, _): finding.line
        case .thread(let thread): thread.anchorLine
        case .comment, .review: nil
        }
    }

    /// Kdy položka vznikla. `nil` = nevíme — nález datum nenese (klíčuje se `headSha`) a
    /// rozdělané (`pending`) review datum odeslání nemá.
    var date: Date? {
        switch self {
        case .finding: nil
        case .thread(let thread): thread.comments.items.first?.createdAt
        case .comment(let comment): comment.createdAt
        case .review(let review): review.submittedAt
        }
    }
}

/// Co se dá do zadání zapnout a vypnout (#333) — jedna volba, jeden zaškrtávací řádek v panelu.
///
/// Výčet je **pořadí v panelu**: čtyři druhy obsahu, pak dvě volby na to, co se běžně vynechává,
/// a nakonec diff hunk. Poslední z nich není druh položky, ale podoba každé z nich — je to ta
/// jediná volba, která nic nepřidává ani neubírá ze seznamu, jen mění, kolik textu z něj bude.
enum AgentPromptChoice: String, Hashable, Sendable, CaseIterable, Codable {
    case findings
    case unresolvedThreads
    case comments
    case reviews
    case resolvedThreads
    case dismissedFindings
    case diffHunks

    /// Popisek zaškrtávacího řádku v panelu.
    ///
    /// **Bez „od kolegů“ u vláken a review** (odchylka od návrhu, sekce 22): do zadání jde
    /// všechno, co aplikace o PR ví, tedy i vlákno, které jsem si na vlastním PR založil sám —
    /// a to je zrovna poznámka „tady se ještě musím vrátit“, tedy práce, ne cizí názor. Popisek,
    /// který by tvrdil „od kolegů“, by o obsahu lhal; autor je u každé položky napsaný v textu.
    var label: String {
        switch self {
        case .findings: "Nálezy mých reviewerů"
        case .unresolvedThreads: "Nevyřešená vlákna u řádků"
        case .comments: "Komentáře pod PR"
        case .reviews: "Souhrny review"
        case .resolvedThreads: "Vyřešená vlákna"
        case .dismissedFindings: "Odmítnuté nálezy"
        case .diffHunks: "Diff hunk u každého místa"
        }
    }

    /// Nápověda u řádku — u dvou voleb říká, proč jsou vypnuté.
    var explanation: String {
        switch self {
        case .findings: "Co nahlásily review skilly na tomhle PR"
        case .unresolvedThreads: "Vlákna u řádků diffu, která na GitHubu nikdo neoznačil za vyřešená"
        case .comments: "Diskuze pod pull requestem — k žádnému řádku se neváže"
        case .reviews: "Próza odeslaných review; často je v ní to, kvůli čemu se změny vyžádaly"
        case .resolvedThreads: "„Vyřešeno“ je stav vlákna na GitHubu, ne důkaz, že je hotovo — proto se dá přibrat"
        case .dismissedFindings: "Nálezy, které jsi posoudil jako neplatné nebo nepatřící sem"
        case .diffHunks: "U dlouhých PR je to většina textu; agent má repo k dispozici, takže je to pohodlí, ne nutnost"
        }
    }

    /// Je to druh položky, nebo podoba textu? Počet se ukazuje jen u těch prvních.
    var countsItems: Bool { self != .diffHunks }

    /// Je to materiál, který **zbývá předat** (#334)?
    ///
    /// Vyřešené vlákno a odmítnutý nález ne: jedno je zavřená diskuze, druhé moje rozhodnutí
    /// (#113), a ani jedno po mně nic nechce — proto se v panelu ukazují vypnuté. `diffHunks`
    /// není druh položky, takže se nepočítá vůbec.
    ///
    /// Tohle je **materiál pro `Policy.handoff`**, tedy pro odznak v railu, pilulku `N k předání`
    /// a panel naráz. Kdyby si ho každé z těch míst vybíralo samo, počítala by tři různá čísla.
    var isPending: Bool {
        switch self {
        case .findings, .unresolvedThreads, .comments, .reviews: true
        case .resolvedThreads, .dismissedFindings, .diffHunks: false
        }
    }

    /// Počet i s podstatným jménem v české podobě — `2 nálezy`, `1 vlákno u řádku`.
    ///
    /// Krátké tvary, ne `label`: odznak v hlavičce sheetu jich nese vedle sebe čtyři a
    /// `2 nálezy mých reviewerů` by z nich udělalo dva řádky. `diffHunks` položky nepočítá,
    /// takže z něj vyjde prázdný řetězec — ptát se na jeho počet je chyba volajícího, ne stav.
    func countLabel(_ count: Int) -> String {
        switch self {
        case .findings:
            Plural.czech(count, one: "nález", few: "nálezy", many: "nálezů")
        case .unresolvedThreads:
            Plural.czech(count, one: "vlákno u řádku", few: "vlákna u řádků", many: "vláken u řádků")
        case .comments:
            Plural.czech(count, one: "komentář pod PR", few: "komentáře pod PR", many: "komentářů pod PR")
        case .reviews:
            Plural.czech(count, one: "souhrn review", few: "souhrny review", many: "souhrnů review")
        case .resolvedThreads:
            Plural.czech(count, one: "vyřešené vlákno", few: "vyřešená vlákna", many: "vyřešených vláken")
        case .dismissedFindings:
            Plural.czech(count, one: "odmítnutý nález", few: "odmítnuté nálezy", many: "odmítnutých nálezů")
        case .diffHunks:
            ""
        }
    }
}
