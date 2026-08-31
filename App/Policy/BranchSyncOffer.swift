import Foundation

/// Druhá akce sekce `Větev` — **`Rebase`** (#466, návrh sekce 36).
///
/// Je to čistá funkce ze stejného důvodu jako `mergeOffer`: `git push` do vlastní větve je věc,
/// která se dá udělat špatně jen jednou, takže otázka „smí se to nabídnout, a když ne, proč“ má
/// mít **jednu** odpověď, vyjmenovanou a testovanou výčtem.
///
/// **Nabídka a plán se skládají zvlášť.** Plán (`BranchSyncPlan`) je snímek toho, co se stane,
/// a existuje i tehdy, když se akce nabídnout nesmí — panel z něj bere počty do nápovědy.
extension Policy {
    /// Proč `Rebase` teď nejde.
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
        /// V cache leží **přerovnaná větev, která ještě neodešla**. Druhý rebase nad ní by tu práci
        /// zahodil potichu, takže se nenabízí — buď se přetlačí, nebo zahodí.
        case rebasedNotPushed

        /// Věta do nápovědy pod kurzorem. **Ke každé patří i další krok** tam, kde nějaký je.
        var sentence: String {
            switch self {
            case .notAllowed(let reason): reason
            case .factsMissing: "Hlavička pull requestu ještě nedorazila."
            case .notOpen(let state): "Pull request není otevřený — je \(state.czechLabel)."
            case .foreignBranch(let known):
                known
                    ? "Hlava pull requestu je v jiném repozitáři (fork). Rebase odsud nejde."
                    : "Z dat pull requestu neplyne, kde jeho větev leží. Obnov okno."
            case .statusLoading: "Zjišťuju, jestli je větev pozadu."
            case .statusFailed(let reason): "Stav větve se nepodařilo zjistit. \(reason)"
            case .upToDate(let base): "Větev je nad \(base) — není co přehrávat."
            case .conflicting(let base):
                "Větev je v konfliktu s \(base). Konflikty odsud zatím vyřešit neumím — "
                    + "otevři terminál."
            case .running: "Právě se to srovnává."
            case .unfinishedRebase: "V kopii repa leží rozdělaný rebase. Napřed ho zahoď."
            case .rebasedNotPushed:
                "V kopii repa leží přerovnaná větev, která ještě neodešla. Udělej force push, nebo ji zahoď."
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
        // **Na původ větve se ptáme jedině tehdy, když hlavička dorazila** (nález Copilota na
        // #466). `switch detail?.isCrossRepository` by slil dvě různé věci do jedné: „hlavička
        // ještě nedorazila“ a „hlavička dorazila a o původu mlčí“. První je `factsMissing` níž,
        // druhé `foreignBranch` — a věta o původu větve nad nenačteným detailem je text, který
        // tvrdí víc, než data unesou. Předčasný `return` k tomu zahazoval ostatní překážky
        // (běžící srovnání, rozdělaný rebase, stav větve), takže by v panelu chyběly zrovna ty,
        // se kterými se dá něco dělat.
        if let detail {
            switch detail.isCrossRepository {
            case .some(true): return .blocked(obstacles + [.foreignBranch(known: true)])
            case .some(false): break
            // `nil` je „nevím“ — a to je u zápisu do remote zákaz, ne povolení. Sem se dojde se
            // starými uloženými daty, která to pole ještě nemají.
            case .none: return .blocked(obstacles + [.foreignBranch(known: false)])
            }
        }

        if let sync {
            if sync.isBusy { obstacles.append(.running) }
            if sync.hasUnfinishedRebase { obstacles.append(.unfinishedRebase) }
            if sync.rebasedBranch != nil { obstacles.append(.rebasedNotPushed) }
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
    /// `Rebase`**.
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
            // konkrétnější: zná jména kolidujících souborů, počet přehraných commitů a nese
            // tlačítka `Force push…` a `Zahodit`.
            case .running, .unfinishedRebase, .rebasedNotPushed: false
            }
        }
    }

    /// Co se stane, **než se to stane** — nápověda pod kurzorem u povoleného `Rebase`.
    ///
    /// **Mluví jen o prvním kroku, a je to celá pointa rozdělení akce**: tlačítko přehraje commity
    /// v kopii repa a **do remote nesáhne**. Věta o lease se odsud přestěhovala do potvrzení, kde
    /// patří — pod kurzorem by ji člověk čekal až u toho kliknutí, které doopravdy pushuje.
    static func branchSyncHelp(for plan: BranchSyncPlan) -> String {
        let replaying = Plural.czech(plan.replaying, one: "commit", few: "commity", many: "commitů")
        return "Přehraje \(replaying) nad \(plan.base) v kopii repa. "
            + "Do remote se nesáhne — force push se potvrzuje zvlášť."
    }

    /// Věta o pojistce do potvrzení přetlačení (#466).
    ///
    /// **Je o tom, co se stane, když se remote mezitím pohnul**, ne o postupu: z „lease čeká hlavu
    /// X“ plyne, že se v tom případě nepřepíše nic. Skládá ji `Policy`, aby ji panel ani sheet
    /// neopisovaly každý po svém.
    static func leaseWarning(for plan: BranchPushPlan) -> String {
        "Force push pošle tvoji větev \(plan.branch) přes --force-with-lease. Čeká na remote hlavu "
            + "\(plan.expectedRemoteSha.prefix(7)) — když se mezitím pohnula, push selže "
            + "a nic se nepřepíše."
    }

    /// Které commity se v potvrzení force pushe vypíšou a kolik jich zbyde (#466, z proklibání).
    ///
    /// **Strop je osm.** Počet přehraných commitů je neomezený a sheet už jednou přetékal, takže
    /// výpis strop mít musí. Osm proto, že tělo sheetu je `ScrollView` a **patka s tlačítky je nad
    /// ním**, tedy vidět pořád — jde tu o to, aby se do prvního pohledu vešla i **výstraha o lease**
    /// pod výpisem. Delší seznam ji odroluje pod hranu a z potvrzení zbude seznam commitů.
    ///
    /// **Zbytek se počítá, neořezává potichu** — `a další N` je tatáž úmluva jako `+2` u labelů
    /// (#392) a patka `Zobrazit všech N` u front: z prostě useknutého seznamu se nepozná, že něco
    /// chybí, a u nevratné akce je „nepozná se“ ta nejdražší vlastnost.
    ///
    /// **Scrollovaný seznam byl zamítnutý:** sheet je `ScrollView` už teď, takže vnořený scroll by
    /// znamenal dvě rolovací plochy nad sebou — a ta vnitřní by u nevratné akce schovávala zrovna
    /// to, co má být přečtené. Celý seznam se dá přečíst v terminálu nebo po pushi na GitHubu.
    static func pushedCommitList(
        _ commits: [RebasedCommit],
        limit: Int = pushedCommitLimit
    ) -> (shown: [RebasedCommit], hidden: Int) {
        guard commits.count > limit else { return (commits, 0) }
        return (Array(commits.prefix(limit)), commits.count - limit)
    }

    static let pushedCommitLimit = 8

    /// Kolikrát se po **vlastním force pushi** přeptat, dokud pull request nehlásí hlavu, kterou
    /// jsme právě pushnuli — a jak dlouho mezi tím čekat.
    ///
    /// **Objekt pull requestu je po force pushi chvíli nekonzistentní, a je to změřené** na
    /// `prism-review-sandbox#10` (čtyři force pushe, `gh pr view --json mergeable,headRefOid`
    /// v cyklu hned po acku pushe):
    ///
    /// | Kolo | `headRefOid` aktuální | `mergeable` usazený |
    /// |---|---|---|
    /// | 0 | 1,61 s | 2,74 s |
    /// | 1 | 2,16 s | 1,23 s |
    /// | 2 | 1,45 s | 0,65 s |
    /// | 3 | 1,91 s | 0,67 s |
    ///
    /// **Dvě věci z toho plynou a jedna je past.** Hlava dorazí za 1,45–2,16 s, takže dotaz
    /// položený hned po pushi vrátí **starou** hlavu — a to je přesně nahlášená vada („po force
    /// pushi nejde mergnout, není refreshnutý poslední commit“): merge posílá `sha` v payloadu,
    /// takže se se starou hlavou nemůže povést.
    ///
    /// Past je ta druhá polovina: **`mergeable` se usadí dřív než dorazí hlava** (0,65 s proti
    /// 1,45 s), a ta usazená odpověď platí pro **starou** hlavu. Čekat na `mergeable != UNKNOWN`
    /// by tedy bylo nejen nedostatečné, ale **zavádějící** — dostaneš hotovou odpověď o commitu,
    /// který už na větvi není. Rozhoduje proto **shoda hlavy**, ne usazenost `mergeable`.
    ///
    /// **Není to trpělivost naslepo, a v tom je rozdíl proti stráži z #465.** Ta zakazuje dotazovat
    /// líné pole `mergeable` dokola, protože se u něj neví, na co se čeká. Tady se čeká na
    /// **známý fakt** — sha, kterou jsme sami pushnuli —, takže má čekání ukončovací podmínku
    /// a ptá se jedině `fetchHeads` (`cost = 1`), ne na `mergeable`. Strop je přesto **tvrdý**:
    /// když hlava do rozpočtu nedorazí, přestane se ptát a nechá se, co GitHub říká. Tvrdit
    /// „mergovatelné“ bez potvrzené hlavy se nesmí — „nevím“ a „nejde“ se nesmí slít.
    static func awaitsPushedHead(expected: String, actual: String?, attempt: Int) -> Bool {
        guard attempt < pushedHeadAttempts else { return false }
        return actual != expected
    }

    /// Osm pokusů po 0,4 s je **3,2 s čekání** — nad naměřeným maximem 2,16 s s rezervou, a pořád
    /// řádově pod tikem pollingu. Krok je krátký schválně: hlava obvykle dorazí do dvou sekund
    /// a delší krok by to čekání zaokrouhlil nahoru.
    static let pushedHeadAttempts = 8
    static let pushedHeadRetryDelay = Duration.milliseconds(400)

    /// Na kterém PR se má v tiku přeptat na **polohu větve proti základu** (#466, z proklikání).
    ///
    /// **Existuje proto, že „pozadu“ nezávisí na hlavě pull requestu, a razítko `updatedAt` proto
    /// na tuhle veličinu nesedí.** Změřeno na `prism-review-sandbox#9`: do `master`u přišel commit,
    /// a `updated_at` PR se **neposunul ani o sekundu** (zůstal na času force pushe z dopoledne);
    /// `base.sha` v objektu PR je pořád hlava z doby vzniku PR a `baseRefOid` z GraphQL taky.
    /// Základ se tedy může pohnout, aniž by se na pull requestu změnilo cokoli, co jde vyčíst
    /// z jeho razítka — takže stav klíčovaný `updatedAt` tvrdil `srovnaná` nad větví o commit
    /// pozadu, a to i po obnovení a po zavření a otevření záložky.
    ///
    /// **Vrací nejvýš jedno PR, a jedině to otevřené a vlastní.** Tři důvody, každý svůj:
    ///
    /// - **Vlastní**, protože na cizím se sekce `Větev` nekreslí — byl by to dotaz za nic
    ///   (tatáž podmínka, jakou má `loadBranchStatus` na `ownership == .mine`).
    /// - **Otevřené**, protože jinde se ta hodnota nekreslí. Seznam ani přehled o „pozadu“ nic
    ///   netvrdí, takže je nemá proč zdržovat.
    /// - **Jedno**, protože z počtu vlastních PR nemá růst počet volání. Kdo se koukne na druhé,
    ///   dostane odpověď při příštím tiku.
    ///
    /// **Není to polling `mergeable`, a v tom je celý rozdíl proti stráži z #465.** Ta vznikla
    /// proti tomu, aby se z **líného** pole `mergeable` stal tik: GitHub ho počítá až na dotaz,
    /// proto ho `fetchBranchStatus` opakuje, dokud se neusadí. Tady se ptáme jedině na `compare`
    /// nad refem, což je hotová hodnota — změřeno **`cost=1` a 0,51–0,62 s** na dotaz pokrývající
    /// dva repozitáře. Drahá polovina stavu se dál obnovuje jen podle `updatedAt`.
    static func divergenceProbe(
        open tab: WindowTab,
        ownership: (PRIdentifier) -> PullRequestOwnership
    ) -> PRIdentifier? {
        guard let pr = tab.pullRequest, ownership(pr) == .mine else { return nil }
        return pr
    }
}
