import SwiftUI

/// Jeden dílek pruhu `Reviewery · 30 dní` (#514) — v bloku na domově i v tabulce v Nastavení.
///
/// **Jeden typ pro pruh i pro legendu**, a je to podmínka, ne úspora: barva v legendě, která se
/// rozejde s barvou v pruhu, je legenda, podle které se dá přečíst opak toho, co je nakreslené.
/// Ze stejného důvodu je tu i **pořadí** — dílek a popisek si odpovídají zleva doprava.
///
/// Barvy jsou z návrhu doslova (`--ok` / `--crit` / `--stale` / `--ink-3` na 50 %); sémantická
/// škála se kreslí z palety, nikdy ze systému (#432).
struct ReviewerBarSegment: Identifiable {
    /// Stabilní identita, ne podíl: dva dílky se stejným počtem jsou běžný stav a `id` z čísla
    /// by je slilo (#361 — identita nesmí být hodnota, která se opakuje).
    let id: String
    let title: String
    let color: Color
    /// Kolik nálezů do dílku padlo. Poměr, ne šířka — tu spočítá `ProportionalColumns`.
    let share: Double

    /// Dílky pruhu jednoho řádku, **bez nulových**: dílek na nulovou šířku s mezerou vedle sebe
    /// dá jednobodovou spáru, tedy něco, co v datech není.
    static func all(of tally: ReviewerTally) -> [ReviewerBarSegment] {
        shares(of: tally).filter { $0.share > 0 }
    }

    /// Legenda — **všechny čtyři**, i ty, které v tomhle řádku nejsou. Popisek je vysvětlení
    /// škály, ne výpis dat; vypadnout by z něj znamenalo, že se legenda mění řádek od řádku.
    static let legend: [ReviewerBarSegment] = shares(of: ReviewerTally(
        reviewer: "",
        repo: RepoID(owner: "legend", name: "legend")
    ))

    private static func shares(of tally: ReviewerTally) -> [ReviewerBarSegment] {
        [
            ReviewerBarSegment(id: "taken", title: "převzato", color: Palette.ok, share: Double(tally.taken)),
            ReviewerBarSegment(id: "invalid", title: "neplatí", color: Palette.crit, share: Double(tally.invalid)),
            ReviewerBarSegment(id: "irrelevant", title: "nepatří sem", color: Palette.stale, share: Double(tally.irrelevant)),
            ReviewerBarSegment(
                id: "undecided",
                title: "nerozhodnuto",
                color: Palette.ink3.opacity(0.5),
                share: Double(tally.undecided)
            ),
        ]
    }
}
