import AppKit

/// Zachytí ukončení aplikace, dokud běží review.
///
/// Session se zavřením aplikace **zabije** a nálezy, které reviewer už nahlásil, jsou pryč
/// — v panelu i na disku. Ověřeno v provozu (#94): PR se dvěma nálezy, z toho jedním
/// `correctness`, skončil po restartu jako `neběželo`.
///
/// Dialog to nevyřeší úplně (pád aplikace ani zabití zvenčí se takhle zachytit nedají), ale
/// pokrývá to, co způsobí uživatel svým jednáním — a to je většina případů. Dotažení nálezů
/// z transcriptu zůstává v #94 jako ta drahá varianta pro zbytek.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Kolik review právě běží. Doplní `PRismApp`, jakmile má store; do té doby nic neběží.
    @MainActor var runningReviews: () -> Int = { 0 }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            let running = runningReviews()
            guard running > 0 else { return .terminateNow }
            return ask(about: running) ? .terminateNow : .terminateCancel
        }
    }

    /// `NSAlert` a `runModal()` schválně, ne SwiftUI: `applicationShouldTerminate` musí
    /// odpovědět **synchronně**, jinak se aplikace ukončí, než se kdokoli zeptá.
    @MainActor private func ask(about running: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = running == 1
            ? "Běží review. Ukončit teď?"
            : "Běží \(running) review. Ukončit teď?"
        // Text říká, co se ztratí, ne jen že se něco děje. „Běží review“ samo o sobě nedává
        // důvod kliknout na Zpět.
        alert.informativeText = """
        Ukončením se session zabije a nálezy, které už reviewer nahlásil, se ztratí. \
        Co doběhlo, zůstane uložené.
        """
        alert.addButton(withTitle: "Ukončit")
        alert.addButton(withTitle: "Zpět")
        // Zpět jako výchozí: ztracený nález je dražší než jedno kliknutí navíc.
        alert.buttons.last?.keyEquivalent = "\r"
        alert.buttons.first?.keyEquivalent = ""
        return alert.runModal() == .alertFirstButtonReturn
    }
}
