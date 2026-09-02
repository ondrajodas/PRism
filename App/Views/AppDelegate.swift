import AppKit

/// Zachytí ukončení aplikace, dokud běží review — a při startu uklidí, co po zabité aplikaci
/// zbylo.
///
/// Dělá u toho čtyři věci a každá řeší jinou ztrátu:
///
/// 1. **Zeptá se** (#94). Nálezy, které reviewer nahlásil, jsou v běžící session, ne na disku,
///    a zavřít okno uprostřed review je obvykle omyl. Dialog nepokrývá pád aplikace ani zabití
///    zvenčí — to dotahuje #97 z transcriptu — ale pokrývá to, co uživatel způsobí svým
///    jednáním, a to je většina případů.
/// 2. **Zabije běžící session** (#264). Do té doby se `claude` zavřením aplikace **nezabil**:
///    osiřelý proces se přerodil na `launchd` a běžel dál — platilo se za review, které už
///    nemá komu doručit nálezy, a držel pracovní strom v cache, který se proto nesmí uklidit.
///    Změřeno: dvě takové session běžely na stroji čtyři dny.
/// 3. **Uklidí sirotky při startu** (#351). Body 1 a 2 platí pro **normální** ukončení; když se
///    aplikace zabije zvenčí — typicky proto, že ztuhla a na Apple event nereaguje — nemá se úklid
///    kde spustit a `claude -p` běží dál pod `launchd`. Změřeno `ps -o ppid` na potomkovi
///    `Foundation.Process`u: přežije rodičovi `SIGTERM` i `SIGKILL`. Prevence na macOS není
///    (viz `RunningSessions`), takže zbývá úklid při dalším startu.
/// 4. **Zapíše snímek otevřených záložek** (#527), a to při **každém** ukončení, ne jen v tom,
///    kde na něco běží. Je to jediné místo, ze kterého se dá zachytit **scroll v diffu**, kterým
///    člověk skončil: `bin/run.sh` po mergi ukončuje aplikaci Apple eventem, tedy touhle cestou.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Kolik review právě běží. Doplní `PRismApp`, jakmile má store; do té doby nic neběží.
    @MainActor var runningReviews: () -> Int = { 0 }

    /// Kolik shellů běží v zásuvce s terminálem (#459). Taky uzávěr a taky z `PRismApp`.
    ///
    /// **Vlastní počet, ne přičtený k review**: dialog o nich mluví každý jinak, protože se s nimi
    /// ztrácí něco jiného — z review se dá dotáhnout, co reviewer nahlásil, kdežto výpis shellu se
    /// nikam neukládá. Skládá to `Policy.quitPrompt`.
    @MainActor var runningTerminals: () -> Int = { 0 }

    /// Zabije běžící review a vrátí se, teprve když po nich nic nezůstalo (#264). Doplní
    /// `PRismApp` ze stejného důvodu jako `runningReviews`.
    @MainActor var stopReviews: @MainActor () async -> Void = {}

    /// Zabije shelly v zásuvce (#459). **Synchronně**, na rozdíl od review: signál odchází přímo
    /// z téhle cesty, takže není na co čekat.
    @MainActor var stopTerminals: @MainActor () -> Void = {}

    /// Zapíše snímek otevřených záložek (#527). Taky **synchronně**, a ze stejného důvodu jako
    /// u shellů: `applicationShouldTerminate` se v běžném případě vrací `.terminateNow`, po
    /// kterém už žádné další kolo runloopu nepřijde — `await` by tady znamenal snímek, na který
    /// nikdo nepočká.
    @MainActor var saveOpenTabs: @MainActor () -> Void = {}

    /// Jak se zeptat. Vlastnost, ne jen metoda, kvůli testům: `NSAlert.runModal()` v nich čeká
    /// na kliknutí, které nikdo neudělá.
    @MainActor var confirmQuit: @MainActor (QuitPrompt) -> Bool = { AppDelegate.ask(about: $0) }

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
    ///
    /// **Úklid osiřelých session (#351) sedí taky tady**, ne v `AppStore`: značky nestojí na
    /// preflightu ani na konfiguraci, a odložit je za složení storu by znamenalo, že sirotek přežije
    /// i tehdy, když preflight neprojde — tedy zrovna po pádu, po kterém se aplikace spouští znovu.
    /// Je to čtení jednoho malého souboru a několik `sysctl`ů, takže se tím start nezdrží;
    /// **synchronně** schválně, aby se úklid nemohl potkat s prvním review. Až **za** delegátem
    /// notifikací, protože ten má na pořadí podmínku a tenhle úklid žádnou — sirotek běží od zabití
    /// aplikace, takže o pár milisekund nejde.
    ///
    /// Návratovou hodnotu nikdo nečte a je to záměr: procesní hygiena se v okně neprojevuje
    /// a stav, který se drží a nikdo ho nezobrazí, je mrtvá váha.
    func applicationDidFinishLaunching(_ notification: Notification) {
        SystemNotificationCenter.prepare()
        RunningSessions.shared.reapOrphans()
        // Diagnostika kreslení (#361). Vypnutá nedělá nic — `start()` se hned vrátí, protože
        // proměnná v prostředí není. Až **za** úklidem sirotků: kdyby se zapisování rozbilo,
        // nemá to zdržet to, na čem něco stojí.
        RenderDiagnostics.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            // Druhý pokus během těch dvou sekund, co se zabíjí, jen zopakuje odpověď. Jinak by
            // otevřel druhý dialog nad ukončením, které už běží, a systému by se odpovědělo
            // dvakrát — `reply(toApplicationShouldTerminate:)` je na jedno odložené ukončení.
            guard !isStoppingReviews else { return .terminateLater }

            // **Záložky napřed, před dotazem** (#527), a je to celý důvod, proč se snímek ukládá
            // i odsud: `bin/run.sh` po mergi ukončuje aplikaci Apple eventem, tedy touhle cestou,
            // a scroll, kterým člověk v diffu skončil, leží do té chvíle jen v paměti. Před
            // dotazem schválně — když se člověk rozhodne **nekončit**, snímek se tím nezkazí
            // (je to tentýž stav, jaký zapíše příští změna záložky), kdežto po zrušeném dotazu
            // by se sem už nikdo nevrátil.
            saveOpenTabs()

            // Co běží a jak se na to zeptat, rozhoduje `Policy.quitPrompt` — `nil` znamená, že
            // neběží nic. Zabíjení shellů se nedá odložit za `terminateNow`, takže se dělá tady:
            // po `.terminateNow` už žádné další kolo runloopu nepřijde a shell by osiřel.
            guard let prompt = Policy.quitPrompt(
                reviews: runningReviews(),
                terminals: runningTerminals()
            ) else {
                return .terminateNow
            }
            guard confirmQuit(prompt) else { return .terminateCancel }
            stopTerminals()
            guard runningReviews() > 0 else { return .terminateNow }
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
    ///
    /// **Text se tady neskládá** (#459) — je z `Policy.quitPrompt`. Věty se totiž liší podle toho,
    /// co běží, a čtyři větve `if`ů ve view vrstvě jsou přesně to, co patří do `Policy`, kde se
    /// dají projít výčtem.
    @MainActor private static func ask(about prompt: QuitPrompt) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = prompt.title
        alert.informativeText = prompt.detail
        alert.addButton(withTitle: "Ukončit")
        alert.addButton(withTitle: "Zpět")
        // Zpět jako výchozí: ztracený nález je dražší než jedno kliknutí navíc.
        alert.buttons.last?.keyEquivalent = "\r"
        alert.buttons.first?.keyEquivalent = ""
        return alert.runModal() == .alertFirstButtonReturn
    }
}
