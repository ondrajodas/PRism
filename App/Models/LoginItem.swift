import Foundation

/// Stav přihlašovací položky (#529) — obraz `SMAppService.Status` bez závislosti na
/// `ServiceManagement`.
///
/// Vlastní typ, aby se dala rozhodovací funkce v `Policy` projít výčtem a aby `App/Store/`
/// nemusel na systémový framework vidět. Čtyři případy, jako u systémového typu — a **žádný
/// pátý pro „nevím“**: status se čte synchronně a vždycky něco vrátí.
enum LoginItemStatus: String, Equatable, Sendable {
    /// Položka v systému není. Výchozí stav a taky to, co se dosadí za neznámý budoucí případ
    /// systémového výčtu: „nespustí se po přihlášení“ je z těch čtyř vět ta, po které nikdo
    /// nezůstane oklamaný, a kliknutí na přepínač se pak pokusí o zápis, který je idempotentní.
    case notRegistered
    /// Zapsaná a povolená — aplikace se po přihlášení spustí.
    case enabled
    /// Zapsaná, ale **vypnutá v Nastavení systému**. Aplikace tam nedosáhne, takže je to stav,
    /// ke kterému patří odskok, ne opakovaný pokus o zápis.
    case requiresApproval
    /// Systém položku téhle aplikace nenašel — rozbitá nebo přesunutá instalace.
    case notFound
}

/// Nepovedený zápis do systému (#529) — **s tím, o co si člověk řekl**.
///
/// Drží se obojí, protože přepínač se po selhání **nesmí tiše vrátit** do vypnuté polohy
/// (poznámka 181 v návrhu): vypadalo by to, jako by kliknutí nedošlo. Ukazuje se tedy poloha,
/// o kterou si člověk řekl, a k ní věta, proč se to nepovedlo.
struct LoginItemFailure: Equatable, Sendable {
    /// Do jaké polohy se přepínač cvakl.
    let requested: Bool
    /// Co k tomu řekl systém. Hláška zůstává, jak přišla — je to jediné, podle čeho se dá
    /// zjistit, co vlastně vadilo.
    let message: String
}

/// Který bundle to o sobě tvrdí (#529).
///
/// Existuje proto, aby se rozhodnutí „smí tahle instalace zakládat přihlašovací položku“ dalo
/// projít výčtem bez `Bundle.main`. Jméno i cesta jsou fakta o instalaci, ne volby.
struct AppInstallation: Equatable, Sendable {
    /// `CFBundleName`. Slot má `PRism-a`, `PRism-d`, … — na tom stojí celé oddělení slotů (#228),
    /// takže je to i to jediné, čím se slotová instance pozná zvnitřku.
    let name: String
    /// Kde bundle leží. Cesta, ne URL: porovnává se prefix a píše se do věty pod přepínačem.
    let path: String

    /// Ta instalace, která právě běží.
    ///
    /// **Bez `fatalError` u chybějícího `CFBundleName`**, na rozdíl od `CacheLayout`: tam je jméno
    /// kořen cache, takže tichý default znamená sáhnout do dat jiné instance. Tady je nejhorší
    /// následek prázdného jména zašedlý přepínač s větou — tedy ta bezpečná strana sama.
    @MainActor static let main = AppInstallation(
        name: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "",
        path: Bundle.main.bundlePath
    )
}
