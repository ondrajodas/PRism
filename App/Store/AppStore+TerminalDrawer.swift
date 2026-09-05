import Foundation

// MARK: - Zásuvka s terminálem (#459, víc relací #460)

extension AppStore {
    /// `⌃\`` — vytáhne nebo schová zásuvku.
    ///
    /// **Schování nic nezabíjí.** Shelly běží dál a při dalším vytažení je v nich to, co v nich
    /// bylo — je to tentýž vztah jako mezi sbaleným panelem nálezů a nálezy samotnými. Zabíjí se
    /// jedině zavřením záložky a ukončením aplikace, tedy tam, kde ten kontext doopravdy končí.
    ///
    /// **Dává relaci `shell`**, tedy tu jednu z relací, která nemá skill (návrh, sekce 35).
    /// Když už nějaká relace je vidět, `` ⌃` `` jen přepne zásuvku a **nepřebíjí ji** — vytáhnout
    /// zásuvku uprostřed běžícího `claude --resume` a dostat místo něj prázdný prompt by bylo to
    /// jediné, co na téhle klávese může překvapit.
    ///
    /// Adresář se hledá **při otevírání**, ne v `body`: rozhodnutí, jestli se startuje v pracovním
    /// stromu review, nebo v klonu, potřebuje sáhnout na disk.
    func toggleTerminal() async {
        isTerminalOpen.toggle()
        guard isTerminalOpen else {
            // Schovaná zásuvka fokus mít nemůže. AppKit ho sice při odebrání plochy z okna sám
            // odevzdá, jenže to je pořadí, na které se nedá spolehnout — a příznak, který zůstane
            // viset, znamená okno s vypnutými zkratkami nad terminálem, který není vidět.
            isTerminalFocused = false
            return
        }
        guard let pr = activeTab.pullRequest else { return }
        await prepareTerminalDrawer(for: pr)
    }

    /// Je v tomhle okně zásuvka? `false` = **`▶` se nekreslí** (testovací store bez hostitele).
    ///
    /// Nekreslí se schválně, místo aby tiše spadlo zpátky na `Terminal.app` (#460): dvě různá
    /// chování pod jednou ikonou znamenají, že se nedá spolehnout ani na jedno. Je to tatáž úvaha
    /// jako u `Policy.terminalSession(of:)`, jen o druhou podmínku dál.
    var hasTerminalDrawer: Bool { terminals != nil }

    // MARK: - Co je v zásuvce vidět

    /// Záložky přepínače pro ten PR. Prázdné = zásuvka zatím žádnou relaci nemá.
    func terminalRows(for pr: PRIdentifier) -> [TerminalSlotRow] {
        Policy.terminalSlotRows(
            terminalSlots[pr] ?? [],
            active: activeTerminalSlots[pr],
            states: terminalStates
        )
    }

    /// Která relace je vidět. `nil` = zásuvka pro ten PR ještě žádnou nemá.
    func activeTerminalSlot(for pr: PRIdentifier) -> TerminalSlot? { activeTerminalSlots[pr] }

    /// Kde stojí shell té relace. `nil` = v cache pro ni **není adresář**, a zásuvka to řekne.
    func terminalDirectory(of slot: TerminalSlot) -> URL? { terminalDirectories[slot] }

    /// Klik na záložku přepínače.
    ///
    /// **Nic nespouští ani nezabíjí** — je to pohled, stejně jako `` ⌃` ``. Plochu vyrobí až
    /// `TerminalSurface`, protože ta zná i adresář.
    func selectTerminalSlot(_ slot: TerminalSlot) {
        guard terminalSlots[slot.pullRequest]?.contains(slot) == true else { return }
        activeTerminalSlots[slot.pullRequest] = slot
    }

    // MARK: - Vznik relací

    /// Připraví zásuvku pro ten PR: relace `shell`, a přepnout na ni **jen když zásuvka pro něj
    /// žádnou nemá**.
    ///
    /// Volá se ze dvou míst a v obou znamená totéž: z `` ⌃` `` a z přepnutí na jiný pull request
    /// s vytaženou zásuvkou — jinak by nad novým PR zůstala cesta do checkoutu toho předchozího.
    func prepareTerminalDrawer(for pr: PRIdentifier) async {
        let slot = TerminalSlot(pullRequest: pr, role: .shell)
        let hadNone = activeTerminalSlots[pr] == nil
        // **Adresář se hledá jen relaci, která ho ještě nemá** (nález Copilota). Hledá se proto,
        // že pracovní strom se posune s novým commitem a eviction ho umí sebrat — shell spuštěný
        // ve smazané složce je horší než žádný. Jenže hotové relaci ho přepsat **nesmí**:
        // `TerminalHost` vrací existující plochu a nový adresář si nevezme, takže by popiska
        // v hlavičce ukazovala jinam, než kde shell doopravdy stojí.
        var directory = terminalDirectories[slot]
        if directory == nil { directory = await resolvedShellDirectory(for: pr) }
        // **Dřív, než se relace zobrazí** (#479): plochu staví až `TerminalSurface` z adresáře,
        // který se zapíše o dva řádky níž, takže tohle je poslední místo před shellem — a `claude`
        // napsaný v něm rukou se ptá na důvěru stejně jako ten z `▶`.
        //
        // **Před `admit`, i za cenu zápisu pro relaci, která nevznikne.** Obráceně by mezi zapsaným
        // slotem a zapsaným adresářem stála odmlka (`await` na hlavním vlákně pustí překreslení)
        // a zásuvka by v ní nakreslila větu o chybějící pracovní kopii. Cena téhle volby je jeden
        // zápis navíc, když je strop relací plný — a i ten je pro složku toho pull requestu, ne pro
        // cizí.
        await registerWorkspaceTrust(for: directory)
        guard admit(slot, showing: hadNone) else { return }
        terminalDirectories[slot] = directory
    }

    /// `▶` v hlavičce dráhy (#460) — **přepne na relaci té dráhy** a pustí v ní `claude --resume`.
    ///
    /// Do #460 to psalo do jediného shellu zásuvky a při obsazeném popředí končilo slepou uličkou.
    /// Relace na dráhu tu uličku ruší: dvě běžící review mají dvě relace a přepíná se mezi nimi.
    ///
    /// Posílá se **celá `shellLine`**, tedy `cd '<strom>' && claude --resume <id> --permission-mode
    /// auto`. Proti řádce, kterou od #453 dostával `Terminal.app`, je v ní navíc **režim
    /// povolení** — session, kterou v zásuvce řídí člověk, nemá přerušovat práci dotazem u každého
    /// kroku (zdůvodnění je u `Policy.drawerPermissionMode`). `cd` v ní není nadbytečné ani
    /// u vlastní relace: shell v ní startuje v adresáři, který dostal, jenže `▶` umí přijít i na
    /// relaci, která už existuje a stojí jinde (starší strom téže dráhy). S `&&` navíc zůstane po
    /// zmizelém stromu `cd: no such file or directory`, což je pravda, podle které se dá jednat.
    ///
    /// **Do běžícího jobu se pořád nepíše** (`busy`) — řádka je pro něj vstup, takže by
    /// v rozdělaném `claude` byla odeslaná zpráva. Nově se z toho ale nestává slepá ulička:
    /// přepne se na tu relaci, takže je vidět, co v ní běží.
    ///
    /// **Fokus si to nebere.** Sebrat ho znamená sáhnout na první responder v tomtéž průchodu,
    /// ve kterém se plocha teprve staví (past z #184), a ověřit se to dá jedině na běžící
    /// aplikaci. Kliknout do zásuvky je proti tomu jeden klik.
    func resumeInDrawer(_ session: TerminalSession, for pr: PRIdentifier) async {
        // Bez hostitele se `▶` nekreslí, takže sem se nedojde — a kdyby přece, nesmí se vymyslet
        // hláška o něčem, o co se nikdo nepokusil.
        guard let terminals else { return }
        let slot = TerminalSlot(pullRequest: pr, role: .session(session.skill))
        isTerminalOpen = true
        // **Důvěra ke složce se zapisuje dřív, než se řádka pošle** (#460): `claude --resume` je
        // interaktivní, takže by se v novém pracovním stromu zeptal, jestli té složce věřit —
        // a strom je nový u **každého** PR, takže by ten dotaz přišel pokaždé znovu.
        //
        // **Pro strom té session, ne jen pro kořen cache** (#479): `shellLine` do něj napřed `cd`
        // udělá, takže `claude` se ptá na **něj** — a je to git pracovní strom, kam se důvěra
        // z předka nedědí.
        await registerWorkspaceTrust(for: session.directory)
        guard admit(slot, showing: true) else {
            terminalFailure = Policy.slotsFullNotice(Policy.terminalSlotTitle(slot.role))
            return
        }
        let outcome = terminals.run(session.shellLine, for: slot, in: session.directory)
        // Cesta v hlavičce se přepisuje **všude, kde se plocha postavila** — tedy i po `noShell`.
        // Vypadá to jako nedůslednost (řádka přece neodešla), ale je to naopak: bez cesty kreslí
        // zásuvka větu „Tenhle pull request nemá v cache pracovní kopii“, a ta by po nepovedeném
        // startu **lhala** — strom je na disku, nepovedl se shell. S cestou je v hlavičce pravda
        // (odkud se startovalo) a puntík řekne, že relace neběží.
        //
        // Po `busy` se naopak **nepřepisuje**: tam se plocha nestavěla a shell dál stojí tam, kde
        // stál, takže nová popiska by tvrdila něco, co není.
        if outcome != .busy { terminalDirectories[slot] = session.directory }
        terminalFailure = Policy.resumeNotice(outcome, in: Policy.terminalSlotTitle(slot.role))
    }

    /// `Otevřít v terminálu` u rozdělaného rebase (#467) — zásuvka **v tom stromě, kde uvázl**.
    ///
    /// **Nic nespouští, jen otevře shell.** Je to ta půlka „co nerozřeší, nechá být“: v rozdělaném
    /// rebase má člověk plnou moc (#459) a kontext připravený — `git status` mu řekne, na čem to
    /// stojí, a `git rebase --continue` to dokončí. Aplikace do toho shellu **nepíše nic**: `▶`
    /// (jediná řádka, kterou umí poslat) míří na `claude --resume` dráhy review, ne sem.
    ///
    /// **Vlastní role, ne `shell`** — adresář je jiný a `TerminalHost` existující ploše adresář
    /// nepřepíše, takže by jedna role se dvěma adresáři znamenala lhavou popisku v hlavičce.
    ///
    /// **Cesta se ověřuje existencí složky, ne stavem v panelu.** Strom mohl zmizet (zahodilo se to
    /// z druhého okna, sebral ho úklid) a shell ve smazané složce je horší než hláška.
    func openConflictTerminal(for pr: PRIdentifier) async {
        guard terminals != nil else { return }
        let slot = TerminalSlot(pullRequest: pr, role: .rebase)
        isTerminalOpen = true
        let directory = await existingDirectory(cacheLayout.syncWorktree(for: pr))
        guard let directory else {
            terminalFailure = "Kopie repa, ve které rebase uvázl, už v cache není."
            return
        }
        // **Důvěra ke složce dřív, než se relace zobrazí** (#460, #479): strom pro srovnání je git
        // pracovní strom, kam se důvěra z předka nedědí — takže by se `claude` napsaný v tom shellu
        // rukou zeptal, jestli té složce věřit.
        await registerWorkspaceTrust(for: directory)
        guard admit(slot, showing: true) else {
            terminalFailure = Policy.slotsFullNotice(Policy.terminalSlotTitle(slot.role))
            return
        }
        terminalDirectories[slot] = directory
    }

    /// Zapíše relaci do seznamu, uklidí po vytlačené a případně na ni přepne.
    ///
    /// `false` = **nevznikla**, protože strop je plný a všechny relace běží. Vytlačuje se jedině
    /// neběžící relace (`Policy.terminalSlotAdmission`), takže se tímhle nikdy nezabije rozdělaná
    /// práce — zahodí se jen výpis, který je z definice minulost.
    @discardableResult
    private func admit(_ slot: TerminalSlot, showing: Bool) -> Bool {
        let slots = terminalSlots[slot.pullRequest] ?? []
        switch Policy.terminalSlotAdmission(of: slot, in: slots, states: terminalStates) {
        case .refused:
            return false
        case .existing:
            if showing { activeTerminalSlots[slot.pullRequest] = slot }
            return true
        case .added(let victim):
            if let victim { discard(victim) }
            terminalSlots[slot.pullRequest] = Policy.terminalSlots(
                terminalSlots[slot.pullRequest] ?? [],
                adding: slot,
                evicting: victim
            )
            if showing || activeTerminalSlots[slot.pullRequest] == nil {
                activeTerminalSlots[slot.pullRequest] = slot
            }
            return true
        }
    }

    /// Zahodí jednu relaci i s jejím shellem a stavem.
    ///
    /// Na koho se přepnout, když zmizela ta aktivní, rozhoduje **`Policy`, ne `if` tady**
    /// (`terminalSlotAfterRemoval`): je to pravidlo nad daty, a napsané na dvou místech by se
    /// rozešlo první úpravou.
    private func discard(_ slot: TerminalSlot) {
        terminals?.stopTerminal(for: slot)
        terminalStates[slot] = nil
        terminalDirectories[slot] = nil
        let slots = terminalSlots[slot.pullRequest] ?? []
        if activeTerminalSlots[slot.pullRequest] == slot {
            activeTerminalSlots[slot.pullRequest] = Policy.terminalSlotAfterRemoval(
                of: slot,
                from: slots
            )
        }
        terminalSlots[slot.pullRequest] = slots.filter { $0 != slot }
    }

    /// Zapíše důvěru do konfigurace Claude Code (#460) — **té složce, ve které shell stojí, a ke
    /// kořeni cache** (#479).
    ///
    /// **Do #479 to byl jen kořen** a stálo to na měření, že se důvěra dědí z libovolného předka.
    /// Dědí se, ale **ne do git pracovního stromu**: složka s `.git` si žádá vlastní záznam
    /// (změřeno na skutečném stromu review v cache, [`docs/claude-cli.md`](../../docs/claude-cli.md)).
    /// Kořen tedy pokrýval bare klony a dialog nad pracovním stromem chodil dál — přesně tam, kam
    /// `▶` míří. Co se zapisuje, rozhoduje `Policy.workspacesToTrust(root:shell:)`.
    ///
    /// Obojí je v cache aplikace, takže **tvrdá podmínka č. 3 platí beze změny**: zapisuje se
    /// důvěra ke složkám, které aplikace sama vyrobila, nikdy k uživatelovu klonu. **Od #479 to
    /// tvrdí kontrola, ne konstrukce** — do té doby byla zapisovaná cesta konstanta, kdežto teď jde
    /// o hodnotu z dat (osa review, checkout), a `CacheFile` je pravidlo o hranici cache, které
    /// v repu už bydlí na jednom místě. Bere se z něj **verdikt pro zápis** (`refusal`), ne ten pro
    /// mazání. Kořen sám se doptat nedá (`contains` posuzuje **rodiče**, takže na kořeni vyjde
    /// `false`), proto je vedle rovnosti s ním.
    ///
    /// **Každá složka jednou za běh aplikace** (`trustedWorkspaces`), aby se 200kB konfigurace
    /// nečetla při každém otevření zásuvky. Zapsané složce se nepíše znovu, ale **neúspěch se
    /// nepamatuje**, takže se příště zkusí znovu.
    ///
    /// **Existence složky se neověřuje, a je to rozhodnutí.** Z `resumeInDrawer` umí přijít strom,
    /// který mezitím sebral úklid cache — záznam pro cestu, na které nic není, ale nikomu nevadí:
    /// `claude` si takové sám vyrábí desítkami (v konfiguraci leží záznamy po dávno smazaných
    /// klonech) a `shellLine` v takovém stromě stejně skončí na `cd`. `stat` navíc před každým
    /// otevřením zásuvky by se platil za nic.
    ///
    /// **Selhání se nehlásí ve stavovém řádku, a je to zapsaná výjimka** z pravidla o spolknutých
    /// chybách. Otázka, kterou to pravidlo klade, zní „pozná uživatel, že se to nepovedlo?“ — a
    /// tady zní odpověď **ano, sám od sebe**: v zásuvce se objeví ten dotaz na důvěru, tedy přesně
    /// to, co tohle mělo ušetřit. Hláška navíc by k tomu nic nepřidala a přišla by při každém
    /// otevření zásuvky. Co se **nesmí** stát, je rozbitá cizí konfigurace — to hlídá
    /// `ClaudeWorkspaceTrust` tím, že na soubor, kterému nerozumí, vůbec nesáhne.
    private func registerWorkspaceTrust(for directory: URL?) async {
        guard let workspaceTrust else { return }
        let layout = CacheLayout.applicationSupport
        let wanted = Policy.workspacesToTrust(root: layout.root, shell: directory)
        for workspace in wanted where !trustedWorkspaces.contains(workspace) {
            // **Hranice cache, a ne opsaná**: verdikt vydává `CacheFile`, kde to pravidlo bydlí
            // (#452). Složka mimo cache se **přeskočí potichu** — je to tatáž volba jako u chyby
            // níž a s touž viditelnou půlkou: přijde dotaz na důvěru. Zapsat `true` cizí složce do
            // uživatelovy konfigurace by naopak nikdo nepoznal.
            //
            // **`refusal`, ne `isInsideCache`** (nález Copilota): to druhé je verdikt pro **mazání**
            // a symbolický odkaz na **samotné složce** neodmítá, protože `contains` rozbaluje jen
            // rodiče. Jenže klíč do konfigurace skládá `realpath`, který rozvine i poslední
            // komponentu — odkaz uvnitř cache mířící ven by tedy prošel kontrolou a zapsal se
            // **cizí cestou**. Zápis je zápis, takže si žádá obě kontroly.
            guard workspace == layout.root || CacheFile.refusal(for: workspace, in: layout) == nil
            else { continue }
            do {
                try await workspaceTrust.trust(workspace)
                trustedWorkspaces.insert(workspace)
            } catch {
                // **Nehlásí se, a jen tady**: složka se nezapíše do `trustedWorkspaces`, takže se
                // to při dalším otevření zásuvky zkusí znovu — a než se to povede, přijde ten dotaz
                // na důvěru, což je ta viditelná půlka. Cyklus se **nepřerušuje**: neúspěch u jedné
                // složky neříká nic o té druhé.
            }
        }
    }

    // MARK: - Kde relace startuje

    /// Adresář pro relaci `shell`: pracovní strom posledního review, jinak bare klon.
    private func resolvedShellDirectory(for pr: PRIdentifier) async -> URL? {
        // Osa posledního review — z ní je cesta ke stromu, ve kterém `claude --resume` session
        // najde (vlákna se klíčují adresářem, viz `TerminalSession.directory`).
        let worktree = timelines(for: pr).compactMap(\.worktree).last
        let clone = checkoutPath(for: pr)
        return Policy.terminalWorkingDirectory(
            worktree: await existingDirectory(worktree),
            clone: await existingDirectory(clone)
        )
    }

    /// Existuje ta složka? **Mimo hlavní vlákno** — je to sice jeden `stat`, ale disk umí zaseknout
    /// (síťový svazek, spící externí disk), a okno se kvůli hledání adresáře zaseknout nesmí.
    ///
    /// **Není `private`, protože na tutéž otázku se ptá i otevření souboru v editoru** (#530): oba
    /// hledají strom v cache, který mohla mezitím sebrat eviction. Druhá kopie by byla druhé místo,
    /// kde se dá zapomenout, že `stat` na hlavní vlákno nepatří.
    func existingDirectory(_ url: URL?) async -> URL? {
        guard let url else { return nil }
        return await Task.detached {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: url.path(percentEncoded: false),
                isDirectory: &isDirectory
            )
            return exists && isDirectory.boolValue ? url : nil
        }.value
    }

    // MARK: - Konec

    /// Kolik shellů právě běží — čte se při ukončení aplikace (#264). Od #460 **přes všechny
    /// relace**, ne jeden na PR.
    var runningTerminals: Int { terminals?.runningTerminals ?? 0 }

    /// Zabije **všechny relace** toho pull requestu.
    ///
    /// Volá se ze zavření záložky: ta je jediné místo, kde kontext PR doopravdy končí — cesta ke
    /// checkoutu, nálezy i rozdělané review se dají otevřít znovu, kdežto shelly by po zavřené
    /// záložce zůstaly běžet bez okna, ve kterém by šly vidět. Od #460 je jich víc a **osiřela by
    /// zrovna ta, která nebyla vidět**, takže se maže celý seznam, ne jen aktivní relace.
    func stopTerminal(for pr: PRIdentifier) {
        terminals?.stopTerminals(for: pr)
        for slot in terminalSlots[pr] ?? [] {
            terminalStates[slot] = nil
            terminalDirectories[slot] = nil
        }
        terminalSlots[pr] = nil
        activeTerminalSlots[pr] = nil
    }

    /// Zabije všechny shelly, protože se zavírá aplikace (#264, #351).
    ///
    /// **Synchronní**, na rozdíl od `stopReviewsBeforeTermination()`: signál odchází přímo z téhle
    /// cesty (`kill(2)`), ne přes zrušení tasku, takže není na co čekat — a čekání by naopak dalo
    /// systému čas aplikaci zavřít dřív, než by signál odešel.
    func stopTerminalsBeforeTermination() {
        terminals?.stopAllTerminals()
    }
}
