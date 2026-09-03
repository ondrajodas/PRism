import Foundation

/// Že běh review jde **jen nad přírůstkem** (#517), a s čím.
///
/// **Vlastní typ, ne dvojice `(IncrementalDiffRange, URL?)`**: soubor bez rozsahu a rozsah bez
/// souboru znamenají dvě různé věci (druhé je „minule bylo čisto“) a z dvojice by to nikdo
/// nepoznal. `nil` na místě celého typu je proti tomu „celý diff“, tedy chování do #517.
struct IncrementalReviewRequest: Sendable, Equatable {
    /// `seen` je hlava předchozího review, `head` ta dnešní.
    let range: IncrementalDiffRange
    /// Soubor s nálezy z minula (#120), nebo `nil`, když minule nic nahlášené nebylo.
    ///
    /// Cestu k němu dostane reviewer v promptu a přečte si ho `Read`em — obsah do promptu
    /// **nejde**, aby se prompt nerozkolísal cizím textem (tatáž úvaha jako u zadání PR).
    let previousFindings: URL?
}

/// Zadání jednoho běhu.
struct ReviewRequest: Sendable, Equatable {
    let key: ReviewRunKey
    /// Pracovní strom, ve kterém session poběží. Připravuje ho `RepoCheckout`, ne runner —
    /// ten do cache nesahá.
    let worktree: URL
    /// Commit, proti kterému se diffuje. Do klíče nepatří: identitu běhu určuje `headSha`,
    /// base se může změnit rebasem cílové větve, aniž by šlo o jiné review.
    let baseSha: String
    /// Psaná půlka zadání z nastavení (#281). Prázdná = výchozí text.
    ///
    /// Putuje **s požadavkem**, přesně jako `baseSha`, a ze stejného důvodu: runner si ji
    /// nemá kde přečíst sám, takže běh doběhne s tou šablonou, se kterou začal — a nezmění
    /// se mu pod rukama, když se během běhu uloží nastavení.
    ///
    /// Jádro kontraktu v ní **není** a nedá se z ní vyhodit; připojuje ho `Policy.reviewPrompt`.
    /// Povolení nástrojů se šablonou nemění vůbec (tvrdá podmínka č. 2) — skládají se
    /// v `ClaudeCommand` z konstant.
    ///
    /// U kontroly nálezů (#150) se **nepoužívá**: `RecheckCommand` má vlastní, natvrdo psaný
    /// prompt, protože jeho odpověď čte parser.
    let promptTemplate: String
    /// Za jak dlouho se session zabije (#320). Putuje **s požadavkem**, ze stejného důvodu jako
    /// šablona: runner si ji nemá kde přečíst sám, takže běh doběhne s tím limitem, se kterým
    /// začal, i kdyby se během něj uložilo nastavení.
    ///
    /// Je už **sražená do mezí** — skládá ji `Configuration.resolved(for:)` přes
    /// `Policy.reviewTimeout(minutes:)`, takže tady se nic nekontroluje.
    ///
    /// **Kontrola nálezů (#150) má tentýž limit.** Je to tatáž session, tentýž strom a tytéž
    /// peníze; druhé číslo by znamenalo druhé místo, kde se u pomalého repa zvedá limit.
    let timeout: Duration
    /// Nálezy z minula, které má běh posoudit (#150). `nil` = běžné review.
    ///
    /// Je to **materiál v promptu**, ne nový nástroj: sada povolení zůstává tatáž (tvrdá
    /// podmínka č. 2).
    let recheck: RecheckMaterial?
    /// Soubor se zadáním PR (#120), nebo `nil`, když se žádné nesehnalo nebo se nepodařilo uložit.
    ///
    /// Putuje **s požadavkem** jako šablona a limit, a ze stejného důvodu: runner si ho nemá kde
    /// zjistit a všechny session jednoho běhu mají dostat tentýž. Do promptu z něj jde **jen
    /// cesta** — obsah čte reviewer sám `Read`em, takže se prompt nemá čím rozkolísat.
    ///
    /// **Sada nástrojů se tím nemění** (tvrdá podmínka č. 2): `Read` v ní je odjakživa a soubor
    /// leží v cache aplikace, kam session vidí, protože v ní stojí i pracovní strom.
    let intentFile: URL?
    /// Že běh má projít **jen přírůstek** (#517), a s jakým materiálem. `nil` = celý diff PR.
    ///
    /// Putuje **s požadavkem** jako šablona, limit a zadání, a ze stejného důvodu: runner si
    /// rozsah nemá kde zjistit a rozhodnutí, nad čím se běží, se nesmí změnit pod rukama běhu,
    /// který už jede.
    ///
    /// **Sada nástrojů se tím nemění** (tvrdá podmínka č. 2): je to rozsah v promptu a nálezy
    /// z minula v souboru, který session přečte `Read`em — tedy tatáž cesta jako u zadání (#120).
    let increment: IncrementalReviewRequest?

    /// - Parameter promptTemplate: prázdná znamená **výchozí šablonu**, ne prompt bez zadání
    ///   (#281). Výchozí hodnota parametru je tu kvůli testům; produkční cesta jde přes
    ///   `AppStore`, který sem dává hodnotu z konfigurace.
    /// - Parameter timeout: výchozí hodnota je tu ze stejného důvodu — produkční cesta bere
    ///   limit z konfigurace repa.
    /// - Parameter intentFile: soubor se zadáním (#120). Výchozí `nil` je tu **jen kvůli testům,
    ///   které o zadání nestojí** — produkční cesta jde přes `AppStore`, který ho připraví.
    ///   Prompt se z něj skládá `Policy.reviewPrompt`, a tam default schválně není.
    init(
        key: ReviewRunKey,
        worktree: URL,
        baseSha: String,
        promptTemplate: String = "",
        timeout: Duration = ReviewTimeout.standard,
        intentFile: URL? = nil,
        increment: IncrementalReviewRequest? = nil
    ) {
        self.key = key
        self.worktree = worktree
        self.baseSha = baseSha
        self.promptTemplate = promptTemplate
        self.timeout = timeout
        self.intentFile = intentFile
        self.increment = increment
        recheck = nil
    }

    private init(
        key: ReviewRunKey,
        worktree: URL,
        baseSha: String,
        timeout: Duration,
        recheck: RecheckMaterial
    ) {
        self.key = key
        self.worktree = worktree
        self.baseSha = baseSha
        promptTemplate = ""
        self.timeout = timeout
        // Kontrola nálezů zadání **nedostává** (#150): má vlastní, natvrdo psaný prompt, jehož
        // odpověď čte parser — cesta k souboru by v něm nebyla k čemu.
        intentFile = nil
        // Kontrola nálezů **přírůstkem není** (#517), i když se ptá na tytéž verdikty: rozsah si
        // skládá sama (`RecheckCommand.prompt`) a nálezy do ní jdou promptem, ne souborem.
        increment = nil
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
        material: RecheckMaterial,
        timeout: Duration = ReviewTimeout.standard
    ) -> ReviewRequest {
        ReviewRequest(
            key: .recheck(of: pullRequest, at: headSha),
            worktree: worktree,
            baseSha: baseSha,
            timeout: timeout,
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
