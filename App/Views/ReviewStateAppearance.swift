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
    /// Barva stavu.
    ///
    /// **Akcent a mint jdou z palety, zbytek škály ze systému** — a ta hranice je vědomá (#309).
    /// Do #309 tu stálo, že se bere sémantická systémová barva, „protože se přizpůsobí režimu
    /// a při změně akcentu systému jde `accentColor` s ní“. **Obojí padlo:** `Color(light:dark:)`
    /// se režimu přizpůsobí taky, takže první polovina nebyla důvod pro systém — a druhá je
    /// zrovna to, co se u #298 zamítlo. Akcent je jediná barva, kterou si okno drží samo (stojí na
    /// ní identita aplikace a spektrum reviewerů), takže se se systémem měnit **nemá**. Ono to
    /// stejně nefungovalo, jak ten komentář sliboval: `.tint(Palette.accent)` z kořene okna na
    /// `Color.accentColor` nezabírá, takže odznak kreslil systémovou modrou i v okně, které je
    /// jinak celé fialové.
    ///
    /// `.green`, `.orange`, `.red`, `.yellow` a `.secondary` **zůstávají systémové**. Převod celé
    /// škály na `Palette.ok`/`find`/`crit`/`stale` je jiná otázka a jinde v repu se zodpovídá
    /// měřením (#218 kapsle stavu, #277 diff); „mají to i tokeny“ samo o sobě důvod není, protože
    /// zelenou a červenou bere ze systému ještě pár desítek míst v `App/`. Převést je zrovna tady
    /// by z tohohle souboru udělalo výjimku, ne pravidlo.
    static func color(of state: ReviewState, blocking: Int = 0) -> Color {
        switch state {
        case .notStarted, .queued, .cloning: .secondary
        // Akcent, ne mint: běžící review je to, co aplikace **dělá**, a návrh to kreslí jako
        // `.pill.run`, tedy v akcentu. Mint je konstatování — viz `Palette.mint`.
        case .running: Palette.accent
        case .clean: .green
        // Vlastní barva, ne zelená ani oranžová: vyřízeno to je, ale ne tím, že by bylo
        // čisto — a od nálezů, které čekají, se to musí poznat i bez čtení textu.
        //
        // **Z palety, ne systémová `.mint`** (#309): odmítnuté review je konstatování, tedy přesně
        // to, co `Palette.mint` znamená, a dvě „skoro stejné“ tyrkysové v jednom okně jsou to,
        // čemu paleta brání. Systémová byla ve světlém režimu k tomu špatně čitelná — čísla jsou
        // v `MintTokenTests`.
        case .dismissed: Palette.mint
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
    ///
    /// **Odmítnuté bere `Palette.mint` z téhož důvodu jako u stavu** (#309) — jsou to dvě kresby
    /// jedné věci (odznak a díl proužku), takže se nesmí lišit ani o odstín.
    static func color(of outcome: ReviewerShare.Outcome) -> Color {
        switch outcome {
        case .blocking: .red
        case .findings: .orange
        case .clean: .green
        case .dismissed: Palette.mint
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
