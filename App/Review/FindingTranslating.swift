import Foundation

/// Překlad textů nálezů do jazyka z nastavení.
///
/// **Až po doběhnutí review, ne instrukcí v promptu** — změna proti zadání #52.
///
/// Důvod je **zbavit se rizika, ne naměřený rozdíl**. Překlad po doběhnutí kvalitu review
/// ovlivnit nemůže konstrukcí: reviewer dostává tentýž prompt jako předtím. Instrukce
/// v promptu ovlivnit může a levně se to nevyvrátí — tři běhy nad týmž commitem daly
/// 1, 2 a 3 nálezy, takže rozptyl mezi běhy je stejně velký jako efekt, který by se dal
/// změřit. Bezpečná varianta je zadarmo, tak se vzala.
///
/// Za protokolem ze stejného důvodu jako `ReviewRunning` — a stejně jako on nemá metodu,
/// kterou by šlo něco odeslat.
protocol FindingTranslating: Sendable {
    /// Přeloží nálezy do daného jazyka.
    ///
    /// Vrací pole **zarovnané se vstupem**: na `i`-tém místě je překlad `i`-tého nálezu,
    /// nebo `nil`, když se ho přeložit nepodařilo. Ztratit nález kvůli překladu nesmí —
    /// nepřeložený se ukáže v originále, chybějící by v UI vypadal jako neexistující.
    func translate(
        _ findings: [ReportedFinding],
        to language: FindingsLanguage
    ) async throws -> [FindingTranslation?]
}
