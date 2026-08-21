import Foundation

/// Přepis surové session, jak ho drží store (#327).
///
/// **Jeden, ne slovník.** Sheet je v okně nejvýš jeden a snímek má megabajty, takže slovník by byl
/// paměť, kterou nikdo nečte — a přesně to `CLAUDE.md` popisuje jako mrtvou váhu. Zavřením sheetu
/// se zahodí (`AppStore.closeRawSession()`), takže se držení omezuje na dobu, po kterou je vidět.
struct RawSessionSnapshot: Equatable, Sendable {
    let target: RawSessionTarget
    var state: RawTranscriptState
    /// Velikost transcriptu při poslední kontrole. `nil` = ještě se neptalo, nebo se nedala zjistit.
    var currentBytes: Int?
}

extension AppStore {
    /// Otevře přepis transcriptu pro tuhle session (#327).
    ///
    /// **Sheet se otevírá hned a obsah dorazí za chvíli** (`.loading`): čte se ze disku, takže je to
    /// zlomek vteřiny, ale ne nula — a sheet, který se otevře až po dočtení, vypadá po kliknutí jako
    /// tlačítko, které nic neudělalo.
    func openRawSession(_ target: RawSessionTarget) async {
        rawSession = RawSessionSnapshot(target: target, state: .loading, currentBytes: nil)
        await loadRawSession(target)
    }

    /// `Načíst znovu` — tentýž snímek znovu, protože soubor mezitím vyrostl.
    ///
    /// **Nepřepíná na `.loading`**, když už něco vidíme: přepis by na okamžik zmizel a scroll by
    /// skočil na začátek, tedy zrovna to, kvůli čemu se přepis neaktualizuje sám.
    func reloadRawSession() async {
        guard let target = rawSession?.target else { return }
        await loadRawSession(target)
    }

    /// Zahodí snímek. Volá se **při zavření sheetu i při přepnutí PR** — snímek patří jedné session
    /// a je to zároveň to, co v okně drží nejvíc paměti.
    func closeRawSession() {
        rawSession = nil
    }

    /// Stav přepisu **té session**, kterou sheet ukazuje.
    ///
    /// Ptá se na cíl schválně: dvě rychlá kliknutí na dvou dráhách by jinak nakreslila přepis jedné
    /// session pod titulkem druhé — a to je přesně ten druh chyby, který se nepozná, protože obojí
    /// vypadá jako platný přepis.
    func rawSessionState(of target: RawSessionTarget) -> RawTranscriptState {
        guard let session = rawSession, session.target == target else { return .loading }
        return session.state
    }

    /// Kolik od snímku přibylo, jak to hlásí patička. `nil` = není co říct.
    func rawSessionGrowth() -> Int? {
        guard let session = rawSession, case .shown(let transcript) = session.state else { return nil }
        return Policy.rawSessionGrowth(snapshot: transcript.fileBytes, now: session.currentBytes)
    }

    /// Přeměří velikost transcriptu, ať patička ví, kolik od otevření přibylo.
    ///
    /// Je to **jeden dotaz na atributy souboru**, ne druhé čtení: patička se z něj dozví jen číslo.
    /// Zapisuje se **jen na změně** — bezpodmínečný zápis do observable stavu z opakovaného úkolu je
    /// ta třída chyb, kterou popisuje #358.
    func refreshRawSessionSize() async {
        guard let session = rawSession, let transcripts else { return }
        let size = await transcripts.size(ofSession: session.target.sessionID, in: session.target.worktree)
        // Cíl se mezitím mohl změnit (jiná dráha, zavřený sheet) — pak číslo patří někomu jinému.
        guard rawSession?.target == session.target, rawSession?.currentBytes != size else { return }
        rawSession?.currentBytes = size
    }

    /// Cesta k transcriptu — `Zkopírovat cestu k transcriptu` a `Ukázat v Finderu`.
    ///
    /// **Doslovný JSON se v okně neukazuje** (rozhodnuto u #327): soubor je lokální, takže na to
    /// stačí cesta a Finder. Na `jq` si aplikace hrát nebude.
    func rawSessionPath(of target: RawSessionTarget) -> URL {
        TranscriptLocation.transcript(
            ofSession: target.sessionID,
            in: target.worktree,
            projects: TranscriptLocation.defaultProjects
        )
    }

    /// **`do`/`catch`, ne `try?`.** Ten by obě odpovědi slil do `nil` — Swift výsledek `try?` nad
    /// funkcí vracející optional zplošťuje —, a rozdíl mezi nimi je tady celý smysl: transcript,
    /// který **není**, už nebude, kdežto ten, který se nedá **přečíst**, tam pořád leží. Je to tatáž
    /// past jako u dotahování nálezů z transcriptu (#97), kde ji chytil test.
    private func loadRawSession(_ target: RawSessionTarget) async {
        guard let transcripts else {
            rawSession = RawSessionSnapshot(
                target: target,
                state: .unreadable("Čtení transcriptů není v tomhle běhu zapnuté."),
                currentBytes: nil
            )
            return
        }

        let state: RawTranscriptState
        do {
            let snapshot = try await transcripts.snapshot(
                ofSession: target.sessionID,
                in: target.worktree,
                at: .now
            )
            state = snapshot.map(Policy.rawSessionState(of:)) ?? .missing
        } catch {
            state = .unreadable(error.localizedDescription)
        }

        // Mezitím se mohl sheet zavřít nebo otevřít jiná dráha — dočtený snímek by pak přepsal
        // stav, o který nikdo nežádal. Je to tatáž brána jako u pozdní události v ose (#308).
        guard rawSession?.target == target else { return }
        rawSession?.state = state
        rawSession?.currentBytes = nil
        await refreshRawSessionSize()
    }
}
