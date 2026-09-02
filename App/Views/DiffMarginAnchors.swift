import Observation

/// Svislý rozsah jednoho řádku, ke kterému se v okraji váže karta (#503) — v souřadnicích
/// **obsahu** diffu.
///
/// V souřadnicích obsahu, ne výřezu, a je to výkonová podmínka, ne libovůle: v nich se
/// scrollováním **nemění**, takže se za jejich čtení při projíždění neplatí. Co se mění, čte
/// jedno místo (`DiffViewport`) — a v okraji je to jediný modifikátor (`DiffMarginView`).
struct DiffMarginSpot: Hashable, Sendable {
    /// Horní hrana řádku v souřadnicích obsahu.
    let top: Double
    let height: Double

    /// Kam míří spojnice ke kartě — na střed řádku. Na horní hranu ne: u zalomeného řádku
    /// (v pohledu pod sebou se zalamuje) by čárka mířila nad text, ke kterému patří.
    var middle: Double { top + height / 2 }
}

/// Kde v obsahu diffu leží řádky s kartou v okraji (#503).
///
/// **Sledovaná krabice, na rozdíl od `DiffRowFrames` a `DiffFileExtents`** — a je to jediné
/// místo v diffu, kde to tak je. Ty dvě čte gesto a ukotvená hlavička, tedy někdo, kdo se
/// překresluje z jiného důvodu; z téhle se **kreslí**, takže bez sledování by karta zůstala
/// stát tam, kde byl řádek před přerovnáním.
///
/// Cena je proto ohraničená dvěma věcmi:
///
/// - **Hlásí se předfiltr, ne celý blok.** Blok posílá jedině řádky, na kterých karta doopravdy
///   je (`DiffMarginMark`) — v běžném bloku tedy prázdno.
/// - **Zápis jedině při změně.** Blok se hlásí znovu při každém nasazení, tedy při projíždění;
///   nezměněné hlášení se zahodí hned na vstupu, takže se sledovaná vlastnost **nedotkne**.
///   Nespoléhá se u toho na to, že `@Observable` zápis téže hodnoty nehlásí (`PollObservationTests`
///   to tvrdí, ale je to vlastnost toolchainu, ne téhle krabice): tady je to podmínka správnosti
///   toho, že projíždění nic nestojí, takže stráž patří sem.
///
/// **Poloha karty se odsud nebere jako důkaz její existence.** O tom, které karty v okraji jsou,
/// rozhoduje `Policy.marginCards` nad daty — kdyby o tom rozhodovalo hlášení, zmizela by karta
/// u řádku, jehož blok je zrovna mimo nasazený pás (#469).
@MainActor @Observable final class DiffMarginAnchors {
    /// Klíč karty (`Policy.marginKey`) → poloha jejího řádku.
    private(set) var spots: [String: DiffMarginSpot] = [:]
    /// Co který blok naposled ohlásil. Nesledované — je to jen paměť pro tu stráž nad zápisem.
    @ObservationIgnored private var byBlock: [String: [String: DiffMarginSpot]] = [:]

    /// Vyprázdní krabici při přepnutí toho, co se kreslí.
    ///
    /// **Je to podmínka, ne úklid** (tentýž důvod jako `subject` u `DiffRowFrames`, #274): `@State`
    /// detailu přetéká mezi pull requesty, takže by v krabici zůstaly polohy z PR, který v okně
    /// dávno není — a klíč `CLAUDE.md|174` má kdejaký PR. Blok se po přepnutí ohlásí znovu, protože
    /// se mu změnil obsah i generace (`DiffBlockSpan`), takže se karty mají kde dozvědět novou
    /// polohu.
    func reset() {
        guard !byBlock.isEmpty || !spots.isEmpty else { return }
        byBlock.removeAll(keepingCapacity: true)
        spots = [:]
    }

    /// Ohlásí polohy řádků s kartou **za celý blok naráz** — tentýž vzorec jako
    /// `DiffRowFrames.note(_:covering:of:block:)` (#252).
    ///
    /// Bere se to po blocích, protože blok je to, co se nasazuje a odpojuje: kdyby se hlásilo po
    /// řádcích, nedalo by se poznat, že řádek z bloku zmizel.
    ///
    /// **Prázdné hlášení znamená „změřeno a žádná karta tu není“**, takže sundá starou polohu.
    /// Blok, který se ještě nerozložil, ho proto **posílat nesmí** (`DiffBlockRowView.noteMargin`)
    /// — jinak si při každém přestavění přepíše platnou polohu na nic.
    func note(_ found: [String: DiffMarginSpot], from block: String) {
        guard byBlock[block, default: [:]] != found else { return }
        // Prázdné hlášení se **nedrží**: blok bez karty nemá v krabici co dělat a zápis `nil` je
        // to, co po přesunu nálezu jinam sundá starou polohu.
        byBlock[block] = found.isEmpty ? nil : found
        spots = byBlock.values.reduce(into: [:]) { merged, block in
            // Dva bloky nemohou hlásit tentýž klíč (jeden řádek je v jednom bloku), takže na
            // pravidle slévání nezáleží — je tu proto, že `merge` bez něj neexistuje.
            merged.merge(block) { first, _ in first }
        }
    }
}
