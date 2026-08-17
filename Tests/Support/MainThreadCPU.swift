import Foundation

/// Kolik CPU si vzalo **hlavní vlákno** — jedno místo pro všechny sondy, které měří tuhnoucí okno
/// (#350, #358, #361).
///
/// **Čte se CPU vlákna, ne nástěnné hodiny**: smyčka většinu času spí, takže nástěnný čas by měřil
/// délku spánku, ne práci. Do #361 měla tuhle dvojici každá sonda vlastní (`IdleWindowSpinProbe`,
/// `DetailProgressMeasurement`) a třetí kopie byla ta chvíle, kdy se to mělo svést na jedno místo.
@MainActor
func mainThreadCPUSeconds() -> TimeInterval {
    TimeInterval(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1_000_000_000
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
