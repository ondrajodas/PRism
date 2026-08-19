import Foundation

@testable import PRism

/// Kolik CPU si vzalo **hlavní vlákno**.
///
/// Od #361 je to jen jméno pro `threadCPUSeconds()` z aplikace: tu funkci potřebuje i sama
/// diagnostika kreslení (`RenderDiagnostics`), takže žije v `App/Support/ThreadCPU.swift` — dvě
/// kopie by byla dvě různá čísla o jedné věci. Jméno tady zůstává proto, že v sondě je podstatné
/// **které** vlákno se měří, a měří se to, na kterém drží runloop.
@MainActor
func mainThreadCPUSeconds() -> TimeInterval {
    threadCPUSeconds()
}

/// Nechá běžet hlavní smyčku a vrátí, kolik CPU si při tom vzalo hlavní vlákno.
///
/// **Není to čekání na jev, je to samo měření** — proto tady, a ne přes `TestWaiting`: sonda chce
/// vědět, co okno stojí, když se v něm **nic nemá dít**, takže se smyčka pouští na pevnou dobu
/// a strop k ničemu není.
@MainActor
func spinMainRunLoop(seconds: TimeInterval) -> TimeInterval {
    let start = mainThreadCPUSeconds()
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    return mainThreadCPUSeconds() - start
}
