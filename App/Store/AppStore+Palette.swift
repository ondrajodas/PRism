import Foundation

/// Command palette ⌘K (#184): co se v ní dá najít a co se stane po `↵`.
///
/// **Psaní v poli nestahuje nic.** Katalog se skládá z toho, co store **už má** — nálezy
/// z uložených záznamů, soubory z načteného diffu, pull requesty z posledního tiku a repozitáře
/// ze snímků, které leží v cache na disku (#533). Je na to test, který po vykonání každého cíle
/// i po každém úhozu kontroluje, že gateway nedostala ani jedno volání navíc.
///
/// **Jedna výjimka, a je za výslovné `↵`** (#533): vstup do repa dotáhne jeho **otevřené** pull
/// requesty (`enterPaletteRepository(_:)`). Je to jediné volání, které paleta pouští, je to
/// čtení (`GitHubGateway` zápisové metody nemá) a nespouští ho psaní ani otevření palety.
///
/// **A nic odsud neodchází.** Ve `CommandPalette.Action` není nic, co by sahalo na jedinou cestu
/// ven (`App/Publish/`, tvrdá podmínka č. 1) — paleta přepíná pohled, otevírá záložky a pouští
/// read-only reviewer. Schválně to tady není napsané jménem toho protokolu: grep, kterým se ta
/// podmínka kontroluje, má vypsat **místa, odkud se odesílá**, ne komentáře o tom, že se odsud ne.
extension AppStore {
    // MARK: - Otevření

    func openPalette() { isPaletteOpen = true }

    /// Zavře paletu **a vrátí ji do první úrovně** (#533).
    ///
    /// Úroveň zaniká se zavřením ze stejného důvodu jako dotaz a kurzor: ⌘K je „začínám hledat“,
    /// takže se nikdo nemá vracet do repa, do kterého vešel před minutou a zapomněl na něj. Dotažený
    /// seznam se zahazuje s ní — kdyby zůstal, ukazoval by po ⌘K PR, o které se nikdo neptal.
    func closePalette() {
        isPaletteOpen = false
        leavePaletteRepository()
    }

    /// Přepnutí pro ⌘K: druhé zmáčknutí paletu zavře, protože stejná klávesa má vrátit okno
    /// tam, kde bylo.
    func togglePalette() {
        if isPaletteOpen {
            closePalette()
        } else {
            openPalette()
        }
    }

    // MARK: - Úrovně (#533)

    /// Vejde do repa — druhá úroveň palety, tedy jeho **otevřené** pull requesty.
    ///
    /// Seznam se dotahuje **při vstupu**, ne při psaní (návrh pozn. 60): je to jediné volání, které
    /// paleta pouští, a je za výslovné `↵`. Záložka se odsud neotvírá — na to je `↵` v druhé
    /// úrovni.
    ///
    /// **Stav `.loading` se nasazuje hned**, ne až v tasku: mezi klikem a prvním `await` by karta
    /// jinak nakreslila prázdnou úroveň, tedy „repo nemá otevřené PR“ nad repem, kterého se nikdo
    /// nezeptal. Je to tatáž úvaha jako u záložky mimo zdroje (#531).
    func enterPaletteRepository(_ repo: RepoID) {
        // **Druhé `↵` na tomtéž repu se neptá znovu** — je to tatáž ochrana, kterou u #531 našel
        // Copilot na dvou `↵` nad řádkem `Odkaz`: dva pokusy o totéž by byly dva podprocesy `gh`
        // a dva zápisy do jednoho stavu. Že už paleta v tom repu stojí, znamená „tahá se, nebo se
        // dotáhlo“, a ani jedno není důvod se ptát podruhé; odchod z úrovně (`esc`, `⌫`) stav
        // zahodí, takže nový vstup se zeptá.
        guard paletteLevel != .repository(repo) else { return }
        paletteLevel = .repository(repo)
        paletteRepository = .loading
        Task { await loadPaletteRepository(repo) }
    }

    /// O úroveň zpět — `esc` a `⌫` na prázdném poli.
    ///
    /// **Zahodí i dotažený seznam.** Zpátky do téhož repa se vchází novým `↵`, a to se zeptá znovu:
    /// mezitím mohl přijít nový PR a starý seznam by o něm mlčel. Stojí to jedno volání za vstup,
    /// tedy přesně tolik, kolik za něj platil první vstup.
    func leavePaletteRepository() {
        paletteLevel = .top
        paletteRepository = nil
    }

    /// Dotáhne otevřené PR repa. Volá se **jedině** z `enterPaletteRepository(_:)`.
    ///
    /// **Odpověď se zahodí, když už paleta v tom repu nestojí** — mezi dotazem a odpovědí je
    /// sekunda, ve které se dá zmáčknout `esc` nebo vejít do jiného repa; zápis by pak nakreslil
    /// cizí seznam pod chipem, který mluví o něčem jiném. Je to tatáž ochrana jako u zavřené
    /// záložky v `loadExternalDetail(of:)` (#531).
    private func loadPaletteRepository(_ repo: RepoID) async {
        let outcome: CommandPalette.RepositoryPullRequests
        do {
            outcome = .loaded(try await gateway.pullRequests(in: repo))
        } catch is CancellationError {
            outcome = .failed("Dotažení se zrušilo.")
        } catch let error as GitHubError {
            outcome = .failed(error.userDescription)
        } catch {
            outcome = .failed(error.localizedDescription)
        }
        // **Jeden guard na všechny cesty**, ne po jednom v každé větvi: na nové cestě ven se dá
        // zapomenout, a chybějící kontrola se pozná jedině tím, že se v kartě objeví cizí seznam.
        guard paletteLevel == .repository(repo) else { return }
        paletteRepository = outcome
    }

    /// Přečte z cache seznamy repozitářů organizací z nastavení (#533).
    ///
    /// **Jen disk.** `RepositoryCatalog.load(organizations:)` se na GitHub neptá — dotahuje
    /// `refresh` a `refreshStale`, a ty pouští jedině okno nastavení. Volá se při startu
    /// (`keepFresh()`) a po změně konfigurace, protože dopsaná organizace může mít snímek v cache
    /// z předchozího spuštění.
    func loadRepositoryCatalog() async {
        guard let repositoryCatalog else { return }
        await repositoryCatalog.load(
            organizations: configuration.global.searchOrganizations
        )
    }

    // MARK: - Katalog

    /// Co paleta prohledává. Skládá se při každém stisku klávesy, a to schválně: snímek pořízený
    /// při otevření by za pár sekund ukazoval nálezy z review, které mezitím doběhlo.
    ///
    /// Čte se **plný** seznam PR (`pullRequests`), ne zúžený filtrem: filtr je zúžení *seznamu*,
    /// kdežto paleta je způsob, jak něco **najít** — a hledání, ze kterého vypadne PR schované
    /// filtrem, je k nepotřebě právě tehdy, když je filtr zapnutý. Nic se tím neriskuje, protože
    /// paleta jen čte; úklid cache visí na `pullRequests` dál a ten se odsud nespouští.
    ///
    /// **Repozitáře tady nejsou, a je to schválně** (#533): jejich řádky se skládají **až pro
    /// dotaz**, protože katalog má nad velkou organizací přes tisíc položek a podtitulek každého
    /// z nich stojí formátování času. Přidává je `paletteSections(for:)`, kde je dotaz po ruce.
    var paletteItems: [CommandPalette.Item] {
        let open = activeTab.pullRequest
        return paletteFindings(open: open)
            + paletteFiles(of: open)
            + palettePullRequests()
            + Policy.paletteActions(
                open: open,
                isReviewing: open.map(isReviewing) ?? false,
                hasRun: open.flatMap { reviewRecords[$0] } != nil,
                layout: diffLayout,
                isPanelExpanded: palettePanelExpansion(open: open),
                section: railSection
            )
    }

    /// Rozložení panelu pro paletu — `nil` v tabech, kde panel v okně **není** (#294).
    ///
    /// Uložený stav se přitom nemění: panel zůstává rozložený i tehdy, když se v otevřeném tabu
    /// nekreslí, takže se po přepnutí zpátky najde tak, jak se nechal. Nabídnout ho k přepnutí ale
    /// nejde — z klávesnice by se tím přestavěl tab, do kterého se člověk vrátí, a v okně by po tom
    /// nezůstala žádná stopa.
    private func palettePanelExpansion(open: PRIdentifier?) -> Bool? {
        guard let open, detailTab(for: open).showsReviewPanel else { return nil }
        return isReviewPanelExpanded
    }

    /// Nálezy **ze všech PR**, ne jen z otevřeného: nález je to jediné, co tahle aplikace má
    /// a prohlížeč ne, takže hledat ho jen v jednom PR by z první skupiny udělalo tu nejužší.
    ///
    /// Odmítnuté (#113) se nenabízejí — nález, kterému nevěřím, není místo, kam chci skočit.
    private func paletteFindings(open: PRIdentifier?) -> [CommandPalette.Item] {
        paletteOrder(open: open).flatMap { pr -> [CommandPalette.Item] in
            guard let record = reviewRecords[pr] else { return [] }
            let categories = resolved(for: pr.repo).blockingCategories
            return Policy.sorted(record.activeFindings, categories: categories)
                .enumerated()
                .map { index, finding in
                    paletteItem(
                        of: finding,
                        index: index,
                        in: pr,
                        isBlocking: Policy.isBlocking(finding, categories: categories)
                    )
                }
        }
    }

    /// V jakém pořadí se prohledávají nálezy podle PR: otevřený první, pak seznam z pollingu.
    ///
    /// Bez tohohle by se iterovalo přes `reviewRecords`, a to je **slovník** — pořadí výsledků
    /// by se měnilo mezi stisky klávesy a řádky by pod rukou poskakovaly.
    private func paletteOrder(open: PRIdentifier?) -> [PRIdentifier] {
        var seen: Set<PRIdentifier> = []
        var order: [PRIdentifier] = []
        for pr in [open].compactMap({ $0 }) + pullRequests.map(\.id) where seen.insert(pr).inserted {
            order.append(pr)
        }
        return order
    }

    private func paletteItem(
        of finding: Finding,
        index: Int,
        in pr: PRIdentifier,
        isBlocking: Bool
    ) -> CommandPalette.Item {
        // Krátké shrnutí, když ho reviewer napsal — řádek palety je jednořádkový, takže celá
        // věta o třech řádcích by se v něm oříznula uprostřed. `singleLine` proto, že i to
        // krátké je cizí text a jeden `\n` v něm by řádek rozhodil.
        let title = (finding.shortSummary ?? finding.summary).singleLine
        return CommandPalette.Item(
            // Index, ne `Policy.key(of:)`: klíč se skládá z revieweera, místa a shrnutí, takže
            // se **umí zopakovat** (týž reviewer nahlásí totéž dvakrát). Dva řádky s jedním `id`
            // by SwiftUI slil do jednoho a zmizel by nález, který se v paletě zrovna hledá.
            id: "finding:\(pr):\(index)",
            group: .findings,
            title: title,
            subtitle: paletteSubtitle(of: finding, in: pr),
            mark: isBlocking ? .blockingFinding : .finding,
            url: paletteURL(of: pr),
            // Celá cesta a reviewer se do podtitulku nevejdou (je v něm jen jméno souboru),
            // ale hledat se podle nich musí dát — `SecretClient.php` je v `src/Vault/…`. Repo
            // je v podtitulku (`vault#85`), tady je kvůli vlastníkovi (`keboola/vault`).
            //
            // **Autor PR tu není** schválně: v řádku nálezu žádné jméno vidět není, a to jediné,
            // které k němu patří, je jméno revieweera. Shoda na autora by tedy vytáhla nález,
            // ve kterém se to jméno nikde nevyskytuje.
            keywords: [finding.file, finding.reviewer, pr.repo.description].compactMap { $0 },
            target: .finding(pr, file: finding.file, line: finding.line)
        )
    }

    /// `vault#85 · SecretClient.php:81`, jak to má návrh. Jméno souboru, ne celá cesta: řádek
    /// nese hlavně shrnutí a dlouhá cesta by ho vytlačila.
    private func paletteSubtitle(of finding: Finding, in pr: PRIdentifier) -> String {
        var parts = [Policy.paletteLabel(of: pr)]
        if let file = finding.file {
            let name = file.split(separator: "/").last.map(String.init) ?? file
            parts.append(finding.line.map { "\(name):\($0)" } ?? name)
        }
        return parts.joined(separator: " · ")
    }

    /// Soubory **jen z otevřeného PR**: diff jiného PR v paměti není a dotáhnout si ho by byl
    /// ten nový dotaz na GitHub, který zadání zakazuje.
    ///
    /// **Podle repa se soubory nehledají**, i když z nějakého repa samozřejmě jsou. Jsou všechny
    /// z jednoho otevřeného PR, takže shoda na jméno repa by je vytáhla **všechny naráz** a nic by
    /// mezi nimi nerozlišila — a v podtitulku je diffstat, takže by z řádku nebylo poznat, proč
    /// vyšel. U nálezu a u PR je to naopak: repo v podtitulku vidět je.
    private func paletteFiles(of open: PRIdentifier?) -> [CommandPalette.Item] {
        guard let open, let diff = loadedDiff(for: open) else { return [] }
        return diff.files.map { file in
            CommandPalette.Item(
                id: "file:\(open):\(file.id)",
                group: .files,
                title: file.displayPath,
                subtitle: paletteSubtitle(of: file),
                mark: .file,
                // `/files` je ta stránka, na které soubor na GitHubu doopravdy je — odkaz na
                // přehled PR by po `⌘↵` skončil jinde, než co je v řádku napsané.
                url: paletteURL(of: open)?.appending(path: "files"),
                // Přejmenovaný soubor se má najít i pod starým jménem — v titulku je jen to nové.
                keywords: [file.oldPath].compactMap { $0 },
                target: .file(open, path: file.displayPath)
            )
        }
    }

    /// `+18 −6`, u binárky slovo — nuly by tvrdily, že soubor nic nemění, a přitom se jen
    /// nedá spočítat.
    private func paletteSubtitle(of file: FileDiff) -> String? {
        if file.isBinary { return "binárka" }
        var parts: [String] = []
        if file.additions > 0 { parts.append("+\(file.additions)") }
        if file.deletions > 0 { parts.append("−\(file.deletions)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Pull requesty — **rozřazené podle autora do dvou skupin** (#336).
    ///
    /// Rozhoduje `Policy.ownership`, tedy tatáž funkce jako v railu a na dashboardu; množina loginů
    /// se bere **jednou pro celý seznam**, ne u každého řádku (`ownLogins` se počítá při každém
    /// čtení).
    ///
    /// **Zařazení padá tady, seskupení až v `Policy.paletteResults`.** Katalog je jeden plochý
    /// seznam, ve kterém si každý řádek nese svou `group`; hledání pak podle ní seskupuje a řeže na
    /// strop. Proto stačí **jeden průchod** — skládat dva seznamy za sebou (`filter` na moje
    /// a `filter` na cizí) by jen zopakovalo tutéž otázku dvakrát a ty dvě odpovědi by se mohly
    /// rozejít v tom, co je „moje“.
    ///
    /// **Cíl zůstává `Target.pullRequest`** — skupina je zařazení, ne druhá cesta k témuž;
    /// po `↵` se v obou případech otevírá tatáž záložka.
    private func palettePullRequests() -> [CommandPalette.Item] {
        let mine = ownLogins
        return pullRequests.map { summary in
            CommandPalette.Item(
                id: "pr:\(summary.id)",
                group: Policy.ownership(of: summary, mine: mine) == .mine ? .myPullRequests : .pullRequests,
                title: summary.title,
                subtitle: paletteSubtitle(of: summary),
                mark: .pullRequest(summary.state),
                url: summary.url,
                // Vlastník repa je jen tady: v podtitulku je `vault#85`, ne `keboola/vault`.
                keywords: [summary.id.repo.description],
                target: .pullRequest(summary.id)
            )
        }
    }

    /// `connection#21663 · sykora-ji` — souřadnice a **autor**.
    ///
    /// Autor je v podtitulku, ne v klíčových slovech (do #184 byl tam): hledat podle jména se musí
    /// dát, ale klíčové slovo se nikde nekreslí, takže by u dotazu na jméno nebylo z řádku poznat,
    /// proč vyšel. Bere se z `PullRequestSummary`, tedy z posledního tiku — žádný nový dotaz.
    ///
    /// **Ve skupině `Moje PR` zůstává týž tvar** (#336), i když návrh tam kreslí `PRism#324 ·
    /// 6 k předání`: ten počet se dá napsat, teprve až předání nese razítko (#334) — do té doby by
    /// šlo o číslo, které nikdo nepředal. Je to tatáž úvaha, kterou u řádku seznamu zapsalo #331.
    /// Autor v tom podtitulku navíc není zbytečný: „moje“ je od #330 **množina** loginů, takže se
    /// z něj pozná PR, který pod svým účtem otevřel agent.
    private func paletteSubtitle(of summary: PullRequestSummary) -> String {
        "\(Policy.paletteLabel(of: summary.id)) · \(summary.author)"
    }

    /// Adresa PR z posledního tiku, jinak ze snímku otevřené záložky. `nil` = o tomhle PR
    /// nevíme ani tolik, takže `⌘↵` nemá kam vést.
    private func paletteURL(of pr: PRIdentifier) -> URL? {
        (summary(for: pr) ?? openTabSnapshots[pr])?.url
    }

    // MARK: - Vložený odkaz (#531)

    /// Výsledky pro dotaz — katalog z paměti a k tomu **řádek `Odkaz`**, když je v poli adresa PR.
    ///
    /// Skládá se to tady, ne ve view: rozhodnutí „tohle je adresa“ dělá `Policy` a „je ten PR ve
    /// zdrojích?“ umí zodpovědět jedině store. Ve `CommandPaletteView` by z toho byla dvě `if`
    /// nad výsledky, tedy přesně to, co v něm být nemá.
    ///
    /// **Pořád se nic nestahuje.** Řádek se skládá z identifikátoru, ne z dotazu na GitHub — co
    /// je to za PR, se zjistí až po `↵`, když se otevře záložka.
    /// Výsledky pro dotaz — **podle úrovně, ve které paleta stojí** (#533).
    ///
    /// Je to jediné místo, kde se to skládá: do #533 to view počítalo ještě jednou samo
    /// (`Policy.paletteResults` nad předanými položkami), takže na jednu otázku byly dvě odpovědi
    /// a druhá úroveň by musela vzniknout v obou.
    func paletteSections(for query: String) -> [CommandPalette.Section] {
        switch paletteLevel {
        case .top:
            return Policy.paletteResults(
                of: paletteItems + paletteRepositoryRows(for: query),
                query: query,
                link: paletteLink(for: query),
                organizations: paletteSearchedOrganizations
            )
        case .repository:
            return paletteRepositorySections(for: query)
        }
    }

    /// Jak paleta vypadá okolo výsledků — chip, výzva, patka, věta o dotahování.
    var paletteStage: CommandPalette.Stage {
        Policy.paletteStage(level: paletteLevel, repository: paletteRepository)
    }

    // MARK: - Repozitáře v paletě (#533)

    /// Řádky skupiny `Repozitáře` pro dotaz — **z cache, bez jediného dotazu na GitHub**.
    ///
    /// Snímky se berou v pořadí organizací z nastavení, takže při stejné váze shody rozhoduje
    /// pořadí, které si člověk poskládal sám (a pak pravidla z `Policy.paletteRepositories`).
    private func paletteRepositoryRows(for query: String) -> [CommandPalette.Item] {
        guard let repositoryCatalog else { return [] }
        // **Líně**, ne do mezipole: snímek `keboola` má přes tisíc rep a tohle se počítá při
        // každém úhozu — `Policy.paletteRepositories` sekvencí projde jednou a zahodí, co nesedí.
        let repositories = paletteSearchedOrganizations
            .lazy
            .compactMap { repositoryCatalog.snapshots[$0] }
            .flatMap(\.repositories)
        return Policy.paletteRepositories(repositories, query: query, now: time.now)
    }

    /// Organizace, ve kterých se doopravdy hledalo — ty z nastavení, které **mají snímek**.
    ///
    /// **Ne celý seznam z konfigurace**, a je to tvrzení, ne detail: nadpis skupiny ta jména
    /// vypisuje, takže organizace bez snímku by v něm slibovala, že se v ní hledalo — a přitom
    /// se ještě nikdy nedotáhla (nebo se nepovedla, což je vidět v nastavení).
    private var paletteSearchedOrganizations: [String] {
        guard let repositoryCatalog else { return [] }
        return Policy.searchOrganizations(in: configuration)
            .filter { repositoryCatalog.snapshots[$0] != nil }
    }

    /// Výsledky druhé úrovně. Prázdno, dokud seznam nedorazil — věta o dotahování je ve `Stage`.
    private func paletteRepositorySections(for query: String) -> [CommandPalette.Section] {
        guard case .loaded(let pullRequests) = paletteRepository else { return [] }
        let items = Policy.paletteRepositoryPullRequests(
            pullRequests,
            mine: ownLogins,
            // **Fronta jsou zdroje, ne otevřené záložky** (#4): odznak `ve frontě` má znamenat
            // „čeká to na mě“, kdežto `adoptedTabs` je „tohle jsem si otevřel ke čtení“.
            sources: Set(self.pullRequests.map(\.id)),
            now: time.now
        )
        return Policy.paletteRepositoryResults(
            of: items,
            query: query,
            total: pullRequests.count
        )
    }

    /// Řádek skupiny `Odkaz` pro dotaz. `nil` = v poli není adresa pull requestu.
    func paletteLink(for query: String) -> CommandPalette.Item? {
        guard let pr = Policy.linkedPullRequest(in: query) else { return nil }
        // `linkOrigin`, ne `origin(of:)`: řádek odkazu se ptá, jestli je ten PR **teď** ve
        // zdrojích, kdežto pilulka v hlavičce na to, odkud se vzala otevřená záložka. U PR,
        // o kterém store neví nic, se ty dvě odpovědi rozcházejí — a tady je správná
        // `není ve zdrojích`.
        return Policy.paletteLink(
            to: pr,
            origin: Policy.linkOrigin(of: pr, sources: Set(pullRequests.map(\.id)))
        )
    }

    // MARK: - Vykonání

    /// Vykoná to, na co se v paletě kliklo (nebo co se potvrdilo `↵`).
    ///
    /// Vrací, co zbývá na okno: `nil` znamená hotovo, `.openSettings` že si má volající otevřít
    /// scénu s nastavením. Store okno otevřít neumí a nemá si to ani pamatovat.
    @discardableResult
    func reveal(_ target: CommandPalette.Target) -> CommandPalette.Effect? {
        switch target {
        case .pullRequest(let pr):
            // **`openPullRequest`, ne `openTab`** (#531): tenhle cíl nese od #531 i řádek
            // `Odkaz`, tedy PR, o kterém store nemusí vědět nic. U PR ze seznamu je to totéž
            // volání jako dřív a nikdo se nikoho na nic neptá.
            openPullRequest(pr)
        // Vstup do repa (#533) — **jediný cíl, po kterém paleta zůstává otevřená**; rozhoduje
        // o tom `Policy.paletteClosesAfter(_:)` u volajícího, ne tenhle `switch`.
        case .repository(let repo):
            enterPaletteRepository(repo)
        case .file(let pr, let path):
            openTab(pr, in: .filesChanged)
            paletteJump = CommandPalette.Jump(pullRequest: pr, file: path, line: nil, kind: .file)
        case .finding(let pr, let file, let line):
            guard let file else {
                // Nález bez místa v kódu se nemá kam scrollovat. Tabulka v tabu `Nálezy` je
                // jediné místo, kde je vidět celý — a skok naslepo do diffu je horší než skok
                // tam, kde ten nález doopravdy je.
                openTab(pr, in: .findings)
                return nil
            }
            openTab(pr, in: .filesChanged)
            paletteJump = CommandPalette.Jump(pullRequest: pr, file: file, line: line, kind: .finding)
        case .action(let action):
            return perform(action)
        }
        return nil
    }

    private func perform(_ action: CommandPalette.Action) -> CommandPalette.Effect? {
        switch action {
        case .runReview(let pr):
            startReview(for: pr)
        case .cancelReview(let pr):
            cancelReview(for: pr)
        case .setDiffLayout(let layout):
            setDiffLayout(layout)
        case .setReviewPanel(let expanded):
            isReviewPanelExpanded = expanded
        case .openSection(let section):
            // Přes `show(_:)`, ne dvěma přiřazeními tady: od #371 sem chodí i karty dashboardu
            // a přepnutí na domácí záložku (bez něj by se nad otevřeným PR nestalo nic
            // viditelného) má být na jednom místě.
            show(section)
        case .refresh:
            Task { await refresh() }
        case .openSettings:
            return .openSettings
        }
        return nil
    }
}
