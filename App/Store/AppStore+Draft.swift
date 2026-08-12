import Foundation

/// Rozdělané review (#65, #66) — komentáře, tělo, verdikt a tažení rozsahu (#110).
///
/// Tažení rozsahu je tady, ne u diffu: vzniká z něj **komentář draftu**, takže je to začátek
/// téhle cesty, ne vlastnost zobrazení.
extension AppStore {
    /// Průběh tažení: `from` je řádek, na kterém začalo, `to` ten pod myší.
    ///
    /// Rozsah se skládá při každém pohybu, protože se z něj kreslí zvýraznění — a musí to být
    /// tentýž rozsah, který vznikne na konci.
    ///
    /// **`to == nil` znamená „pod myší žádný řádek není“** — prázdná protistrana ve split pohledu,
    /// mezera mezi soubory, hlavička hunku. Rozdělaný rozsah se pak **drží**: přejetí přes prázdné
    /// místo není zrušení výběru, a bez tohohle se rozsah srazil na první řádek a po přejetí na
    /// další řádek se zase objevil (nahlášené při zkoušení #110). Dokud ale rozsah není žádný,
    /// platí samotný začátek, ať z tažení vznikne aspoň jednořádkový komentář.
    ///
    /// Když rozsah `Policy` složit nedá (druhý konec v jiném souboru nebo mimo diff), drží se
    /// poslední platný ze stejného důvodu.
    func dragCommentRange(path: String, from: DraftAnchor, to: DraftAnchor?, for pr: PRIdentifier) {
        guard case .loaded(let diff, _) = diffStates[pr], let file = diff.file(at: path) else { return }
        guard let target = to ?? (commentDrag == nil ? from : nil),
              let range = Policy.commentRange(from: from.end, to: target.end, in: file)
        else { return }
        commentDrag = CommentRangeDrag(pullRequest: pr, path: path, anchor: range)
    }

    /// Konec tažení: z rozsahu vznikne komentář. Tažení, které nikam nedošlo (rozsah délky 1),
    /// dá obyčejný jednořádkový komentář — je to totéž, co tlačítko u řádku.
    func finishCommentRange() {
        guard let drag = commentDrag else { return }
        commentDrag = nil
        addDraftComment(at: drag.anchor, path: drag.path, for: drag.pullRequest)
    }

    func draft(for pr: PRIdentifier) -> ReviewDraft? { drafts[pr] }

    /// Je co odeslat? Podle toho svítí indikátor v řádku seznamu i v detailu.
    func hasDraft(_ pr: PRIdentifier) -> Bool { drafts[pr] != nil }

    func draftComments(for pr: PRIdentifier) -> [ReviewDraftComment] { drafts[pr]?.comments ?? [] }

    /// Píše se draft proti staršímu commitu, než je hlava PR?
    ///
    /// `false`, dokud hlavu neznáme: „nevím“ není „zastaralé“ a banner o zablokovaném
    /// odeslání nad načítajícím se detailem by lhal. Odeslání se stejně ptá
    /// `draftSendBlock(for:)`, které neznámou hlavu bere jako vlastní důvod.
    func isDraftStale(for pr: PRIdentifier) -> Bool {
        guard let draft = drafts[pr], let head = head(of: pr) else { return false }
        return Policy.isStale(draft, head: head)
    }

    /// Dá se do draftu psát?
    ///
    /// Nový draft potřebuje `headSha` — bez něj by nešlo poznat, proti čemu je psaný, ani ho
    /// odeslat. Do rozepsaného se psát dá vždycky, ten svůj commit už zná.
    func canComposeDraft(for pr: PRIdentifier) -> Bool {
        drafts[pr] != nil || head(of: pr) != nil
    }

    /// Kam by převzatý nález šel. Bublina podle toho pojmenuje tlačítko a řekne proč.
    func draftTarget(for finding: Finding, in pr: PRIdentifier) -> DraftTarget {
        Policy.draftTarget(for: finding, in: loadedDiff(for: pr))
    }

    /// Je nález už v rozdělaném review?
    func isAdopted(_ finding: Finding, in pr: PRIdentifier) -> Bool {
        Policy.isAdopted(
            finding,
            target: draftTarget(for: finding, in: pr),
            in: drafts[pr],
            repo: pr.repo
        )
    }

    /// Převezme nález do rozdělaného review.
    ///
    /// Kam patří, rozhoduje `Policy.draftTarget` — tedy pravidlo GitHubu, ne vzhled okna:
    /// řádek uvnitř hunku unese řádkový komentář, cokoli jiného jde do těla jako permalink.
    /// Text se předvyplní tím, co napsal reviewer, a jde přepsat.
    func adoptFinding(_ finding: Finding, for pr: PRIdentifier) {
        let text = Policy.adoptedText(of: finding)
        switch draftTarget(for: finding, in: pr) {
        case .line(let path, let anchor):
            addDraftComment(
                at: anchor,
                path: path,
                body: text,
                origin: .finding(reviewer: finding.reviewer),
                for: pr
            )
        case .body(let path, let line):
            appendDraftNote(text: text, path: path, line: line, for: pr)
        }
    }

    /// Přidá poznámku do těla review — a **ukáže ji** (#242).
    ///
    /// Kam text spadl, se musí poznat: řádkový komentář je vidět hned pod řádkem, kdežto položka
    /// v těle je jinde v okně — od #242 klidně za složeným panelem a od #294 klidně v tabu, kde
    /// panel není vůbec. Proto tudy chodí obojí, co do těla píše: převzetí nálezu bez kotvy
    /// i poznámka k řádku, na který GitHub komentář nepustí.
    ///
    /// **Vlastní metoda, ne `revealDraft(in:)` u volajícího**: dvě kopie téhle dvojice by
    /// znamenaly, že se v jedné z nich zapomene — a tichá ztráta rozepsané věty je to nejdražší,
    /// co tady umí zmizet.
    func appendDraftNote(text: String, path: String?, line: Int?, for pr: PRIdentifier) {
        appendDraftBodyItem(text: text, path: path, line: line, for: pr)
        revealDraft(in: pr)
    }

    /// Založí řádkový komentář. Prázdný schválně — text se dopisuje v bublině.
    func addDraftComment(
        at anchor: DraftAnchor,
        path: String,
        body: String = "",
        origin: ReviewDraftComment.Origin = .own,
        for pr: PRIdentifier
    ) {
        // Snímek kódu se bere **tady**, z načteného diffu (#69): bez něj se po novém commitu
        // nedá poznat, jestli na tom řádku pořád stojí to, co člověk komentoval. Jedno místo,
        // které to ví — view by si stranu a číslo muselo párovat samo.
        let comment = ReviewDraftComment(
            path: path,
            anchor: anchor,
            snapshot: snapshot(of: anchor, path: path, in: pr),
            body: body,
            origin: origin
        )
        mutateDraft(for: pr) { $0.comments.append(comment) }
        // Komentář, který se dá ⇧ klikem roztáhnout na rozsah. Drží se **id**, ne kotva:
        // z komentáře se druhý konec dopočítá, kdežto uložená kotva by se s ním po roztažení
        // rozešla.
        rangeTargets[pr] = comment.id
    }

    /// Snímek kódu pod kotvou z načteného diffu. Prázdný, když diff není — revalidace to pak
    /// řekne jako „nevím“ místo aby předstírala, že kotva sedí.
    private func snapshot(of anchor: DraftAnchor, path: String, in pr: PRIdentifier) -> DraftSnapshot {
        guard case .loaded(let diff, _) = diffStates[pr], let file = diff.file(at: path) else {
            return DraftSnapshot()
        }
        return Policy.snapshot(of: anchor, in: file)
    }

    /// Roztáhne naposledy přidaný komentář na rozsah končící (nebo začínající) tímhle řádkem.
    ///
    /// Tohle je ⇧ klik na tlačítko u řádku. Když není co roztahovat — nic se nepřidávalo, cíl
    /// se mezitím vyjmul, nebo je v jiném souboru — **založí se obyčejný komentář**. Kliknutí,
    /// po kterém se nestane nic, vypadá jako rozbitá aplikace.
    ///
    /// Rozsah skládá `Policy.commentRange`, protože o pořadí konců rozhoduje diff, ne čísla
    /// (#110). Bez načteného diffu se rozsah nemá o co opřít, takže vyjde jednořádkový komentář.
    func extendDraftComment(to anchor: DraftAnchor, path: String, for pr: PRIdentifier) {
        guard let id = rangeTargets[pr],
              let existing = draft(for: pr)?.comments.first(where: { $0.id == id }),
              existing.path == path,
              case .loaded(let diff, _) = diffStates[pr],
              let file = diff.file(at: path),
              // Na místě zůstává **kotva**, tedy začátek už existujícího rozsahu (u jednořádkového
              // komentáře jeho řádek). Roztahovat od konce by druhým ⇧ klikem zahodilo první konec:
              // z 25–26 by po kliku na 27 vyšlo 26–27. Chytil to test.
              let range = Policy.commentRange(
                  from: existing.anchor.start ?? existing.anchor.end,
                  to: anchor.end,
                  in: file
              )
        else {
            addDraftComment(at: anchor, path: path, for: pr)
            return
        }

        mutateDraft(for: pr) { draft in
            guard let index = draft.comments.firstIndex(where: { $0.id == id }) else { return }
            let comment = draft.comments[index]
            // Nový komentář se **stejným `id`**: kotva je `let`, ale identita musí zůstat, ať
            // si editor udrží rozepsaný text a bublina nepřeskočí jako nová.
            draft.comments[index] = ReviewDraftComment(
                id: comment.id,
                path: comment.path,
                anchor: range,
                // Roztažením se mění oba konce, takže se snímek bere znovu — starý by po dalším
                // commitu hledal řádek, který v rozsahu už není.
                snapshot: Policy.snapshot(of: range, in: file),
                body: comment.body,
                origin: comment.origin
            )
        }
    }

    /// Jediná cesta, kterou se draft mění — a hned se ukládá.
    ///
    /// `headSha` nového draftu se bere z detailu; bez něj se draft **nezakládá**, protože by
    /// nešlo poznat, proti čemu je psaný. Existujícímu draftu se `headSha` nepřepisuje —
    /// přenesení na nový commit je #69.
    func mutateDraft(for pr: PRIdentifier, _ change: (inout ReviewDraft) -> Void) {
        guard var draft = drafts[pr] ?? head(of: pr).map({ ReviewDraft(pullRequest: pr, headSha: $0) })
        else { return }
        change(&draft)
        // Razítko se dává **na jednom místě**, protože tudy chodí každá změna draftu (#181).
        // Kdyby si ho nasazoval každý volající, jedna cesta by na něj časem zapomněla a draft
        // by v dashboardu vypadal starší, než je.
        draft.updatedAt = time.now
        // Prázdný draft se maže — „draft existuje“ musí znamenat „je co poslat“.
        drafts[pr] = draft.isEmpty ? nil : draft
        persistDraft(for: pr)
    }
}
