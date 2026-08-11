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
    /// Nálezy z minula, které má běh posoudit (#150). `nil` = běžné review.
    ///
    /// Je to **materiál v promptu**, ne nový nástroj: sada povolení zůstává tatáž (tvrdá
    /// podmínka č. 2).
    let recheck: RecheckMaterial?

    init(key: ReviewRunKey, worktree: URL, baseSha: String) {
        self.key = key
        self.worktree = worktree
        self.baseSha = baseSha
        recheck = nil
    }

    private init(key: ReviewRunKey, worktree: URL, baseSha: String, recheck: RecheckMaterial) {
        self.key = key
        self.worktree = worktree
        self.baseSha = baseSha
        self.recheck = recheck
    }

    /// Zadání kontroly nálezů (#150).
    ///
    /// Klíč skládá **tenhle factory**, aby nemohl vzniknout požadavek s materiálem a klíčem
    /// běžného review: prompt se rozhoduje podle materiálu a ukládání podle druhu v klíči, takže
    /// dvě různá tvrzení o témže běhu by znamenala kontrolu uloženou jako nález.
    ///
    /// - Parameter headSha: hlava PR, nad kterou se kontroluje — ne commit, na kterém nálezy
    ///   vznikly. Ten nese `material`.
    static func recheck(
        of pullRequest: PRIdentifier,
        at headSha: String,
        worktree: URL,
        baseSha: String,
        material: RecheckMaterial
    ) -> ReviewRequest {
        ReviewRequest(
            key: .recheck(of: pullRequest, at: headSha),
            worktree: worktree,
            baseSha: baseSha,
            recheck: material
        )
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
