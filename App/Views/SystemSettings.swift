import AppKit
import Foundation

/// Odskok do Nastavení systému (#414).
///
/// Existuje kvůli jedinému místu: prázdný stav sekce `Dění`, když systém notifikace **zakázal**.
/// Aplikace tam sama nedosáhne (`UNUserNotificationCenter` povolení znovu vyžádat neumí, jednou
/// odmítnuté zůstává odmítnuté), takže otevřít ten panel je jediný další krok, který se dá
/// nabídnout — a stav bez dalšího kroku je hláška, u které se nedá nic dělat.
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
}
