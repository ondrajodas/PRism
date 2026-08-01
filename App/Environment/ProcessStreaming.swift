import Foundation

/// Jedna událost z běžícího podprocesu.
enum ProcessEvent: Sendable, Equatable {
    /// Jeden řádek stdout, bez ukončovacího konce řádku.
    case line(String)
    /// Proces doběhl. `standardOutput` tu schválně není — ten už odešel po řádcích.
    case finished(exitCode: Int32, standardError: String)
}

/// Spuštění podprocesu, jehož výstup se čte **po řádcích, jak vzniká**.
///
/// Vlastní protokol, ne další metoda `ProcessRunning`: streamování potřebuje jediný
/// volající (`ReviewRunner` nad `claude --output-format stream-json`), kdežto fake
/// implementace `ProcessRunning` jsou u `gh` i `git` v každém druhém testu. Přidat metodu
/// do sdíleného protokolu by znamenalo dopsat ji do všech fakes, které ji nikdy nezavolají.
///
/// Přibylo tu i `workingDirectory`, které `ProcessRunning` nemá: `claude` pracovní složku
/// flagem předat neumí, je to `cwd` procesu (ověřeno u #12). `git` si vystačí s `-C`, takže
/// se bufferovaná cesta nemění.
protocol ProcessStreaming: Sendable {
    /// Vrací proud událostí. Chyby přicházejí **v proudu**, ne z téhle funkce:
    ///
    /// - `ProcessError.launchFailed`, když se binárka nespustila,
    /// - `ProcessError.timedOut`, když proces nedoběhl v limitu a byl zabit. Řádky, které
    ///   do té doby dorazily, zůstávají doručené — u zabitého review jsou to jediné nálezy,
    ///   které jsou.
    ///
    /// Zrušení konzumenta proud ukončí a **proces zabije**.
    ///
    /// `environment` se **přidává** k prostředí aplikace, nepřepisuje ho celé.
    func stream(
        _ executable: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?,
        timeout: Duration
    ) -> AsyncThrowingStream<ProcessEvent, any Error>
}
