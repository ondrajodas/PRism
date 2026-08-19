import Foundation

/// Kolik CPU si vzalo vlákno, které se ptá — **jedno místo pro aplikaci i pro sondy** (#350, #358,
/// #361).
///
/// **Čte se CPU vlákna, ne nástěnné hodiny**: hlavní smyčka většinu času spí, takže nástěnný čas by
/// měřil délku spánku, ne práci. Právě rozdíl mezi obojím je celá diagnóza tuhnoucího okna — 99 %
/// CPU hlavního vlákna nad oknem, ve kterém se nic neděje.
///
/// Do #361 to byla funkce v `Tests/`. Přestěhovala se sem, protože ji potřebuje i sama aplikace
/// (`RenderDiagnostics`), a dvě kopie by znamenaly dvě různá čísla o jedné věci.
func threadCPUSeconds() -> TimeInterval {
    TimeInterval(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1_000_000_000
}
