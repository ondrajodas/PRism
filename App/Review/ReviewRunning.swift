import Foundation

/// Zadání jednoho běhu.
struct ReviewRequest: Sendable, Equatable {
    let key: ReviewRunKey
    /// Pracovní strom, ve kterém session poběží. Připravuje ho `RepoCheckout`, ne runner —
    /// ten do cache nesahá.
    let worktree: URL
    /// Commit, proti kterému se diffuje. Do klíče nepatří: identitu běhu určuje `headSha`,
    /// base se může změnit rebasem cílové větve, aniž by šlo o jiné review.
    let baseSha: String

    init(key: ReviewRunKey, worktree: URL, baseSha: String) {
        self.key = key
        self.worktree = worktree
        self.baseSha = baseSha
    }
}

/// Spuštění jedné headless session na jeden skill.
///
/// Za protokolem, aby šlo v testech nahradit fakem — a aby bylo z typu vidět, že runner
/// umí jen spustit a sebrat výsledek. Nic neposílá a nic nezapisuje.
///
/// **Selhání session není chyba volání.** Spadlá i vytimeoutovaná session se vrací jako
/// `ReviewRun` s příslušným `outcome`, protože obojí je výsledek, který se zobrazuje.
/// Vyhodí se jen `CancellationError`, když běh zrušil ten, kdo si o něj řekl.
protocol ReviewRunning: Sendable {
    func run(
        _ request: ReviewRequest,
        progress: @escaping ReviewProgressHandler
    ) async throws -> ReviewRun

    /// Konfigurace se načetla znovu — limit souběhu se mohl změnit.
    ///
    /// Výchozí implementace nedělá nic: limit hlídá jen skutečný runner a fakes v testech
    /// by tuhle metodu jinak musely dopisovat všechny.
    func configurationChanged() async
}

extension ReviewRunning {
    func configurationChanged() async {}

    func run(_ request: ReviewRequest) async throws -> ReviewRun {
        try await run(request, progress: { _ in })
    }
}
