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

/// Kolik CPU si vzalo **jiné** vlákno, než ze kterého se ptáme (#361).
///
/// `CLOCK_THREAD_CPUTIME_ID` umí jedině vlákno samo o sobě — a to je zrovna to, co u zaseknutého
/// okna nejde: hlavní vlákno se nemá kdy zeptat, protože se z transakce nevrátí do runloopu. Port
/// se proto vezme **na tom vlákně, které se má hlídat**
/// (`currentThreadPort()`, tedy `pthread_mach_thread_np(pthread_self())`) a čte se odjinud.
///
/// `nil` = port už neplatí, typicky protože vlákno skončilo (aplikace se zavírá). **Nevrací nulu**:
/// nula by v záznamu vypadala jako „hlavní vlákno nic nedělalo“, což je pravý opak toho, co se
/// tímhle měří.
func threadCPUSeconds(of thread: mach_port_t) -> TimeInterval? {
    var info = thread_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
            thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), raw, &count)
        }
    }
    guard status == KERN_SUCCESS else { return nil }
    // **Uživatelský i systémový čas**, ať je to srovnatelné s `CLOCK_THREAD_CPUTIME_ID` výš —
    // ten je taky součet obojího. Jinak by dvě čísla v jednom souboru měřila dvě různé věci.
    return seconds(of: info.user_time) + seconds(of: info.system_time)
}

/// Port vlákna, na kterém se to volá. Platí po celou dobu jeho života a **neuvolňuje se**
/// (`pthread_mach_thread_np`, ne `mach_thread_self`, které si žádá `mach_port_deallocate`).
func currentThreadPort() -> mach_port_t {
    pthread_mach_thread_np(pthread_self())
}

private func seconds(of value: time_value_t) -> TimeInterval {
    TimeInterval(value.seconds) + TimeInterval(value.microseconds) / 1_000_000
}
