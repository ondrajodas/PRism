import Foundation

/// Identita procesu, kterou nejde splést s recyklovaným PID (#351).
///
/// Samotné PID identita **není**: čísla se na macOS recyklují, takže PID zapsané před hodinou
/// může dneska patřit cizímu procesu. Na tom stojí tvrzení, kvůli kterému #351 vzniklo —
/// **zabít cizí `claude` je horší než nechat běžet sirotka** —, takže se k číslu přidává
/// okamžik vzniku procesu z jádra. Ten je na BSD kanonická druhá půlka identity: PID se
/// recykluje, ale dvojice `(pid, startedAt)` ne.
struct ProcessIdentity: Codable, Equatable, Sendable {
    let pid: pid_t

    /// Kdy proces vznikl, podle jádra, v mikrosekundách od epochy.
    ///
    /// Mikrosekundy schválně, ne sekundy: `KERN_PROC_PID` je vydává (`p_starttime` je
    /// `timeval`) a dva procesy spuštěné v téže sekundě jsou běžný stav — se sekundovou
    /// přesností by je od sebe identita neodlišila.
    let startedAt: Int64
}

/// Co jádro ví o procesu, a zabití toho procesu.
///
/// Za protokolem ze stejného důvodu jako `ExecutableProbe`: úklid osiřelých session se má
/// dát vyzkoušet vyčerpávajícím výčtem, včetně stavů, které se skutečnými procesy nasimulovat
/// nejde (PID, které mezitím dostal někdo jiný).
///
/// **`kill` bere identitu, ne PID**, a je to celý smysl toho protokolu. S PID by se dalo
/// zabít cokoli a kontrola by závisela na tom, jestli si na ni volající vzpomněl; s identitou
/// si ji implementace udělá sama těsně před signálem, takže mezi kontrolou a signálem nezbývá
/// okno, ve kterém se PID přesune k cizímu procesu.
protocol ProcessInspecting: Sendable {
    /// Kdo právě běží pod tím PID; `nil`, když nikdo.
    func identity(of pid: pid_t) -> ProcessIdentity?

    /// Pošle `SIGKILL` — ale **jedině tehdy, když na té identitě pořád sedí tentýž proces.**
    /// Vrácené `true` znamená, že signál odešel.
    @discardableResult func kill(_ identity: ProcessIdentity) -> Bool
}
