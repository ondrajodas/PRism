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
    /// Co se v tom adresáři pustí — `Policy.drawerResumeCommand(sessionID:)`.
    ///
    /// **Od #460 to není doslova to, co kopíruje `⧉`**: je v tom navíc režim povolení
    /// (`--permission-mode auto`), protože session, kterou v zásuvce řídí člověk, nemá přerušovat
    /// práci dotazem u každého kroku. Skládá to ale pořád **jedna funkce** nad `resumeCommand`,
    /// takže se ty dva texty nemají čím rozejít a liší se přesně o jednu vyjmenovanou věc.
    let command: String
    /// Skill té dráhy. Od #460 z něj je **relace v zásuvce** (`TerminalSlot.Role.session`) a její
    /// popisek v přepínači — dvě session dvou reviewerů se totiž musí dát rozeznat a otevřít vedle
    /// sebe. Do #460 tady nebyl, protože cizí okno terminálu se neoznačovalo ničím.
    let skill: String

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
    /// **Jedno místo, a je to podmínka toho, co #453 slibuje**: tenhle text kopíruje `⧉`
    /// a **staví na něm** i to, co pouští `▶` (`drawerResumeCommand`), takže dvě kopie by se
    /// rozešly první úpravou — a rozdíl mezi „co mám ve schránce“ a „co se mi otevřelo“ se nedá
    /// poznat jinak než tím, že jedno z toho nefunguje.
    ///
    /// **Do #460 to byl doslova týž příkaz.** Od #460 se liší o režim povolení, který dostane
    /// jedině zásuvka — zdůvodnění je u `drawerPermissionMode`.
    static func resumeCommand(sessionID: String) -> String {
        "claude --resume \(sessionID)"
    }

    /// Režim povolení, ve kterém běží session puštěná z `▶` (#460).
    ///
    /// **`auto`, ne `bypassPermissions` a ne `dontAsk`.** Z šesti režimů, které `claude
    /// --permission-mode` nabízí, je `auto` ten jediný s **vyjmenovanými a čitelnými pravidly**:
    /// `claude auto-mode defaults` vypíše `allow`, `soft_deny` i `hard_deny`, takže hranice
    /// existují a dá se do nich podívat. `bypassPermissions` je podle `--help` doslova „bypass all
    /// permission checks“ (to, co zapíná `--dangerously-skip-permissions`) a do tohohle repa
    /// nepatří; `manual` a `acceptEdits` dotazy neodstraní, `plan` mění, co session dělá.
    ///
    /// **Nová práva to nedává.** Zásuvka je plnohodnotný shell s kapslí `plná práva` — cokoli, co
    /// ta session udělá, si tam člověk může napsat sám. Odpadají **dotazy**, ne hranice.
    ///
    /// **Napevno, ne v nastavení**: konfigurace pro jedno tlačítko je předčasná a `config.json` je
    /// dlouhý. Až si někdo řekne o opak, je to jeden klíč navíc.
    static let drawerPermissionMode = "auto"

    /// Příkaz, který se pouští **v zásuvce** — `resumeCommand` a k němu režim povolení (#460).
    ///
    /// **Tady se `▶` a `⧉` rozcházejí, a je to vědomá změna proti #453.** Do #460 tu stálo, že je
    /// to týž příkaz, protože rozdíl mezi „co mám ve schránce“ a „co se mi otevřelo“ se pozná
    /// jedině tím, že jedno z toho nefunguje. Zůstává z toho to podstatné: **skládá se to z jedné
    /// funkce**, takže se text nemá čím rozejít, a liší se přesně o jednu vyjmenovanou věc.
    /// `⧉` ji nedostane schválně — kdo si příkaz kopíruje jinam, dostane ho tak, jak by ho psal.
    static func drawerResumeCommand(sessionID: String) -> String {
        "\(resumeCommand(sessionID: sessionID)) --permission-mode \(drawerPermissionMode)"
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
        return TerminalSession(
            directory: worktree,
            command: drawerResumeCommand(sessionID: sessionID),
            skill: lane.skill
        )
    }
}
