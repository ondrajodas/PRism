import Foundation

/// Co se právě děje se srovnáním větve (#466). Chybějící záznam = nic se neděje.
///
/// **Stav okna, ne cesta ven** — drží ho `AppStore` (`branchSyncStates`), stejně jako
/// `MetadataActionState` a ze stejného důvodu: akce se ovládá z panelu a musí přežít překliknutí
/// tabu. Publisher ani pusher se ve store nedrží (tvrdá podmínka č. 1).
///
/// **Rozdělaný rebase je vlastní případ, ne `failed`.** Selhání říká „nepovedlo se, nic tu
/// nezůstalo“; tohle říká „v kopii repa leží rozdělaná práce a jde zahodit“ — a to je jiný další
/// krok. Tichý rozdělaný stav v cache je horší než chyba, protože příští akce nad tím PR se nad
/// ním zachová divně.
enum BranchSyncState: Equatable, Sendable {
    /// Dotahuje se základ a přehrávají commity.
    case rebasing
    /// **Session slévá konflikty** (#467) — `round` je kolikáté kolo, `files` na čem uvázl rebase.
    ///
    /// Vlastní stav, ne `rebasing`: platí se za něj penězi a běží minuty, takže musí být poznat,
    /// **co** se zdrží a **kolikáté** kolo to je. Co session dělá právě teď, drží `AppStore` vedle
    /// (`branchSyncActivity`) — mění se při každém tool cally a přepisovat kvůli tomu celý stav by
    /// znamenalo špinit i to, co se nemění.
    case resolving(round: Int, files: [String])
    /// **Přerovnáno, nepřetlačeno** — commity leží srovnané v kopii repa a do remote se nesáhlo.
    ///
    /// Vlastní stav, protože je to **normální mezistav, ne porucha**: první krok akce doběhl a na
    /// druhý (nevratný) se čeká na potvrzení. Musí být z panelu poznat, že v cache něco leží, a musí
    /// to jít zahodit jedním tlačítkem — tatáž úvaha jako u rozdělaného rebase, jen tady nic
    /// neselhalo.
    case rebased(RebasedBranch)
    /// Přetlačuje se — **jediný okamžik, kdy aplikace zapisuje do remote**.
    case pushing
    /// Zahazuje se rozdělaný nebo nepřetlačený rebase.
    case discarding
    /// Hotovo: přehrálo se `replayed` commitů a větev je přetlačená.
    case pushed(replayed: Int)
    /// Rebase doběhl, ale hlava se nezměnila — nebylo co přetlačit. **Vlastní případ, ne
    /// `pushed(0)`**: „nic se neposlalo“ a „poslalo se nula commitů“ jsou dvě různé věty a jenom
    /// jedna z nich je pravda.
    case alreadyInSync
    /// Konflikt, rebase **zahozený** — v cache po něm nic nezůstalo.
    case conflicted(files: [String])
    /// Konflikt a v cache **leží rozdělaný rebase**. Jde zahodit tlačítkem.
    ///
    /// Prázdný seznam souborů znamená „našel se při otevření PR“ — tedy nevíme, na čem to
    /// tehdy uvázlo. Mlčet o něm je horší: příští rebase v tom stromě by skončil hláškou, které
    /// by nikdo nerozuměl.
    case unfinished(files: [String])
    /// **Session konflikty nerozřešila** (#467) a rebase **zůstal rozdělaný**.
    ///
    /// Vlastní případ vedle `unfinished`, ne příznak u něj: „na tohle nestačím“ je jiná věta než
    /// „v kopii repa něco leží“ — u prvního se za pokus **zaplatilo** a je z něj co říct
    /// (`detail`), u druhého se jen našel strom v cache. Slít je do jednoho stavu by znamenalo, že
    /// zaplacený pokus vypadá stejně jako nález při otevření PR.
    ///
    /// `detail` je věta od session (čím si není jistá, nebo proč to nešlo), případně důvod, proč se
    /// její výsledek nepřijal. `nil` = neřekla nic.
    case unresolved(files: [String], detail: String?)
    case failed(BranchSyncError)

    var isBusy: Bool {
        switch self {
        case .rebasing, .resolving, .pushing, .discarding: true
        case .rebased, .pushed, .alreadyInSync, .conflicted, .unfinished, .unresolved, .failed:
            false
        }
    }

    /// Běží nad tím `claude` session? Na tom stojí tlačítko `Zrušit` u hlášky (#467).
    ///
    /// **Vlastní otázka, ne `isBusy`.** Zrušit se dá jedině to, co má co zabít: rebase i zahazování
    /// jsou volání `gitu` v řádu sekund, kdežto slévání je session, která běží minuty a stojí
    /// peníze — a „rozmyslel jsem si to“ u ní nesmí znamenat čekat na konec (tatáž úvaha jako
    /// u `cancelAsk`, #452).
    var isResolving: Bool {
        if case .resolving = self { true } else { false }
    }

    /// Leží v cache rozdělaný rebase? Na tom stojí tlačítko `Zahodit rebase`.
    ///
    /// **Obojí, `unfinished` i `unresolved`** (#467): jsou to dvě různé věty o jednom a tomtéž
    /// stavu kopie repa, takže se z nich musí dát zahodit stejně. Kdyby to platilo jen o prvním,
    /// zůstal by po nerozřešené session rozdělaný rebase, který panel nenabídne uklidit — tedy
    /// zrovna ten tichý stav v cache, kterému se celá tahle akce vyhýbá.
    var hasUnfinishedRebase: Bool {
        switch self {
        case .unfinished, .unresolved: true
        default: false
        }
    }

    /// Má se u hlášky nabídnout terminál? (#467, návrh sekce 36)
    ///
    /// Jedině tam, kde v kopii repa leží **rozdělaný rebase** — tam je kontext připravený a člověk
    /// v něm má plnou moc (#459). U zahozeného konfliktu (`conflicted`) v cache nic není, takže by
    /// terminál otevřel strom na hlavě PR a nebylo by v něm co dokončovat.
    var offersTerminal: Bool { hasUnfinishedRebase }

    /// Přerovnaná větev, která čeká na přetlačení. `nil` = nečeká nic.
    ///
    /// Na tomhle stojí tlačítko `Force push…` v panelu **i** to, že se druhý rebase nenabídne:
    /// přehrát commity znovu nad výsledkem, který ještě neodešel, by tu práci zahodilo potichu.
    var rebasedBranch: RebasedBranch? {
        if case .rebased(let branch) = self { branch } else { nil }
    }

    /// Leží v cache něco, co má smysl zahodit? Rozdělaný rebase **i** nepřetlačený výsledek.
    var hasDiscardableWork: Bool { hasUnfinishedRebase || rebasedBranch != nil }

    /// Věta do panelu. **U každého stavu jiná** — a u selhání jiná podle toho, co selhalo:
    /// odmítnutý lease se od ostatních chyb pozná (`BranchSyncError.leaseRejected`), protože
    /// z něj plyne jiný další krok.
    var sentence: String {
        switch self {
        case .rebasing: "Přehrávám commity nad základem."
        case .resolving(let round, let files):
            Policy.conflictActivity(round: round, files: files)
        case .rebased(let branch):
            "Rebase hotový v kopii repa — \(Plural.czech(branch.replayed, one: "commit přehraný", few: "commity přehrané", many: "commitů přehraných")). "
                + "Do remote se zatím nesáhlo."
        case .pushing: "Pushuju větev."
        case .discarding: "Zahazuju rozdělanou práci."
        case .pushed(let replayed):
            "Hotovo — force push poslal \(Plural.czech(replayed, one: "commit", few: "commity", many: "commitů"))."
        case .alreadyInSync: "Větev už nad základem byla, do remote se nesáhlo."
        case .conflicted(let files):
            "Rebase narazil na konflikt (\(Self.list(files))) a je zahozený — v kopii repa po něm nic nezůstalo. "
                + "Vyřeš ho v terminálu."
        case .unfinished(let files):
            files.isEmpty
                ? "V kopii repa leží rozdělaný rebase. Zahoď ho, nebo ho dokonči v terminálu."
                : "Rebase narazil na konflikt (\(Self.list(files))) a zůstal rozdělaný v kopii repa. "
                    + "Zahoď ho, nebo ho dokonči v terminálu."
        case .unresolved(let files, let detail):
            // **Podmět dřív než seznam souborů.** Se seznamem vpředu se věta při třech jménech
            // rozpadla („Konflikt v a, b, c session nerozřešila…“, vidět v renderu sondy) — je
            // to cizí text neznámé délky, takže nesmí stát mezi podmětem a přísudkem.
            "Session konflikt nerozřešila (\(Self.list(files)))\(detail.map { " — \($0)" } ?? ""). "
                + "Rebase zůstal rozdělaný v kopii repa: zahoď ho, nebo ho dokonči v terminálu."
        case .failed(let error): error.sentence
        }
    }

    /// Kolidující soubory do věty. **Nejvýš tři jména** — panel má 300 bodů a seznam dvaceti
    /// jmen z něj udělá odstavec, ve kterém se ta věta ztratí (tatáž mez jako
    /// u `Policy.failingChecksSentence`).
    private static func list(_ files: [String]) -> String {
        guard !files.isEmpty else { return "soubory nezjištěny" }
        let shown = files.prefix(3).joined(separator: ", ")
        let rest = files.count - min(files.count, 3)
        guard rest > 0 else { return shown }
        return "\(shown) a \(Plural.czech(rest, one: "další", few: "další", many: "dalších"))"
    }
}

/// Proč se srovnání větve nepovedlo (#466).
///
/// **Odmítnutý lease je vlastní případ, ne `failed(text z gitu)`.** Znamená, že se remote mezitím
/// pohnul, **nic se nepřepsalo** a dá se to zkusit znovu — kdežto ostatní chyby znamenají, že se
/// nedá pokračovat, dokud se něco nezmění. Dva různé stavy, dvě různé věty (zadání #466).
enum BranchSyncError: Error, Equatable, Sendable {
    /// Brána je vypnutá, nebo chybí nástroj. Věta je ta, na které skončí publisher.
    case notAllowed(String)
    /// Pull request není můj. **První guard z tvrdé podmínky č. 1**, ověřený proti datům PR.
    case notMine(author: String)
    /// Hlava pull requestu je v jiném repozitáři (fork). Přetlačovat by se muselo tam, a to
    /// odsud nejde.
    case foreignBranch
    /// Data pull requestu neříkají, kde jeho hlava leží — bez toho se nepushuje.
    case unknownBranchOrigin
    /// Hlava PR se mezi složením plánu a pushem posunula.
    case headMoved(expected: String, actual: String)
    /// Větev pull requestu se mezitím jmenuje jinak — plán mluví o jiné větvi, než která na PR je.
    case branchChanged(expected: String, actual: String)
    case pullRequestNotOpen(PullRequestState)
    /// Pracovní strom leží mimo cache aplikace (tvrdá podmínka č. 3).
    case outsideCache(String)
    /// Remote se pohnul, `--force-with-lease` push odmítl a **nic nepřepsal**.
    case leaseRejected
    case toolUnavailable(String)
    case timedOut
    case interrupted
    /// Cokoli dalšího — text od `gitu`.
    case failed(String)

    var sentence: String {
        switch self {
        case .notAllowed(let reason): reason
        case .notMine(let author):
            "Pull request je od @\(author) — force push jde jedině na vlastní větev."
        case .foreignBranch:
            "Hlava pull requestu je v jiném repozitáři (fork). Rebase odsud nejde."
        case .unknownBranchOrigin:
            "Z dat pull requestu neplyne, kde jeho větev leží. Obnov okno a zkus to znovu."
        case .headMoved(let expected, let actual):
            "Hlava pull requestu se mezitím posunula (\(Self.short(expected)) → \(Self.short(actual))). "
                + "Do remote se nesáhlo. Obnov okno a zkus to znovu."
        case .branchChanged(let expected, let actual):
            "Větev pull requestu se mezitím přejmenovala (\(expected) → \(actual)). "
                + "Do remote se nesáhlo. Obnov okno a zkus to znovu."
        case .pullRequestNotOpen(let state):
            "Pull request není otevřený — je \(state.czechLabel)."
        case .outsideCache(let path):
            "Pracovní strom \(path) leží mimo cache aplikace — odsud se nepushuje."
        case .leaseRejected:
            "Větev se na GitHubu mezitím pohnula, takže se nic nepřepsalo. "
                + "Načti pull request znovu a zkus to znovu."
        case .toolUnavailable(let detail): "Nepodařilo se spustit git: \(detail)"
        case .timedOut: "git neodpověděl včas. Do remote se nemuselo dostat nic."
        case .interrupted: "Přerušeno."
        case .failed(let detail): "Nepovedlo se: \(detail)"
        }
    }

    /// Dá se to zkusit znovu **s týmž plánem**?
    ///
    /// **Jméno nese „s týmž plánem“ schválně**, protože právě to se u téhle otázky dvakrát
    /// přehlédlo (viz níž). Retry v potvrzovacím sheetu neskládá plán znovu — pošle **tentýž**
    /// `BranchPushPlan`, tedy tentýž `expectedRemoteSha` a totéž jméno větve.
    ///
    /// **Ano** jedině tam, kde se pokus **nedokončil**: `timedOut`, `interrupted` a `failed`.
    /// Plán je pořád platný, takže druhý pokus má proti čemu uspět. `failed` je neznámá chyba —
    /// tam je opakování ta mírnější volba a `--force-with-lease` pořád chrání.
    ///
    /// **Ne** u **neshody stavu**: `leaseRejected`, `headMoved` a `branchChanged`. Tady je plán
    /// **zastaralý z definice** — pre-flight bude srovnávat tentýž očekávaný SHA (resp. jméno
    /// větve) proti téže posunuté skutečnosti, takže druhý pokus dopadne **identicky**. Věty
    /// u všech tří proto posílají obnovit data (`Obnov okno`, `Načti pull request znovu`)
    /// a tlačítko musí být zhasnuté: živé tlačítko vedle věty „obnov a zkus to znovu“ zve
    /// k opakování, které nemůže vyjít.
    ///
    /// **Ne** ani u strukturálních překážek: dokud je PR cizí, zavřený nebo ve forku, dokud je
    /// brána vypnutá, cesta mimo cache nebo `git` nedostupný, nezmění se opakováním nic.
    ///
    /// **Historie téhle vlastnosti je poučnější než ona sama.** Napsaná byla se šesti `true`,
    /// komentář u ní tvrdil jediné (`leaseRejected`). Revize to označila za rozpor a komentář se
    /// srovnal **s kódem** — jenže špatně byl kód, ne komentář. Až druhá revize ukázala, že retry
    /// s týmž plánem nemá u neshody stavu jak uspět. Poučení: **když se komentář rozejde s kódem,
    /// není předem jasné, která strana je ta chybná.**
    var canRetrySamePlan: Bool {
        switch self {
        case .timedOut, .interrupted, .failed: true
        case .leaseRejected, .headMoved, .branchChanged, .notAllowed, .notMine, .foreignBranch,
            .unknownBranchOrigin, .pullRequestNotOpen, .outsideCache, .toolUnavailable:
            false
        }
    }

    private static func short(_ sha: String) -> String { String(sha.prefix(7)) }
}
