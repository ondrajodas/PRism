import Foundation

/// Rozhodovací logika bez I/O.
///
/// Namespace, ne typ k instanciování — všechno uvnitř jsou čisté funkce, které se testují
/// bez mockování. Když se přistihneš, že píšeš `if` nad stavem ve view nebo v runneru,
/// patří to sem.
enum Policy {}
