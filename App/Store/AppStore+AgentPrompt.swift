import Foundation

/// Zadání pro agenta na vlastním PR (#333).
///
/// **Nic odsud neodchází.** Text končí ve schránce nebo v souboru, který si člověk vybere;
/// `ReviewPublishing` se u vlastního PR nepoužívá vůbec, takže store si tady nedrží ani cestu ke
/// `gh` (tvrdá podmínka č. 1, bod 2 a 3). Je na to test — `SingleWayOutTests`.
extension AppStore {
    /// Zadání složené z toho, co aplikace o PR **právě teď ví**.
    ///
    /// Skládá se při každém čtení, ne do stavu: `Conversation` se nepersistuje a nálezy se mění
    /// dalším během, takže uložené zadání by za minutu tvrdilo něco jiného, než je na obrazovce.
    /// Je to pár desítek řetězců, ne obarvení dvou tisíc řádků — cena je v hluku měření.
    ///
    /// **Nálezy se berou z uloženého záznamu, ne po filtru reviewerů**: filtr je pohled (koho
    /// zrovna nečtu), kdežto zadání je to, co se má opravit. Ztlumený reviewer by z něj tiše
    /// vypadl a v panelu by u volby stálo o dva nálezy méně, než kolik jich na PR je.
    func agentPrompt(for pr: PRIdentifier) -> AgentPrompt {
        let record = reviewRecord(for: pr)
        return Policy.agentPrompt(
            for: agentPromptSubject(for: pr),
            findings: record?.findings ?? [],
            dismissals: record?.dismissals ?? [:],
            conversation: conversation(for: pr),
            diff: loadedDiff(for: pr),
            blocking: resolved(for: pr.repo).blockingCategories,
            options: agentPromptOptions
        )
    }

    /// Je co předat? **Bez sázení textu.**
    ///
    /// Ptá se na to zkratka `⌘⇧P`, tedy něco, co se vyhodnocuje při každém překreslení detailu —
    /// a to je zrovna to místo, kde se nemá skládat pár kilobajtů markdownu (pravidlo #224).
    /// Panel text potřebuje (kreslí z něj náhled), zkratka jen ví, jestli má být zakázaná.
    func hasAgentPromptItems(for pr: PRIdentifier) -> Bool {
        let record = reviewRecord(for: pr)
        return Policy.agentPromptItems(
            findings: record?.findings ?? [],
            dismissals: record?.dismissals ?? [:],
            conversation: conversation(for: pr)
        )
        .contains { agentPromptOptions.includes($0.choice) }
    }

    /// Ke kterému PR zadání patří — větev a hlava z dotaženého detailu.
    ///
    /// Detail nemusí být načtený; pak zbyde samotná identita PR a text řekne, že hlavu neznáme.
    /// Předstírat ji prázdným řetězcem by znamenalo zadání, u kterého nejde poznat, proti čemu
    /// platí (tvrdá podmínka č. 5).
    private func agentPromptSubject(for pr: PRIdentifier) -> AgentPromptSubject {
        guard case .loaded(let detail, _) = detailStates[pr] else {
            return AgentPromptSubject(pullRequest: pr)
        }
        return AgentPromptSubject(pullRequest: pr, branch: detail.headRef, headSha: detail.headSha)
    }

    /// Přepne volbu v panelu. Zadání se tím **přeskládá při dalším čtení** — nikde se nedrží.
    func toggleAgentPromptOption(_ choice: AgentPromptChoice) {
        agentPromptOptions.toggle(choice)
    }

    /// Ukáže panel se zadáním — tab i rozložení, jako `revealDraft(in:)` u cizího PR.
    ///
    /// Používá to zkratka `⌘⇧P` a odkaz z hlavičky: složený panel by zkratku udělal němou a to je
    /// k nerozeznání od rozbité aplikace.
    func revealAgentPrompt(in pr: PRIdentifier) {
        reviewPanelTab = .agentPrompt
        isReviewPanelExpanded = true
        guard !detailTab(for: pr).showsReviewPanel else { return }
        setDetailTab(.standard, for: pr)
    }
}
