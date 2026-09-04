import AppKit
import Foundation

/// Odskok do Nastavení systému (#414, druhý panel #529).
///
/// Existuje kvůli místům, kde aplikace **sama nedosáhne** a stav bez dalšího kroku by byl hláška,
/// u které se nedá nic dělat: prázdný stav sekce `Dění`, když systém notifikace **zakázal**
/// (`UNUserNotificationCenter` povolení znovu vyžádat neumí, jednou odmítnuté zůstává odmítnuté),
/// a od #529 přihlašovací položka **vypnutá v Nastavení systému** (`requiresApproval` —
/// `SMAppService.register()` ten zákaz nezvrátí).
///
/// **Vlastní typ, ne `NSWorkspace` ve view.** Adresa je jediné, co se na tom dá pokazit, a takhle
/// se dá zkontrolovat testem, aniž by se v něm otevíralo okno systému.
enum SystemSettings {
    /// Panel `Oznámení` v Nastavení systému.
    ///
    /// Schéma `x-apple.systempreferences:` s identifikátorem panelu. **Bez `?PRism`**: hledání
    /// aplikace v tom seznamu si systém řídí sám a parametr, který se změní s verzí systému,
    /// znamená odkaz, který jednoho dne otevře prázdno.
    static let notifications = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")

    /// Otevře panel `Oznámení`. Když se adresa nesloží nebo ji systém odmítne, **nestane se nic** —
    /// je to odskok, ne operace s následkem, takže hlásit „nepodařilo se otevřít nastavení“ by
    /// zabralo místo hláškám, po kterých má následovat akce.
    static func openNotifications() {
        guard let notifications else { return }
        NSWorkspace.shared.open(notifications)
    }

    /// Panel `Položky při přihlášení` v Nastavení systému (#529).
    ///
    /// Tentýž tvar jako u `notifications`, tedy schéma s identifikátorem panelu a **bez
    /// parametru s aplikací**: seznam si systém řídí sám a parametr, který se změní s verzí
    /// systému, znamená odkaz, který jednoho dne otevře prázdno.
    static let loginItems = URL(
        string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    )

    /// Otevře panel `Položky při přihlášení`. Selhání se **nehlásí**, ze stejného důvodu jako
    /// u notifikací: je to odskok, ne operace s následkem.
    static func openLoginItems() {
        guard let loginItems else { return }
        NSWorkspace.shared.open(loginItems)
    }
}
