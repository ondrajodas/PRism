import Foundation

/// Command palette ⌘K (#184): co se v ní dá najít a co se stane po `↵`.
///
/// **Nic se odsud nestahuje.** Katalog se skládá z toho, co store **už má v paměti** — nálezy
/// z uložených záznamů, soubory z načteného diffu, pull requesty z posledního tiku. Žádný nový
/// dotaz na GitHub, jak říká zadání issue; je na to test, který po vykonání každého cíle
/// kontroluje, že gateway nedostala ani jedno volání navíc.
///
/// **A nic odsud neodchází.** Ve `CommandPalette.Action` není nic, co by sahalo na jedinou cestu
/// ven (`App/Publish/`, tvrdá podmínka č. 1) — paleta přepíná pohled, otevírá záložky a pouští
/// read-only reviewer. Schválně to tady není napsané jménem toho protokolu: grep, kterým se ta
/// podmínka kontroluje, má vypsat **místa, odkud se odesílá**, ne komentáře o tom, že se odsud ne.
extension AppStore {
    // MARK: - Otevření

    func openPalette() { isPaletteOpen = true }

    func closePalette() { isPaletteOpen = false }

    /// Přepnutí pro ⌘K: druhé zmáčknutí paletu zavře, protože stejná klávesa má vrátit okno
    /// tam, kde bylo.
    func togglePalette() { isPaletteOpen.toggle() }

    // MARK: - Katalog

    /// Co paleta prohledává. Skládá se při každém stisku klávesy, a to schválně: snímek pořízený
    /// při otevření by za pár sekund ukazoval nálezy z review, které mezitím doběhlo.
    ///
    /// Čte se **plný** seznam PR (`pullRequests`), ne zúžený filtrem: filtr je zúžení *seznamu*,
    /// kdežto paleta je způsob, jak něco **najít** — a hledání, ze kterého vypadne PR schované
    /// filtrem, je k nepotřebě právě tehdy, když je filtr zapnutý. Nic se tím neriskuje, protože
    /// paleta jen čte; úklid cache visí na `pullRequests` dál a ten se odsud nespouští.
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

    // MARK: - Vykonání

    /// Vykoná to, na co se v paletě kliklo (nebo co se potvrdilo `↵`).
    ///
    /// Vrací, co zbývá na okno: `nil` znamená hotovo, `.openSettings` že si má volající otevřít
    /// scénu s nastavením. Store okno otevřít neumí a nemá si to ani pamatovat.
    @discardableResult
    func reveal(_ target: CommandPalette.Target) -> CommandPalette.Effect? {
        switch target {
        case .pullRequest(let pr):
            openTab(pr)
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
