import Foundation
import Synchronization

/// Aktuální konfigurace pro kód, který běží mimo hlavní vlákno.
///
/// `AppStore` je `@MainActor`, takže limit souběžných session, rozpočet cache ani volba
/// modelu si na něj sáhnout nemůžou — a přitom se musí číst **při použití**, jinak by se
/// změna konfigurace projevila až po restartu.
final class ConfigurationBox: Sendable {
    private let storage: Mutex<Configuration>

    init(_ configuration: Configuration) {
        storage = Mutex(configuration)
    }

    var value: Configuration {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}
