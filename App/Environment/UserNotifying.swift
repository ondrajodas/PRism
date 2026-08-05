import Foundation

/// Doručení notifikace a kliknutí na ni.
///
/// Notifikace jsou přístup ke stroji jako podprocesy nebo hodiny, takže patří sem a za
/// protokol — `AppStore` na `UNUserNotificationCenter` sahat nemá a v testech se nesmí
/// doručovat nic. Vrstva bez konzumenta: první, kdo ji použije, je #82.
///
/// **O oprávnění si říká `deliver(_:)` sám**, ne zvláštní metoda. Dialog se má objevit až
/// u první notifikace, ne při startu (ten hned po instalaci se odklikne pryč) — a když je
/// to jedna cesta, nedá se ta chvíle minout ani zapomenout. Cenou je, že se stav oprávnění
/// nedozvíme, dokud se něco neposílá; to je ale právě ta zamýšlená vlastnost.
protocol UserNotifying: Sendable {
    /// Doručí notifikaci. Při prvním volání si vyžádá oprávnění.
    ///
    /// Nevyhazuje: odmítnuté oprávnění ani selhání systému nejsou chyba běhu aplikace, jen
    /// důvod, proč nic nepřišlo — a ten musí jít **vyjmenovat**, ne spolknout.
    func deliver(_ notification: PullRequestNotification) async -> NotificationDelivery

    /// Proud kliknutí — pull requesty, na jejichž notifikaci se kliklo.
    ///
    /// **Jeden konzument.** Delegáta má systém jednoho, takže i proud je jeden: druhé volání
    /// by prvnímu kliknutí kradlo. Proud si je přitom **drží**, dokud si je někdo nevyzvedne
    /// — systém umí doručit kliknutí dřív, než se `AppStore` vůbec složí (aplikaci spustilo
    /// právě to kliknutí), a taková notifikace se nesmí ztratit.
    func clicks() -> AsyncStream<PRIdentifier>
}

/// Notifikace, kterou aplikace posílá. Vždycky se váže na pull request.
///
/// Identifikátor je **typ, ne text k parsování**: klik z něj musí vybrat řádek, a řetězec
/// složený do titulku by se musel rozebírat zpátky. Že se na disk (do `userInfo`) ukládá
/// jako řetězec, je věc implementace — `PRIdentifier` je `LosslessStringConvertible`.
struct PullRequestNotification: Sendable, Equatable {
    /// Koho se notifikace týká. Klik na ni vybere tenhle PR.
    let pullRequest: PRIdentifier
    let title: String
    let body: String
    /// Co ji vyvolalo (#86). Nese si to notifikace sama, aby brána nemusela hádat z textu —
    /// druhá cesta k témuž údaji by se s první rozešla.
    let event: NotificationEvent

    /// Identita, pod kterou se notifikace doručí (#87).
    ///
    /// **Stejná identita nahradí to, co ještě visí** — a je to schválně: druhý výsledek review
    /// nad tímtéž PR je oprava toho prvního, ne druhá informace.
    ///
    /// Skládá se z PR a **skupiny** události, ne z události samotné: všechny tři výsledky review
    /// se navzájem přepisují (`NotificationEvent.replacementGroup`), takže po opakovaném běhu
    /// nezůstane vedle „3 nálezy“ viset stará hláška „nenašel žádný nález“. Hláška o novém PR
    /// má vlastní skupinu, protože to je jiná informace.
    ///
    /// **Změna proti #88**, kde to bylo náhodné `UUID`, aby se nic nenahrazovalo. Tehdy to bylo
    /// správně (slévání ještě nebylo rozhodnuté), teď je náhrada ta žádaná vlastnost.
    var identifier: String {
        "\(pullRequest)|\(event.replacementGroup)"
    }

    /// Do kterého vlákna notifikace patří (#87) — podle něj je systém řadí k sobě.
    ///
    /// **Podle PR**, ne podle repa: notifikace o témž pull requestu patří k sobě (nový PR, pak
    /// jeho review), kdežto seskupení po repu by u firemního monorepa slilo věci, které spolu
    /// nemají nic společného. Souhrn za víc PR má vlastní vlákno — viz `Policy`.
    var threadIdentifier: String {
        pullRequest.description
    }
}

/// Jak dopadlo doručení.
///
/// Tři případy, ne boolean: „uživatel to zakázal“ a „systém to nevzal“ vedou jinam.
/// První se dá spravit jedině v Nastavení systému, druhá je chyba, u které je co vypsat —
/// a `AppStore` z toho skládá dvě různé věty. Tatáž úvaha jako u `ReviewState`, kde se
/// `clean` nesmí slít s `failed`.
enum NotificationDelivery: Sendable, Equatable {
    /// Předáno systému. Že se notifikace **ukázala**, odsud poznat nejde — o zobrazení
    /// rozhoduje systém (soustředění, zrcadlení obrazovky).
    case delivered
    /// Oprávnění není. Aplikace kvůli tomu **nespadne, jen mlčí** — a právě proto to musí
    /// být v okně vidět, jinak se bude hledat, proč nic nechodí.
    case notAuthorized
    /// Systém doručení odmítl. Text je to, co k tomu řekl.
    case failed(String)

    /// Má cenu to zkusit znovu? (#85)
    ///
    /// **Jen u `failed`.** Zakázané oprávnění se opakováním nespraví, takže zkoušet ho každou
    /// minutu je volání za nic — a `delivered` se opakovat nemá vůbec. Rozlišení bydlí tady,
    /// ne u volajícího: kdyby si ho každý odvozoval sám, druhá kopie by u nového případu
    /// výčtu odpověděla jinak.
    var isWorthRetrying: Bool {
        if case .failed = self { return true }
        return false
    }
}
