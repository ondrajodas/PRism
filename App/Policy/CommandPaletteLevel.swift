import Foundation

/// Druhá úroveň palety ⌘K (#533) — repozitáře organizací a otevřené PR jednoho z nich.
///
/// **Rozhodnutí o úrovni patří sem, ne do view a ne do storu.** Co říká patka, co je ve výzvě
/// pole, jestli `esc` zavírá nebo vrací, který řádek nechá paletu otevřenou a jak se řadí
/// repozitáře — to všechno jsou výčty nad daty, takže se dají projít testem bez okna.
/// `CommandPaletteView` z toho jen sází.
///
/// **Řádky se skládají tady, i když data drží store.** Podtitulek `7 otevřených PR · naposledy
/// před hodinou` je tvrzení (množné číslo, „naposledy“, nula jako `bez otevřených PR`), a taková
/// věta se má dát otestovat výčtem — ne přečíst ze screenshotu.
extension Policy {
    // MARK: - Co se v úrovni kreslí

    /// Všechno, co v paletě **nezávisí na dotazu** (#533).
    ///
    /// - Parameter repository: stav dotahování otevřených PR. `nil` v první úrovni, kde se nic
    ///   netahá — a v druhé úrovni to `nil` být nemá, protože vstup do repa dotažení **spouští**.
    static func paletteStage(
        level: CommandPalette.Level,
        repository: CommandPalette.RepositoryPullRequests? = nil
    ) -> CommandPalette.Stage {
        CommandPalette.Stage(
            level: level,
            chip: level.repository?.description,
            prompt: palettePrompt(at: level),
            hints: paletteHints(at: level),
            notice: paletteNotice(of: repository),
            // Vrací se odsud, kam se dalo vejít. První úroveň je ta, ve které `esc` zavírá —
            // jinak by se paleta nedala zavřít vůbec.
            goesBack: level.repository != nil
        )
    }

    /// Výzva v prázdném poli.
    ///
    /// **Vyjmenovává, co paleta doopravdy najde** — od #533 tedy i repozitář. Kdyby ho nejmenovala,
    /// byla by skupina `Repozitáře` věc, na kterou se přijde omylem.
    ///
    /// Čte se odsud i nápověda tlačítka `⌘K` v hlavičce okna: dvě kopie téže věty by se rozešly
    /// zrovna v tom slově, které se přidalo.
    static func palettePrompt(at level: CommandPalette.Level) -> String {
        switch level {
        case .top: "Najít nález, soubor, pull request, repozitář nebo akci"
        // **Ne „Najít…“**: v druhé úrovni se nic nehledá, jen se zužuje hotový seznam. Slovo
        // „filtrovat“ je ten rozdíl, ze kterého se pozná, že `↵` neotevře nic mimo tohle repo.
        case .repository: "Filtrovat podle titulku, čísla nebo autora"
        }
    }

    /// Co se napíše, když není vidět ani jeden řádek.
    ///
    /// **Prázdný dotaz a napsaný dotaz jsou dva různé stavy**, a je to celý důvod, proč tahle
    /// funkce bere dotaz. „Na „“ nic nesedí“ nad prázdným polem je nesmysl, který se v druhé
    /// úrovni vyrobí snadno: repo bez otevřených PR není prázdný **výsledek**, ale prázdné
    /// **repo** — a to je jiná věta.
    ///
    /// V první úrovni se prázdný dotaz **nemá kde stát** (skupina `Akce` má vždycky nějaký
    /// řádek), ale odpověď tady je: kdo tu funkci zavolá, dostane větu, ne prázdno.
    ///
    /// Druhá věta je ta cennější — říká, **kde** se hledalo. Paleta nechodí na GitHub, takže
    /// „nic nesedí“ neznamená, že takový pull request neexistuje.
    static func paletteEmpty(at level: CommandPalette.Level, query: String) -> CommandPalette.EmptyState {
        let asked = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch level {
        case .top:
            return CommandPalette.EmptyState(
                headline: asked ? "Na „\(query)“ nic nesedí." : "Není tu nic, co by šlo najít.",
                note: "Hledá se v nálezech, souborech otevřeného PR, pull requestech, "
                    + "repozitářích tvých organizací a akcích — jen v tom, co je načtené."
            )
        case .repository(let repo):
            guard asked else {
                return CommandPalette.EmptyState(
                    // **Bez druhé věty**: nehledalo se, takže „hledá se v otevřených PR“ by
                    // odpovídalo na otázku, kterou nikdo nepoložil.
                    headline: "V repu \(repo) není žádný otevřený pull request.",
                    note: nil
                )
            }
            return CommandPalette.EmptyState(
                headline: "Na „\(query)“ nic nesedí.",
                note: "Hledá se v otevřených pull requestech repa \(repo) — podle titulku, "
                    + "čísla a autora."
            )
        }
    }

    /// Patka palety — klávesy **podle úrovně**.
    ///
    /// **`⌘↵` se tady kreslí literálem, a je to zapsaná výjimka** (#441): registruje ho paleta
    /// sama (`CommandPaletteView.shortcuts`), protože je to překryv, který existuje jen otevřený
    /// — v katalogu okna tedy nemá co dělat a odvodit se popiska nemá odkud. Do #533 ten literál
    /// stál ve view vedle registrace; přestěhoval se sem, protože se **patka mění podle úrovně**,
    /// a to je rozhodnutí. Kdo tu klávesu ve view změní, musí změnit i tenhle řádek.
    ///
    /// **Podle úrovně, ne podle vybraného řádku** (návrh, s09link): klávesy jsou vlastnost karty.
    /// Proto tady zůstává `↵ otevřít` i v první úrovni, kde je pod kurzorem řádek repozitáře
    /// a `↵` na něm otevře **seznam** — zákres to v úzkém výřezu kreslí jako `↵ do repa`, ale to
    /// by znamenalo patku, která se mění pod rukou při každé šipce. Že se vchází do repa, říká
    /// **řádek** (značka a podtitulek), ne patka.
    static func paletteHints(at level: CommandPalette.Level) -> [CommandPalette.Hint] {
        var hints = [CommandPalette.Hint(key: "↑↓", what: "pohyb")]
        switch level {
        case .top:
            hints.append(CommandPalette.Hint(key: "↵", what: "otevřít"))
        // **„ke čtení“ je tvrzení, ne zdvořilost**: PR z repa mimo zdroje se otevře jako záložka
        // bez fronty, karet a automatu (#531), a tohle je jediné místo, kde se to dá říct dřív,
        // než se klikne.
        case .repository:
            hints.append(CommandPalette.Hint(key: "↵", what: "otevřít ke čtení"))
        }
        hints.append(CommandPalette.Hint(key: "⌘↵", what: "otevřít na GitHubu"))
        hints.append(
            CommandPalette.Hint(
                key: "esc",
                what: level.repository == nil ? "zavřít" : "o úroveň zpět"
            )
        )
        return hints
    }

    /// Věta o tom, že se seznam tahá nebo že se nepovedl.
    private static func paletteNotice(
        of repository: CommandPalette.RepositoryPullRequests?
    ) -> CommandPalette.Notice? {
        switch repository {
        case .loading: .loading("Dotahují se otevřené pull requesty…")
        case .failed(let reason): .failed(reason)
        case .loaded, nil: nil
        }
    }

    // MARK: - Klávesy, které mění úroveň

    /// Vrací `⌫` o úroveň zpět?
    ///
    /// **Jen na prázdném poli, a je to podmínka, ne pohodlí.** Zkratka na `⌫` platí pro celé okno
    /// (viz `HiddenShortcuts`), takže nad neprázdným polem by **přebila mazání znaků** — psát by
    /// v paletě přestalo jít. Tlačítko se proto vůbec nesmí objevit, dokud je v poli text; to je
    /// ten důvod, proč se tady rozhoduje podle dotazu, a ne až v akci.
    static func paletteBackspaceGoesBack(level: CommandPalette.Level, query: String) -> Bool {
        level.repository != nil && query.isEmpty
    }

    /// Zavře se paleta po vykonání tohohle řádku?
    ///
    /// **Jedna výjimka, a je to celé pravidlo**: vstup do repa paletu nechává otevřenou, protože
    /// je to půlka jednoho hmatu — napsat repo, vybrat PR. Všechno ostatní kartu zavírá, i akce,
    /// po které okno zůstane, jak bylo (#184).
    static func paletteClosesAfter(_ target: CommandPalette.Target) -> Bool {
        switch target {
        case .repository: false
        case .finding, .file, .pullRequest, .action: true
        }
    }

    // MARK: - Řádky repozitářů (první úroveň)

    /// Řádky skupiny `Repozitáře` pro dotaz (#533).
    ///
    /// **Filtruje se dřív, než se skládají řádky**, a je to ta podstatná věc na téhle funkci:
    /// organizace `keboola` má přes tisíc rep a katalog se v paletě prochází **při každém úhozu**.
    /// Skládat pro všechna repa podtitulek (množné číslo plus relativní čas) by znamenalo tisíc
    /// formátování na stisk klávesy — tedy zrovna ta třída práce, kterou stačí udělat pro šest
    /// řádků, které se vejdou.
    ///
    /// **Hledá se v `owner/name`, ne v podtitulku.** Váha se počítá `pickerRank`em nad tímtéž
    /// textem, jaký bude v titulku, takže druhý průchod v `paletteResults` vydá totéž pořadí
    /// a strop neuřízne řádek, který by se pak vytáhl nahoru. Že se `7 otevřených PR` nedá hledat,
    /// je záměr: `otevřených` sedí na každý řádek a nerozlišuje nic.
    ///
    /// **Řadí se podle počtu otevřených PR, ne podle jména ani stáří** (a zákres to tak kreslí:
    /// `keboola/vault` 7, `vault-cli` 2, `php-vault-client` 0). Je to nabídka, **kam jít**, takže
    /// nahoru patří repo, ve kterém je co číst; repo bez otevřených PR je ten řádek, po kterém
    /// druhá úroveň zůstane prázdná. Při shodě rozhoduje poslední push a pak jméno — dvě kritéria
    /// navíc, aby pořadí nezáviselo na tom, jak `gh` seznam vydal.
    /// - Parameter repositories: repa všech organizací za sebou. **Sekvence, ne pole**, aby se
    ///   snímky daly předat líně (`lazy.flatMap`) — jinak by se při každém úhozu kopírovalo přes
    ///   tisíc struktur do mezipole, které se stejně zahodí. Prochází se **jednou**.
    static func paletteRepositories(
        _ repositories: some Sequence<OrganizationRepository>,
        query: String,
        limit: Int = paletteGroupLimit,
        now: Date
    ) -> [CommandPalette.Item] {
        let matched = repositories.compactMap { repository -> (OrganizationRepository, Int)? in
            guard let rank = pickerRank(of: repository.repo.description, query: query) else {
                return nil
            }
            return (repository, rank)
        }
        let ordered = matched
            .sorted { one, other in
                if one.1 != other.1 { return one.1 < other.1 }
                return isBeforeInPalette(one.0, other.0)
            }
            .prefix(limit)
        let formatter = momentAgoFormatter()
        return ordered.map { repository, _ in
            CommandPalette.Item(
                id: "repo:\(repository.repo)",
                group: .repositories,
                title: repository.repo.description,
                subtitle: paletteRepositorySubtitle(repository, now: now, formatter: formatter),
                mark: .repository,
                // `/pulls`, ne přehled repa: `⌘↵` má otevřít to, co je v řádku napsané, tedy
                // seznam otevřených PR — je to tatáž úvaha jako `/files` u řádku souboru.
                url: githubPullsURL(of: repository.repo),
                target: .repository(repository.repo)
            )
        }
    }

    /// Pořadí dvou rep při shodné váze shody: víc otevřených PR, pak novější push, pak jméno.
    private static func isBeforeInPalette(
        _ one: OrganizationRepository,
        _ other: OrganizationRepository
    ) -> Bool {
        if one.openPullRequests != other.openPullRequests {
            return one.openPullRequests > other.openPullRequests
        }
        // Prázdné repo (`lastPushedAt == nil`) padá na konec — `distantPast` je tady odpověď
        // „nevím o žádném pushi“, ne vymyšlené datum: rozhoduje jedině pořadí.
        let onePush = one.lastPushedAt ?? .distantPast
        let otherPush = other.lastPushedAt ?? .distantPast
        if onePush != otherPush { return onePush > otherPush }
        return one.repo.description < other.repo.description
    }

    /// `7 otevřených PR · naposledy před hodinou`, jak to má návrh.
    ///
    /// **Nula je slovo, ne číslice**: `0 otevřených PR` se v řádku čte jako počet, který se
    /// nepodařilo spočítat, kdežto `bez otevřených PR` je tvrzení. Je to tentýž důvod, kvůli
    /// kterému `paletteSubtitle(of file:)` píše u binárky slovo místo nul.
    ///
    /// **Chybějící razítko pushe se vynechá celé** (prázdné repo, `gh` u něj `pushedAt` nemá) —
    /// `naposledy nikdy` by tvrdilo víc, než co data unesou.
    private static func paletteRepositorySubtitle(
        _ repository: OrganizationRepository,
        now: Date,
        formatter: RelativeDateTimeFormatter
    ) -> String {
        var parts = [
            repository.openPullRequests == 0
                ? "bez otevřených PR"
                : Plural.czech(
                    repository.openPullRequests,
                    one: "otevřený PR",
                    few: "otevřené PR",
                    many: "otevřených PR"
                ),
        ]
        if let pushed = repository.lastPushedAt {
            parts.append("naposledy \(formatter.localizedString(for: pushed, relativeTo: now))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Řádky otevřených PR (druhá úroveň)

    /// Řádky druhé úrovně — otevřené PR repa **podle poslední změny** (#533).
    ///
    /// Řazení je tady, protože `gh pr list` vrací PR podle **čísla** (změřeno, viz
    /// `GitHubGateway.pullRequests(in:)`). Při shodném razítku rozhoduje vyšší číslo, aby pořadí
    /// nezáviselo na tom, v jakém pořadí odpověď přišla.
    ///
    /// **Skládá se celý seznam, ne jen to, co se vejde** — na rozdíl od rep. Je to obsah celé
    /// úrovně, ne jedna skupina z šesti, takže se nemá čím zúžit: strop je `gh --limit`, tedy
    /// stovka, a přes ni se scrolluje.
    ///
    /// - Parameters:
    ///   - mine: moje loginy (`AppStore.ownLogins`) — z nich se pozná odznak `moje`.
    ///   - sources: identifikátory PR ze zdrojů, tedy to, co je ve frontě (#4).
    static func paletteRepositoryPullRequests(
        _ pullRequests: [PullRequestSummary],
        mine: Set<String> = [],
        sources: Set<PRIdentifier> = [],
        now: Date
    ) -> [CommandPalette.Item] {
        let formatter = momentAgoFormatter()
        return pullRequests
            .sorted { one, other in
                if one.updatedAt != other.updatedAt { return one.updatedAt > other.updatedAt }
                return one.id.number > other.id.number
            }
            .map { summary in
                CommandPalette.Item(
                    id: "repo-pr:\(summary.id)",
                    group: .repositoryPullRequests,
                    // Číslo **před** titulkem a `verbatim` až ve view: `#91` je to, čím se řádek
                    // pozná, a hledá se podle něj — proto je v titulku, ne v podtitulku.
                    title: "#\(summary.id.number) · \(summary.title)",
                    subtitle: paletteRepositoryPullRequestSubtitle(
                        summary,
                        now: now,
                        formatter: formatter
                    ),
                    mark: .pullRequest(summary.state),
                    url: summary.url,
                    // **Bez klíčových slov, a je to tentýž důvod jako u souborů**: všechny řádky
                    // jsou z jednoho repa, takže shoda na jeho jméno by vytáhla celý seznam a nic
                    // by mezi řádky nerozlišila.
                    badge: paletteBadge(of: summary, mine: mine, sources: sources),
                    target: .pullRequest(summary.id)
                )
            }
    }

    /// `odinuv · před 2 hodinami`, u rozpracovaného PR ještě `· draft`.
    ///
    /// **`draft` je slovo, ne jen odstín značky** — tatáž úvaha jako v řádku seznamu PR: tvar
    /// značky je u otevřeného a rozpracovaného PR tentýž, takže rozdíl nese jedině barva a ta
    /// sama nestačí.
    ///
    /// **Ostatní stavy se nepíšou**, protože se dotahují jen otevřené PR: `zavřený` ani `mergnutý`
    /// se v tom seznamu nemá kde vzít, a napsat je „pro úplnost“ by znamenalo slovo, které nikdy
    /// nikdo neuvidí.
    private static func paletteRepositoryPullRequestSubtitle(
        _ summary: PullRequestSummary,
        now: Date,
        formatter: RelativeDateTimeFormatter
    ) -> String {
        var parts = [
            summary.author,
            formatter.localizedString(for: summary.updatedAt, relativeTo: now),
        ]
        if summary.state == .draft { parts.append("draft") }
        return parts.joined(separator: " · ")
    }

    /// Odznak řádku v druhé úrovni — `moje`, `ve frontě`, nebo nic.
    ///
    /// **`moje` má přednost, a není to volba mezi dvěma pravdami.** Fronta je od #332 množina
    /// **cizích** PR, takže vlastní PR ve frontě není, i kdyby si ho člověk přitáhl zdrojem —
    /// `ve frontě` u vlastního PR by tvrdilo, že se na něj čeká review ode mě.
    static func paletteBadge(
        of summary: PullRequestSummary,
        mine: Set<String>,
        sources: Set<PRIdentifier>
    ) -> CommandPalette.Badge? {
        if ownership(of: summary, mine: mine) == .mine { return .mine }
        return sources.contains(summary.id) ? .inQueue : nil
    }
}
