import Foundation
import Testing

/// Sledování skutečného podprocesu v testech — jedno místo pro tři suity, které se ptají na totéž
/// (#296): `SubprocessStreamerTests`, `AppStoreTerminationProcessTests` a `RealEnvironmentTests`.
///
/// **Zabití se ověřuje na PID, ne na souboru, který proces po sobě nechá** (#101), a **ne na tom,
/// jak dlouho volání trvalo** (#296). Obojí je totéž pravidlo z jiné strany: čeká se na **jev**.
/// Soubor po procesu znamená dočkat se konce jeho `sleep`, takže rezerva proti zpoždění se dá
/// zvětšit jedině tím, že test poběží stejně dlouho; a měřený čas volání je pod zátěží nečitelný —
/// u #296 vycházel 17,7 až 26,7 s tam, kde na volném stroji stačí 0,3 s, takže strop odvozený od
/// volného stroje barvil suitu na červeno nad aplikací, která fungovala. Zmizelý PID se pozná
/// **v okamžiku, kdy nastane**, takže velkorysý strop test nezdrží.
enum ProcessProbeFailure: Error {
    case neverStarted
}

/// PID procesu, který si ho sám zapsal do souboru (`echo $$ > …`).
///
/// Čeká se na něj pollingem, ne pevnou odmlkou — start `/bin/sh` trvá jednotky milisekund, ale pod
/// zátěží klidně stovky. Rušit se totiž má proces, který **doopravdy běží**: jinak by test prošel
/// i tehdy, kdyby se nespustil vůbec.
///
/// **Nekladné číslo se nepřijme**, i když ho `echo $$` dát nemůže. `kill(0, …)` míří na celou
/// **procesovou skupinu** volajícího a negativní PID taky na skupinu — takže hodnota, která se sem
/// omylem dostane, by z kontroly existence jednoho procesu udělala něco úplně jiného. Upozornil na
/// to Copilot na #121.
func processID(writtenTo file: URL) async throws -> pid_t {
    var found: pid_t?
    await waitUntil("proces se rozběhne a napíše svoje PID") {
        guard
            let text = try? String(contentsOf: file, encoding: .utf8),
            let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
            pid > 0
        else { return false }
        found = pid
        return true
    }
    guard let found else { throw ProcessProbeFailure.neverStarted }
    return found
}

/// Zmizel proces? `kill(pid, 0)` jen ověřuje existenci, nic neposílá.
///
/// Čeká se na **výsledek**, ne pevnou dobu: když zrušení zabije proces hned (běžný případ), vrátí to
/// po prvním kole. Strop je tu proti zátěži, ne proti pomalému zabíjení — mezi doručeným `SIGKILL`em
/// a zmizením z tabulky procesů je ještě sklizení, které s aplikací nesouvisí.
func processHasGone(_ pid: pid_t) async -> Bool {
    await waitUntil("proces \(pid) zmizí") { kill(pid, 0) != 0 }
}

/// Cesta k souboru, do kterého si podproces zapíše svoje PID. Jméno je pokaždé jiné, aby si dvě
/// suity běžící paralelně nepřepsaly navzájem výsledek.
func temporaryPIDFile(_ label: String) -> URL {
    URL(filePath: NSTemporaryDirectory())
        .appending(path: "prism-\(label)-\(UUID().uuidString).pid")
}
