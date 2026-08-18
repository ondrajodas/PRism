import Foundation

/// Co na vlastním PR **zbývá předat** agentovi (#334).
///
/// Je to jedna odpověď pro tři místa — odznak sekce `Moje PR` v railu, pilulka `N k předání`
/// v řádku seznamu a panel `Zadání`. Kdyby si na „co je nové“ odpovídalo každé z nich samo,
/// rozešlo by se to: odznak by svítil nad řádkem, který tvrdí, že je hotovo. Proto je rozhodnutí
/// **jedna čistá funkce** (`Policy.handoff(_:record:conversation:head:commits:)`) a tenhle typ je
/// celý její výsledek.
struct HandoffReport: Equatable, Sendable {
    /// V jakém stavu je předání. Pořadí případů je pořadí rozhodování ve `Policy.handoff`.
    enum Stage: Equatable, Sendable {
        /// Nepředáno — panel se chová jako do #334.
        case never
        /// Předáno, ale proti **neznámé hlavě**: platnost se nedá potvrdit ani vyvrátit.
        ///
        /// Vlastní případ, ne `outdated`: „zadání zastaralo“ je tvrzení o pushnutých commitech,
        /// kdežto tady se jen neví, proti čemu se předávalo. Splynutí by v panelu vypsalo počet
        /// commitů, který nikdo nespočítal.
        case unverified
        /// Hlava se posunula — zadání mluví o kódu, který na PR není.
        case outdated
        /// Předáno proti dnešní hlavě, ale něco zbývá: nepředaná položka, nová položka, nebo
        /// cizí odpověď v předaném vlákně.
        case changed
        /// Předáno a od té doby nic nového.
        case delivered
    }

    let stage: Stage
    /// Razítko. `nil` jedině u `.never`.
    let handoff: Handoff?
    /// Kolik položek zbývá předat — obsah pilulky `N k předání`.
    ///
    /// U `.outdated` je to **všechno**, co je k předání: po pushi neplatí ani to, co se předalo,
    /// takže „zbývá 1“ nad šesti nálezy proti staré hlavě by lhalo o tom, co je potřeba udělat.
    let pending: Int
    /// Identity nepředaných položek **z diskuze** (`AgentPromptItem.id`) — z nich se skládá
    /// `Sestavit i tak (jen nové vlákno)`.
    ///
    /// Nálezy v tom nejsou schválně: po pushi platí pro starý kód, takže se do zadání
    /// nepředvybírají (#334). Ze seznamu ale **nemizí** — to smí jedině odmítnutí (#113).
    let freshDiscussion: Set<String>
    /// Aktivní nálezy, které platí pro starou hlavu. Nenulové jedině u `.outdated`.
    let staleFindings: Int
    /// Kolik commitů přišlo od předané hlavy. `nil` = ze seznamu commitů se to nepozná
    /// (nenačetl se, nebo v něm předaná hlava není — typicky po force pushi).
    let commits: Int?
    /// Posunula se hlava od předání?
    ///
    /// **Vlastní příznak vedle `stage`**, protože posunutá hlava a zastaralé nálezy jsou dvě různé
    /// věci: po pushi je `stage` `.outdated` jen tehdy, dokud nálezy platí pro starší commit — jak
    /// se review pustí znovu, je `.changed`, ale věta v panelu má pořád říct, že pod předaným
    /// zadáním přišel commit.
    let hasMovedHead: Bool

    init(
        stage: Stage,
        handoff: Handoff?,
        pending: Int,
        freshDiscussion: Set<String>,
        staleFindings: Int,
        commits: Int?,
        hasMovedHead: Bool = false
    ) {
        self.stage = stage
        self.handoff = handoff
        self.pending = pending
        self.freshDiscussion = freshDiscussion
        self.staleFindings = staleFindings
        self.commits = commits
        self.hasMovedHead = hasMovedHead
    }

    /// Nic se nepředávalo a nic se neví. Výchozí hodnota pro místa, která razítko nemají po ruce.
    static let never = HandoffReport(
        stage: .never,
        handoff: nil,
        pending: 0,
        freshDiscussion: [],
        staleFindings: 0,
        commits: nil
    )

    /// Čeká na tomhle PR můj tah? **Obsah odznaku v railu** a jediné, co z reportu čte fronta.
    ///
    /// Je to `pending > 0`, tedy „zbývá tu něco, co jsem nepředal?“ — ne „je tu něco?“. Po
    /// předání zhasne, i když nálezy dál existují; rozsvítí ho teprve nová položka, cizí odpověď
    /// v předaném vlákně nebo nový commit.
    var awaitsMove: Bool { pending > 0 }

    /// Kreslí panel volby a náhled, nebo razítko?
    ///
    /// `.delivered` je jediný stav, ve kterém se zaškrtávací řádky schovají: není z čeho vybírat,
    /// všechno je předané. `.outdated` má vlastní podobu (varování a dvě cesty dál), takže volby
    /// nekreslí ani ten.
    var showsChoices: Bool {
        switch stage {
        case .never, .unverified, .changed: true
        case .delivered, .outdated: false
        }
    }
}

extension Policy {
    /// Co zbývá předat (#334). **Jediné místo, kde se rozhoduje, co je „nové“.**
    ///
    /// Materiál je to, co by neslo zadání pro agenta pod všemi zapnutými volbami
    /// (`AgentPromptChoice.isPending`) — tedy nálezy, nevyřešená vlákna, komentáře pod PR
    /// a souhrny review. Vyřešená vlákna a odmítnuté nálezy (#113) v něm nejsou: jedno je
    /// zavřená diskuze, druhé moje rozhodnutí, a ani jedno po mně nic nechce.
    ///
    /// **Změna proti #331**, kde odznak počítal „nezpracovaný nález nebo nevyřešené **cizí**
    /// vlákno“. Otázka se změnila, takže se změnil i materiál: „zbývá tu něco, co jsem nepředal?“
    /// se ptá po tom, co půjde do zadání — a tam patří i vlákno, které jsem si na vlastním PR
    /// založil sám (poznámka „tady se musím vrátit“ je práce, viz `Policy.agentPromptItems`),
    /// i komentář pod PR a souhrn review, kvůli kterému se změny vyžádaly. Odznak tím počítá
    /// totéž, co pilulka v řádku a co panel — a to je celý důvod, proč tahle funkce existuje.
    ///
    /// - Parameters:
    ///   - head: hlava PR, jak ji známe **teď**. `nil` (detail se nenačetl) se bere jako „hlava
    ///     se neposunula“, a je to vědomá **spodní hranice**: hlavu aplikace zná jedině
    ///     z dotaženého detailu, a ten se tahá při zobrazení PR, ne pollingem (`gh search prs`
    ///     ho nevrací, viz #4). Kdyby neznámá hlava znamenala `.outdated`, odznak by po předání
    ///     nikdy nezhasl — tedy přesně to, co tohle issue opravuje. Odznak, který o části práce
    ///     ještě neví, nelže; odznak, který ji hlásí pořád, se přestane čítat.
    ///   - commits: commity PR **od nejstaršího**, jak je vydává gateway. Slouží jen k počtu
    ///     v panelu; bez nich se počet nenapíše, což je jiná věta, ne chybějící stav.
    static func handoff(
        _ stamp: Handoff?,
        record: ReviewRecord?,
        conversation: Conversation?,
        head: String?,
        commits: [PullRequestCommit]? = nil
    ) -> HandoffReport {
        let material = agentPromptItems(
            findings: record?.findings ?? [],
            dismissals: record?.dismissals ?? [:],
            conversation: conversation
        )
        .filter(\.choice.isPending)

        guard let stamp else {
            return HandoffReport(
                stage: .never,
                handoff: nil,
                pending: material.count,
                freshDiscussion: discussionIDs(of: material),
                staleFindings: 0,
                commits: nil
            )
        }

        let unhanded = material.filter { isUnhanded($0, since: stamp, in: conversation) }
        let discussion = discussionIDs(of: unhanded)

        guard let againstHeadSha = stamp.headSha else {
            return HandoffReport(
                stage: .unverified,
                handoff: stamp,
                // Všechno, ne jen nepředané: bez hlavy se nedá tvrdit, že předané ještě platí.
                pending: material.count,
                freshDiscussion: discussion,
                staleFindings: 0,
                commits: nil
            )
        }

        if let head, head != againstHeadSha {
            // **Zastaralé jsou nálezy, ne razítko**, a rozhoduje to `headSha` záznamu: jak se proti
            // dnešní hlavě pustí review znovu, jsou nálezy platné a `Pustit review znovu` by byla
            // rada, která už proběhla. Bez téhle podmínky by panel zůstal v režimu varování
            // **navždycky** a volby by se v něm nedaly zapnout (nálezem Copilota na #373).
            let staleFindings = record.map { $0.headSha == head ? 0 : $0.activeFindings.count } ?? 0
            return HandoffReport(
                stage: staleFindings > 0 ? .outdated : .changed,
                handoff: stamp,
                // Všechno, ne jen nepředané: pod předaným zadáním se změnil kód, takže se má
                // předat znovu — a nový commit má rozsvítit odznak i tehdy, když se v diskuzi nic
                // nestalo (zadání #334).
                pending: material.count,
                freshDiscussion: discussion,
                staleFindings: staleFindings,
                commits: commitCount(since: againstHeadSha, in: commits),
                hasMovedHead: true
            )
        }

        return HandoffReport(
            stage: unhanded.isEmpty ? .delivered : .changed,
            handoff: stamp,
            pending: unhanded.count,
            freshDiscussion: discussion,
            staleFindings: 0,
            commits: nil
        )
    }

    /// Zbývá tuhle položku předat?
    ///
    /// Nepředaná je zjevně ta, která v razítku není. Druhý případ je **předané vlákno, do
    /// kterého mezitím někdo odpověděl**: identita vlákna se odpovědí nemění, takže samotné
    /// „už jsem ho poslal“ by novou větu od kolegy zahodilo. Vlastní odpovědi se nepočítají —
    /// že jsem něco napsal já, není novinka (tatáž úvaha jako u „od tvé poslední návštěvy“).
    private static func isUnhanded(
        _ item: AgentPromptItem,
        since stamp: Handoff,
        in conversation: Conversation?
    ) -> Bool {
        guard stamp.includes(item.id) else { return true }
        guard case .thread(let thread) = item, let conversation else { return false }
        return thread.comments.items.contains { $0.createdAt > stamp.at && !conversation.isMine($0) }
    }

    /// Identity položek z diskuze — vlákna, komentáře pod PR a souhrny review, bez nálezů.
    private static func discussionIDs(of items: [AgentPromptItem]) -> Set<String> {
        Set(items.filter { $0.choice != .findings }.map(\.id))
    }

    /// Kolik commitů přišlo za hlavou, proti které se předávalo.
    ///
    /// `nil`, když se předaná hlava v seznamu nenajde. Znamená to jedno ze dvou: seznam se
    /// nenačetl, nebo se historie přepsala (force push, rebase) a ten commit na větvi už není.
    /// Obojí je „nevím kolik“, a to se v panelu píše jinak než „přišly dva“ — dopočítat rozdíl
    /// z délky seznamu by dalo číslo, které s pushnutými commity nemá nic společného.
    private static func commitCount(since headSha: String, in commits: [PullRequestCommit]?) -> Int? {
        guard let commits, let index = commits.firstIndex(where: { $0.sha == headSha }) else {
            return nil
        }
        return commits.count - index - 1
    }
}
