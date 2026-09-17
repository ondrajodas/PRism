import Foundation

/// Návrh review, který aplikace složí sama (#520).
///
/// **Dvě fáze, ne jedna, a je to kvůli diffu.** Rozhodnutí (co se převezme, co zůstane sporné)
/// padne hned po doběhnutí reviewerů — z uložených nálezů, tedy bez jediného volání navíc; z něj
/// je razítko na záznamu, pilulka ve frontě a řádek v `Dění`. **Komentáře** se ale do rozdělaného
/// review složí teprve tehdy, když je načtený diff: kam převzatý nález patří, rozhoduje
/// `Policy.draftTarget` podle hunků (`.line` uvnitř hunku, jinak odkaz do těla), takže bez diffu
/// by se ze **všech** nálezů staly odkazy v těle — a to je horší výsledek než počkat.
///
/// **Zamítnutá varianta: dotáhnout detail a diff hned po review.** Diff je jedno volání navíc na
/// každé doběhlé review, detail ale další čtyři (checky, commity, labely) — a diffy všech
/// reviewovaných PR by se držely v paměti, i když se na ně nikdo nepodívá. Odložit skládání do
/// chvíle, kdy se PR otevře, nestojí nic: tam se detail i diff načítají tak jako tak.
///
/// **Nic z toho nikam neodesílá.** Návrh končí v `ReviewDraft`, tedy tam, kde končí i to, co
/// naklikám sám — odejít umí jedině přes `ReviewPublishing.submit`, z potvrzení s celým payloadem
/// (tvrdá podmínka č. 1). Verdikt zůstává **návrhem** (#114): do draftu se nezapisuje.
extension AppStore {
    // MARK: - Rozhodnutí

    /// Po doběhnutí **všech** reviewerů: rozhodni, co by se převzalo, a zapiš to k nálezům.
    ///
    /// Volá se z `review(_:)` hned za oznámením výsledku — tedy na jednom místě a za všemi
    /// cestami, kterými běh končí. Rozhoduje `Policy.autoDraft`; tady zůstává jen to, odkud se
    /// berou jeho vstupy a co se s výsledkem udělá.
    ///
    /// **Selhání zápisu se spolkne, a je to vědomé.** Razítko je pohodlí, ne výsledek review:
    /// nálezy na disku jsou a panel se chová jako do #520. Hlásit poruchu kvůli nezapsanému
    /// pohodlí by znamenalo červený stav nad review, které doběhlo v pořádku.
    ///
    /// **Hlava se předává, nebere se z `detailStates`**, a je to rozdíl, na kterém záleží: `head(of:)`
    /// je z detailu načteného ve chvíli, kdy se PR otevřel, kdežto běh si právě dotáhl čerstvý.
    /// Čtení z okna by tedy nad otevřeným PR odmítlo návrh za „zastaralé nálezy“ pokaždé, když si
    /// tab pamatuje starší commit.
    func planAutoDraft(for pr: PRIdentifier, at headSha: String) async {
        guard let reviews, let record = reviewRecords[pr] else { return }
        let decision = Policy.autoDraft(
            record: record,
            draft: drafts[pr],
            ownership: ownership(of: pr),
            isAllowed: resolved(for: pr.repo).autoDraft,
            head: headSha
        )
        guard case .compose(let plan) = decision else { return }

        let stamp = StoredAutoDraft(
            at: time.now,
            adopted: plan.adopt.count,
            contested: plan.contested
        )
        do {
            reviewRecords[pr] = try await reviews.saveAutoDraft(stamp, for: pr, at: record.headSha)
        } catch {
            return
        }
        // Řádek v `Dění` **až po zápisu**: kdyby se zapsal dřív a razítko se uložit nepovedlo,
        // osa by tvrdila, že návrh leží v panelu, ve kterém by nebyl.
        await recordActivity(Policy.autoDraftEvent(
            for: pr,
            ownership: ownership(of: pr),
            at: time.now,
            adopted: stamp.adopted,
            contested: stamp.contested.count
        ))
        // Když je PR zrovna otevřený, je diff po ruce a návrh se složí hned. Jinak počká na
        // otevření — viz `loadDiff` a `loadDetail`.
        await materializeAutoDraft(for: pr)
    }

    // MARK: - Složení draftu

    /// Složí rozdělané review podle razítka, jestli je z čeho a je kam.
    ///
    /// **Šest bran a každá z nich znamená „takhle ne“**, ne „zkusíme to jinak“:
    ///
    /// 1. **Razítko.** Bez něj se nic neskládá — návrh je rozhodnutí, které padlo jednou.
    /// 2. **Brána `autoDraft`.** Ptá se na ni i tahle cesta, ne jen `Policy.autoDraft`: skládání
    ///    je odložené (viz úvod), takže mezi rozhodnutím a složením se volba dá vypnout — a pak už
    ///    nemá vzniknout nic. Je to tatáž kontrola na druhém konci, ne druhé pravidlo.
    /// 3. **Rozdělané review.** Existující draft se **nepřepisuje**: co jsem začal psát já, si
    ///    aplikace nepřepíše ani o komentář. Zároveň je to pojistka proti druhému složení — tahle
    ///    metoda se volá při každém načtení diffu.
    /// 4. **Hlava** (tvrdá podmínka č. 5). Nálezy musí platit pro kód, který v PR je; jak se hlava
    ///    pohne, návrh **zhasne** místo aby se složil proti kódu, který neexistuje.
    /// 5. **Načtený diff.** Bez něj by se z řádkových komentářů staly odkazy do těla, viz úvod.
    /// 6. **Je co převzít.** Návrh, ve kterém jsou jen sporné nálezy, draft nezakládá — pruh
    ///    v panelu ho vysvětlí i nad prázdným panelem.
    ///
    /// Jde se přes `adoptFinding`, tedy **tou samou cestou jako kliknutí na `Převzít`**. Druhá
    /// cesta k témuž by znamenala, že se převzatý nález chová jinak podle toho, kdo ho převzal —
    /// a to je zrovna ten rozdíl, který se v odeslaném review nesmí objevit.
    func materializeAutoDraft(for pr: PRIdentifier) async {
        guard let record = reviewRecords[pr], let stamp = record.autoDraft else { return }
        guard resolved(for: pr.repo).autoDraft else { return }
        guard drafts[pr] == nil else { return }
        guard !record.isStale, head(of: pr) == record.headSha else { return }
        guard case .loaded = diffStates[pr] else { return }

        let plan = Policy.autoDraftPlan(of: record)
        for finding in plan.adopt {
            adoptFinding(finding, for: pr)
        }
        await align(stamp, to: plan, for: pr, at: record.headSha)
    }

    /// Srovná razítko s tím, co se doopravdy složilo.
    ///
    /// **Je to oprava, ne úklid** (nález vlastní revize): mezi rozhodnutím a složením uběhne čas —
    /// klidně hodina, než PR otevřu —, a dá se v něm nález **odmítnout** (#113). Bez tohohle by
    /// pruh tvrdil `z 5 nálezů 3 převzaty` nad panelem se dvěma komentáři, tedy přesně tu větu,
    /// která tvrdí víc, než co je vidět.
    ///
    /// **Razítko se nepřerazítkuje**: `at` zůstává okamžik, kdy návrh vznikl. Mění se počty, ne to,
    /// kdy se to stalo. A když se nic nezměnilo, **nezapisuje se nic** — zápis do cache při každém
    /// otevření PR by byl provoz za nic.
    private func align(
        _ stamp: StoredAutoDraft,
        to plan: AutoDraftPlan,
        for pr: PRIdentifier,
        at headSha: String
    ) async {
        let composed = StoredAutoDraft(at: stamp.at, adopted: plan.adopt.count, contested: plan.contested)
        guard composed != stamp, let reviews else { return }
        reviewRecords[pr] = try? await reviews.saveAutoDraft(composed, for: pr, at: headSha)
            ?? reviewRecords[pr]
    }

    // MARK: - Co je z návrhu vidět

    /// Razítko návrhu pro tenhle PR. `nil` = žádný návrh se neskládal, zahodil se, nebo se hlava
    /// posunula pod ním (rozhoduje `Policy.autoDraftStamp`, ne tahle metoda).
    func autoDraftStamp(for pr: PRIdentifier) -> StoredAutoDraft? {
        Policy.autoDraftStamp(of: reviewRecords[pr], head: head(of: pr))
    }

    /// Značky `sporné` u nálezů. Prázdné = nekreslí se nic.
    func autoDraftDoubts(for pr: PRIdentifier) -> [FindingKey: AutoDraftDoubt] {
        Policy.autoDraftDoubts(of: reviewRecords[pr], head: head(of: pr))
    }

    /// Pilulka v řádku fronty. `nil` = řádek o návrhu mlčí.
    ///
    /// Bere **stejný verdikt jako panel** (`prefillableSuggestion`), ne `suggestedVerdict`: na
    /// vlastním PR se nepředvyplňuje nic, protože `APPROVE` tam GitHub odmítne (422, změřeno
    /// u #62) — a pilulka `návrh: schválit` nad takovým PR by slibovala verdikt, který neodejde.
    /// Je to nález vlastní revize a tatáž brána, jakou má panel (#114).
    func autoDraftPill(for pr: PRIdentifier) -> AutoDraftPill? {
        Policy.autoDraftPill(
            stamp: autoDraftStamp(for: pr),
            suggestion: prefillableSuggestion(for: pr),
            isAllowed: resolved(for: pr.repo).autoDraft
        )
    }

    // MARK: - Zahození

    /// `Zahodit návrh` — smaže razítko **i draft**, takže po něm zbude dnešní prázdný panel.
    ///
    /// **Obojí naráz, ne jen jedno z nich.** Samotné smazání razítka by nechalo v panelu komentáře,
    /// o kterých by nebylo poznat, odkud jsou; samotné smazání draftu by nechalo razítko, které by
    /// návrh při dalším načtení diffu složilo znovu — tedy tlačítko, po kterém se nic nestane.
    ///
    /// Nesmaže to **nic z nálezů**: zahozený návrh nálezy nesundává, to smí jedině odmítnutí
    /// (#113). Řádek v `Dění` taky zůstává — je to záznam toho, co se stalo, ne stav.
    func discardAutoDraft(for pr: PRIdentifier) async {
        discardDraft(for: pr)
        await forgetAutoDraftStamp(for: pr)
    }

    /// Smaže razítko. **Chodí tudy i obyčejné `Zahodit review` a úspěšné odeslání** —
    /// `AppStore.discardDraft` si to volá samo.
    ///
    /// Je to nález vlastní revize a byla to dvojí tichá vada: po `Zahodit review` i **po odeslaném
    /// review** zůstávalo razítko ležet, takže při dalším načtení diffu prošel
    /// `materializeAutoDraft` všemi branami (draft už žádný není) a **složil tytéž komentáře
    /// znovu**. Stačilo přepnout na jiný PR a zpátky.
    ///
    /// **Selhání zápisu se spolkne**: v paměti razítko mizí tak jako tak a nejhorší následek je
    /// návrh, který se po restartu vrátí. Je to pohodlí, ne výsledek review — poruchu nad
    /// doběhlým review by to nezasloužilo.
    func forgetAutoDraftStamp(for pr: PRIdentifier) async {
        guard let reviews, let record = reviewRecords[pr], record.autoDraft != nil else { return }
        reviewRecords[pr]?.autoDraft = nil
        reviewRecords[pr] = (try? await reviews.saveAutoDraft(nil, for: pr, at: record.headSha))
            ?? reviewRecords[pr]
    }
}
