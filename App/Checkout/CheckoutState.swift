import Foundation

/// Jak si stojí pracovní kopie **repozitáře**.
///
/// Klíčem je repo, ne PR: bare klon je jeden pro celý repozitář, takže dvě PR téhož repa
/// sdílejí jeden stav. Držet to per PR znamenalo, že si dvě mapy můžou odporovat — jedno
/// PR hlásí selhání nad klonem, který mezitím pro druhé PR v pořádku vznikl.
enum CheckoutState: Sendable, Equatable {
    /// V cache nic není, nebo se to nikdy nezkoušelo.
    case absent
    /// Právě se klonuje nebo aktualizuje.
    case preparing
    case ready(URL)
    /// Nepovedlo se; `detail` je věta pro člověka i s výstupem `gitu`.
    case failed(String)
}
