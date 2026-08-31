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
    case failed(BranchSyncError)

    var isBusy: Bool {
        switch self {
        case .rebasing, .pushing, .discarding: true
        case .rebased, .pushed, .alreadyInSync, .conflicted, .unfinished, .failed: false
        }
    }

    /// Leží v cache rozdělaný rebase? Na tom stojí tlačítko `Zahodit rebase`.
    var hasUnfinishedRebase: Bool {
        if case .unfinished = self { true } else { false }
    }

    /// Přerovnaná větev, která čeká na přetlačení. `nil` = nečeká nic.
    ///
    /// Na tomhle stojí tlačítko `Přetlačit…` v panelu **i** to, že se druhý rebase nenabídne:
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
        case .rebased(let branch):
            "Srovnáno v kopii repa — \(Plural.czech(branch.replayed, one: "commit přehraný", few: "commity přehrané", many: "commitů přehraných")). "
                + "Do remote se zatím nesáhlo."
        case .pushing: "Přetlačuju větev."
        case .discarding: "Zahazuju rozdělanou práci."
        case .pushed(let replayed):
            "Srovnáno — přetlačeno \(Plural.czech(replayed, one: "commit", few: "commity", many: "commitů"))."
        case .alreadyInSync: "Větev už nad základem byla, do remote se nesáhlo."
        case .conflicted(let files):
            "Rebase narazil na konflikt (\(Self.list(files))) a je zahozený — v kopii repa po něm nic nezůstalo. "
                + "Vyřeš ho v terminálu."
        case .unfinished(let files):
            files.isEmpty
                ? "V kopii repa leží rozdělaný rebase. Zahoď ho, nebo ho dokonči v terminálu."
                : "Rebase narazil na konflikt (\(Self.list(files))) a zůstal rozdělaný v kopii repa. "
                    + "Zahoď ho, nebo ho dokonči v terminálu."
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
            "Pull request je od @\(author) — přetlačit se dá jedině vlastní větev."
        case .foreignBranch:
            "Hlava pull requestu je v jiném repozitáři (fork). Srovnat ji odsud nejde."
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

    /// Dá se to zkusit znovu bez toho, aby se něco změnilo jinde?
    ///
    /// **Dělí se to podle toho, jestli je překážka pomíjivá, nebo strukturální** — ne podle
    /// jednoho konkrétního chybového stavu.
    ///
    /// **Ano** u překážek, které druhý pokus může minout: odmítnutý lease, posunutá hlava
    /// a přerovnaná větev zmizí po obnovení dat, `timedOut` a `interrupted` jsou o tom, že se běh
    /// nedokončil, a `failed` je neznámá chyba, o které se nedá tvrdit, že se zopakuje.
    ///
    /// **Ne** tam, kde druhý pokus dopadne stejně: dokud je PR cizí, zavřený nebo ve forku, dokud
    /// je brána vypnutá, cesta mimo cache nebo `git` nedostupný, nezmění se opakováním nic —
    /// a tlačítko, po kterém se nic nestane, je horší než zašedlé.
    var canRetry: Bool {
        switch self {
        case .leaseRejected, .headMoved, .branchChanged, .timedOut, .interrupted, .failed: true
        case .notAllowed, .notMine, .foreignBranch, .unknownBranchOrigin, .pullRequestNotOpen,
            .outsideCache, .toolUnavailable:
            false
        }
    }

    private static func short(_ sha: String) -> String { String(sha.prefix(7)) }
}
