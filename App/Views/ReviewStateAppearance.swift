import SwiftUI

/// Jak stav review vypadá — barva a popisek na jednom místě (#172).
///
/// Vlastní typ proto, že od #172 tutéž barvu potřebují **dvě** místa v řádku: odznak a proužek
/// na hraně. Dvě kopie `switch`e nad `ReviewState` by se dřív nebo později rozešly a řádek by
/// pak tvrdil barvou něco jiného než textem.
///
/// **Blokující je vstup, ne další případ stavu.** `completed(findings: 3)` se od
/// `completed(findings: 3)` s jedním blokujícím liší jen tím, co s tím mám udělat — proto se
/// počet blokujících přidává až tady, a `ReviewState` zůstává, jak je.
enum ReviewStateAppearance {
    /// Barva stavu. Bere se **sémantická systémová**, ne hex z návrhu: v light i dark režimu
    /// se přizpůsobí sama a při změně akcentu systému jde `accentColor` s ní.
    static func color(of state: ReviewState, blocking: Int = 0) -> Color {
        switch state {
        case .notStarted, .queued, .cloning: .secondary
        case .running: .accentColor
        case .clean: .green
        // Vlastní barva, ne zelená ani oranžová: vyřízeno to je, ale ne tím, že by bylo
        // čisto — a od nálezů, které čekají, se to musí poznat i bez čtení textu.
        case .dismissed: .mint
        // Blokující nález je červený jako selhání schválně (#172): obojí znamená „tímhle se
        // musíš zabývat teď“, kdežto oranžová znamená „něco se našlo“. Do #172 se tyhle dvě
        // situace v řádku nedaly rozeznat vůbec.
        case .completed: blocking > 0 ? .red : .orange
        // Nedoběhlé běhy zůstávají červené **bez ohledu na nálezy**. Oranžová znamená „něco
        // se našlo“, kdežto tady je hlavní zpráva, že běh neskončil — `timeout · 0` oranžově
        // by vypadalo jako výsledek, a přitom je to selhání.
        case .checkoutFailed, .failed, .timedOut, .interrupted: .red
        case .stale: .yellow
        }
    }

    /// Barva jednoho dílu proužku reviewerů. Stejná škála jako u stavu, jen o jedno patro níž:
    /// červená blokuje, oranžová našla, zelená je čistá, šedá nemá co říct.
    static func color(of outcome: ReviewerShare.Outcome) -> Color {
        switch outcome {
        case .blocking: .red
        case .findings: .orange
        case .clean: .green
        case .dismissed: .mint
        case .inconclusive: .secondary
        }
    }

    /// Text odznaku. U nálezů nese i to, kolik jich blokuje — samotné „3 nálezy“ neřeklo,
    /// jestli je mezi nimi ten, kvůli kterému se PR nemerguje.
    static func label(of state: ReviewState, blocking: Int = 0) -> String {
        switch state {
        case .notStarted: "neběželo"
        case .queued: "ve frontě"
        case .cloning: "ve frontě · clone"
        case .checkoutFailed: "clone selhal"
        case .running(let finished, let total): "běží \(finished)/\(total)"
        case .clean: "čisté"
        case .completed(let findings): findingsLabel(findings, blocking: blocking)
        // Ne „čisté“: reviewer našel a já to zamítl, což je jiné tvrzení. Počet zůstává, ať
        // je z řádku poznat, kolik jsem toho přeskočil.
        case .dismissed(let findings): "odmítnuto · \(findings)"
        case .failed: "selhalo"
        case .timedOut(let findings): partialLabel("timeout", findings, blocking: blocking)
        // Ne „timeout“: běh neskončil limitem, ale s aplikací — a dělá se s tím něco jiného.
        case .interrupted(let findings): partialLabel("přerušeno", findings, blocking: blocking)
        case .stale: "zastaralé"
        }
    }

    /// „3 nálezy · 1 blokuje“ — dvě čísla, protože odpovídají na dvě otázky: kolik je práce
    /// a jestli se to smí mergnout. Bez blokujících zůstává jen počet, ať odznak nenarůstá
    /// o „0 blokuje“.
    private static func findingsLabel(_ findings: Int, blocking: Int) -> String {
        let count = Plural.czech(findings, one: "nález", few: "nálezy", many: "nálezů")
        guard blocking > 0 else { return count }
        return "\(count) · \(blocking) blokuje"
    }

    /// U nedoběhlého běhu je důvod první — částečné nálezy se nesmí tvářit jako výsledek.
    /// Blokující se připojí, protože platí i z poloviny běhu.
    private static func partialLabel(_ reason: String, _ findings: Int, blocking: Int) -> String {
        guard findings > 0 else { return reason }
        guard blocking > 0 else { return "\(reason) · \(findings)" }
        return "\(reason) · \(findings) · \(blocking) blokuje"
    }
}
