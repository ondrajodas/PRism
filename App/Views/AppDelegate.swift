import AppKit

/// Zachytí ukončení aplikace, dokud běží review.
///
/// Dělá u toho dvě věci a každá řeší jinou ztrátu:
///
/// 1. **Zeptá se** (#94). Nálezy, které reviewer nahlásil, jsou v běžící session, ne na disku,
///    a zavřít okno uprostřed review je obvykle omyl. Dialog nepokrývá pád aplikace ani zabití
///    zvenčí — to dotahuje #97 z transcriptu — ale pokrývá to, co uživatel způsobí svým
///    jednáním, a to je většina případů.
/// 2. **Zabije běžící session** (#264). Do té doby se `claude` zavřením aplikace **nezabil**:
///    osiřelý proces se přerodil na `launchd` a běžel dál — platilo se za review, které už
///    nemá komu doručit nálezy, a držel pracovní strom v cache, který se proto nesmí uklidit.
///    Změřeno: dvě takové session běžely na stroji čtyři dny.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Kolik review právě běží. Doplní `PRismApp`, jakmile má store; do té doby nic neběží.
    @MainActor var runningReviews: () -> Int = { 0 }

    /// Zabije běžící review a vrátí se, teprve když po nich nic nezůstalo (#264). Doplní
    /// `PRismApp` ze stejného důvodu jako `runningReviews`.
    @MainActor var stopReviews: @MainActor () async -> Void = {}

    /// Jak se zeptat. Vlastnost, ne jen metoda, kvůli testům: `NSAlert.runModal()` v nich čeká
    /// na kliknutí, které nikdo neudělá.
    @MainActor var confirmQuit: @MainActor (Int) -> Bool = { AppDelegate.ask(about: $0) }

    /// Odpověď systému, že se aplikace smí zavřít. Taky vlastnost, a taky kvůli testům:
    /// `reply(toApplicationShouldTerminate:)` mimo odložené ukončení by hosta testů ukončil
    /// doopravdy.
    @MainActor var allowTermination: @MainActor () -> Void = {
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    /// Zabíjení už běží, takže se na nic nečeká a nic se nepotvrzuje podruhé.
    @MainActor private var isStoppingReviews = false

    /// Delegát notifikací musí stát dřív, než systém doručí první kliknutí (#88).
    ///
    /// Když aplikaci spustilo právě kliknutí na notifikaci, přijde hned po startu — tedy dřív,
    /// než projde preflight a složí se `AppStore`. Bez tohohle by delegát vznikl teprve s ním
    /// a kliknutí by se ztratilo; proud kliknutí si je proto podrží, dokud si je store
    /// nevyzvedne. **O oprávnění se tím nežádá** — na to se čeká až do první notifikace.
    func applicationDidFinishLaunching(_ notification: Notification) {
        SystemNotificationCenter.prepare()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            // Druhý pokus během těch dvou sekund, co se zabíjí, jen zopakuje odpověď. Jinak by
            // otevřel druhý dialog nad ukončením, které už běží, a systému by se odpovědělo
            // dvakrát — `reply(toApplicationShouldTerminate:)` je na jedno odložené ukončení.
            guard !isStoppingReviews else { return .terminateLater }

            let running = runningReviews()
            guard running > 0 else { return .terminateNow }
            guard confirmQuit(running) else { return .terminateCancel }
            isStoppingReviews = true

            // **Odloží se jen zabíjení, ne dotaz.** Dotaz musí padnout synchronně, jinak by se
            // aplikace zavřela dřív, než se kdokoli zeptá (#94); zabití session je proti tomu
            // `async` — jde přes zrušení běhu, které si musí projít několik hopů mezi aktory.
            // `terminateNow` hned po něm by aplikaci zavřel dřív, než signál odejde, a přesně
            // to bylo #264. Odpověď dorazí vždycky: `stopReviewsBeforeTermination` má vlastní
            // strop, takže ze zaseknuté session nevznikne aplikace, která se nedá zavřít.
            Task { @MainActor in
                await stopReviews()
                allowTermination()
            }
            return .terminateLater
        }
    }

    /// `NSAlert` a `runModal()` schválně, ne SwiftUI: dotaz musí padnout **synchronně**, jinak
    /// se aplikace ukončí, než se kdokoli zeptá.
    @MainActor private static func ask(about running: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = running == 1
            ? "Běží review. Ukončit teď?"
            : "Běží \(running) review. Ukončit teď?"
        // Text říká, co se stane, ne jen že se něco děje. „Běží review“ samo o sobě nedává
        // důvod kliknout na Zpět. **Neslibuje ale ani víc, než co data unesou:** dotáhne se to,
        // co reviewer do zabití nahlásil, a jen z běhu, který stihl ohlásit svoje id session.
        alert.informativeText = """
        Běžící session se ukončením zabijí. Co doběhlo, zůstane uložené; z nedoběhlého se po \
        dalším spuštění dotáhne, co reviewer nahlásil do té chvíle.
        """
        alert.addButton(withTitle: "Ukončit")
        alert.addButton(withTitle: "Zpět")
        // Zpět jako výchozí: ztracený nález je dražší než jedno kliknutí navíc.
        alert.buttons.last?.keyEquivalent = "\r"
        alert.buttons.first?.keyEquivalent = ""
        return alert.runModal() == .alertFirstButtonReturn
    }
}
