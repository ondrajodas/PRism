import Foundation

/// Detail spadlého checku (#214) — anotace a konec logu.
///
/// **Nikdy dopředu a nikdy pro všechny checky**: jde se jen pro ten, na který se kliklo. Log
/// celého běhu je log všech jeho jobů (u změřeného PR 23), takže tahat ho pro seznam je N+1 past
/// o tři řády dražší než u detailu.
///
/// **Nic z toho se neukládá na disk.** Log není nález: neplatí proti `headSha`, nedá se odmítnout
/// a příště se stáhne znovu — v cache vedle nálezů nemá co dělat. Nepřežije ani sbalení checku, ani
/// restart aplikace; drží ho ta cesta, která ho stáhla, a zaniká s ní.
extension AppStore {
    /// Rozbalený check daného PR. `nil` = žádný.
    func expandedCheck(in pr: PRIdentifier) -> String? { expandedChecks[pr] }

    /// Co se ví o rozbaleném checku.
    func checkDetail(of check: String, in pr: PRIdentifier) -> CheckDetailState? {
        checkDetails[CheckKey(pullRequest: pr, check: check)]
    }

    /// Rozbalí nebo sbalí check — a **při rozbalení jde pro detail**.
    ///
    /// Rozbalený je **jen jeden na PR**: dva otevřené konce logu pod sebou znamenají scrollování
    /// přes to, co se zrovna nečte, a hlavně dvě sady megabajtů v paměti.
    ///
    /// Sbalení **zahodí stažený text**, ne jen schová. Je to výslovné přání u #214: log nemá přežít
    /// ani zavření checku, takže se po rozbalení stahuje znovu.
    func toggleCheck(_ check: PullRequestCheck, in pr: PRIdentifier) {
        let key = CheckKey(pullRequest: pr, check: check.name)
        if expandedChecks[pr] == check.name {
            collapseCheck(in: pr)
            return
        }
        // Předchozí rozbalený se zahodí celý, i s textem.
        collapseCheck(in: pr)
        // Bez čísla jobu se detail **nenabízí** (viz `PullRequestCheck.jobID`), takže tudy
        // neprojde ani omylem.
        guard let jobID = check.jobID else { return }

        expandedChecks[pr] = check.name
        checkDetails[key] = CheckDetailState()
        checkTasks[key] = Task { [weak self] in
            await self?.loadCheckDetail(key: key, repo: pr.repo, jobID: jobID)
        }
    }

    /// Sbalí rozbalený check a **zruší jeho stahování**.
    ///
    /// Zrušení je podmínka, ne úklid: stahování osmimegového logu trvá vteřiny a bez zrušení by
    /// doběhlo do stavu, který už nikdo nečte — a zapsalo by text, který se má zapomenout.
    func collapseCheck(in pr: PRIdentifier) {
        guard let open = expandedChecks[pr] else { return }
        let key = CheckKey(pullRequest: pr, check: open)
        checkTasks[key]?.cancel()
        checkTasks[key] = nil
        checkDetails[key] = nil
        expandedChecks[pr] = nil
    }

    /// Anotace a konec logu k jednomu checku.
    ///
    /// **Anotace a log jsou dvě samostatné cesty**, takže se čekají zvlášť: anotace jsou levné
    /// (0,56 s změřeno) a bývají prázdné, log je drahý a je to ta hlavní cesta k příčině. Kdyby se
    /// čekalo na obojí naráz, drželo by rychlejší anotace za pomalejším logem.
    func loadCheckDetail(key: CheckKey, repo: RepoID, jobID: Int) async {
        await loadAnnotations(key: key, repo: repo, checkRunID: jobID)
        guard !Task.isCancelled else { return }
        await loadJobLog(key: key, repo: repo, jobID: jobID)
    }

    private func loadAnnotations(key: CheckKey, repo: RepoID, checkRunID: Int) async {
        do {
            let annotations = try await gateway.fetchAnnotations(repo: repo, checkRunID: checkRunID)
            // **`isCancelled` se musí ptát i na povedené cestě**, ne jen na té chybové. Sbalit
            // a hned zase rozbalit tentýž check znamená, že tady visí **stará** úloha, ale v mapě
            // je pod tímtéž klíčem už **nový** stav — samotné `checkDetails[key] != nil` by ho
            // tedy přepsalo daty z běhu, který si nikdo nevyžádal.
            guard !Task.isCancelled, checkDetails[key] != nil else { return }
            checkDetails[key]?.annotations = .loaded(annotations)
        } catch is CancellationError {
            // Sbalený check není porucha.
        } catch {
            guard !Task.isCancelled, checkDetails[key] != nil else { return }
            // **Selhání se nesmí tvářit jako „anotace nejsou“.** Prázdno je běžný stav (workflow
            // je neemituje), takže by se z chyby stalo tvrzení o CI.
            checkDetails[key]?.annotations = .failed(Self.reason(error))
        }
    }

    /// Konec logu — **až po zjištění velikosti, pokud se zjistit dá**.
    ///
    /// Nad známým stropem se **nestahuje vůbec** a na místě logu je věta s konkrétní velikostí. Bez
    /// toho by strop znamenal stáhnout 8,78 MB (4 s), jen aby se zjistilo, že se nemá ukazovat.
    ///
    /// **Nezjištěná velikost ale log neruší** (#292, mění #214): `HEAD` je ochrana proti obřímu
    /// logu, ne podmínka toho, že se log ukáže. Když velikost nepřijde, stáhne se a strop se
    /// uplatní na tom, co doopravdy přišlo. Do #292 tady byla chyba a stálo to celou funkci — jedna
    /// hlavička znamenala „konec logu se nepodařilo stáhnout“ u **každého** checku.
    private func loadJobLog(key: CheckKey, repo: RepoID, jobID: Int) async {
        do {
            let known = try await sizeIfKnown(repo: repo, jobID: jobID)
            guard !Task.isCancelled, checkDetails[key] != nil else { return }

            if let known, case .tooLarge(let reason) = Policy.logAvailability(bytes: known) {
                checkDetails[key]?.log = .tooLarge(reason)
                return
            }

            let raw = try await gateway.fetchJobLog(repo: repo, jobID: jobID)
            guard !Task.isCancelled, checkDetails[key] != nil else { return }
            // **Strop podruhé, na skutečné velikosti.** U známé velikosti to nic nemění (je to
            // tentýž text), u neznámé je to jediné místo, kde se mez ještě dá udržet: `Ukázat celý
            // log` by jinak nabídl sazbu 8,78 MB v `NSTextView`, což je změřených 850 ms.
            if case .tooLarge(let reason) = Policy.logAvailability(bytes: raw.utf8.count) {
                checkDetails[key]?.log = .tooLarge(reason)
                return
            }
            // Celý text se drží kvůli `Ukázat celý log`; ořez je věc zobrazení, ne stahování.
            checkDetails[key]?.log = .loaded(full: raw, tail: Policy.logTail(raw))
        } catch is CancellationError {
            // Sbalený check není porucha.
        } catch {
            // `isCancelled` i tady, ze stejného důvodu jako u anotací výš: po sbalení a novém
            // rozbalení by chyba starého běhu přepsala stav toho nového.
            guard !Task.isCancelled, checkDetails[key] != nil else { return }
            // **Nikdy prázdno**: „log se nepodařilo stáhnout“ se nesmí čít jako „log je prázdný“.
            checkDetails[key]?.log = .failed(Self.reason(error))
        }
    }

    /// Velikost logu, když ji jde zjistit; `nil` = nezjistila se.
    ///
    /// Selhání `HEAD`u se schválně **nepropisuje do stavu** a není to zapomenutá chyba: hned za ním
    /// jde stažení, tedy ta operace, o kterou uživateli jde. Když se stažení povede, nemá se o čem
    /// dozvídat — velikost byla jen k rozhodnutí, jestli stahovat. Když se nepovede, dostane
    /// **chybu stažení**, která je konkrétnější než chyba dotazu na velikost (nese kód i výstup
    /// `gh`). Zrušení se propouští dál, ať se po sbalení checku nestahuje nazdařbůh.
    private func sizeIfKnown(repo: RepoID, jobID: Int) async throws -> Int? {
        do {
            return try await gateway.fetchJobLogSize(repo: repo, jobID: jobID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private static func reason(_ error: any Error) -> String {
        (error as? GitHubError)?.userDescription ?? error.localizedDescription
    }
}

/// Klíč detailu checku — PR **a** jméno checku.
///
/// Jméno samo nestačí: `Tests (aws)` je na každém druhém PR a detail by se mezi nimi pletl.
struct CheckKey: Hashable, Sendable {
    let pullRequest: PRIdentifier
    let check: String
}

/// Co se ví o rozbaleném checku (#214). Dvě nezávislé cesty, každá se svým stavem.
struct CheckDetailState: Hashable, Sendable {
    var annotations: AnnotationsState = .loading
    var log: LogState = .loading

    /// Anotace check-runu. **Selhání je vlastní stav**, ne prázdno: prázdno znamená „workflow je
    /// neemituje“, což je běžné, kdežto chyba znamená „nevíme“.
    enum AnnotationsState: Hashable, Sendable {
        case loading
        case loaded(CheckAnnotations)
        case failed(String)
    }

    /// Log jobu. Čtyři stavy, protože „moc velký“ není chyba ani prázdno — je to rozhodnutí
    /// s vysvětlením, u kterého se ani nestahovalo.
    enum LogState: Hashable, Sendable {
        case loading
        case loaded(full: String, tail: LogTail)
        /// Nad stropem — věta s konkrétní velikostí, log se **nestahoval**.
        case tooLarge(String)
        case failed(String)
    }
}
