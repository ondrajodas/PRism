import Foundation

/// Rozhodnutí „celé review, nebo jen přírůstek“ pro **jeden běh** (#517) i s materiálem k němu.
///
/// **Jeden typ, ne čtyři parametry.** Rozsah, seznam nálezů z minula, soubor a cena prvního kola
/// spolu drží: index v tom seznamu je `id` v otázce **i** v odpovědi, takže kdyby se dvě z těch
/// věcí předávaly zvlášť, dalo by se spárovat verdikt s jiným seznamem, než na jaký se ptalo.
///
/// **Skládá se jednou pro celý běh**, ze stejného důvodu jako šablona promptu a limit: sada je
/// v tu chvíli hotová a rozhodnutí se nesmí změnit pod rukama session, která už jede.
struct IncrementalRun: Sendable {
    /// Nad čím poběží který reviewer. Skill, který v mapě není, jde nad celým diffem.
    let scopes: [String: ReviewScope]
    /// Nálezy z minula **v pořadí, ve kterém se na ně ptalo** — index je `id`.
    let previous: [Finding]
    /// Soubor, ve kterém ten seznam leží (#120). `nil` = nebylo co poslat (minule čisto), nebo se
    /// zápis nepovedl.
    ///
    /// V obou případech se běh na verdikty **neptá**, ale v okně to nevyjde stejně: `nil` se do
    /// výsledku propíše jako `askedForVerdicts == false`, a když je k tomu co nést, dráha řekne
    /// **neposouzených — materiál se nepodařilo uložit**, ne `bez odpovědi`. „Nezeptali jsme se“
    /// je věta o nás, „neodpověděl“ o modelu.
    let previousFindingsFile: URL?
    /// Co stál **celý** běh z prvního kola, na skill — druhá polovina věty o ceně přírůstku.
    let wholeUsage: [String: RunUsage]

    /// Rozhodnutí bez materiálu — nikdo nejde nad přírůstkem, takže není co posílat.
    ///
    /// **Rozhodnutí se přesto nesou dál** (nálezem Copilota na #517): jsou mezi nimi zrovna ty
    /// tři důvody, které se v `Průběhu` vysvětlují (`rewroteHistory`, `unknownAncestry`,
    /// `noFinishedRun`), a prázdná mapa by znamenala, že se do osy nepošle nic a věta
    /// `celý diff — …` se nikdy nenakreslí. Tedy přesně to, čemu se `ReviewScope.saysWhyWhole`
    /// vyhýbá: rozhodnutí držené, ale nikde nečtené.
    static func withoutMaterial(_ scopes: [String: ReviewScope]) -> IncrementalRun {
        IncrementalRun(
            scopes: scopes,
            previous: [],
            previousFindingsFile: nil,
            wholeUsage: [:]
        )
    }

    /// Rozsah pro jednoho revieweera. `nil` = jde nad celým diffem.
    func range(of skill: String) -> IncrementalDiffRange? { scopes[skill]?.increment }

    /// Rozhodnutí, které patří do osy. `nil` = není co říct, viz `ReviewScope.belongsInTimeline`.
    ///
    /// Skill, který v mapě není, se sem nedostane: mapa se plní ze sady, se kterou běh jede, takže
    /// chybějící klíč znamená „tenhle reviewer teď neběží“, ne „běží nad celým diffem“.
    func reportableScope(of skill: String) -> ReviewScope? {
        guard let scope = scopes[skill], scope.belongsInTimeline else { return nil }
        return scope
    }

    /// Co se o přírůstku dostane do požadavku. `nil` = celý diff, tedy chování do #517.
    func request(for skill: String) -> IncrementalReviewRequest? {
        range(of: skill).map {
            IncrementalReviewRequest(range: $0, previousFindings: previousFindingsFile)
        }
    }

    /// Doplní doběhlému běhu jeho přírůstkovou půlku — verdikty a přenesené nálezy (#517).
    ///
    /// Skládá se to **z materiálu toho běhu**, ne z toho, co je zrovna v okně: verdikty jsou
    /// v posledním sdělení session a spárovat je umí jedině ten, kdo drží seznam, na který se
    /// ptalo. Čte se stejně defenzivně jako u kontroly nálezů (`RecheckCommand.parse`) — je to
    /// volný text od modelu, ne formát, na kterém bychom se dohodli.
    ///
    /// **Přenáší se i u běhu, který nedoběhl** (spadl, vypršel čas). Nálezy z minula nejsou
    /// tvrzení tohohle běhu, takže je jeho selhání nemá čím zrušit — zůstanou v okně jako
    /// `bez odpovědi`. Zahodit je by znamenalo přijít o nálezy kvůli session, která se nespustila.
    ///
    /// `askedForVerdicts` se bere z **existence souboru**, ne z toho, kolik verdiktů se přečetlo:
    /// prázdná mapa vznikne i tak, že běh odpověděl nečitelně, a ty dva stavy se nesmí slít.
    func completing(_ run: ReviewRun) -> ReviewRun {
        guard let range = range(of: run.key.skillID) else { return run }
        var completed = run
        completed.increment = IncrementalReviewOutcome(
            range: range,
            carried: Policy.carriedFindings(of: previous, by: run.key.skillID, to: range.head),
            statuses: Policy.incrementalStatuses(
                RecheckCommand.parse(run.summary.outcome?.text, count: previous.count),
                of: previous,
                by: run.key.skillID
            ),
            wholeUsage: wholeUsage[run.key.skillID],
            askedForVerdicts: previousFindingsFile != nil
        )
        return completed
    }
}

/// Přírůstkové review po pushi (#517) — rozhodnutí a materiál. Stav ve `AppStore.swift` k tomu
/// **žádný nepřibyl**: rozhodnutí žije jen v tom jednom běhu, který ho vyrobil.
extension AppStore {
    /// Sdílí předchozí hlava historii s tou dnešní? Odpovídá `git` v pracovní kopii.
    ///
    /// **Neptá se, když není proti čemu** — a je to úspora `gitu`, ne úprava rozhodnutí:
    /// `Policy.reviewScope` v těch případech ancestry vůbec nečte, protože záznam a nastavení
    /// posuzuje dřív. Vrací se `.unknown`, tedy „nezjišťovalo se“.
    func incrementalAncestry(
        of previous: ReviewRecord?,
        head: String,
        in worktree: URL,
        using checkout: any RepoCheckout,
        enabled: Bool
    ) async -> BranchAncestry {
        guard enabled, let previous, !previous.headSha.isEmpty, previous.headSha != head else {
            return .unknown
        }
        return await checkout.ancestry(of: previous.headSha, in: worktree)
    }

    /// Rozhodnutí na skill a materiál k němu.
    ///
    /// Soubor s nálezy z minula se zakládá **jen tehdy, když někdo poběží nad přírůstkem**: běh,
    /// který jde nad celým diffem, ho nemá kde přečíst a psát ho do cache pro nic je zbytečný
    /// zápis při každém review. **Rozhodnutí se ale nesou vždycky** — jsou mezi nimi ty tři, které
    /// se v `Průběhu` vysvětlují.
    func incrementalRun(
        for pr: PRIdentifier,
        at headSha: String,
        skills: [String],
        previous: ReviewRecord?,
        ancestry: BranchAncestry
    ) async -> IncrementalRun {
        let enabled = resolved(for: pr.repo).incrementalAfterPush
        var scopes: [String: ReviewScope] = [:]
        for skill in skills {
            scopes[skill] = Policy.reviewScope(
                record: previous,
                head: headSha,
                skill: skill,
                ancestry: ancestry,
                enabled: enabled
            )
        }
        guard let previous, scopes.values.contains(where: { $0.increment != nil }) else {
            return .withoutMaterial(scopes)
        }

        let findings = Policy.previousFindings(of: previous)
        return IncrementalRun(
            scopes: scopes,
            previous: findings,
            previousFindingsFile: findings.isEmpty
                ? nil
                : savePreviousFindings(findings, of: previous, for: pr, at: headSha),
            wholeUsage: wholeUsage(in: previous)
        )
    }

    /// Uloží nálezy z minula vedle pracovního stromu a vrátí cestu k nim.
    ///
    /// **Selhání zápisu review nepoloží a nezmlčí se** — `try?` je tu proto, že o následku
    /// rozhoduje volající, a ten ho **ukáže**: `nil` znamená `askedForVerdicts == false`, takže
    /// u dráhy stojí *N neposouzených — materiál se nepodařilo uložit*, ne `bez odpovědi`. Staré
    /// nálezy se přitom přenesou dál, takže se nic neztrácí; padnout kvůli nezapsanému kilobajtu
    /// na celé review by znamenalo znovu zaplatit celý diff.
    ///
    /// Hranici cache drží **tatáž kontrola jako jinde v repu** (`CacheTextFile`, tvrdá podmínka
    /// č. 3) a layout se bere z `cacheLayout`, tedy z toho, ve kterém stojí i checkout.
    private func savePreviousFindings(
        _ findings: [Finding],
        of previous: ReviewRecord,
        for pr: PRIdentifier,
        at headSha: String
    ) -> URL? {
        try? CacheTextFile.write(
            IncrementalCommand.previousFindings(findings, at: previous.headSha),
            to: cacheLayout.previousFindingsFile(for: pr, at: headSha),
            in: cacheLayout
        )
    }

    /// Co stál celý běh z prvního kola, na skill.
    ///
    /// **Řetězí se přes kola** (`run.increment?.wholeUsage`): druhý přírůstek nad týmž PR má
    /// srovnávat cenu s tím **celým** během, ne s předchozím přírůstkem — jinak by po pár
    /// pushnutích věta o ceně tvrdila, že se přírůstek vyplatil proti přírůstku.
    private func wholeUsage(in record: ReviewRecord) -> [String: RunUsage] {
        var usage: [String: RunUsage] = [:]
        for run in record.runs {
            guard let whole = run.increment?.wholeUsage ?? run.usage else { continue }
            usage[run.skillID] = whole
        }
        return usage
    }
}
