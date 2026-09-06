import Foundation

/// Pilulka o agentovi v řádku `Moje PR` (#511, #509).
///
/// **Dva stavy, ne jeden s `Bool`em**: „něco běží“ a „něco na tebe čeká“ jsou dvě různé odpovědi
/// na otázku, kvůli které se na řádek kouká — a jedna z nich znamená čekat, druhá jít k počítači.
enum AgentRowPill: Equatable, Sendable {
    /// Agent zrovna pracuje. `elapsed` je hotový text (`4 min`), ne počet — skloňování a mez
    /// „ještě ani minuta“ patří do `Policy`, ne do řádku.
    case running(elapsed: String)
    /// Commit agenta leží v kopii repa a čeká na potvrzení force pushe.
    case awaitingPush

    var text: String {
        switch self {
        case .running(let elapsed): "agent běží · \(elapsed)"
        case .awaitingPush: "push čeká na tebe"
        }
    }
}

extension Policy {
    // MARK: - Jak běh dopadl

    /// Výsledek běhu z toho, co ve stromě leží (#511). `nil` = tenhle stav o agentovi nemluví.
    ///
    /// **Rozhoduje `origin`, ne počet commitů**: `rebased` vzniká i po obyčejném rebase (#466)
    /// a věta o agentovi nad přehranými commity by tvrdila něco, co se nestalo — je to tatáž
    /// hranice, kvůli které #510 zavedlo `BranchWorkOrigin`.
    ///
    /// **`BranchSyncState.failed` sem nepatří, a je to schválně.** Ten stav nenese, kdo ho
    /// způsobil — rebase i agent končí v témže případu —, takže by se z něj „agent spadl“
    /// **hádalo**. Kdo o běhu agenta ví (store, který ho pustil), skládá `.failed` sám.
    static func agentRun(of state: BranchSyncState) -> AgentRunOutcome? {
        switch state {
        case .rebased(let branch) where branch.origin == .agent:
            return agentRun(files: branch.fix?.files.count ?? 0, skipped: branch.fix?.skipped)
        case .fixedNothing(let detail):
            return .nothing(detail: detail)
        case .fixRejected(let detail):
            return .discarded(detail: detail)
        case .rebased, .rebasing, .resolving, .fixing, .pushing, .discarding, .pushed,
            .alreadyInSync, .conflicted, .unfinished, .unresolved, .failed:
            return nil
        }
    }

    /// Hotovo, nebo částečně? **Rozhoduje jediná věc — jestli se agent k něčemu přiznal.**
    ///
    /// Je to jedno místo schválně: „částečně“ se nesmí odvozovat z počtu souborů (dvě položky se
    /// dají opravit v jednom souboru) ani z délky účtu. Jediné, co o nesplněné části zadání něco
    /// ví, je věta, kterou o ní session sama napsala (`AgentFixAnswer.skipped`).
    static func agentRun(files: Int, skipped: String?) -> AgentRunOutcome {
        guard let skipped, !skipped.isEmpty else { return .done(files: files) }
        return .partial(files: files, skipped: skipped)
    }

    // MARK: - Věta do panelu

    /// Věta o výsledku běhu — **jediné místo, kde se skládá** (#511).
    ///
    /// Tvar je ze zadání: *Agent upravil 2 soubory ve stromě 499-sync · nic se neodeslalo.*
    /// Tři části a každá odpovídá na jinou otázku: **co udělal**, **kde to leží** a **co se
    /// nestalo**. Ta třetí je v ní proto, že je to celá hranice #510 — a je snazší ji přehlédnout
    /// než přečíst, protože se o ní mlčí.
    ///
    /// **O testech se nemluví ani slovem** (viz `AgentRunOutcome`): session je pustit nemůže
    /// a aplikace je nad jejím výsledkem nepouští.
    ///
    /// **Věta od modelu je až na konci.** `skipped` je cizí text neznámé délky, takže nesmí stát
    /// mezi tím, co ví aplikace — je to tatáž úvaha jako u `unresolved`, kde seznam souborů
    /// rozdělil podmět a přísudek.
    ///
    /// - Parameter worktree: jméno stromu (`499-sync`), ne celá cesta: v panelu je 300 bodů
    ///   a sedmdesát znaků cache z nich udělá odstavec. `nil` = strom neznáme, a pak se o něm
    ///   **mlčí** místo vymýšlení.
    static func agentRunSentence(_ outcome: AgentRunOutcome, worktree: String?) -> String {
        switch outcome {
        case .done(let files):
            return agentWorkSentence(files: files, worktree: worktree)
        case .partial(let files, let skipped):
            return agentWorkSentence(files: files, worktree: worktree) + " " + skipped
        case .nothing(let detail):
            return "Agent nic nezměnil, takže není co commitnout." + (detail.map { " \($0)" } ?? "")
        case .failed(let detail), .discarded(let detail):
            // Obojí už větu **je** — složil ji ten, kdo o té chybě něco ví (session, `git`,
            // zrušení). Druhá věta kolem ní by z jedné příčiny udělala dvě tvrzení.
            return detail
        }
    }

    /// Společná půlka `done` a `partial`: co vzniklo, kde to leží a co se nestalo.
    private static func agentWorkSentence(files: Int, worktree: String?) -> String {
        // **Nula souborů je vlastní věta, ne `0 souborů`.** Účet od modelu může být nečitelný
        // (`AgentFixCommand.parse` vrátí prázdno), přitom commit vznikl — a `git` je tady ta
        // strana, která má pravdu. Tvrdit „upravil 0 souborů“ nad commitem, který existuje, je
        // text, který si odporuje sám se sebou.
        let what = files > 0
            ? "Agent upravil \(Plural.czech(files, one: "soubor", few: "soubory", many: "souborů"))"
            : "Agent připravil commit"
        let place = worktree.map { " ve stromě \($0)" } ?? " v kopii repa"
        return what + place + " · nic se neodeslalo."
    }

    // MARK: - Živý ocas

    /// Kolik kroků se v panelu drží (#511).
    ///
    /// **Čtyři, a je to mez toho, co se kreslí, ne toho, co se ví.** Sekce `Větev` má 300 bodů
    /// a nad ocasem stojí věta o stavu, tlačítko a řada akcí; osm řádků by z panelu udělalo log
    /// a vytlačilo by ven to, kvůli čemu se na sekci kouká. Celý záznam běhu ocas nahrazovat
    /// nemá — patnáctiminutová session jich vyrobí stovky.
    static let agentTailLength = 4

    /// Přidá krok do ocasu a **usekne ho na `agentTailLength`** (#511, pravidlo #224).
    ///
    /// **Mez je v téhle funkci, ne v tom, kdo ji volá.** Ocas je paměť, která roste s během:
    /// bez vypsaného stropu je to únik paměti s odkladem, a mez schovaná ve view by neplatila pro
    /// data, která ve store zůstanou i po zavření panelu. Vyprazdňuje ho konec běhu
    /// (`AppStore.branchSyncTail[pr] = nil`), tedy táž ruka, která ho plní.
    ///
    /// **Bezprostřední opakování se nezdvojuje.** Session čte tentýž soubor po částech, takže
    /// `čte X` přijde třikrát za sebou — a tři stejné řádky ze čtyř znamenají ocas, ze kterého
    /// není poznat, že se něco děje. Opakování dál v ocase se **nechává být**: `čte A`, `čte B`,
    /// `čte A` je pravdivý postup, ne šum.
    static func agentTail(_ tail: [String], appending step: String) -> [String] {
        guard !step.isEmpty else { return tail }
        guard tail.last != step else { return tail }
        return Array((tail + [step]).suffix(agentTailLength))
    }

    // MARK: - Commit agenta jako řádek pro prohlížeč commitů

    /// Přeloží commit z kopie repa na to, co umí nakreslit hlavička rozkliknutého commitu (#317).
    ///
    /// **Překlad, ne výroba.** Všechny čtyři údaje jsou přečtené z `gitu`; co v datech není
    /// (účet na GitHubu, obrázek autora), zůstává `nil`, protože ten commit na GitHubu **není**.
    /// `isMerge` je `false` z definice: aplikace commituje `git commit` nad jednou hlavou.
    ///
    /// **Vlastní funkce, ne konstruktor u `AgentFixCommit`**: `AgentFixCommit` je odpověď `gitu`
    /// a nemá vědět, jak se kreslí seznam commitů pull requestu.
    static func agentCommitRow(_ commit: AgentFixCommit) -> PullRequestCommit {
        PullRequestCommit(
            sha: commit.sha,
            message: commit.message,
            authorName: commit.authorName,
            authorLogin: nil,
            avatarURL: nil,
            committedAt: commit.committedAt,
            isMerge: false
        )
    }

    // MARK: - Pilulka v řádku `Moje PR`

    /// Co o agentovi říká řádek seznamu (#511). `nil` = nic — cizí PR, nebo se nic neděje.
    ///
    /// **Jen na vlastním PR**, jako všechno kolem agenta: na cizím se nespouští (`Policy.agentFix`
    /// vrací `notMine` jako první odpověď), takže by pilulka na cizím řádku byla stav, který nemá
    /// jak vzniknout — a kdyby vznikl, byla by to chyba, kterou má být poznat.
    static func agentRowPill(
        sync: BranchSyncState?,
        ownership: PullRequestOwnership,
        now: Date
    ) -> AgentRowPill? {
        guard ownership == .mine, let sync else { return nil }
        switch sync {
        case .fixing(_, let since): return .running(elapsed: agentElapsed(since: since, now: now))
        case .rebased(let branch) where branch.origin == .agent: return .awaitingPush
        default: return nil
        }
    }

    /// Jak dlouho agent běží, do pilulky (#511).
    ///
    /// **Minuty, ne vteřiny**, a je to mez běhu, ne úspora znaků: session má limit patnáct minut
    /// (`AgentFixCommand.timeout`), takže je minuta jednotka, ve které se ta otázka klade —
    /// a vteřiny by z pilulky v seznamu udělaly věc, která se hýbe pod rukou.
    ///
    /// **Pod minutu se nepíše `0 min`.** Nula by tvrdila, že se nic neděje, zrovna když se
    /// začalo; a záporný rozdíl (posunuté hodiny) spadne do téže odpovědi, protože „běží
    /// −3 minuty“ je text, který nemá co znamenat.
    static func agentElapsed(since: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(since) / 60)
        guard minutes >= 1 else { return "<1 min" }
        return "\(minutes) min"
    }
}
