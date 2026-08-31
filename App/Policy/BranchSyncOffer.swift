import Foundation

/// Druhá akce sekce `Větev` — **`Srovnat s main`** (#466, návrh sekce 36).
///
/// Je to čistá funkce ze stejného důvodu jako `mergeOffer`: `git push` do vlastní větve je věc,
/// která se dá udělat špatně jen jednou, takže otázka „smí se to nabídnout, a když ne, proč“ má
/// mít **jednu** odpověď, vyjmenovanou a testovanou výčtem.
///
/// **Nabídka a plán se skládají zvlášť.** Plán (`BranchSyncPlan`) je snímek toho, co se stane,
/// a existuje i tehdy, když se akce nabídnout nesmí — panel z něj bere počty do nápovědy.
extension Policy {
    /// Proč `Srovnat s main` teď nejde.
    ///
    /// **Vlastní výčet, ne `MergeObstacle`.** Rebase brání něco jiného než mergi: červený check
    /// mu nevadí (srovnat větev je zrovna to, co se s ním dělá), kdežto konflikt nebo rozdělaný
    /// rebase v cache ho zastaví, aniž by mergi vadily.
    enum SyncObstacle: Hashable, Sendable {
        /// Odesílání není povolené, nebo chybí nástroj. Věta je ta, na které skončí pusher.
        case notAllowed(String)
        /// Hlavička PR ještě nedorazila, takže není z čeho složit plán.
        case factsMissing
        /// Pull request není otevřený.
        case notOpen(PullRequestState)
        /// Hlava je v jiném repozitáři (fork), nebo se neví kde.
        case foreignBranch(known: Bool)
        /// Stav větve se teprve dotahuje, nebo se ho nepodařilo zjistit.
        case statusLoading
        case statusFailed(String)
        /// Větev je nad základem — není co přehrávat.
        case upToDate(base: String)
        /// Větve jdou proti sobě; rebase by skončil konfliktem.
        case conflicting(base: String)
        /// Právě běží rebase nebo push.
        case running
        /// V cache leží rozdělaný rebase — napřed se musí zahodit.
        case unfinishedRebase

        /// Věta do nápovědy pod kurzorem. **Ke každé patří i další krok** tam, kde nějaký je.
        var sentence: String {
            switch self {
            case .notAllowed(let reason): reason
            case .factsMissing: "Hlavička pull requestu ještě nedorazila."
            case .notOpen(let state): "Pull request není otevřený — je \(state.czechLabel)."
            case .foreignBranch(let known):
                known
                    ? "Hlava pull requestu je v jiném repozitáři (fork). Srovnat ji odsud nejde."
                    : "Z dat pull requestu neplyne, kde jeho větev leží. Obnov okno."
            case .statusLoading: "Zjišťuju, jestli je větev pozadu."
            case .statusFailed(let reason): "Stav větve se nepodařilo zjistit. \(reason)"
            case .upToDate(let base): "Větev je nad \(base) — není co přehrávat."
            case .conflicting(let base):
                "Větev je v konfliktu s \(base). Konflikty odsud zatím vyřešit neumím — "
                    + "otevři terminál."
            case .running: "Právě se to srovnává."
            case .unfinishedRebase: "V kopii repa leží rozdělaný rebase. Napřed ho zahoď."
            }
        }
    }

    /// Smí se odsud srovnat větev? Tvarem totéž co `MergeOffer` a ze stejného důvodu: na cizím PR
    /// se akce **nekreslí vůbec**, zašedlá s důvodem patří tam, kde se stav **mění**.
    enum SyncOffer: Hashable, Sendable {
        case absent
        case blocked([SyncObstacle])
        case allowed

        var isVisible: Bool { self != .absent }

        var isAllowed: Bool { self == .allowed }

        var obstacles: [SyncObstacle] {
            if case .blocked(let obstacles) = self { obstacles } else { [] }
        }
    }

    /// Plán srovnání z toho, co o PR víme. `nil` = ještě není z čeho ho složit.
    ///
    /// **Bez jména větve, bez základu, bez hlavy a bez divergence se nesestaví.** Jméno větve
    /// a hlava jsou to, čím se guard v pusheru brání omylu, a divergence je to, co říká, kolik
    /// commitů se přehraje — plán, ve kterém kterákoli z těch hodnot chybí, by tvrdil něco, co
    /// nevíme.
    static func branchSyncPlan(of detail: PullRequest?, status: BranchStatusState?) -> BranchSyncPlan? {
        guard let detail, !detail.headRef.isEmpty, !detail.baseRef.isEmpty, !detail.headSha.isEmpty
        else { return nil }
        guard let divergence = status?.status?.divergence else { return nil }
        return BranchSyncPlan(
            pullRequest: detail.id,
            branch: detail.headRef,
            base: detail.baseRef,
            expectedRemoteSha: detail.headSha,
            replaying: divergence.ahead,
            behind: divergence.behind
        )
    }

    /// Smí se srovnat, a když ne, proč.
    ///
    /// **Pořadí důvodů je pořadí, ve kterém se s nimi dá něco dělat**: napřed to, co je mimo větev
    /// (brána, stav PR, fork), pak to, co se právě děje, pak to, co ještě nevíme, a nakonec to, co
    /// plyne z polohy větve.
    static func branchSyncOffer(
        editing: MetadataEditing,
        plan: BranchSyncPlan?,
        detail: PullRequest?,
        status: BranchStatusState?,
        sync: BranchSyncState?
    ) -> SyncOffer {
        guard editing.isVisible else { return .absent }

        var obstacles: [SyncObstacle] = []
        if let reason = editing.reason { obstacles.append(.notAllowed(reason)) }
        if let state = detail?.state {
            switch state {
            // **Draft se srovnat smí.** Rozpracovaný PR je zrovna ten, na kterém se pushuje
            // nejvíc — zakázat na něm rebase by tuhle akci vypnulo tam, kde je nejužitečnější.
            case .open, .draft: break
            // Konec výčtu, ne jeden důvod z pěti: nad mergnutým PR nemá smysl psát nic dalšího.
            case .merged, .closed: return .blocked(obstacles + [.notOpen(state)])
            }
        }
        switch detail?.isCrossRepository {
        case .some(true): return .blocked(obstacles + [.foreignBranch(known: true)])
        case .some(false): break
        // `nil` je „nevím“ — a to je u zápisu do remote zákaz, ne povolení. Sem se dojde jedině
        // s nenačteným detailem (pak níž stejně chybí plán) nebo se starými uloženými daty.
        case .none: return .blocked(obstacles + [.foreignBranch(known: false)])
        }

        if let sync {
            if sync.isBusy { obstacles.append(.running) }
            if sync.hasUnfinishedRebase { obstacles.append(.unfinishedRebase) }
        }

        switch status {
        case .none, .loading: obstacles.append(.statusLoading)
        case .failed(let reason): obstacles.append(.statusFailed(reason))
        case .loaded(let status, _):
            if status.mergeability == .conflicting || status.mergeState == .dirty {
                obstacles.append(.conflicting(base: plan?.base ?? "základem"))
            }
        }

        guard let plan else {
            obstacles.append(.factsMissing)
            return .blocked(obstacles)
        }
        // **Jen když je větev pozadu** (zadání #466). Odpovídá na to `compare`, ne
        // `mergeStateStatus` — ten u větve o commit pozadu vrací `CLEAN` všude, kde na základu
        // není ochrana *Require branches to be up to date* (změřeno, viz `BranchDivergenceQuery`).
        if plan.behind == 0 { obstacles.append(.upToDate(base: plan.base)) }

        return obstacles.isEmpty ? .allowed : .blocked(obstacles)
    }

    /// Která z akcí sekce je hlavní (návrh, sekce 36): **`Mergnout…` když je zeleno, jinak
    /// `Srovnat s main`**.
    ///
    /// Obě jsou v panelu vždycky — srovnat větev dává smysl i tehdy, když už mergnout jde,
    /// a schovávat akci podle stavu by znamenalo, že se tlačítko pod rukou stěhuje. Mění se jen
    /// zvýraznění.
    enum BranchAction: Hashable, Sendable {
        case merge
        case sync
    }

    static func primaryBranchAction(merge: MergeOffer) -> BranchAction {
        merge.isAllowed ? .merge : .sync
    }

    /// Jméno základu do popisku `Srovnat s …`.
    ///
    /// **Bere se z prvního plánu, který ho zná**, a to je rozhodnutí, ne shoda: plán merge si žádá
    /// detail a commity, plán srovnání k tomu **ještě divergenci**, takže dorazí o jedno volání
    /// později. Tvrdit `main` v repozitáři, kde se základ jmenuje `master`, by přitom bylo zbytečné
    /// zrovna v té chvíli, kdy už jeho jméno **víme**.
    ///
    /// `fallbackBase` je z návrhu (sekce 36) a platí jedině tehdy, než dorazí hlavička PR — v tom
    /// stavu je tlačítko stejně zakázané.
    static func syncBase(of section: BranchSection) -> String {
        section.syncPlan?.base ?? section.plan?.base ?? fallbackBase
    }

    static let fallbackBase = "main"

    /// Které překážky srovnání si žádají **vlastní větu ve výstraze v panelu**.
    ///
    /// Pravidlo z #392 a #465 říká, že zašedlé tlačítko musí mít důvod **napsaný v panelu**, ne jen
    /// v nápovědě pod kurzorem. U srovnání je ale většina důvodů v panelu **už napsaná jinde**,
    /// takže vypsat je všechny znamená totéž dvakrát — a věta, která se opakuje, se přestane číst.
    /// Rozhoduje se to tady, ne ve view, a `switch` je vyčerpávající schválně: nová překážka si
    /// vynutí rozhodnutí při překladu.
    ///
    /// Vlastní věta zbývá **jediné** — hlavě v jiném repozitáři. Ta se nikde jinde v sekci
    /// neobjeví, takže by u ní zašedlé tlačítko mlčelo.
    static func syncWarnings(_ offer: SyncOffer) -> [SyncObstacle] {
        offer.obstacles.filter { obstacle in
            switch obstacle {
            case .foreignBranch: true
            // Tytéž věty už nese výstraha mergnutí — `editing.reason`, stav PR i nenačtená
            // hlavička jsou překážky **obou** akcí a `MergeObstacle` je má taky.
            case .notAllowed, .notOpen, .factsMissing: false
            // O stavu větve mluví řádky nad výstrahou (`srovnaná`, `konflikt`, `o N commitů
            // vzadu`) a u mergnutí i jeho vlastní výstraha.
            case .statusLoading, .statusFailed, .upToDate, .conflicting: false
            // O tomhle mluví hláška **pod** akcemi (`BranchSyncState.sentence`), a ta je
            // konkrétnější: zná jména kolidujících souborů a nese tlačítko `Zahodit rebase`.
            case .running, .unfinishedRebase: false
            }
        }
    }

    /// Co se stane, **než se to stane** — nápověda pod kurzorem u povoleného `Srovnat s main`.
    ///
    /// Vypsané je obojí, na co se u přetlačení ptáš: **kolik commitů se přehraje** a **přes co se
    /// přetlačí**. Druhá věta je o pojistce, ne o postupu: z „lease čeká hlavu X“ plyne, co se
    /// stane, když se remote mezitím pohnul — nic.
    static func branchSyncHelp(for plan: BranchSyncPlan) -> String {
        let replaying = Plural.czech(plan.replaying, one: "commit", few: "commity", many: "commitů")
        return "Přehraje \(replaying) nad \(plan.base) a přetlačí větev \(plan.branch). "
            + "Čeká na remote hlavu \(plan.expectedRemoteSha.prefix(7)) — když se mezitím pohnula, "
            + "push selže a nic se nepřepíše."
    }
}
