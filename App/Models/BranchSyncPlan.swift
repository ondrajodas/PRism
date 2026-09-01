import Foundation

/// Co se stane při `Rebase` (#466) — **snímek z dat pull requestu**, ne z toho, co leží
/// v cache.
///
/// Celý plán se skládá z odpovědi GitHubu (`Policy.branchSyncPlan`), a je to první polovina
/// prvního guardu z tvrdé podmínky č. 1: cílem přetlačení smí být **hlava pull requestu, jehož
/// autorem jsem já**, ne větev, která se náhodou tak jmenuje. Jméno větve si nastaví kdokoli,
/// kdežto `headRefName` a `headRefOid` patří k pull requestu a k jeho autorovi.
struct BranchSyncPlan: Hashable, Sendable {
    let pullRequest: PRIdentifier
    /// Jméno větve **z dat pull requestu** (`headRefName`). Zároveň to, co se přetlačuje.
    let branch: String
    /// Cílová větev, nad kterou se commity přehrají.
    let base: String
    /// Hlava, kterou má remote nést, **než se sáhne na `push`**.
    ///
    /// Jde do `--force-with-lease=<větev>:<sha>` — tedy do podmínky, kterou vyhodnocuje server.
    /// Když se remote mezitím pohnul, push **selže** a nic se nepřepíše (změřeno, viz
    /// `GitBranchPush`).
    let expectedRemoteSha: String
    /// Kolik commitů větev nese nad základem — tedy kolik se jich přehraje. Z `compare` (#466),
    /// takže je to počet proti **aktuálnímu** základu, ne počet commitů pull requestu.
    let replaying: Int
    /// O kolik commitů je větev za základem. `0` znamená, že není co srovnávat.
    let behind: Int
}

/// Co se má přetlačit do remote (#466) — payload **jediné cesty ven přes `git`**.
///
/// **Vlastní typ vedle `BranchSyncPlan`**, ne tentýž: plán je snímek toho, co se chystá, kdežto
/// tohle vzniká až po rebasu a nese to, co z něj vypadlo — hlavu, která se má na remote dostat,
/// a strom, ze kterého se pushuje. Kdyby to bylo jedno pole v plánu, dal by se plán složit
/// i **bez** rebasu, a tím i pushnout něco, co nikdo nepřehrál.
struct BranchPushPlan: Hashable, Sendable {
    let pullRequest: PRIdentifier
    /// Větev na remote, do které se píše. Z dat pull requestu, viz `BranchSyncPlan.branch`.
    let branch: String
    /// Co má na remote ležet — lease. Z dat pull requestu.
    let expectedRemoteSha: String
    /// Co se tam má dostat — hlava po rebasu.
    let sha: String
    /// Odkud se pushuje. **Musí ležet v cache aplikace** (tvrdá podmínka č. 3); ověřuje to
    /// `GitBranchPush` toutéž kontrolou, kterou má úklid a úložiště (`CacheLayout.contains`).
    let worktree: URL
}

/// Jak dopadlo přehrání commitů nad základem (#466).
///
/// **Konflikt je stav, ne chyba**, a proto je v návratové hodnotě, ne v `throw`: z konfliktu
/// plyne jiný další krok (zahodit rebase, otevřít terminál) než z toho, že se nedá spustit `git`.
enum RebaseOutcome: Equatable, Sendable {
    case rebased(RebasedBranch)
    /// Commity se přehrát nedaly. `aborted` říká, jestli se povedlo strom vrátit tam, kde byl —
    /// když ne, **leží v cache rozdělaný rebase** a musí to být vidět v okně.
    ///
    /// **`worktree` je v tom stavu od #467**, a je to o něco víc než pohodlí: v nezahozeném rebase
    /// pracuje session, takže musí být odkud vzít cestu — a odvodit si ji z `CacheLayout` na straně
    /// volajícího by znamenalo druhé místo, které ví, kde ten strom leží. `nil` u zahozeného
    /// konfliktu není, protože strom existuje i po `--abort`; `nil` je jedině tam, kde se cesta
    /// nedozvěděla (starý fake v testu).
    case conflicted(files: [String], aborted: Bool, worktree: URL? = nil)
}

/// Co vzniklo ze slití konfliktů, když se výsledek zapisoval do indexu (#467).
struct ConflictStaging: Equatable, Sendable {
    /// `git diff HEAD -- <kolidující soubory>` **před** zápisem do indexu. Prázdný znamená
    /// „session soubory nezměnila“ — což je legitimní výsledek (vzala jednu stranu tak, jak byla),
    /// ale okno o něm nesmí mlčet.
    var diff: String
    /// Soubory, ve kterých zůstaly konfliktní značky. **Do indexu se nezapsaly.**
    var unresolved: [String]

    init(diff: String = "", unresolved: [String] = []) {
        self.diff = diff
        self.unresolved = unresolved
    }
}

/// Výsledek přehrání commitů (#466).
struct RebasedBranch: Hashable, Sendable {
    /// Pracovní strom v cache, ve kterém výsledek leží. Odsud se pushuje.
    let worktree: URL
    /// Hlava po rebasu.
    let headSha: String
    /// **Ze které hlavy se přehrávalo** — hlava pull requestu ve chvíli rebase.
    ///
    /// Vzniklo to rozdělením akce na dva kroky (rebase a přetlačení zvlášť) a **je to pojistka, ne
    /// údaj**. Mezi rebasem a potvrzením přetlačení může být libovolně dlouhá pauza — okno se dá
    /// zavřít a přijít znovu —, takže se hlava PR mezitím může pohnout (push z jiného stroje,
    /// z terminálu, z GitHubu). Kdyby se lease skládal z **aktuální** hlavy, prošel by a přepsal
    /// by ten nový commit; s touhle hodnotou narazí pre-flight na `headMoved` a nepřetlačí nic.
    /// Rebase se pak musí spustit znovu.
    let rebasedFrom: String
    /// Commity, které **na větvi přibudou** — v pořadí od nejstaršího, tedy jak na ní budou ležet.
    ///
    /// **Je to `rebasedFrom..HEAD`, ne `base..HEAD`, a je to změřené.** Na
    /// `prism-review-sandbox#10` se přehrál **jeden** vlastní commit, ale refu na remote chyběly
    /// **dva**: ten přehraný a k tomu commit z base, kvůli kterému byla větev pozadu — rebase ho
    /// dostal do historie větve. Do #466 se tady vypisovalo `base..HEAD`, takže sheet pod nadpisem
    /// `Co odejde` tvrdil jeden commit tam, kde push zanese dva.
    ///
    /// **Nadpis proto mluví o větvi, ne o nahrávání.** Objekty commitu z base na remote **už jsou**
    /// (leží v base), force push přepisuje jedině **ref větve** — takže „odejde“ by u něj bylo
    /// nepřesné, kdežto „na větvi přibude“ platí.
    ///
    /// **Když se log přečíst nepodaří, `RebasedBranch` nevznikne vůbec** — `commits(in:above:)`
    /// hodí chybu a `syncWorktreeState` odpoví `.empty`. Je to schválně: nabídnout force push
    /// a u toho vypsat prázdný seznam by vypadalo jako „nic neodejde“, což je ten nejhorší možný
    /// omyl u nevratné akce.
    let arriving: [RebasedCommit]

    /// Kolik z nich je **tvých přehraných** (`base..HEAD`).
    ///
    /// **Vlastní číslo, ne délka seznamu**, a je to změna proti #466: jsou to doopravdy **dvě různé
    /// veličiny** (změřeno 1 proti 2), takže je nemá slévat jedno číslo — má je rozlišit jméno.
    /// Panel mluví dál o přehraných commitech, potvrzení vypisuje obojí pojmenované.
    let replayed: Int

    /// Co s konflikty udělala session (#467). `nil` = **žádné nebyly, nebo se to nedá vědět**.
    ///
    /// Dvě různé cesty k `nil` a obě jsou v pořádku: bezkonfliktní rebase konflikty nemá, a rebase
    /// **najdený v cache po restartu aplikace** o nich vědět nemůže — účet session se z pracovního
    /// stromu nezrekonstruuje a vymyslet se nesmí (viz `ConflictResolution`). Pushuje se v obou
    /// případech to samé, protože hlava i `rebasedFrom` v cache jsou.
    var resolution: ConflictResolution?

    init(
        worktree: URL,
        headSha: String,
        rebasedFrom: String,
        arriving: [RebasedCommit],
        replayed: Int,
        resolution: ConflictResolution? = nil
    ) {
        self.worktree = worktree
        self.headSha = headSha
        self.rebasedFrom = rebasedFrom
        self.arriving = arriving
        self.replayed = replayed
        self.resolution = resolution
    }

    /// Kolik commitů z base se pod ně dostalo — dopočítané, aby nešlo tvrdit dvě různá čísla.
    var fromBase: Int { max(0, arriving.count - replayed) }

    /// Tentýž výsledek s připsaným účtem session. **Vzniká ve store, ne v `RepoCheckoutu`**:
    /// checkout o session nic neví a vědět nemá (je to lokální modul nad `gitem`).
    func reporting(_ resolution: ConflictResolution?) -> RebasedBranch {
        var copy = self
        copy.resolution = resolution
        return copy
    }
}

/// Jeden přehraný commit — to, co se vypisuje v potvrzení force pushe (#466, z proklikání).
struct RebasedCommit: Hashable, Sendable {
    /// Sha **po** rebasu. Krátká podoba je v potvrzení vidět schválně: dá se porovnat s tím, co je
    /// po pushi na GitHubu, kdežto samotný titulek se u přerovnané větve nezmění a nic nedokazuje.
    let sha: String
    /// První řádek zprávy. Sražený `String.singleLine`, protože je to **cizí text** — víceřádková
    /// zpráva se do řádku výpisu vysypat nesmí.
    let title: String

    var shortSha: String { String(sha.prefix(7)) }
}

/// Řádek výpisu v potvrzení force pushe — commit a **odkud se na větvi vzal**.
///
/// **Vlastní typ, ne tuple v `ForEach`i** (#361): identita se má brát z uloženého pole, ne přes
/// `Array(…enumerated())`, kde se čte skrz tuple. `id` je `sha`, protože ta je v jednom rozsahu
/// jednoznačná.
struct PushedCommitRow: Hashable, Sendable, Identifiable {
    let commit: RebasedCommit
    /// Přišel rebasem z base (dole v historii), nebo je to tvůj přehraný (nad nimi)?
    let isFromBase: Bool

    var id: String { commit.sha }
}

/// Co leží ve stromě pro srovnání větve (#466).
///
/// **Tři stavy, ne boolean „běží rebase“.** Rozdělením akce na dva kroky vznikl mezistav
/// *přerovnáno, nepřetlačeno* — a ten je stejně důležitý jako rozdělaný rebase: v obou případech
/// leží v kopii repa práce, o které má rozhodnout člověk, a v obou by o ní okno po restartu
/// aplikace mlčelo, kdyby se nehledala. Tichý stav v cache je horší než chyba.
enum SyncWorktreeState: Equatable, Sendable {
    /// Strom není, nebo v něm stojí přesně hlava pull requestu — tedy nic rozdělaného.
    case empty
    /// Leží tam rozdělaný rebase (`rebase-merge` / `rebase-apply`).
    case unfinishedRebase
    /// Rebase doběhl a výsledek **neodešel**.
    case rebased(RebasedBranch)
}
