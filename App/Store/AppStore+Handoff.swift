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
    ///
    /// **Volající si bere celý report, ne jedno číslo** (#335). Do #335 tu vedle stál
    /// `pendingHandoffCount(for:)`, ale od chvíle, kdy řádek čte i cizí aktivitu, by to byla tatáž
    /// práce dvakrát: report se skládá při každém čtení a `List` staví řádky při každém překreslení.
    ///
    /// Cizí aktivita (#335) se počítá proti **značce v paměti** (`visitSnapshots`), ne proti
    /// ledgeru: tenhle getter čte SwiftUI při každém překreslení řádku, kdežto `VisitLedger` dekóduje
    /// celý slovník návštěv z předvoleb. Značku zakládá `seedVisitBaseline(for:)` — při zobrazení PR
    /// i při rozhlídce na pozadí —, takže PR, o kterém aplikace ještě neslyšela, vyjde jako „nevím“
    /// a řádek o novinkách mlčí. To je bezpečná strana: „od minule“ nad prázdnou značkou by
    /// znamenalo „od začátku věků“.
    func handoffReport(for pr: PRIdentifier) -> HandoffReport {
        Policy.handoff(
            handoffStamps[pr],
            record: reviewRecord(for: pr),
            conversation: conversation(for: pr),
            head: head(of: pr),
            commits: commits[pr],
            activitySince: visitSnapshots[pr]
        )
    }

    /// Zapíše předání (#334) — **zkopírováním nebo uložením do souboru**, ne otevřením sheetu.
    ///
    /// Otevřený sheet je náhled; předané je to, co si člověk vzal. Kdyby razítko vznikalo
    /// otevřením, odznak by zhasl nad zadáním, které nikdo nikam nedal.
    ///
    /// Ukládá se **hlava i identity předaných položek** — proč, je u `Handoff`. Do paměti hned,
    /// na disk asynchronně: pravda za běhu je paměť (tentýž vzor jako u `AutoRunLedger`), protože
    /// odznak se překresluje dřív, než dopadne zápis.
    ///
    /// **Identity se sčítají s předchozím razítkem** a **hlava se posune jedině tehdy, když se
    /// předávaly nálezy.** Obojí kvůli zúženému zadání po pushi (`Sestavit i tak (jen nové
    /// vlákno)`): to se skládá proti dnešní hlavě, ale nálezy v něm nejsou — takže kdyby posunulo
    /// hlavu, panel by přestal hlásit, že uložené nálezy platí pro starý commit, a kdyby razítko
    /// přepsalo identity, byly by dřív předané nálezy najednou „nepředané“ a odznak by se rozsvítil
    /// za práci, která odešla (nálezem Copilota na #373). Hlava proto říká, **proti jakému kódu
    /// platí předané nálezy**; předání bez nálezů na tom nic nemění.
    func noteHandoff(of prompt: AgentPrompt) {
        let pr = prompt.subject.pullRequest
        let previous = handoffStamps[pr]
        let carriesFindings = (prompt.included.count(of: .findings) ?? 0) > 0
            || (prompt.included.count(of: .dismissedFindings) ?? 0) > 0
        let stamp = Handoff(
            at: time.now,
            headSha: carriesFindings ? prompt.subject.headSha : previous?.headSha ?? prompt.subject.headSha,
            handed: (previous?.handed ?? []).union(prompt.handed)
        )
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
