import Foundation

/// Jeden běh osmé session (#521) — napsat tělo návrhu review mým hlasem.
///
/// **Nese text, nic jiného.** Ani cestu k repozitáři, ani pull request, ani pracovní strom: session
/// nemá jediný nástroj, takže by neměla čím je použít — a typ, ve kterém se taková cesta nedá ani
/// napsat, je silnější tvrzení než prompt, který o ní mlčí. Je to tatáž volba jako u `BriefRequest`
/// a je na ni **negativní test**: ve vstupu nesmí být cesta do cache.
struct ReviewBodyRequest: Sendable, Equatable {
    /// Materiál. Skládá ho `Policy.reviewBodyInput`, ne runner — rozhodovací logika do promptu
    /// nepatří (tatáž úmluva jako u briefu z #516 a konfliktů z #467).
    let input: String
    let timeout: Duration

    init(input: String, timeout: Duration = ReviewBodyCommand.timeout) {
        self.input = input
        self.timeout = timeout
    }
}

/// Výsledek jednoho běhu.
struct ReviewBodyAnswer: Sendable, Equatable {
    /// Odstavec, který session napsala (`ReviewBodyCommand.parse`). `nil` = nenapsala nic
    /// použitelného — a **composer pak zůstane prázdný**, o čem pruh nad panelem mluví. Půlka
    /// odstavce je u textu odesílaného na GitHub horší než věta o tom, že se to nepovedlo.
    let text: String?
    /// Co běh stál. `nil` = cenu nenahlásil (zabitá session bez `result` eventu).
    let usage: RunUsage?
    /// Proč to nedopadlo. `nil` = doběhlo v pořádku.
    let failure: String?
}

/// Session, která **napíše tělo review mým hlasem** (#521) — osmá vyjmenovaná a třetí
/// s **prázdnou sadou nástrojů** (po překladu nálezů a briefu).
///
/// **Není to review logika, a proto sem patří.** Reviewer čte kód a hlásí nálezy; tahle session
/// nedostane ani `Read`, takže se o repozitáři nemá jak dozvědět nic — dostane hotové nálezy
/// z návrhu (#520) a moje starší těla review a **formuluje**. Kdyby měla číst kód, patřila by ta
/// úvaha do skillu, ne do aplikace (viz *Co aplikace je* v `CLAUDE.md`).
///
/// **Nic z toho neodesílá.** Výsledek končí v `ReviewDraft.body`, tedy tam, kde končí i to, co
/// napíšu sám — odejít umí jedině přes `ReviewPublishing.submit`, z potvrzení s celým payloadem
/// (tvrdá podmínka č. 1). Odstavec je **text v composeru**, editovatelný, nic víc.
///
/// Za protokolem ze stejného důvodu jako ostatní session: v testech se nahradí fakem a **z typu je
/// vidět, co to umí**. Jedna metoda, která bere text a vrací text; není tu nic, čím by se dalo
/// sáhnout na disk, na `git` nebo na GitHub.
///
/// **Selhání session není chyba volání** (tentýž vzor jako u revieweera, briefu a agenta): spadlá
/// i vytimeoutovaná session se vrací jako `ReviewBodyAnswer` s vyplněným `failure`, protože je to
/// výsledek, který se ukazuje. Vyhodí se jen `CancellationError`.
protocol ReviewBodyWriting: Sendable {
    func write(_ request: ReviewBodyRequest) async throws -> ReviewBodyAnswer
}
