import Foundation

/// Detail PR a jeho záložky.
///
/// Detail se dotahuje **při výběru řádku**, ne pollingem: pro všech N PR by to byla tatáž
/// N+1 past, kvůli které se netahá konverzace.
extension AppStore {
    /// Který tab je vidět. Výchozí drží `PullRequestTab.standard`, ať je odpověď na jednom
    /// místě — čte ji i test, který hlídá, že se to nerozejde.
    ///
    /// **Nezarovnává se na data** (#306). Do #306 tu bylo zarovnání na `Policy.tabs(hasChecks:)`,
    /// protože se `Kontroly` u PR bez CI nekreslily a uložená volba na ně nesměla ukazovat — bez
    /// zarovnání by v okně nesvítila žádná záložka a plocha tabu by zůstala prázdná. Ta záložka je
    /// od #306 v pruhu vždycky, takže zarovnání ztratilo předmět; s ním odpadl i jeho vedlejší
    /// účinek, kvůli kterému se volba schválně **nemazala**: člověk z tabu `Kontroly` vypadával
    /// při každém příchodu na PR, dokud checky nedorazily (dotahují se s detailem, takže chvíli
    /// nejsou). Zůstalo z toho pravidlo, ne úklid — volba je odpověď na „kam se koukám“ a ta se
    /// nesmí měnit tím, co zrovna dorazilo ze sítě.
    func detailTab(for pr: PRIdentifier) -> PullRequestTab {
        detailTabs[pr] ?? .standard
    }

    func setDetailTab(_ tab: PullRequestTab, for pr: PRIdentifier) {
        // Výchozí volba se z mapy maže, ať v ní nezůstávají klíče bez informace.
        detailTabs[pr] = tab == .standard ? nil : tab
    }

    /// Co je v tabu `Kontroly` k vidění (#306).
    ///
    /// Skládá se **ve store, ne ve view**: čtou to dvě místa — odznak v pruhu záložek a plocha
    /// tabu — a obě mapy, ze kterých se to skládá, drží store. Dvě různá skládání by znamenala
    /// odznak, který mluví o jiném stavu než plocha pod ním.
    func checksTabState(for pr: PRIdentifier) -> ChecksTabState {
        Policy.checksTab(checks: checks[pr], failure: checkFailures[pr])
    }

    func detailState(for pr: PRIdentifier) -> DetailState? { detailStates[pr] }

    /// Ukáže rozdělané review v panelu — přepne na jeho tab, **rozloží složený panel** a od #294
    /// si i **přepne do tabu, ve kterém panel vůbec je**.
    ///
    /// Tudy chodí všechno, co do těla review něco doručí (#242). Do té doby stačilo přepnout tab
    /// panelu, protože nálezy měly v panelu vlastní; po přidání záložky `Nálezy` se ale panel dá
    /// složit a rozepsaná věta by spadla za proužek na hraně okna, tedy tam, kde ji nikdo nehledá.
    ///
    /// **Třetí krok přidala #294**, která panel v `Kontrolách`, `Nálezech` a `Průběhu` schovává
    /// celý. Bez něj by `Převzít` v tabu `Nálezy` neudělalo nic viditelného — a to je horší než
    /// složený panel: složený je vidět aspoň jako proužek. Cílem je `PullRequestTab.standard`,
    /// protože panel je v každém povoleném tabu tentýž, a `Přehled` je ten, který nepotřebuje
    /// načtený diff. Je to tatáž úvaha jako u skoku na nález, který si přepne do diffu:
    /// **přepnout tab je správnější než kliknutí ignorovat.**
    ///
    /// Z tabu, kde panel je, se **nepřepíná nikam** — jinak by převzetí nálezu v diffu člověka
    /// vyhodilo z kódu, který zrovna čte.
    ///
    /// **Na vlastním PR z toho vyjde tab se zadáním** (#333): `Moje review` tam v panelu není,
    /// takže by se přepínalo na segment, který se nekreslí — a panel by zůstal na `Nálezech`, tedy
    /// jinde, než kam text spadl. Překlad dělá `Policy`, aby na tu otázku byla jedna odpověď.
    func revealDraft(in pr: PRIdentifier) {
        reviewPanelTab = Policy.reviewPanelTab(.draft, for: ownership(of: pr))
        isReviewPanelExpanded = true
        guard !detailTab(for: pr).showsReviewPanel else { return }
        setDetailTab(.standard, for: pr)
    }

    /// Popis PR, jak ho napsal autor. `nil` = detail se ještě nenačetl.
    func description(of pr: PRIdentifier) -> String? {
        guard case .loaded(let detail, _) = detailStates[pr] else { return nil }
        return detail.body
    }

    /// Hlava PR, jak ji naposledy vrátil `gh pr view`. `nil` = ještě nevíme.
    ///
    /// Na tom visí dvě věci: proti čemu se zakládá nový draft a jestli je ten stávající
    /// zastaralý. „Nevím“ se přitom nesmí splést se „zastaralé“ — proto optional a ne
    /// prázdný řetězec.
    func head(of pr: PRIdentifier) -> String? {
        guard case .loaded(let detail, _) = detailStates[pr] else { return nil }
        return detail.headSha
    }

    /// Dotáhne detail vybraného PR. Načtený se drží, dokud se nezmění `updatedAt` — stejná
    /// cache jako u diffu.
    func loadDetail(for pullRequest: PullRequestSummary) async {
        let id = pullRequest.id
        guard !hasCurrentDetail(for: pullRequest) else {
            // Detail je z cache, ale o checcích **nemusíme vědět nic** (#306): `loadChecks` běží až
            // po něm, takže přepnutí PR uprostřed toho volání ho zruší — a zrušení se schválně
            // nezapisuje. Bez tohohle dotažení by v tabu `Kontroly` po návratu na PR svítilo
            // `Načítám kontroly…` navždycky, protože detail se už znovu nenačítá. Ptá se jedině
            // tehdy, když **není ani seznam, ani porucha**: obojí je hotová odpověď a přepisovat ji
            // při každém příchodu na PR by z checků udělalo polling.
            if checks[id] == nil, checkFailures[id] == nil { await loadChecks(for: id) }
            // Commity mají tentýž problém i tutéž odpověď (#316): `loadCommits` běží až po detailu,
            // takže se dá zrušit přepnutím PR — a bez tohohle dotažení by v tabu `Commity` po
            // návratu na PR svítilo `Načítám commity…` navždycky. Ptá se jedině tehdy, když **není
            // ani seznam, ani porucha**; obojí je hotová odpověď a přepisovat ji při každém příchodu
            // na PR by z commitů udělalo polling.
            if commits[id] == nil, commitFailures[id] == nil { await loadCommits(for: id) }
            return
        }
        detailStates[id] = .loading

        do {
            let detail = try await gateway.fetchDetail(id: id)
            detailStates[id] = .loaded(detail, updatedAt: pullRequest.updatedAt)
            // Hlavu si pamatuje i návštěva (#173): datum commitu na poznání nových commitů
            // nestačí, protože po rebase je starší než moje poslední návštěva.
            noteHead(detail.headSha, for: id)
        } catch is CancellationError {
            // Maže se **jen** rozdělaný stav: mezitím spuštěné načtení už mohlo doběhnout.
            if detailStates[id] == .loading { detailStates[id] = nil }
            // Odchod z obrazovky, ne porucha — a checky se pak nemají proč tahat.
            return
        } catch let error as GitHubError {
            detailStates[id] = .failed(error.userDescription)
        } catch {
            detailStates[id] = .failed(error.localizedDescription)
        }

        // Checky se tahají **s detailem** (#209), ne pollingem přes všechna PR: to je tatáž N+1
        // past, kvůli které se netahá ani detail.
        //
        // **I tehdy, když detail spadl** (#306). Do #306 byly uvnitř `do` bloku, protože se tab
        // `Kontroly` u nenačtených checků vůbec nekreslil — po spadlém detailu tedy nebylo kde
        // lhát. Teď se kreslí vždycky, takže by v něm nad spadlým detailem svítilo `Načítám
        // kontroly…` navždycky, a to je text, který tvrdí víc, než data unesou. Volání navíc to
        // není zdarma, ale `gh pr checks` na `gh pr view` nestojí: jsou to dva různé dotazy a
        // není důvod, aby se checky nedaly načíst kvůli tomu, že se nepodařila hlavička.
        await loadChecks(for: id)

        // Commity taky (#316), a taky **i po spadlém detailu**: tab `Commity` je v pruhu vždycky,
        // takže bez tohohle volání by nad nenačtenou hlavičkou svítilo `Načítám commity…` navždycky.
        // Je to jedno volání (`per_page=100`, změřeno 1,20 s pro sedm commitů) a platí se za odznak
        // s počtem, který má být vidět, aniž by se do tabu chodilo.
        //
        // **Za checky, ne souběžně.** Sériově proto, že obojí je `gh` podproces a paralelní
        // spouštění by jich na jeden výběr řádku zvedlo počet naráz běžících; přínos by byl
        // sekunda, cena dva procesy místo jednoho v nejužším místě aplikace.
        await loadCommits(for: id)
    }

    /// Dotáhne checky k PR. **Selhání se neschovává do prázdna** (#215).
    ///
    /// Do #215 tu stálo `(try? await gateway.fetchChecks(id: id)) ?? []` s tím, že checky jsou
    /// doplněk k PR, ne důvod položit načtení hlavičky. To první pořád platí — pád se sem
    /// nepropaguje —, ale prázdno je od #215 **tvrzení**: znamená „tenhle PR nemá CI“, takže by
    /// z chyby sítě tiše vyšlo zrovna ono (do #306 na tom navíc viselo, jestli se tab vůbec
    /// nakreslí). Gateway se přitom snaží ten rozdíl udržet (prázdný výstup s nulovým kódem = PR
    /// bez checků, nenulový s prázdným výstupem = chyba), takže by ho zahodilo právě tohle místo.
    ///
    /// Po selhání se **stará sada nechává být**: zastaralý seznam s větou nad ním je pořád
    /// lepší než plocha s chybou místo checků, které se před chvílí načetly. Zrušení (`.task` při
    /// přepnutí PR) se nezapisuje vůbec — to není porucha, to je odchod z obrazovky.
    ///
    /// **Volá se i z tabu** (#306, `Zkusit znovu`): dokud běželo jen z `loadDetail`, nešel selhaný
    /// pokus zopakovat, protože detail má cache podle `updatedAt` — po chybě sítě tedy tab zůstal
    /// v poruše až do dalšího commitu.
    func loadChecks(for id: PRIdentifier) async {
        do {
            checks[id] = try await gateway.fetchChecks(id: id)
            checkFailures[id] = nil
        } catch is CancellationError {
            // Nic: přepnutí PR není porucha.
        } catch let error as GitHubError {
            checkFailures[id] = error.userDescription
        } catch {
            checkFailures[id] = error.localizedDescription
        }
    }

    private func hasCurrentDetail(for pullRequest: PullRequestSummary) -> Bool {
        guard case .loaded(_, let updatedAt) = detailStates[pullRequest.id] else { return false }
        return updatedAt == pullRequest.updatedAt
    }
}
