import Foundation

/// Co je o **těle** návrhu review vidět (#521) — věta v pruhu nad panelem a dráha v `Průběhu`.
/// Čisté funkce, žádné I/O.
extension Policy {
    /// Jak se dráha těla jmenuje v tabu `Průběh` (#521).
    ///
    /// **Není to jméno skillu a nesmí se s ním potkat**: dráha se do seznamu reviewerů nedává,
    /// kreslí se pod ním zvlášť (jako anotace, #524), takže by dvě stejná `id` nemohla vzniknout
    /// ani tehdy, kdyby se nějaký skill takhle jmenoval.
    static let reviewBodyLaneName = "tělo review"

    /// Druhá řádka pruhu nad panelem: **odkud je ten odstavec** (#521). `nil` = pruh mlčí.
    ///
    /// **Tři věty, ne dvě**, a je to celý smysl tohohle rozhodnutí:
    ///
    /// 1. **Tělo je podle mých review.** To je stav, který issue popisuje — a věta z něj doslova.
    /// 2. **Tělo je napsané neutrálně.** Nový uživatel žádné uložené review nemá, takže by první
    ///    věta o jeho hlasu tvrdila víc, než data unesou — a je to zrovna ten vzor, který se
    ///    v tomhle repu hlídá (`docs/github-cli.md`).
    /// 3. **Tělo se nenapsalo.** Composer zůstal prázdný a bez věty je to k nerozeznání od návrhu,
    ///    ve kterém se tělo nepsalo vůbec (vypnutá session, starší razítko).
    ///
    /// **Nebere se `nil`em ticho u prvního stavu.** Pruh nad panelem existuje kvůli jediné větě:
    /// *co je pod ním, nenapsal jsem já*. Tělo je z toho ta největší část, takže o něm pruh musí
    /// mluvit i tehdy, když všechno dopadlo.
    static func reviewBodyNote(_ body: AutoDraftBody?) -> String? {
        guard let body else { return nil }
        switch body.failure {
        case .session(let detail):
            return "Tělo se nenapsalo, composer zůstal prázdný. \(detail)"
        case .handWritten:
            return "Tělo si píšeš sám — automat do composeru nesáhl."
        case nil:
            guard body.samples > 0 else {
                return "Tělo je napsané neutrálně — žádné tvoje odeslané review se ještě neuložilo."
            }
            return "Tělo je podle tvých posledních review (\(body.samples))."
        }
    }

    /// Dráha osmé session do tabu `Průběh` (#521). `nil` = **nekreslí se nic**.
    ///
    /// **Vlastní funkce, ne další položka v `Policy.lanes`** — tatáž podmínka jako u anotací
    /// (#524): `lanes` vypisuje **tytéž reviewery jako `Policy.chips`** (je na to test) a tělo mezi
    /// ně nepatří, protože chip vedle nich nese počet nálezů, který osmá session nemá a mít nebude.
    ///
    /// **Hlava se nehlídá tady, a to je správně.** `AutoDraftBody` leží v razítku návrhu, které
    /// vydává `Policy.autoDraftStamp(of:head:)` — a to se hlavy ptá. Druhá kontrola nad tou samou
    /// hodnotou by byla druhé místo, kde se dá zapomenout; tvrdá podmínka č. 5 tu platí **přes
    /// razítko**, ne vedle něj.
    ///
    /// Přednost má **běh** před uloženým výsledkem, jako u anotací: dokud session píše, je pravdou
    /// o tom PR ona.
    ///
    /// - Parameters:
    ///   - isRunning: píše se právě teď? Bere se z paměti storu — průběh se neukládá, takže po
    ///     restartu je odpověď `false` a dráha se vezme z razítka.
    ///   - body: co z běhu zbylo v razítku návrhu. `nil` = nepsalo se.
    ///   - samples: kolik vzorků hlasu šlo do **běžícího** zadání. Po doběhnutí se bere z razítka,
    ///     takže tenhle parametr platí jedině pro běžící dráhu.
    static func reviewBodyLane(isRunning: Bool, body: AutoDraftBody?, samples: Int = 0) -> ReviewerLane? {
        if isRunning {
            // `used: true` u běžící dráhy **nic netvrdí**: věta pod dráhou ho čte jedině u doběhlé
            // (`ReviewerLaneText.finished`), protože dokud session píše, není co použít ani
            // nepoužít. `false` by bylo stejně nevypovídající a svádělo by k tomu číst z něj stav.
            return reviewBodyLane(state: .running, samples: samples, used: true, body: nil)
        }
        guard let body else { return nil }
        // **`handWritten` je doběhlá dráha, ne spadlá**, a je to rozdíl, na kterém záleží: session
        // doběhla a peníze stála, jen se její odstavec nepoužil. Červená dráha by o běhu tvrdila,
        // že se pokazil — a to by poslalo hledat poruchu, která není.
        let state: ReviewerLane.State = switch body.failure {
        case .session(let detail): .failed(detail: detail)
        case .handWritten, nil: .finished
        }
        return reviewBodyLane(state: state, samples: body.samples, used: body.isUsed, body: body)
    }

    /// Jedna dráha. **Dvě fáze, ne tři jako u revieweera a u anotací** — a je to tvrzení, ne
    /// zkratka: osmá session nemá jediný nástroj, takže fáze `prochází kód` by u ní byla krok,
    /// který se nemá jak stát. Tvar běhu je `session → píše tělo`.
    private static func reviewBodyLane(
        state: ReviewerLane.State,
        samples: Int,
        used: Bool,
        body: AutoDraftBody?
    ) -> ReviewerLane {
        let failed = state != .running && state != .finished
        return ReviewerLane(
            skill: reviewBodyLaneName,
            kind: .reviewBody(samples: samples, used: used),
            state: state,
            phases: [
                ReviewerLane.Phase(
                    title: ReviewerLane.Title.session,
                    detail: nil,
                    state: failed ? .failed : .done
                ),
                ReviewerLane.Phase(
                    title: ReviewerLane.Title.body,
                    detail: nil,
                    state: failed ? .failed : (state == .running ? .running : .done)
                ),
            ],
            lastTool: nil,
            finishedAt: body?.finishedAt,
            // **Navěky `nil`, a je to to tvrzení**: odstavec není nález, takže dráha nesmí nést
            // číslo, které se čte jako „tolik toho našla“. Co napsala, nese `kind`.
            reportedFindings: nil,
            usage: body?.usage,
            // **Obojí `nil` schválně.** Session nemá pracovní strom, takže `Policy.rawSessionTarget`
            // ani `Policy.terminalSession` nemají z čeho cíl složit — a tlačítko `Surová session`
            // nad session bez stromu by slibovalo přepis, ke kterému se nedá dojít. Sessioní `id`
            // se proto ani nedrží: údaj, ze kterého v okně nic neplyne, je jen další pole, které se
            // umí rozejít s pravdou.
            sessionID: nil,
            worktree: nil,
            droppedEntries: 0,
            loadedSkill: nil,
            intentGap: nil,
            // Rozbalovací výpis kroků dráha nemá — session bez nástrojů žádné kroky nedělá.
            entries: [],
            increment: nil,
            wholeReason: nil,
            // **`true`, ne `false`**: kapsle `mimo sadu` mluví o skillu, který z nastavení zmizel,
            // a u těla by tvrdila, že sem tahle dráha nepatří.
            isConfigured: true
        )
    }
}
