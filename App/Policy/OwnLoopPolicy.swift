import Foundation

extension Policy {
    /// Kde smyčka vlastního PR stojí (#508) — **jedna čistá funkce pro celou dráhu**.
    ///
    /// **Na cizím PR vrací `nil`, a to je celý ten první test.** Smyčka je „co udělám se **svojí**
    /// větví“; nad cizí to je nadpis bez obsahu, stejně jako sekce `Větev` (#465). Nekreslí se
    /// zašedle, nekreslí se vůbec.
    ///
    /// **Walk, ne pět nezávislých odznaků.** Stanice se procházejí v pořadí `Station.allCases`
    /// a walk se **zastaví na první, která není hotová** — ta je `active`, nese větu i akci.
    ///
    /// **Za zastávkou se ale nemlčí, a je to změna pravidla z proklikání** (#508, druhé kolo).
    /// Do téhle změny bylo všechno za zastávkou `idle`; dráha tím odpovídala jedině na otázku
    /// „kam až jsem došel“. Otázka je ale **„co ještě chybí“**, a na tu se odpovídá zeleně: co je
    /// hotové, má být vidět, i když se walk zastavil dřív. Rozhoduje `ownLoopFacts(of:branch:)` —
    /// stanice za zastávkou se vyhodnotí, jen když **všechna dřívější fakta, na kterých stojí,
    /// jsou hotová**, a nakreslí se `done` jen tehdy, když **projde**. Cokoli jiného je `idle`:
    /// nenačtené checky nejsou zeleno a „nevím“ není hotovo.
    ///
    /// **Šedá za zastávkou přesto řekne jedním slovem proč** (#508, čtvrté kolo). Vyhodnocená, ale
    /// nehotová stanice si nese `reason` — `pozadu`, `konflikt`, `nepřetlačeno`, `zjišťuju` —
    /// a ten se nakreslí místo detailu. **Stav zůstává `idle`**, takže rozdělaná (a tedy
    /// zvýrazněná) kapsle je dál právě jedna: ta, o které mluví věta pod dráhou. Stanice, která se
    /// **nevyhodnocovala**, mlčí dál — vymyslet jí důvod by bylo tvrzení z chybějících dat.
    ///
    /// **Nepřebírá se pravidlo desky, že slévatelnost vyhrává vždycky** (#515). Deska vybírá
    /// **nejlevnější tah**, takže mergnutelný PR patří do `K merge`, i když na něm něco zbývá
    /// předat. Dráha odpovídá na jinou otázku — **kde v kole jsem** —, a `Zadání ✓` nad šesti
    /// nepředanými položkami by byla nepravda. Dvě odpovědi to nejsou: každá odpovídá na svoje.
    ///
    /// **„Nevím“ je odpověď, ne „nejde“** (#572). Checky i vyžádaní reviewery se dotahují až
    /// s detailem, takže hned po startu o nich okno neví nic — a stanice v tom stavu je `unknown`
    /// s větou `zjišťuju`, ne `failed`.
    ///
    /// **Merge dráha neřeší** (#508, čtvrté kolo): sedmá stanice odešla, protože stála na celém
    /// kole a byla prakticky vždycky šedá. Nabídku merge proto tahle funkce **nebere ani jako
    /// vstup** — kdyby ji brala, byl by to držený parametr, který nikdo nečte. Kde se merguje, se
    /// nezměnilo: sekce `Větev` a `Policy.mergeOffer` (#465).
    ///
    /// - Parameters:
    ///   - ownership: čí PR to je. Cokoli jiného než `.mine` vrací `nil`.
    ///   - state: stav pull requestu. `merged` a `closed` smyčku **zkracují** — nad mergnutým PR
    ///     nemá smysl tvrdit, že zbývá předat zadání.
    ///   - review: stav review na tomhle PR, tedy tatáž hodnota, jakou ukazuje řádek seznamu.
    ///   - handoff: co zbývá předat (#334). Čte se z něj `pending` i `stage` — na rozdíl od desky,
    ///     která bere jedině `awaitsMove`: dráha o nepředaném zadání říká i **proč** zbývá.
    ///   - sync: co se právě děje s větví (#466). `nil` = neděje se nic.
    ///   - status: co GitHub říká o slévatelnosti (#465). `nil` = ještě se neptalo.
    ///   - checks: kontroly. `nil` = nenačetly se (**„nevím“**), `[]` = PR bez CI (odpověď).
    ///   - reviewers: kdo na PR stojí a jak odpověděl (#392). `nil` = metadata se nenačetla.
    static func ownLoop(
        ownership: PullRequestOwnership,
        state: PullRequestState,
        review: ReviewState,
        handoff: HandoffReport,
        sync: BranchSyncState? = nil,
        status: BranchStatusState? = nil,
        checks: [PullRequestCheck]? = nil,
        reviewers: [RequestedReviewer]? = nil
    ) -> OwnLoop? {
        guard ownership == .mine else { return nil }
        let stamp = handoffStamp(handoff)
        if let closed = closedLoop(state: state, stamp: stamp) { return closed }

        var stations: [OwnLoop.Stop] = []
        var stop: (station: OwnLoop.Station, sentence: String, move: OwnLoop.Move?)?
        /// Co se cestou **dokončilo**. Před zastávkou v tom leží všechno předchozí (walk jinak
        /// nepokračuje), za ní jedině to, co se doopravdy vyhodnotilo a prošlo — a právě proto
        /// stačí `ownLoopFacts(of:branch:)` vyjmenovat **přímé** předpoklady: co na nich stojí
        /// dál, na ně nedosáhne samo.
        var done: Set<OwnLoop.Station> = []

        for station in OwnLoop.Station.allCases {
            guard ownLoopFacts(of: station, branch: sync).isSubset(of: done) else {
                // Fakta téhle stanice stojí na kroku, který se neudělal — `idle` **bez slova** je
                // odpověď, ne úspora: nevyhodnocovala se, takže se o ní nedá říct ani proč není
                // zelená. Před zastávkou sem walk nedojde: tam je hotové všechno předchozí.
                stations.append(OwnLoop.Stop(station: station, state: .idle, detail: nil))
                continue
            }
            switch step(
                at: station,
                review: review,
                handoff: handoff,
                sync: sync,
                status: status,
                checks: checks,
                reviewers: reviewers
            ) {
            case .passed(let detail):
                done.insert(station)
                stations.append(OwnLoop.Stop(station: station, state: .done, detail: detail))
            case .stopped(let state, let detail, let reason, let sentence, let action):
                guard stop == nil else {
                    // Za zastávkou se kreslí zelená, nebo **šedá s jedním slovem**: rozdělaná smí
                    // být jedna — ta, o které mluví věta pod dráhou —, ale mlčet o důvodu by
                    // znamenalo, že se z dráhy nepozná ani „větev je pozadu“ (#508, čtvrté kolo).
                    stations.append(OwnLoop.Stop(station: station, state: .idle, detail: reason))
                    continue
                }
                stations.append(OwnLoop.Stop(station: station, state: state, detail: detail))
                stop = (station, sentence, action)
            }
        }
        return OwnLoop(
            stations: stations,
            active: stop?.station,
            // Bez zastávky je hotové celé kolo. **Merge tady stanice není** (#508, čtvrté kolo),
            // takže věta říká, kde bydlí — je to údaj o místě, ne tvrzení, že to jde mergnout.
            last: stop?.sentence ?? "Všech pět stanic je hotových — merge zůstává v sekci Větev.",
            move: stop?.move,
            stamp: stamp
        )
    }

    /// Na dokončení kterých **dřívějších** stanic stojí fakta téhle (#508, třetí kolo).
    ///
    /// **Jediné místo, kde se rozhoduje, co se smí kreslit za zastávkou** — a je to výčet, ne
    /// podmínka ve view. Stanice za zastávkou se vyhodnotí, jedině když je celý tenhle výčet
    /// hotový; jinak by dráha tvrdila něco nad daty, která mluví o **jiném** stavu repozitáře.
    /// Vyjmenovávají se **přímé** předpoklady: `done` se plní jedině stanicemi, které prošly,
    /// takže se přenos přes řetěz udělá sám.
    ///
    /// **`Push` na ničem nestojí, a to je ten podstatný řádek.** „Větev je pushnutá a srovnaná nad
    /// základem“ je tvrzení o **dnešní** větvi; nepředané nálezy z něj nedělají nepravdu, jenom
    /// ohlašují další kolo. Ze stejného důvodu na ničem nestojí `Nálezy`.
    ///
    /// **`CI` a `Review` stojí na `Push`i jedině tehdy, když se ví, že naše práce na GitHubu
    /// není** (#508, třetí kolo — mění druhé). Obojí mluví o **hlavě, která je na GitHubu**, a to
    /// je celý ten rozdíl: zhasnout je smí jedině fakt, který říká, že ta hlava **není ta naše** —
    /// tedy nepřetlačená práce v cache. Poloha větve **proti základu** hlavou nehýbe: větev může
    /// být o jednadvacet commitů pozadu i v konfliktu se základem, a checky nad tou hlavou přesto
    /// doběhly a schválení na ni platí. Právě tohle spletlo druhé kolo dohromady, a bylo to vidět
    /// na `keboola/platform-libraries#566`: schválený PR se zeleným CI měl obojí šedé, protože
    /// větev byla pozadu.
    ///
    /// **Je z toho poučení, ne jen oprava jednoho řádku:** hrubý předpoklad tvaru „stanice X stojí
    /// na stanici Y“ zhasne **i fakta, která s Y nesouvisí**. Předpoklad se musí umět vyslovit
    /// nad tím, co se doopravdy ví (*o větvi se neví, že by byla rozešlá*), ne nad zástupným
    /// stavem sousední stanice (*`Push` je hotový*).
    ///
    /// **Nenačtený ani nezjištěný stav větve je „nevím“, ne „rozešlo se to“.** Zhasnout kvůli němu
    /// by znamenalo brát chybějící odpověď jako důkaz. Nezhasne se tedy nic a `Push` si svoje
    /// „zjišťuju“ řekne sám.
    ///
    /// - Parameter sync: co leží v kopii repa (#466). **Jediný vstup, který o hlavě na GitHubu
    ///   něco říká** — `BranchStatus` mluví o poloze proti základu, ne o tom, čí je hlava.
    static func ownLoopFacts(
        of station: OwnLoop.Station,
        branch sync: BranchSyncState? = nil
    ) -> Set<OwnLoop.Station> {
        switch station {
        case .findings: []
        case .handoff: [.findings]
        case .push: []
        case .ci, .review: headReachedGitHub(sync) ? [] : [.push]
        }
    }

    /// Je hlava, o které GitHub mluví, ta naše?
    ///
    /// **`true` znamená „neví se o ničem, co by naši práci drželo mimo GitHub“, ne „ověřeno“** —
    /// a je to schválně slabší tvrzení: aplikace zná jedině **svoji** rozdělanou práci (rebase ve
    /// vlastním stromě v cache), o commitech, které si člověk udělal ve svém klonu, neví nic.
    /// Vnitřek `ownLoopFacts(of:branch:)`, ne druhé rozhodovací místo.
    private static func headReachedGitHub(_ sync: BranchSyncState?) -> Bool {
        guard let sync else { return true }
        // Rozdělané i přerovnané: v obou případech leží v cache commity, které v remote nejsou.
        if sync.isBusy || sync.rebasedBranch != nil { return false }
        switch sync {
        case .conflicted, .unfinished, .unresolved, .failed:
            // Nedokončený rebase i spadlé přetlačení: co je na GitHubu, je **předchozí** hlava.
            // U `.failed` se zaokrouhluje k opatrnější odpovědi — o výsledku pushe se z chyby
            // nedá říct nic jistého.
            return false
        // **Nepřijatá práce agenta se počítá jako `unresolved`** (#510): ve stromě v cache po ní
        // může ležet změna, o které GitHub neví.
        case .fixRejected:
            return false
        // **Agent, který nic nezměnil, hlavou nehnul** — v cache po něm nic neleží, takže se
        // odpovídá stejně jako u `alreadyInSync`.
        case .pushed, .alreadyInSync, .fixedNothing:
            return true
        case .rebasing, .resolving, .fixing, .pushing, .discarding, .rebased:
            // Odchycené výš; vypsané kvůli vyčerpávajícímu `switch`i, který ohlídá nový případ
            // při překladu.
            return false
        }
    }

    /// Co walk s jednou stanicí udělá: pustí dál, nebo se na ní zastaví.
    ///
    /// **Vnitřní typ, ne součást `OwnLoop`u**: je to mezikrok skládání, ne stav, který by někdo
    /// kreslil. Kdyby byl venku, dala by se dráha složit odjinud než tady.
    private enum LoopStep {
        case passed(detail: String?)
        /// - Parameters:
        ///   - detail: co v kapsli stojí, když je tahle stanice **ta aktivní** — plná odpověď
        ///     i s počtem (`o 4 vzadu`, `3 neprošly`), protože pod ní stojí věta.
        ///   - reason: **jedno slovo**, které se nakreslí, když je stanice **za zastávkou**.
        ///     Vlastní hodnota vedle `detail`u schválně: šedá kapsle stojí sama (věta pod dráhou
        ///     mluví o jiné stanici) a dělí se o šířku s ostatními čtyřmi, takže se z ní musí dát
        ///     přečíst **druh** překážky, ne její míra. Nikdy prázdné a **nikdy s číslem** —
        ///     počet nad cizí větou se čte jako tvrzení o tom, co je zrovna na tahu.
        case stopped(
            state: ReviewerLane.PhaseState,
            detail: String?,
            reason: String,
            sentence: String,
            move: OwnLoop.Move?
        )
    }

    private static func step(
        at station: OwnLoop.Station,
        review: ReviewState,
        handoff: HandoffReport,
        sync: BranchSyncState?,
        status: BranchStatusState?,
        checks: [PullRequestCheck]?,
        reviewers: [RequestedReviewer]?
    ) -> LoopStep {
        switch station {
        case .findings: findingsStep(review)
        case .handoff: handoffStep(handoff)
        case .push: pushStep(sync: sync, status: status)
        case .ci: checksStep(checks)
        case .review: reviewStep(reviewers)
        }
    }

    // MARK: - Mergnutý a zavřený PR

    /// Smyčka nad PR, který už nikam nevede.
    ///
    /// **Zkracuje se celá, ne jen poslední stanice.** Nad mergnutým PR by walk zastavil tam, kde
    /// zrovna zbylo něco nepředaného — a věta `6 k předání` nad mergnutou větví je rada, kterou
    /// nemá kdo splnit. `merged` je proto pět hotových stanic, `closed` pět nedojetých:
    /// `stopped` je ta hodnota, kterou dráha reviewera používá pro „nedoběhlo, protože se to
    /// zastavilo“, takže se nový stav nezavádí.
    private static func closedLoop(state: PullRequestState, stamp: String?) -> OwnLoop? {
        switch state {
        case .open, .draft:
            return nil
        case .merged:
            return OwnLoop(
                stations: OwnLoop.Station.allCases.map {
                    OwnLoop.Stop(station: $0, state: .done, detail: nil)
                },
                active: nil,
                last: "Mergnuto — smyčka došla do konce.",
                move: nil,
                stamp: stamp
            )
        case .closed:
            return OwnLoop(
                stations: OwnLoop.Station.allCases.map {
                    OwnLoop.Stop(station: $0, state: .stopped, detail: nil)
                },
                active: nil,
                last: "Pull request je zavřený — smyčka nikam nevede.",
                move: nil,
                stamp: stamp
            )
        }
    }

    // MARK: - Stanice

    /// `Nálezy` — co o kódu řekly moje reviewery.
    ///
    /// **Neprůkazný běh smyčku zastaví** (#383), a je to schválně: `inconclusive` existuje právě
    /// proto, aby se nečetl jako `čisto`, a pustit ho dál by ho tiše přečetlo jako čisto. Stav je
    /// `unknown`, ne `failed` — session doběhla.
    ///
    /// **`reason` se tady nikdy nenakreslí** — `Nálezy` jsou první stanice, takže jsou buď hotové,
    /// nebo tou zastávkou. Vyplněný je stejně: pravidlo *nehotová stanice řekne jedním slovem
    /// proč* je **bezpodmínečné**, a kdyby se výčet předpokladů v `ownLoopFacts` někdy změnil,
    /// nesmí dráha potichu zmlknout.
    private static func findingsStep(_ review: ReviewState) -> LoopStep {
        switch review {
        case .notStarted:
            .stopped(
                state: .running,
                detail: "nespuštěno",
                reason: "nespuštěno",
                sentence: "Review na tomhle PR ještě neběželo — pusť ho, ať je z čeho složit zadání.",
                move: nil
            )
        case .queued:
            .stopped(
                state: .running,
                detail: "čeká na slot",
                reason: "fronta",
                sentence: "Review čeká na volný slot.",
                move: nil
            )
        case .cloning:
            .stopped(
                state: .running,
                detail: "kopie repa",
                reason: "klonuje",
                sentence: "Připravuje se pracovní kopie repa.",
                move: nil
            )
        case .running(let finished, let total):
            .stopped(
                state: .running,
                detail: "\(finished)/\(total)",
                reason: "běží",
                sentence: "Reviewery běží — hotových je \(finished) ze \(total).",
                move: nil
            )
        case .checkoutFailed(let detail):
            .stopped(
                state: .failed,
                detail: "kopie repa",
                reason: "spadlo",
                sentence: "Pracovní kopii repa se nepodařilo připravit: \(detail)",
                move: nil
            )
        case .failed(let detail):
            .stopped(
                state: .failed,
                detail: "spadlo",
                reason: "spadlo",
                sentence: "Review spadlo (\(detail)) — nálezy z něj nejsou, což není totéž jako čisto.",
                move: nil
            )
        case .timedOut:
            .stopped(
                state: .stopped,
                detail: "timeout",
                reason: "timeout",
                sentence: "Review nedoběhlo do limitu, takže za zbytek kódu nemluví.",
                move: nil
            )
        case .interrupted:
            .stopped(
                state: .stopped,
                detail: "přerušeno",
                reason: "přerušeno",
                sentence: "Review skončilo s aplikací, takže za zbytek kódu nemluví.",
                move: nil
            )
        case .inconclusive(let reason):
            .stopped(
                state: .unknown,
                detail: "neprůkazné",
                reason: "neprůkazné",
                sentence: inconclusiveSentence(reason),
                move: nil
            )
        case .stale:
            .stopped(
                state: .stopped,
                detail: "zastaralé",
                reason: "zastaralé",
                sentence: "Nálezy platí ke staršímu commitu, než jaký PR má teď — pusť review znovu.",
                move: nil
            )
        case .clean:
            .passed(detail: "čisto")
        case .completed(let findings):
            .passed(detail: Plural.czech(findings, one: "nález", few: "nálezy", many: "nálezů"))
        case .dismissed(let findings):
            .passed(detail: "\(findings) odmítnuto")
        }
    }

    /// Proč se z běhu čisto tvrdit nedá. **Věta, ne odznak** — odznaky (`ztracené nálezy`,
    /// `bez hlášení`, `kód nepřečten`) skládá `ReviewStateAppearance` a v kapsli dráhy by se
    /// neušly; tady je celý důvod, protože `.last` je řádek pod fázemi.
    private static func inconclusiveSentence(_ reason: InconclusiveReason) -> String {
        switch reason {
        case .droppedFindings:
            "Review doběhlo, ale z části nálezů se nepodařilo přečíst povinné pole — čisto z toho neplyne."
        case .noReport:
            "Review doběhlo, aniž by nahlásilo nálezy — čisto z toho neplyne."
        case .unreadCode:
            "Review doběhlo, ale neotevřelo ani jeden soubor z kopie repa — čisto z toho neplyne."
        }
    }

    /// `Zadání` — co zbývá předat agentovi (#334).
    ///
    /// **Rozhoduje `pending`, ne `stage`.** `stage` říká, *proč* něco zbývá, a to je věta pod
    /// dráhou; jestli stanice pustí dál, je otázka „zbývá tu něco?“ — a na tu odpovídá jedno
    /// číslo. Kdyby to bylo obráceně, byla by `changed` s nulou (nová hlava, ale žádná položka)
    /// zastávka bez obsahu.
    ///
    /// **`reason` se tady nenakreslí** ze stejného důvodu jako u `Nálezů`: `Zadání` stojí na
    /// `Nálezech`, takže se buď vyhodnotí jako první nehotová (a je zastávkou), nebo se
    /// nevyhodnotí vůbec.
    private static func handoffStep(_ report: HandoffReport) -> LoopStep {
        guard report.pending > 0 else {
            guard let stamp = report.handoff else { return .passed(detail: "nic k předání") }
            return .passed(detail: "\(stamp.count) předáno")
        }
        let count = Plural.czech(report.pending, one: "položka", few: "položky", many: "položek")
        return .stopped(
            state: .running,
            detail: "\(report.pending) k předání",
            reason: "nepředáno",
            sentence: handoffSentence(report, count: count),
            move: .openHandoff
        )
    }

    /// Věta k nepředanému zadání. **U každého stavu jiná**, protože z každého plyne jiný další
    /// krok — a `outdated` je jediný, kde je tím krokem pustit review znovu.
    private static func handoffSentence(_ report: HandoffReport, count: String) -> String {
        switch report.stage {
        case .never:
            return "Čeká \(count) k předání agentovi."
        case .unverified:
            return "Zadání se předávalo proti neznámé hlavě, takže se nedá potvrdit, že platí — "
                + "\(count) k předání."
        case .outdated:
            let stale = Plural.czech(
                report.staleFindings, one: "nález", few: "nálezy", many: "nálezů"
            )
            return "Pod předaným zadáním přišel commit a \(stale) platí ke staršímu kódu — "
                + "pusť review znovu a předej to celé."
        case .changed:
            return report.hasMovedHead
                ? "Pod předaným zadáním přišel commit — \(count) k předání."
                : "Od předání přibylo \(count)."
        case .delivered:
            // Sem se nedojde: `delivered` znamená `pending == 0`, což odchytí `handoffStep`.
            // Vypsané je to proto, že vyčerpávající `switch` je jediné, co ohlídá nový stav
            // při překladu.
            return "Zadání je předané."
        }
    }

    /// `Push` — srovnat větev nad základem a přetlačit ji (#466).
    ///
    /// **Rozdělaná práce v kopii repa přebíjí stav na GitHubu**, a je to pořadí, ne shoda: dokud
    /// v cache leží přerovnaná nebo rozdělaná větev, je další krok o ní, ne o tom, co si o větvi
    /// myslí GitHub (ten o rebase v cache neví vůbec).
    ///
    /// **Tohle je ta stanice, kvůli které slovo za zastávkou vzniklo** (#508, čtvrté kolo).
    /// `Push` na ničem nestojí, takže se vyhodnotí vždycky — a když se walk zastavil na
    /// `Nálezech` nebo `Zadání`, byla do téhle změny šedá a **němá**. Že je větev o jednadvacet
    /// commitů pozadu, se pak dalo přečíst jedině v sekci `Větev`.
    private static func pushStep(sync: BranchSyncState?, status: BranchStatusState?) -> LoopStep {
        if let sync, let step = syncStep(sync) { return step }
        switch status {
        case .none, .loading:
            return .stopped(
                state: .unknown,
                detail: "zjišťuju",
                reason: "zjišťuju",
                sentence: "Zjišťuju, jak větev stojí nad základem.",
                move: nil
            )
        case .failed(let reason):
            // **Ne „konflikt“ a ne „srovnaná“** — tatáž hranice jako u `Policy.branchFacts`.
            return .stopped(
                state: .unknown,
                detail: "nevím",
                reason: "nevím",
                sentence: "Stav větve se nepodařilo zjistit. \(reason)",
                move: nil
            )
        case .loaded(let status, _):
            return branchStep(status)
        }
    }

    /// Krok podle toho, co leží v kopii repa. `nil` = neleží nic, co by rozhodovalo.
    private static func syncStep(_ sync: BranchSyncState) -> LoopStep? {
        if sync.isBusy {
            return .stopped(
                state: .running,
                detail: "pracuje se",
                reason: "probíhá",
                sentence: sync.sentence,
                move: .openBranch
            )
        }
        if let branch = sync.rebasedBranch {
            return .stopped(
                state: .running,
                detail: "\(branch.replayed) přerovnáno",
                reason: "nepřetlačeno",
                sentence: sync.sentence,
                move: .openBranch
            )
        }
        switch sync {
        case .conflicted, .unfinished, .unresolved, .failed:
            return .stopped(
                state: .failed,
                detail: "rebase",
                reason: "rebase",
                sentence: sync.sentence,
                move: .openBranch
            )
        // **Vlastní slovo, ne `rebase`** (#510): po agentovi žádný rozdělaný rebase v tom stromě
        // neleží, takže by kapsle pojmenovala něco, co se nestalo — tatáž třída chyby jako věta
        // o rebase nad jeho commitem.
        case .fixRejected:
            return .stopped(
                state: .failed,
                detail: "nepřijato",
                reason: "nepřijato",
                sentence: sync.sentence,
                move: .openBranch
            )
        case .pushed, .alreadyInSync, .fixedNothing, .rebasing, .resolving, .fixing, .pushing,
            .discarding, .rebased:
            // Doběhlé srovnání o dnešní poloze větve nerozhoduje — to řekne `BranchStatus` níž.
            // Totéž platí o agentovi, který nic nezměnil (#510): v cache po něm nic neleží.
            // Běžící a přerovnané stavy odchytily větve výš; vypsané jsou kvůli vyčerpávajícímu
            // `switch`i, který ohlídá nový případ při překladu.
            return nil
        }
    }

    private static func branchStep(_ status: BranchStatus) -> LoopStep {
        if status.mergeability == .conflicting || status.mergeState == .dirty {
            return .stopped(
                state: .failed,
                detail: "konflikt",
                reason: "konflikt",
                sentence: "Větev je v konfliktu se základem — srovnej ji.",
                move: .openBranch
            )
        }
        if let divergence = status.divergence, divergence.isBehind {
            let commits = Plural.czech(divergence.behind, one: "commit", few: "commity", many: "commitů")
            return .stopped(
                state: .running,
                detail: "o \(divergence.behind) vzadu",
                reason: "pozadu",
                sentence: "Větev je o \(commits) pozadu za základem — srovnej ji rebasem.",
                move: .openBranch
            )
        }
        if status.mergeState == .behind {
            return .stopped(
                state: .running,
                detail: "za základem",
                reason: "pozadu",
                sentence: "Větev je pozadu za základem — srovnej ji rebasem.",
                move: .openBranch
            )
        }
        return .passed(detail: "srovnaná")
    }

    /// `CI` — kontroly na GitHubu.
    ///
    /// **`nil` a `[]` se nesmí slít**: nenačtené checky jsou „nevím“, prázdné pole je odpověď
    /// „tenhle PR nemá CI“ (a to je běžný stav, ne porucha).
    private static func checksStep(_ checks: [PullRequestCheck]?) -> LoopStep {
        guard let checks else {
            return .stopped(
                state: .unknown,
                detail: "zjišťuju",
                reason: "zjišťuju",
                sentence: "Kontroly se načítají.",
                move: nil
            )
        }
        let summary = summary(of: checks)
        guard !summary.isEmpty else { return .passed(detail: "bez checků") }
        if summary.failed > 0 {
            let word = Plural.word(summary.failed, one: "neprošel", few: "neprošly", many: "neprošlo")
            return .stopped(
                state: .failed,
                detail: "\(summary.failed) \(word)",
                reason: "neprošlo",
                sentence: "\(Plural.czech(summary.failed, one: "check", few: "checky", many: "checků")) "
                    + "\(word) — oprav to a pushni znovu.",
                move: .openChecks
            )
        }
        if summary.running > 0 {
            return .stopped(
                state: .running,
                detail: "\(summary.running) běží",
                reason: "běží",
                sentence: "\(Plural.czech(summary.running, one: "check", few: "checky", many: "checků")) "
                    + "ještě běží.",
                move: .openChecks
            )
        }
        return .passed(detail: summary.passed > 0 ? "zeleno" : "přeskočeno")
    }

    /// `Review` — kdo na PR stojí a jak odpověděl (#392).
    ///
    /// **U `čeká` není akce, a je to schválně**: čekat na kolegu není můj tah. `chce změny` akci
    /// má — vede do konverzace, kde ta věta stojí.
    ///
    /// **Schválení přebíjí visící žádost** (#508, třetí kolo). Pořadí je `chce změny` → `schválil`
    /// → `čeká`, a ta prostřední dvojice se do třetího kola četla obráceně: `#566` je schválený
    /// (`reviewDecision: APPROVED`) a zároveň má otevřenou žádost na dalšího člověka, takže dráha
    /// hlásila `čeká 1` nad hotovým review. Rozhodnuto je, že **stanice je tím hotová** — jedno
    /// schválení stačí GitHubu i nám. Visící žádost se tím **neztrácí**: sekce `Reviewery`
    /// v panelu (#392) ji kreslí dál, včetně toho, na koho se čeká.
    ///
    /// **`chce změny` nezezelená ani se schválením**, a je to ta půlka, která se uvolnit nesmí:
    /// je to jediná odpověď, která něco blokuje, takže se testuje první.
    private static func reviewStep(_ reviewers: [RequestedReviewer]?) -> LoopStep {
        guard let reviewers else {
            return .stopped(
                state: .unknown,
                detail: "zjišťuju",
                reason: "zjišťuju",
                sentence: "Reviewery se načítají.",
                move: nil
            )
        }
        let blocking = reviewers.count { $0.answer == .changesRequested }
        if blocking > 0 {
            return .stopped(
                state: .failed,
                detail: "\(blocking) chce změny",
                reason: "změny",
                sentence: Plural.czech(
                    blocking, one: "reviewer chce", few: "reviewery chtějí", many: "reviewerů chce"
                ) + " změny — přečti si je a předej je agentovi.",
                move: .openConversation
            )
        }
        let approved = reviewers.count { $0.answer == .approved }
        if approved > 0 { return .passed(detail: "schváleno") }
        let waiting = reviewers.count { $0.answer == .waiting }
        if waiting > 0 {
            return .stopped(
                state: .running,
                detail: "čeká \(waiting)",
                reason: "čeká",
                sentence: "Čeká se na \(Plural.czech(waiting, one: "reviewera", few: "reviewery", many: "reviewerů")) "
                    + "— tvůj tah to není.",
                move: nil
            )
        }
        return .passed(detail: "bez reviewerů")
    }

    /// Razítko do hlavičky dráhy — **počet předaných položek a hlava, proti které se předávalo**.
    /// `nil` = nepředávalo se, takže není co říct. Čas v něm **není**: formátovat datum je věc
    /// locale, a `Policy` je čistá funkce.
    private static func handoffStamp(_ report: HandoffReport) -> String? {
        guard let stamp = report.handoff else { return nil }
        let count = Plural.czech(stamp.count, one: "položka", few: "položky", many: "položek")
        guard let head = stamp.shortHead else { return "předáno \(count)" }
        return "předáno \(count) · proti \(head)"
    }
}
