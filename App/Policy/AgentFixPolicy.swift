import Foundation

/// Co se má stát s cizí aktivitou na **vlastním** PR (#510).
///
/// **Tři odpovědi, ne `Bool`.** „Nespouštěj“ a „zařaď to, něco už běží“ jsou dvě různé věci: první
/// znamená, že se ten podnět zahodí (a razítko se posune), druhá, že se k němu vrátíme, jakmile
/// běžící session skončí. Kdyby to byl `Bool`, zmizel by podnět, který přišel v nejhorší možnou
/// chvíli — tedy zrovna ten, o kterém se nedozvím.
enum AgentFixDecision: Equatable, Sendable {
    /// Pusť session nad stromem `-sync` toho PR.
    case start
    /// Nad tímhle PR už session běží — podnět se zařadí a vyřídí se po ní.
    case queue
    /// Nespouštět, a **je vidět proč**.
    case ignore(AgentFixRefusal)
}

/// Proč se agent nepustil (#510). **Výčet, ne věta**: rozhodnutí se testuje výčtem a důvod se
/// z něj musí dát přečíst — „nespustilo se to“ bez důvodu je k nerozeznání od rozbité aplikace.
enum AgentFixRefusal: Equatable, Sendable {
    /// Cizí PR. **První v řadě**, jako u automatu (#332): co není moje, se dál nezvažuje.
    case notMine
    /// Brána `autoAgent` je vypnutá — globálně nebo pro tohle repo. **Výchozí stav.**
    case gateClosed
    /// PR není otevřený (zavřený, mergnutý). Draft se **nevyřazuje**, viz `agentFix(…)`.
    case notOpen(PullRequestState)
    /// Nic cizího od minule — tedy nic, na co by se opravovalo.
    case nothingNew
}

extension Policy {
    // MARK: - Kdy se agent pustí

    /// Pustí se na tenhle podnět agent? Čistá funkce, testuje se **vyčerpávajícím výčtem**.
    ///
    /// **Pořadí kontrol je součástí odpovědi**, ne detail implementace: vyhrává ta první, která
    /// zabere, a odpovídá pořadí, ve kterém se ty otázky dají zodpovědět bez dat od ostatních.
    ///
    /// 1. **Vlastnictví.** Na cizím PR se agent nepouští **nikdy** a nezáleží na tom, co si repo
    ///    řeklo — je to tatáž konstrukce jako `automaticallyReviewable` (#332). Aplikace nemá co
    ///    opravovat cizí práci.
    /// 2. **Brána.** `autoAgent` z `ResolvedConfig`, tedy globálně i per repo, **ve výchozím stavu
    ///    vypnutá**. Právě to drží vlastnost „samo nic nezačne“ (tvrdá podmínka č. 2).
    /// 3. **Stav PR.** Zavřený ani mergnutý PR se neopravuje: commit ve stromě `-sync` by neměl kam
    ///    odejít. **Draft se ale vyřazuje schválně**, na rozdíl od automatu review (#25): Copilot
    ///    review na draftu píše a je to zrovna ten hlas, kvůli kterému tohle vzniklo.
    /// 4. **Je co opravovat.** Prázdná cizí aktivita znamená, že se nic nestalo — moje vlastní
    ///    komentáře ani moje pushe v ní nejsou (`ForeignActivity`, #335), takže vlastní hlas
    ///    agenta nepustí. To je ta věta, na které celé #510 stojí.
    /// 5. **Jedna session na PR.** Až úplně nakonec: druhý agent by pracoval v tomtéž stromě.
    ///
    /// - Parameters:
    ///   - ownership: čí PR to je (`Policy.ownership(of:mine:)`). Bez výchozí hodnoty, jako
    ///     u `automaticallyReviewable`: mlčky dosazené „moje“ by pravidlo tiše vypnulo.
    ///   - isAllowed: `ResolvedConfig.autoAgent` toho repa. Bez výchozí hodnoty ze stejného
    ///     důvodu — brána, kterou lze zapomenout, není brána.
    ///   - activity: co na PR od minule udělal někdo jiný (#335).
    ///   - isRunning: běží nad tímhle PR agent, nebo srovnání větve? **Obojí**, protože obojí
    ///     pracuje ve stromě `-sync`.
    static func agentFix(
        ownership: PullRequestOwnership,
        state: PullRequestState,
        isAllowed: Bool,
        activity: ForeignActivity,
        isRunning: Bool
    ) -> AgentFixDecision {
        guard ownership == .mine else { return .ignore(.notMine) }
        guard isAllowed else { return .ignore(.gateClosed) }
        guard state == .open || state == .draft else { return .ignore(.notOpen(state)) }
        guard !activity.isEmpty else { return .ignore(.nothingNew) }
        guard !isRunning else { return .queue }
        return .start
    }

    /// Které položky zadání ta aktivita znamená (#510) — vstup pro `only:` u
    /// `agentPromptSelection(…)`.
    ///
    /// **Jen nové položky, ne celý PR** (zadání #510): agent má opravit to, co přišlo, ne projít
    /// znovu všechno, co se na PR kdy řeklo. Zadání se přitom skládá **toutéž cestou jako
    /// `Sestavit prompt`** (#333) — druhá cesta k témuž textu by se s panelem rozešla.
    ///
    /// **Komentář ve vlákně se převádí na vlákno**, ne na komentář: `ForeignActivity.comments`
    /// míchá komentáře pod PR s těmi ve vláknech (`Policy.changes(in:since:)`), kdežto zadání zná
    /// vlákno jako **jednu položku** i s kontextem u řádku. Kdyby se hledalo podle identity
    /// komentáře, nová odpověď v existujícím vlákně by do zadání nepřinesla nic.
    ///
    /// Bez konverzace vyjde **prázdno**, ne „všechno“: bez ní se položky nedají spárovat a zúžení
    /// na prázdno znamená, že se nespustí nic — což je bezpečná strana.
    static func agentFixItems(_ activity: ForeignActivity, in conversation: Conversation?) -> Set<String> {
        guard let conversation else { return [] }
        let fresh = Set(activity.comments.map(\.id))
        var ids = Set(activity.reviews.map { AgentPromptItem.review($0).id })
        for comment in conversation.comments.items where fresh.contains(comment.id) {
            ids.insert(AgentPromptItem.comment(comment).id)
        }
        for thread in conversation.threads.items
        where thread.comments.items.contains(where: { fresh.contains($0.id) }) {
            ids.insert(AgentPromptItem.thread(thread).id)
        }
        return ids
    }

    // MARK: - Prompt

    /// Prompt pro session, která opravuje vlastní PR (#510).
    ///
    /// **Anglicky, jako všechny prompty v tomhle repu** — je to text pro model, ne pro okno.
    /// Vložené zadání (`handoff`) je proti tomu česky: skládá ho `Policy.agentPromptText` a je to
    /// tentýž text, který se z panelu kopíruje ven. Druhá podoba zadání jen kvůli jazyku by
    /// znamenala druhé místo, kde se rozhoduje, co se agentovi předává.
    ///
    /// **Pět věcí, které v něm být musí** — čtyři meze a k nim tvar odpovědi:
    ///
    /// - **Že se pracuje ve stromě, ve kterém session stojí.** Je to strom `-sync` v cache, ne
    ///   uživatelův klon; `Write` a `Edit` mají vypsaný rozsah právě na něj (změřená brána, viz
    ///   `ConflictCommand.allowedTools(in:)`).
    /// - **Že necommituje a nepushuje.** Commituje **aplikace** (jako u #467) a do remote se sáhne
    ///   jedině potvrzením force pushe (#466). Držet to doopravdy je práce sady bez `Bash`e —
    ///   tahle věta je pojistka, ne brána.
    /// - **Že testy nepouští.** Nemá čím (`Bash` v sadě není) a tvrdit v účtu „testy zelené“ bez
    ///   toho, že by je kdo pustil, je zrovna ten druh tvrzení, které data neunesou.
    /// - **Že se má přiznat.** Položka, kterou nejde opravit z kódu (rozhodnutí o produktu, spor
    ///   dvou reviewerů), se **nechá být** a napíše se to — uhádaná oprava, která projde a rozbije
    ///   se v provozu, je horší výsledek než „na tohle nestačím“.
    /// - **Tvar účtu.** Vlastní nástroj na hlášení výsledku session nedostala (u té, která smí
    ///   psát, se výčet nemá rozšiřovat o nic navíc), takže je JSON v posledním sdělení jediná
    ///   cesta — a čte se defenzivně (`AgentFixCommand.parse`).
    static func agentFixPrompt(handoff: String, base: String) -> String {
        var parts: [String] = []
        parts.append("""
            Somebody reviewed a pull request of mine and left feedback on it. The pull request's \
            branch is checked out in the current directory, on top of `\(base.isEmpty ? "the base branch" : base)`. \
            Fix what the feedback asks for by editing the files in place. Read enough of the code \
            around each place to understand it before you change anything.
            """)
        parts.append("""
            Rules you must not break: do not commit, do not run `git` at all, do not push, do not \
            touch anything outside the current directory. Committing the result is done by the \
            application, not by you — and nothing leaves this machine until a human confirms it. \
            You cannot run tests or any other command, so do not claim in your report that \
            anything was verified by running it.
            """)
        parts.append("""
            If a point needs a decision you cannot make from the code — a product decision, two \
            reviewers asking for opposite things, a rewrite that reaches outside this pull \
            request — leave it alone and report it as "skipped" with the reason. A guessed fix \
            that compiles and breaks in production is a worse outcome than admitting you could \
            not do it.
            """)
        parts.append("""
            This is the feedback, as the application collected it. It is in Czech; answer the \
            parts of your report that are marked Czech in Czech, everything else in English.

            \(handoff)
            """)
        parts.append("""
            When you are done, output only a JSON object, no prose and no code fences:
            {"files": ["<path relative to the current directory>"], "summary": "<one Czech \
            sentence about what you changed>", "skipped": "<one Czech sentence about what you \
            left alone and why, or omit>"}
            """)
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Commit

    /// Zpráva commitu, který nad prací agenta udělá **aplikace** (#510).
    ///
    /// **Skládá ji `Policy`, ne session, a je to rozhodnutí, ne úspora.** Hlavička commitu je
    /// jediné místo, kde by se text od modelu dostal do **historie repa** — tedy tam, odkud se
    /// nedá vzít zpět jedním kliknutím. Zpráva je proto úplně určená daty, která má aplikace
    /// v ruce: číslo pull requestu a to, že jde o opravu po review.
    ///
    /// **Anglicky a v Conventional Commits**, jako všechny commit messages v tomhle repu, a **bez
    /// jakékoli AI atribuce** — na tom se nic nemění tím, že soubory upravila session.
    ///
    /// Co session udělala, se ztratit nemá: shrnutí i to, co nechala být, se ukazuje v panelu
    /// a v potvrzení force pushe (`ConflictResolution`-ovou cestou), tedy tam, kde se to dá přečíst
    /// **před** odesláním.
    static func agentFixCommitMessage(for pr: PRIdentifier) -> String {
        "fix: address review feedback (#\(pr.number))"
    }

    // MARK: - Věty do okna

    /// Věta pod akcemi, dokud agent běží. **Nese počet položek** — patnáctiminutové ticho nad
    /// „Agent pracuje“ je k nerozeznání od zaseknutého okna (tatáž úvaha jako
    /// u `conflictActivity`).
    static func agentFixActivity(items: Int) -> String {
        "Agent opravuje, co přišlo v review (\(Plural.czech(items, one: "položka", few: "položky", many: "položek")))."
    }

    /// Věta o tom, že agent psal mimo svůj strom — **a co z toho plyne**.
    ///
    /// Vlastní věta vedle `writesOutsideWorktree` (#467), ne tatáž: tam zůstává rozdělaný rebase,
    /// tady leží ve stromě rozdělaná **oprava**. Další krok je proto jiný a věta ho musí říct.
    static func agentFixWritesOutside(_ paths: [String]) -> String {
        let list = paths.prefix(2).joined(separator: ", ")
        let rest = paths.count - min(paths.count, 2)
        let tail = rest > 0
            ? "\(list) a \(Plural.czech(rest, one: "další", few: "další", many: "dalších"))"
            : list
        return "Agent psal mimo kopii repa (\(tail)), takže se jeho výsledek nepřijal a nic se necommitlo. "
            + "Co ve stromě zůstalo, zahoď, nebo si to prohlédni v terminálu."
    }

    /// Věta o tom, jak agent dopadl — do stavu `rebased`, když commit vznikl z jeho práce.
    ///
    /// **Vlastní věta, ne ta o rebase**: v tom stavu neleží přehrané commity, ale jeden commit
    /// s opravou. Text „Rebase hotový“ by nad ním tvrdil něco, co se nestalo (a je to zrovna ta
    /// třída chyb, kterou Copilot v tomhle repu nachází: text, který tvrdí víc, než data unesou).
    static func agentFixResult(files: Int, skipped: String?) -> String {
        let count = Plural.czech(files, one: "soubor", few: "soubory", many: "souborů")
        let head = files > 0
            ? "Agent upravil \(count) a commit leží v kopii repa."
            : "Agent commit připravil v kopii repa."
        return head + " Do remote se zatím nesáhlo." + (skipped.map { " \($0)" } ?? "")
    }

    /// Věta o tom, že agent doběhl a **nic nezměnil**. Vlastní stav, ne selhání: je to legitimní
    /// výsledek („na tohle nestačím“, „nemám co opravit“), po kterém v cache nic neleží.
    static func agentFixNothing(detail: String?) -> String {
        "Agent nic nezměnil, takže není co commitnout." + (detail.map { " \($0)" } ?? "")
    }
}
