import Foundation

/// Razítko předání zadání agentovi (#334).
///
/// **Předání nic nemění na GitHubu.** Je to lokální stav v cache, ne značka na PR — kdyby se
/// zapisovalo ven, byla by to druhá cesta ven a tu tvrdá podmínka č. 1 nepřipouští. Nic v tomhle
/// souboru nezná `gh`, `ReviewPublishing` ani `URL` na GitHub API.
extension AppStore {
    /// Razítka z cache. Volá se **jednou při startu**, jako uložené nálezy a drafty.
    func loadStoredHandoffs() async {
        guard let handoffs else { return }
        handoffStamps = await handoffs.load()
    }

    /// Razítko u PR. `nil` = nepředáno.
    func handoff(for pr: PRIdentifier) -> Handoff? { handoffStamps[pr] }

    /// Co zbývá předat (#334) — jedna odpověď pro odznak v railu, pilulku v řádku i panel.
    ///
    /// Skládá se **při každém čtení**: razítko je v paměti, materiál taky (nálezy a konverzace),
    /// takže je to pár desítek porovnání řetězců, ne obarvení dvou tisíc řádků. Držet výsledek ve
    /// stavu by znamenalo druhou pravdu, kterou by musel obnovovat každý zápis nálezu, každý tik
    /// konverzace a každé předání.
    ///
    /// Commity jdou dovnitř jen kvůli počtu v panelu (`mezitím přišly 2 commity`) a tahají se
    /// s detailem PR (#316), tedy přesně tam, kde se ta věta kreslí. V seznamu žádné nejsou, takže
    /// odtud vyjde `nil` — a to je jiná věta, ne chybějící stav.
    func handoffReport(for pr: PRIdentifier) -> HandoffReport {
        Policy.handoff(
            handoffStamps[pr],
            record: reviewRecord(for: pr),
            conversation: conversation(for: pr),
            head: head(of: pr),
            commits: commits[pr]
        )
    }

    /// Kolik položek na vlastním PR zbývá předat — pilulka `N k předání` v řádku seznamu
    /// i na dashboardu. Nula znamená „nic nezbývá“, takže se pilulka nekreslí.
    func pendingHandoffCount(for pr: PRIdentifier) -> Int {
        handoffReport(for: pr).pending
    }

    /// Zapíše předání (#334) — **zkopírováním nebo uložením do souboru**, ne otevřením sheetu.
    ///
    /// Otevřený sheet je náhled; předané je to, co si člověk vzal. Kdyby razítko vznikalo
    /// otevřením, odznak by zhasl nad zadáním, které nikdo nikam nedal.
    ///
    /// Ukládá se **hlava i identity předaných položek** — proč, je u `Handoff`. Do paměti hned,
    /// na disk asynchronně: pravda za běhu je paměť (tentýž vzor jako u `AutoRunLedger`), protože
    /// odznak se překresluje dřív, než dopadne zápis.
    func noteHandoff(of prompt: AgentPrompt) {
        let stamp = Handoff(
            at: time.now,
            headSha: prompt.subject.headSha,
            handed: prompt.handed
        )
        let pr = prompt.subject.pullRequest
        handoffStamps[pr] = stamp
        guard let handoffs else { return }
        Task { await handoffs.record(stamp, for: pr) }
    }

    /// Zadání **jen z toho, co po předání přibylo v diskuzi** (#334) — `Sestavit i tak
    /// (jen nové vlákno)` po pushi.
    ///
    /// Nálezy v něm nejsou: po pushi platí pro starý kód, takže by agenta poslaly opravovat
    /// řádky, které v PR nejsou. Ze seznamu ale nemizí — sundat nález smí jedině odmítnutí (#113).
    ///
    /// `nil`, když po předání nepřišlo nic: prázdný sheet s hlavičkou a bez položek vypadá jako
    /// rozbitá aplikace, takže tlačítko je v tu chvíli zakázané s důvodem.
    func freshAgentPrompt(for pr: PRIdentifier) -> AgentPrompt? {
        let fresh = handoffReport(for: pr).freshDiscussion
        guard !fresh.isEmpty else { return nil }
        return agentPrompt(for: pr, only: fresh)
    }
}
