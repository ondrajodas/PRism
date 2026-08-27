import Foundation

/// Sekce `Větev` v panelu (#465) — **stav větve a to, co se s ní dá udělat**.
///
/// Je to čistá funkce a je to schválně: merge je nevratný, takže otázka „smí se to nabídnout, a
/// když ne, proč“ má mít **jednu** odpověď, vyjmenovanou a testovanou výčtem. Kdyby ji skládal
/// panel `if`em nad čtyřmi mapami storu, byla by ta odpověď tolikrát, kolik je míst, která se
/// ptají.
///
/// Sekce je zároveň **místo pro druhou akci** (`Srovnat s main`, #466): stav, ze kterého se
/// rozhoduje o mergi, je tentýž, ze kterého se rozhoduje o srovnání větve — proto je `BranchSection`
/// složená ze `stavu` a `nabídky`, ne z jednoho tlačítka.
extension Policy {
    /// Jeden řádek sekce: co se popisuje vlevo a jak to dopadlo vpravo.
    ///
    /// Tvar je z návrhu (`.rv-row` — `who` vlevo, `ans` vpravo), tedy tentýž jako u reviewerů:
    /// když se panel zúží, ustoupí popis a odpověď zůstane celá.
    struct BranchFact: Hashable, Sendable {
        /// Jak se odpověď obarví. **Ne barva, ale význam** — barvu z toho dělá view z palety
        /// (`ok`, `crit`), protože sémantická škála se v tomhle repu nekreslí ze systému (#432).
        enum Tone: Hashable, Sendable {
            case neutral
            case done
            case blocked
        }

        let text: String
        let answer: String
        let tone: Tone
    }

    /// Co brání mergi. **Vyjmenované, ne jedna věta** — v panelu z toho vzniká výčet a každý
    /// z důvodů vede jinam (červený check se opraví pushem, pozadu za základem srovnáním větve,
    /// vypnutá brána v nastavení).
    ///
    /// Věta je u případu, ne u volajícího: kdyby ji skládal panel, měl by ji sheet i nápověda pod
    /// kurzorem pokaždé jinak.
    enum MergeObstacle: Hashable, Sendable {
        /// Odesílání není povolené, nebo chybí `gh`. Věta je ta, na které skončí publisher —
        /// tatáž jako u labelů (`Policy.MetadataEditing.blocked`).
        case notAllowed(String)
        /// Hlavička PR nebo seznam commitů ještě nedorazily, takže není z čeho složit plán.
        /// **Bez plánu se nesmí nabízet nic** — potvrzení by vypisovalo prázdno.
        case factsMissing
        /// Stav větve se teprve dotahuje.
        case statusLoading
        /// Stav větve se nepodařilo zjistit.
        case statusFailed(String)
        /// GitHub ještě nespočítal, jestli to jde — líné pole vrátilo `UNKNOWN` i po opakovaném
        /// dotazu.
        case statusUnknown
        /// Větve jdou proti sobě.
        case conflicting(base: String)
        /// Větev je pozadu za základem. **Bez počtu commitů**, ten přijde s #466 (srovnání větve),
        /// kde bude po ruce klon v cache a dá se spočítat lokálně — `compare` API by za to jedno
        /// číslo tahalo celý seznam souborů.
        case behind(base: String)
        /// Merge nepouštějí pravidla repozitáře (`BLOCKED`).
        case protected
        /// Pull request je rozpracovaný.
        case draftPullRequest
        /// Pull request není otevřený.
        case notOpen(PullRequestState)
        /// Check neprošel. Prázdný seznam znamená „GitHub hlásí spadlý check, ale jména nemáme“ —
        /// checky se dotahují zvlášť a nemusí být načtené.
        case failingChecks([String])
        /// Můj reviewer hlásí blokující nález.
        case blockingFindings(Int)

        /// Věta do panelu. **Ke každé patří i další krok** tam, kde nějaký je — důvod, ze kterého
        /// nevyplývá, co s ním, je jen zpráva o smůle.
        var sentence: String {
            switch self {
            case .notAllowed(let reason):
                reason
            case .factsMissing:
                "Hlavička pull requestu a jeho commity ještě nedorazily."
            case .statusLoading:
                "Zjišťuju, jestli se dá mergnout."
            case .statusFailed(let reason):
                "Stav větve se nepodařilo zjistit. \(reason)"
            case .statusUnknown:
                // GitHub `mergeable` počítá až na vyžádání; gateway se ptá opakovaně, takže sem
                // se dojde jedině tehdy, když to nestihl ani napodruhé.
                "GitHub ještě nespočítal, jestli se dá mergnout. Obnov okno a zkus to znovu."
            case .conflicting(let base):
                "Větev je v konfliktu s \(base)."
            case .behind(let base):
                "Větev je pozadu za \(base)."
            case .protected:
                // **Tři důvody v jedné větě schválně.** `BLOCKED` znamená kterýkoli z nich
                // a GitHub nedává, který — změřeno na `cli/cli#14278`, kde vyšel i u `MERGEABLE`,
                // protože do toho repa nemáme zápis. Vybrat jeden by byla určitá nepravda.
                "Merge nepouštějí pravidla repozitáře — chybí schválení, běží povinný check, "
                    + "nebo do repozitáře nemáš zápis."
            case .draftPullRequest:
                "Pull request je rozpracovaný. Označ ho na GitHubu jako připravený."
            case .notOpen(let state):
                "Pull request není otevřený — je \(state.czechLabel)."
            case .failingChecks(let names):
                Policy.failingChecksSentence(names)
            case .blockingFindings(let count):
                count == 1
                    ? "Reviewer hlásí blokující nález."
                    : "Revieweři hlásí \(Plural.czech(count, one: "blokující nález", few: "blokující nálezy", many: "blokujících nálezů"))."
            }
        }
    }

    /// Smí se odsud mergnout?
    ///
    /// **Tři stavy, ne boolean** — tatáž úvaha jako u `MetadataEditing`: na cizím PR se akce
    /// nekreslí **vůbec** (mergnout cizí frontu se odsud nedělá nikdy), kdežto zašedlá s důvodem
    /// je správná podoba tam, kde se stav **mění** — červený check, větev pozadu, vypnutá brána.
    enum MergeOffer: Hashable, Sendable {
        /// Cizí PR — tlačítko se nekreslí.
        case absent
        case blocked([MergeObstacle])
        case allowed

        var isVisible: Bool { self != .absent }

        var isAllowed: Bool { self == .allowed }

        /// Proč to nejde. Prázdné, když to jde.
        var obstacles: [MergeObstacle] {
            if case .blocked(let obstacles) = self { obstacles } else { [] }
        }
    }

    /// Sekce `Větev` celá — dva řádky stavu, nabídka merge a plán, který se potvrzuje.
    ///
    /// **Skládá se na jednom místě**, ne po částech ve view: řádek „srovnaná / za základem“
    /// a zašednutí tlačítka odpovídají na tutéž otázku, takže dvě skládání by uměla říct každé
    /// něco jiného.
    struct BranchSection: Hashable, Sendable {
        let facts: [BranchFact]
        let merge: MergeOffer
        /// Co se potvrzuje. `nil` = není z čeho ho složit; pak je `merge` vždycky `blocked`
        /// s `factsMissing`.
        let plan: MergePlan?
    }

    /// Celá sekce z toho, co o PR víme.
    ///
    /// `nil` na cizím PR — tam se nekreslí ani stav, ne jen akce: sekce `Větev` odpovídá na
    /// otázku, co se dá udělat s **mojí** větví, a nad cizí je to nadpis bez obsahu.
    static func branchSection(
        editing: MetadataEditing,
        detail: PullRequest?,
        commits: [PullRequestCommit]?,
        status: BranchStatusState?,
        checks: [PullRequestCheck]?,
        blockingFindings: Int
    ) -> BranchSection? {
        guard editing.isVisible else { return nil }
        let plan = mergePlan(of: detail, commits: commits)
        return BranchSection(
            facts: branchFacts(plan: plan, commits: commits, status: status, checks: checks),
            merge: mergeOffer(
                editing: editing,
                plan: plan,
                state: detail?.state,
                status: status,
                checks: checks,
                blockingFindings: blockingFindings
            ),
            plan: plan
        )
    }

    /// Dva řádky stavu z návrhu: kam se to slévá a co je na tom hotové.
    static func branchFacts(
        plan: MergePlan?,
        commits: [PullRequestCommit]?,
        status: BranchStatusState?,
        checks: [PullRequestCheck]?
    ) -> [BranchFact] {
        [syncFact(plan: plan, status: status), checksFact(commits: commits, checks: checks)]
    }

    /// Řádek „kam se to slévá a jestli je větev srovnaná“.
    private static func syncFact(plan: MergePlan?, status: BranchStatusState?) -> BranchFact {
        let route = plan.map { "\($0.head) → \($0.base)" } ?? "větev se načítá"
        let answer: (String, BranchFact.Tone) = switch status {
        case .loaded(let status, _): syncAnswer(of: status)
        case .loading, .none: ("zjišťuju", .neutral)
        // **Ne „konflikt“ a ne „srovnaná“.** Nevědět je vlastní odpověď; tvrdit o nevratné akci
        // něco z chybějících dat je ta nejhorší možná varianta.
        case .failed: ("nevím", .neutral)
        }
        return BranchFact(text: route, answer: answer.0, tone: answer.1)
    }

    private static func syncAnswer(of status: BranchStatus) -> (String, BranchFact.Tone) {
        if status.mergeability == .conflicting || status.mergeState == .dirty {
            return ("konflikt", .blocked)
        }
        return switch status.mergeState {
        case .behind: ("za základem", .blocked)
        case .draft: ("rozpracovaný", .neutral)
        case .unknown: ("nevím", .neutral)
        // `DIRTY` je odchycený `if`em nad tímhle `switch`em (je to konflikt, ať `mergeable` říká
        // cokoli), takže sem nedojde. Vypsaný je proto, že vyčerpávající `switch` je to jediné,
        // co u cizího výčtu ohlídá novou hodnotu při překladu — a `default` by ji spolkl.
        case .dirty: ("konflikt", .blocked)
        // `BLOCKED` a `UNSTABLE` jsou o pravidlech a o checcích, ne o poloze větve — tenhle řádek
        // říká jenom to, jestli je větev nad základem. Proč merge nejde, stojí ve výstraze pod ním.
        case .clean, .blocked, .unstable, .hasHooks: ("srovnaná", .done)
        }
    }

    /// Řádek „kolik commitů a jak dopadly checky“.
    private static func checksFact(
        commits: [PullRequestCommit]?,
        checks: [PullRequestCheck]?
    ) -> BranchFact {
        let count = commits.map {
            Plural.czech($0.count, one: "commit", few: "commity", many: "commitů")
        } ?? "commity se načítají"
        guard let checks else {
            return BranchFact(text: count, answer: "checky se načítají", tone: .neutral)
        }
        let summary = summary(of: checks)
        guard !summary.isEmpty else {
            // Prázdno je **odpověď**: PR bez CI je běžný a věta o něm nemá vypadat jako porucha.
            return BranchFact(text: count, answer: "bez checků", tone: .neutral)
        }
        let text = "\(count) · \(Plural.czech(checks.count, one: "check", few: "checky", many: "checků"))"
        if summary.failed > 0 {
            let word = Plural.word(summary.failed, one: "neprošel", few: "neprošly", many: "neprošlo")
            return BranchFact(text: text, answer: "\(summary.failed) \(word)", tone: .blocked)
        }
        if summary.running > 0 {
            return BranchFact(text: text, answer: "\(summary.running) běží", tone: .neutral)
        }
        guard summary.passed > 0 else {
            return BranchFact(text: text, answer: "přeskočeno", tone: .neutral)
        }
        return BranchFact(text: text, answer: "zeleno", tone: .done)
    }

    /// Smí se mergnout, a když ne, proč.
    ///
    /// **Pořadí důvodů je pořadí, ve kterém se s nimi dá něco dělat**: napřed to, co je mimo větev
    /// (brána, stav PR), pak to, co ještě nevíme, a nakonec to, co se opravuje prací na ní.
    static func mergeOffer(
        editing: MetadataEditing,
        plan: MergePlan?,
        state: PullRequestState?,
        status: BranchStatusState?,
        checks: [PullRequestCheck]?,
        blockingFindings: Int
    ) -> MergeOffer {
        guard editing.isVisible else { return .absent }

        var obstacles: [MergeObstacle] = []
        if let reason = editing.reason { obstacles.append(.notAllowed(reason)) }
        if let state {
            switch state {
            case .draft: obstacles.append(.draftPullRequest)
            case .merged, .closed:
                // **Konec výčtu, ne jeden důvod z pěti.** Nad mergnutým PR nemá smysl psát, že se
                // zjišťuje slévatelnost nebo že je větev pozadu — je po všem a jediná pravdivá
                // věta je tahle. Platí to i po vlastním mergi z tohohle okna, kdy se stav načte
                // znovu hned (`AppStore.pullRequestWasMerged`).
                return .blocked(obstacles + [.notOpen(state)])
            case .open: break
            }
        }
        guard let plan else {
            obstacles.append(.factsMissing)
            return .blocked(obstacles)
        }

        switch status {
        case .none, .loading: obstacles.append(.statusLoading)
        case .failed(let reason): obstacles.append(.statusFailed(reason))
        case .loaded(let status, _): obstacles += branchObstacles(of: status, base: plan.base)
        }

        obstacles += checkObstacles(status: status?.status, checks: checks)
        if blockingFindings > 0 { obstacles.append(.blockingFindings(blockingFindings)) }

        // **Sjednocuje se tady, ne při kreslení.** `draftPullRequest` umí přijít ze stavu PR
        // i z `mergeStateStatus`, a dvě stejné věty pod sebou vypadají jako dvě různé překážky.
        // `Set` ne — na pořadí záleží, viz komentář nad funkcí.
        var seen: Set<MergeObstacle> = []
        let unique = obstacles.filter { seen.insert($0).inserted }
        return unique.isEmpty ? .allowed : .blocked(unique)
    }

    private static func branchObstacles(of status: BranchStatus, base: String) -> [MergeObstacle] {
        var found: [MergeObstacle] = []
        if status.mergeability == .conflicting || status.mergeState == .dirty {
            found.append(.conflicting(base: base))
        } else if status.mergeability == .unknown {
            // **Až za konfliktem**: `CONFLICTING` je odpověď, kdežto `UNKNOWN` je „ještě jsem
            // nepočítal“ — hlásit obojí naráz by znamenalo větu „nevím“ nad větou „je konflikt“.
            found.append(.statusUnknown)
        }
        switch status.mergeState {
        case .behind: found.append(.behind(base: base))
        case .blocked: found.append(.protected)
        case .draft: found.append(.draftPullRequest)
        // `DIRTY` už je ve `found` z `if`u výš — přidat ho podruhé by dalo dvě věty o jednom
        // konfliktu. Vypsaný je kvůli vyčerpávajícímu `switch`i, viz `syncAnswer`.
        case .dirty: break
        // `HAS_HOOKS` je čistý stav s nastavenými hooky, `CLEAN` čistý stav, `UNSTABLE` řeší
        // checky níž a `UNKNOWN` je pokryté `mergeability` výš — merge sám o sobě nebrání ani jeden.
        case .clean, .hasHooks, .unstable, .unknown: break
        }
        return found
    }

    /// Spadlý check merge **blokuje, i když by ho GitHub pustil**.
    ///
    /// `UNSTABLE` znamená „nepovinný check spadl“ a GitHub merge dovolí; aplikace je tady schválně
    /// **striktnější** — tatáž úvaha jako u odpovědi na zavřeném PR (#73). Zeleno je jediný stav,
    /// ve kterém se dá mergnout bez čtení, a nabídnout nevratnou akci nad červeným checkem znamená
    /// nabídnout ji nad rozbitým kódem.
    ///
    /// **Běžící check merge nebrání**: mergnout rozběhnutou CI je legitimní rozhodnutí a povinný
    /// check zavře GitHub sám (`BLOCKED`).
    private static func checkObstacles(
        status: BranchStatus?,
        checks: [PullRequestCheck]?
    ) -> [MergeObstacle] {
        // Zrušený se počítá ke spadlým, stejně jako v `Policy.summary(of:)` — z obojího plyne, že
        // se PR nemá čím pochlubit, a druhé pravidlo by znamenalo hlavičku a panel v rozporu.
        let failing = (checks ?? [])
            .filter { $0.outcome == .failed || $0.outcome == .cancelled }
            .map(\.name)
            .sorted()
        guard failing.isEmpty else { return [.failingChecks(failing)] }
        // Jména nemusí být načtená — checky se dotahují zvlášť. `UNSTABLE` je pak jediné, z čeho
        // se o spadlém checku dozvíme, a mlčet o něm je horší než věta bez jména.
        guard status?.mergeState == .unstable else { return [] }
        return [.failingChecks([])]
    }

    /// Věta o spadlých checcích. **Jména se vypisují nejvýš tři** — panel má 300 bodů a seznam
    /// dvaceti jmen z něj udělá odstavec, ve kterém se ta věta ztratí.
    private static func failingChecksSentence(_ names: [String]) -> String {
        guard let first = names.first else { return "Některý check neprošel." }
        guard names.count > 1 else { return "Check „\(first)“ neprošel." }
        let shown = names.prefix(3).map { "„\($0)“" }.joined(separator: ", ")
        let rest = names.count - min(names.count, 3)
        guard rest > 0 else { return "Neprošly checky \(shown)." }
        return "Neprošly checky \(shown) a \(Plural.czech(rest, one: "další", few: "další", many: "dalších"))."
    }

    /// Titulek squash commitu — **`titulek PR (#číslo)`**, jak to dělá GitHub sám.
    ///
    /// Posílá se doslova (`commit_title`), protože bez něj si ho GitHub skládá podle nastavení
    /// repozitáře, do kterého aplikace nevidí — a potvrzení by pak ukazovalo titulek, který nemusí
    /// vzniknout. Číslo se sází ručně, ne přes formátování: `#465` není množství a v české locale
    /// by se z něj stalo `#4 65`.
    static func squashTitle(of title: String, number: Int) -> String {
        "\(title) (#\(number))"
    }

    /// Plán merge z toho, co o PR víme. `nil` = ještě není z čeho ho složit.
    ///
    /// **Bez hlavičky a bez commitů se nesestaví.** Jméno větve, cíl, hlava i počet slévaných
    /// commitů jsou to, co potvrzení vypisuje — a potvrzení, ve kterém kterákoli z těch hodnot
    /// chybí, není potvrzení. Prázdný seznam commitů je přitom platná odpověď jedině teoreticky
    /// (PR bez commitu nevznikne), takže se `nil` a `[]` schválně liší: `nil` je „nevíme“.
    static func mergePlan(of detail: PullRequest?, commits: [PullRequestCommit]?) -> MergePlan? {
        guard let detail, let commits, !detail.headRef.isEmpty, !detail.baseRef.isEmpty else {
            return nil
        }
        return MergePlan(
            pullRequest: detail.id,
            headSha: detail.headSha,
            head: detail.headRef,
            base: detail.baseRef,
            // **Počet z načteného seznamu, ne z vlastního dotazu.** `gh pr view --json commits`
            // vrací celá těla zpráv (změřeno na `PRism#470`: dva commity, 1,4 kB), takže druhý
            // dotaz by za jedno číslo platil velikost, kterou tab `Commity` už jednou zaplatil.
            commits: commits.count,
            commitTitle: squashTitle(of: detail.title, number: detail.number)
        )
    }
}
