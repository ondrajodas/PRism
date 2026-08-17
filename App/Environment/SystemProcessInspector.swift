import Darwin
import Foundation

/// `ProcessInspecting` nad skutečnou tabulkou procesů.
///
/// Identitu čte `sysctl(KERN_PROC_PID)`, ne `ps`: podproces navíc při každém startu je zbytečný
/// a hlavně by se výsledek musel parsovat z textu. Tři věci, které jsou u toho změřené a na
/// kterých kód stojí:
///
/// - **Rozhoduje `size`, ne návratový kód.** `sysctl` vrátí `0` i pro PID, které neexistuje —
///   jen nezapíše nic a nechá `size == 0`. Kdyby se kontroloval jen návratový kód, vypadala by
///   nulová `kinfo_proc` jako platná odpověď: `pid == 0` a `startedAt == 0`.
/// - **Nekladné PID se odmítne dřív, než se na cokoli zeptáme.** `sysctl` pro `pid == 0`
///   **odpoví** (jádro), a `kill(0, …)` míří na celou **procesovou skupinu volajícího** —
///   tedy na aplikaci samotnou. Je to tatáž past, na kterou u #121 upozornil Copilot
///   v testovací sondě.
/// - **Odpověď se ověří proti tomu, na co jsme se ptali** (`p_pid == pid`). Je to jeden `if`
///   nad daty, která už v ruce jsou, a bez něj by celá identita stála na tom, že se `sysctl`
///   nikdy nespletl.
struct SystemProcessInspector: ProcessInspecting {
    func identity(of pid: pid_t) -> ProcessIdentity? {
        guard pid > 0 else { return nil }

        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0,
            size == MemoryLayout<kinfo_proc>.stride,
            info.kp_proc.p_pid == pid
        else { return nil }

        let started = info.kp_proc.p_un.__p_starttime
        return ProcessIdentity(
            pid: pid,
            startedAt: Int64(started.tv_sec) * 1_000_000 + Int64(started.tv_usec)
        )
    }

    /// Ověří identitu **znovu, těsně před signálem**, a teprve pak zabíjí.
    ///
    /// Volající identitu zpravidla ověřil taky (rozhoduje o tom `Policy.orphanVerdict`), ale
    /// mezi jeho kontrolou a tímhle voláním je čas — a kdyby v něm proces doběhl a jádro jeho
    /// číslo vydalo znovu, mířil by `SIGKILL` na cizí proces. Kontrola tady to okno zavírá na
    /// jediné volání `sysctl`.
    @discardableResult
    func kill(_ identity: ProcessIdentity) -> Bool {
        guard self.identity(of: identity.pid) == identity else { return false }
        return Darwin.kill(identity.pid, SIGKILL) == 0
    }
}
