import Foundation

/// Session, kterou jde pustit v terminálu (#453; od #460 v **zásuvce**, ne v `Terminal.app`).
///
/// Nese **adresář a příkaz zvlášť**, ne hotový řádek: co se pustí, je rozhodnutí (`Policy`),
/// kdežto jak se to poskládá do jedné řádky pro shell, je sazba — a testuje se každé jinak.
struct TerminalSession: Equatable, Sendable {
    /// Pracovní adresář té session — worktree v cache aplikace.
    ///
    /// Není to kosmetika: `claude --resume` hledá vlákno podle adresáře, ve kterém se spustí
    /// (`~/.claude/projects/<zakódovaná cesta>/`), takže tentýž příkaz jinde session **nenajde**.
    let directory: URL
    /// Co se v tom adresáři pustí. **Týž příkaz, jaký kopíruje `Zkopírovat resume`** — skládá ho
    /// `Policy.resumeCommand(sessionID:)`.
    let command: String

    /// Řádka pro shell. Od #460 ji dostává **zásuvka**, do #460 ji dostával `Terminal.app`.
    ///
    /// **`&&`, ne `;`**: pracovní strom umí zmizet (úklid cache, eviction), a `claude --resume`
    /// spuštěný místo něj v domovském adresáři by odpověděl, že takové vlákno neexistuje — tedy
    /// větou o session, ne o adresáři. S `&&` zůstane v terminálu `cd: no such file or directory`,
    /// což je pravda a dá se podle ní jednat.
    ///
    /// **`cd` je v zásuvce potřeba stejně jako v cizím okně**, i když shell startuje v adresáři,
    /// který mu dal store: zásuvka smí mít shell puštěný odjinud (`` ⌃` `` nad klonem, protože
    /// review ještě neběželo), a tam by `claude --resume` vlákno nenašel.
    var shellLine: String {
        "cd \(ShellQuoting.quoted(directory)) && \(command)"
    }
}

extension Policy {
    /// Příkaz, kterým se session obnoví.
    ///
    /// **Jedno místo, a je to podmínka toho, co #453 slibuje**: `⧉` ten text kopíruje a `▶` ho
    /// pouští, takže dvě kopie by se rozešly první úpravou — a rozdíl mezi „co mám ve schránce“
    /// a „co se mi otevřelo“ se nedá poznat jinak než tím, že jedno z toho nefunguje.
    static func resumeCommand(sessionID: String) -> String {
        "claude --resume \(sessionID)"
    }

    /// Kterou session dráha umí pustit v terminálu (#453). `nil` = tlačítko se **nekreslí**.
    ///
    /// **Zašedlé by tu bylo horší**: tvrdilo by „tady se to dělá, jen teď ne“, kdežto u dráhy,
    /// která teprve čeká na slot, by slibovalo něco, co přijde samo. Je to tatáž úvaha jako
    /// u `Ukázat session` (`rawSessionTarget(of:slug:)`) a u `Zkopírovat resume`.
    ///
    /// **Pracovní strom je podmínka stejně jako `session_id`**, i když zadání #453 mluví jen
    /// o `id`. Bez adresáře se totiž nedá poskládat příkaz, který by session doopravdy navázal
    /// (viz `TerminalSession.directory`) — vyjela by zásuvka, ve které `claude` oznámí, že
    /// takové vlákno nezná. „Nabízí se to jen tam, kde je co obnovit“ tedy platí doslova: bez
    /// stromu obnovit co není. Dráha bez uložené osy zná `session_id` a strom ne, takže tenhle
    /// rozdíl není teoretický (soubory z doby před #203).
    static func terminalSession(of lane: ReviewerLane) -> TerminalSession? {
        guard let sessionID = lane.sessionID, let worktree = lane.worktree else { return nil }
        return TerminalSession(directory: worktree, command: resumeCommand(sessionID: sessionID))
    }
}
