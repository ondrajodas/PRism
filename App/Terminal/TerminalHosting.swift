import AppKit

/// Vestavěné terminály (#459) — kdo je drží, kdo je umí vyrobit a kdo je umí zabít.
///
/// **Za protokolem ze stejného důvodu jako zbytek vnějšího světa**: shell je cizí proces, který
/// se v testu nedá ani spolehlivě vyrobit, ani vzít zpátky. Nejcennější tvrzení kolem něj je
/// přitom „něco se **ne**stalo“ — že zavření záložky shell zabilo a že ukončení aplikace po sobě
/// nic nenechalo —, a to jde napsat jedině proti fake implementaci.
///
/// **Tvrdá podmínka č. 1 se tím mění, ale jinak, než by se čekalo** (viz `CLAUDE.md`): aplikace
/// sama pořád nic neodesílá a publisher v `App/Publish/` zůstává jedinou cestou ven **v jejím
/// kódu** — tenhle protokol žádnou zápisovou metodu nemá a nezná ani `gh`. Co přestává platit, je
/// dokazatelnost testem: ze shellu, který si člověk pustí, jde `gh pr merge` i `git push`, a na to
/// žádná stráž v kódu nedosáhne. Plnou moc má odsud **člověk**, ne aplikace, a hlavička zásuvky to
/// říká kapslí `plná práva`.
///
/// Jméno protokolu publisheru se tu **schválně nepíše**: `CLAUDE.md` slibuje, že grep na něj vypíše
/// pořád tentýž seznam souborů, a comment navíc by ten slib porušil, aniž by co přidal.
@MainActor
protocol TerminalHosting: AnyObject {
    /// Kolik shellů právě běží. Čte se při ukončení aplikace (#264, #94).
    var runningTerminals: Int { get }

    /// Kam se hlásí změna stavu shellu, aby ji mohlo okno nakreslit.
    ///
    /// Uzávěr, ne `@Observable` na protokolu: pozorování přes existenciál nefunguje, kdežto stav
    /// v `AppStore` je to, co okno kreslí odjakživa. Je to tentýž tvar jako `health.lastCall`
    /// nebo `polling.afterSuccessfulTick`.
    var report: (@MainActor (PRIdentifier, TerminalRunState) -> Void)? { get set }

    /// Kam se hlásí, že zásuvka získala nebo ztratila fokus.
    ///
    /// Na tomhle jediném signálu stojí poznámka 110 z návrhu: dokud je aktivní terminál, okenní
    /// zkratky bez `⌘` se neuplatní (`Policy.shortcutYieldsToTerminal`). Je to **jeden příznak na
    /// okno, ne na pull request** — fokus má v jednu chvíli právě jedno místo.
    var focusChanged: (@MainActor (Bool) -> Void)? { get set }

    /// Plocha terminálu toho pull requestu — **vyrobí ji, když ještě není, jinak vrátí tutéž**.
    ///
    /// Idempotence je podmínka, ne pohodlí: `makeNSView` se volá při každém složení SwiftUI stromu,
    /// takže nová plocha při každém překreslení by znamenala nový shell při každém překreslení.
    func terminal(for pr: PRIdentifier, in directory: URL) -> NSView

    /// Zabije shell toho pull requestu; `true`, když nějaký byl.
    ///
    /// Volá se ze zavření záložky a ze zavření zásuvky, takže musí být bezpečné zavolat to nad
    /// pull requestem, který terminál nikdy neměl.
    @discardableResult func stopTerminal(for pr: PRIdentifier) -> Bool

    /// Zabije všechny — ukončení aplikace (#264, #351).
    func stopAllTerminals()
}
