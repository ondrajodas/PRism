import Foundation

/// Proč si automat nález **nevzal** do návrhu review (#520).
///
/// **Výčet, ne věta, a je to podmínka celého issue.** Když se část nálezů převezme sama a část
/// ne, musí být z okna poznat **které a proč** — jinak by se odeslalo víc, než jsem četl, a to
/// je ta nejdražší chyba, kterou umí návrh udělat. Věta v UI se z toho odvozuje (`label`,
/// `help`), takže se text a rozhodnutí nemají čím rozejít.
///
/// **Není to hodnocení nálezu.** Sporný nález dál platí, dál blokuje a dál se dá převzít
/// kliknutím — návrh z něj **nesundá nic** (to smí jedině odmítnutí, #113). Říká jen, že si ho
/// aplikace nevzala sama.
enum AutoDraftDoubt: Hashable, Codable, Sendable {
    /// Reviewer si nálezem není jistý (`PLAUSIBLE`).
    case plausible
    /// Reviewer verdikt vůbec nenapsal.
    ///
    /// **Vlastní případ, ne `plausible`.** „Nejsem si jistý“ a „neřekl jsem“ jsou dvě různé věty
    /// a slít je do jedné by znamenalo tvrdit v okně něco, co reviewer nenapsal — tatáž úvaha
    /// jako u `FindingVerdict`, které neznámou hodnotu nehádá.
    case noVerdict
    /// Na jednom místě se reviewery neshodnou. Nese **jejich jména**, protože právě ta jsou
    /// v okně ta informace: `php-review ↔ security-review`.
    case disagreement(reviewers: [String])

    /// Důvod, jak se píše v pilulce u nálezu.
    ///
    /// `PLAUSIBLE` velkými zůstává **verdiktem reviewera**, ne přeloženým slovem: je to hodnota
    /// z `ReportFindings`, takže se má dát najít v surové session stejně, jako stojí v okně.
    var label: String {
        switch self {
        case .plausible: "PLAUSIBLE"
        case .noVerdict: "bez verdiktu"
        case .disagreement(let reviewers): reviewers.joined(separator: " ↔ ")
        }
    }

    /// Celá věta do nápovědy — **říká, co s tím**, ne co je vidět.
    var help: String {
        switch self {
        case .plausible:
            "Reviewer si nálezem není jistý (PLAUSIBLE), takže si ho návrh nevzal. Převzít ho jde kliknutím."
        case .noVerdict:
            "Reviewer u nálezu žádný verdikt nenapsal, takže si ho návrh nevzal. Převzít ho jde kliknutím."
        case .disagreement(let reviewers):
            "Na tomhle místě se reviewery neshodnou (\(reviewers.joined(separator: ", "))), takže si nález návrh nevzal. Rozhodnout to má člověk."
        }
    }
}
