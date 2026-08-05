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
}
