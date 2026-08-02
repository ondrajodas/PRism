import Foundation

/// Překlad textů nálezů do jazyka z nastavení.
///
/// **Až po doběhnutí review, ne instrukcí v promptu** — a je to změna proti zadání #52,
/// podložená měřením. Věta „piš nálezy česky“ v promptu stála na skutečném PR dva ze tří
/// nálezů: anglicky vyšly tři (stejně jako před tou změnou), česky jeden. Reviewer má
/// přemýšlet a psát v jazyce, ve kterém je nejsilnější; jazyk je věc zobrazení.
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
