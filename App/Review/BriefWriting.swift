import Foundation

/// Jeden běh šesté session (#516) — složit až tři pojmenované věty ze stavu aplikace.
///
/// **Nese text, nic jiného.** Ani cestu k repozitáři, ani pull request, ani pracovní strom:
/// session nemá jediný nástroj, takže by neměla čím je použít — a typ, ve kterém se taková cesta
/// nedá ani napsat, je silnější tvrzení než prompt, který o ní mlčí.
struct BriefRequest: Sendable, Equatable {
    /// Materiál. Skládá ho `Policy.briefInput`, ne runner — rozhodovací logika do promptu nepatří
    /// (tatáž úmluva jako u konfliktů z #467 a agenta z #510).
    let input: String
    let timeout: Duration

    init(input: String, timeout: Duration = BriefCommand.timeout) {
        self.input = input
        self.timeout = timeout
    }
}

/// Výsledek jednoho běhu.
struct BriefAnswer: Sendable, Equatable {
    /// Co session napsala, rozebrané na pojmenované řádky (`BriefCommand.parse`). `nil` =
    /// nenapsala nic použitelného — a to je **porucha, ne prázdno**: blok o tom musí říct, jinak
    /// vypadá jako „nic se neděje“.
    ///
    /// **Jeden nebo dva řádky jsou v pořádku.** Otázka, na kterou ve vstupu odpověď není, se má
    /// vynechat — vynucená věta je zrovna to, čemu se tím vyhýbáme.
    let lines: [BriefLine]?
    /// Co běh stál. `nil` = cenu nenahlásil (zabitá session bez `result` eventu).
    let usage: RunUsage?
    /// Proč to nedopadlo. `nil` = doběhlo v pořádku.
    let failure: String?
}

/// Session, která **přečte stav aplikace nahlas** (#516) — šestá vyjmenovaná a druhá
/// s **prázdnou sadou nástrojů** (první je překlad nálezů).
///
/// **Není to review logika, a proto sem patří.** Review čte kód a hlásí nálezy; tahle session
/// nedostane ani `Read`, takže se o repozitáři nemá jak dozvědět nic — dostane hotový text
/// z `Policy.briefInput` a **přeformuluje** ho. Kdyby měla číst kód, patřila by ta úvaha do
/// skillu, ne do aplikace (viz *Co aplikace je* v `CLAUDE.md`).
///
/// Za protokolem ze stejného důvodu jako ostatní session: v testech se nahradí fakem a **z typu
/// je vidět, co to umí**. Jedna metoda, která bere text a vrací text; není tu nic, čím by se dalo
/// sáhnout na disk, na `git` nebo na GitHub.
///
/// **Selhání session není chyba volání** (tentýž vzor jako u revieweera, konfliktů a agenta):
/// spadlá i vytimeoutovaná session se vrací jako `BriefAnswer` s vyplněným `failure`, protože je
/// to výsledek, který se ukazuje. Vyhodí se jen `CancellationError`.
protocol BriefWriting: Sendable {
    func write(_ request: BriefRequest) async throws -> BriefAnswer
}
