import Foundation
import Network

/// Má stroj vůbec cestu do sítě?
///
/// Vlastní signál, ne dohad ze selhaných volání: **„stroj je bez sítě“ není „služba je
/// mimo“** a puntík to musí říct správně. Odvozovat to z toho, že selhalo obojí, by navíc
/// znamenalo čekat na dvě selhání — kdežto vypnutá Wi-Fi je vidět hned.
protocol NetworkReachability: Sendable {
    /// Proud změn. První hodnota přijde, jak jen to systém zvládne; do té doby se neví nic.
    func updates() -> AsyncStream<Bool>
}

/// `NWPathMonitor` za tím protokolem.
struct PathMonitorReachability: NetworkReachability {
    func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            // Zrušení proudu musí monitor zastavit — jinak by po zavření okna dál běžel
            // a držel si vlákno.
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "cz.prism.reachability"))
        }
    }
}
