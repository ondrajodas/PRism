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
    /// **Celá škála jde z palety** (#432) — `ok`, `find`, `crit`, `stale`, akcent a mint. Ze
    /// systému zůstává jedině `.secondary`, a to proto, že to není barva ze škály, ale „nemám co
    /// říct“: neutrální šedá, která se řídí kontrastem okolí.
    ///
    /// **Změna proti #309**, kde tady stálo, že z palety jdou jen akcent a mint a že převod
    /// zbytku „je jiná otázka, která se zodpovídá měřením“. To měření je hotové a otočilo to:
    /// systémové `.green`/`.red`/`.orange` jsou navržené jako **výplň** tlačítka s bílým textem,
    /// ne jako barva textu na tlumeném washi, takže na kapsli stavu vyšly ve světlém režimu na
    /// **1,63 až 2,70** (a `3 nálezy` na systémové oranžové na **1,85**, tedy nejhůř z celé škály)
    /// — pod hranicí čitelnosti. Tokeny jsou na tohle použití ztmavené a dají **3,05 až 3,77**;
    /// čísla i prahy jsou v `PillTypesettingTests`, včetně toho, proč je to měření dolní odhad.
    /// Je to tatáž třída jako u `zastaralé` (#383) a `dismissed` (#309), jen zbytek výčtu.
    ///
    /// Argument z #309, který padl s ní: „zelenou a červenou bere ze systému ještě pár desítek
    /// míst v `App/`, takže převod zrovna tady by z tohohle souboru udělal výjimku“. #432 převedlo
    /// **všechna ta místa naráz**, takže se z výjimky stalo pravidlo — hlídá ho `StatusScaleTests`.
    ///
    /// Co z #309 **platí dál**: akcent je jediná barva, kterou si okno drží samo (stojí na ní
    /// identita aplikace a spektrum reviewerů), takže se se systémem měnit **nemá** —
    /// a `.tint(Palette.accent)` z kořene okna na `Color.accentColor` stejně nezabírá, takže by
    /// odznak kreslil systémovou modrou v okně, které je jinak celé fialové.
    static func color(of state: ReviewState, blocking: Int = 0) -> Color {
        switch state {
        case .notStarted, .queued, .cloning: .secondary
        // Akcent, ne mint: běžící review je to, co aplikace **dělá**, a návrh to kreslí jako
        // `.pill.run`, tedy v akcentu. Mint je konstatování — viz `Palette.mint`.
        case .running: Palette.accent
        case .clean: Palette.ok
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
        case .completed: blocking > 0 ? Palette.crit : Palette.find
        // Nedoběhlé běhy zůstávají červené **bez ohledu na nálezy**. Oranžová znamená „něco
        // se našlo“, kdežto tady je hlavní zpráva, že běh neskončil — `timeout · 0` oranžově
        // by vypadalo jako výsledek, a přitom je to selhání.
        case .checkoutFailed, .failed, .timedOut, .interrupted: Palette.crit
        // **Okrová, ne červená ani zelená** (#383). Neprůkazné review neselhalo — session
        // doběhla —, takže červená by o něm lhala; a zelená by lhala opačným směrem. Je to
        // tatáž třída jako `stale`: výsledek, který se nedá použít, jen z jiného důvodu.
        // Sdílený odstín je schválně, protože sdílené je i to, co se s tím dělá (pustit znovu);
        // rozeznat se to má **textem**, který u obou stojí vedle puntíku.
        //
        // **Z palety, ne systémová `.yellow`** — do #432 to byla výjimka z pravidla „zbytek škály
        // ze systému“, dneska je to to pravidlo. Opírá se o dvě věci, ne o vkus. **Návrh** má
        // `.pill.stale { color: var(--stale) }`, tedy `#9A6700`, takže systémová žlutá je odchylka
        // od schváleného mockupu — srovnat to s ním bránu nepotřebuje (#283). A **měření**:
        // odznak je text na vlastní kapsli (`color.opacity(0.15)`), a systémová `#FFCC00` na ní má
        // ve světlém režimu kontrast **1,41** (na ploše 1,51), tedy nečitelno; token má **4,00**
        // a 4,87. V tmavém režimu je to výměna 9,28 → 6,38, tedy pořád s rezervou. U `zastaralé`
        // to byla tichá vada od #172 — u tří nových odznaků by byla horší, protože právě text
        // je to jediné, čím se od sebe liší.
        //
        // Tatáž úvaha jako u `dismissed` (#309), včetně toho, čím se rozhodlo: čitelnost ve
        // světlém režimu, ne to, že „mají to i tokeny“. Chip revieweera kreslí `inconclusive`
        // v `Palette.stale` od #218, takže tím řádek a chip nad ním konečně říkají barvou totéž.
        case .inconclusive, .stale: Palette.stale
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
        // Odznak říká **co chybí**, ne že je něco nejisté (#383): „nejisté“ je hodnocení, kdežto
        // tyhle tři jsou fakta a každé vede k něčemu jinému. Krátké schválně — vejít se musí do
        // řádku seznamu vedle titulku PR; celá věta je v nápovědě chipu a v prázdném tabu nálezů.
        case .inconclusive(let reason): inconclusiveLabel(reason)
        case .timedOut(let findings): partialLabel("timeout", findings, blocking: blocking)
        // Ne „timeout“: běh neskončil limitem, ale s aplikací — a dělá se s tím něco jiného.
        case .interrupted(let findings): partialLabel("přerušeno", findings, blocking: blocking)
        case .stale: "zastaralé"
        }
    }

    /// Odznak neprůkazného review (#383). Tři různé texty, protože jsou to tři různá zjištění —
    /// a slít je do jednoho by znamenalo přesně tu záměnu, kvůli které stav vznikl.
    private static func inconclusiveLabel(_ reason: InconclusiveReason) -> String {
        switch reason {
        case .droppedFindings: "ztracené nálezy"
        case .noReport: "bez hlášení"
        case .unreadCode: "kód nepřečten"
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
