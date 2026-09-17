import Foundation

/// Odložený běh (#519) — automat se na tenhle PR podíval, poznal, že je velký, a slíbil ho na noc.
///
/// **Ukládá se na disk** (`deferred.json`), protože bez toho by noc bez běžící aplikace neudělala
/// nic a ráno by to vypadalo, že automat nefunguje. Slib se drží i po restartu: co se nestihlo,
/// se pustí při prvním tiku po `runAt`.
///
/// **Klíčuje se k PR, ne k `headSha`** — jako odložení PR (#512) a ze stejného důvodu: odklad není
/// nález, takže tvrdá podmínka č. 5 na něj nedopadá. Hlavu si přesto nese, protože je to jediné,
/// z čeho se pozná, o kterém kódu se rozhodovalo; po pushi se rozhoduje znovu (viz
/// `AppStore.review`).
struct DeferredRun: Codable, Hashable, Sendable {
    let pullRequest: PRIdentifier
    /// Hlava, nad kterou odklad padl. Do rozhodování nevstupuje — je to záznam, ne podmínka.
    let headSha: String
    /// Kolik řádků PR mění. **Z hlavičky PR** (`additions + deletions`), ne z diffu: ten se
    /// u velkého PR nemusí ani stáhnout (#542 — nad 300 souborů vrací GitHub 406), takže by se
    /// práh nedal změřit zrovna u toho, kvůli komu existuje.
    let changedLines: Int
    /// Práh, který v tu chvíli platil. Ukládá se, aby věta v dráze říkala **to, podle čeho se
    /// rozhodlo** — ne to, co je v nastavení dneska.
    let threshold: Int
    let deferredAt: Date
    /// Kdy se má pustit. Nejbližší začátek tichých hodin po `deferredAt`.
    let runAt: Date
}
