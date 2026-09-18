import Foundation

/// Věta *proč* u jednoho hunku, tak jak ji nahlásila sedmá session (#524).
///
/// **Není to nález a nesmí se s ním slít.** Nález tvrdí, že je něco špatně, a váže se na něj
/// blokující příznak, návrh verdiktu, odznaky i souhrn; anotace říká, **co se v tom hunku děje**.
/// Hranice mezi tím dvojím je **v tvaru schématu, které aplikace parsuje**, ne v promptu
/// (`AnnotationSchema`): pole pro závažnost tenhle typ nemá a mít nebude, takže se z anotace nedá
/// udělat nález ani omylem. Do #524 ji měla držet **dvojice popis-nástroj**; nástroj odpadl (proč,
/// je u `AnnotationSchema`) a hranice zůstala — parser se o pole, které ve schématu není, prostě
/// nezajímá.
///
/// **Jedna vrstva, ne dvě jako u nálezů.** `ReportedFinding` a `Finding` jsou oddělené proto, že
/// aplikace k nálezu dopisuje **kdo** ho našel a **proti čemu** — u anotací je reviewer jeden
/// (jedna session na hlavu) a commit nese `StoredAnnotations.headSha`, takže by druhá vrstva
/// nenesla nic než opis.
struct HunkAnnotation: Hashable, Codable, Sendable {
    /// Cesta v diffu tak, jak ji session opsala. Pravdou zůstává diff — spárovat se to musí
    /// (`Policy.annotations(of:in:)`), protože cesta z modelu nemusí sedět na žádný soubor.
    let file: String
    /// **Pořadí hunku v diffu toho souboru, počítáno od jedné.**
    ///
    /// Páruje se přes index, ne přes text (zadání #524): úryvek kódu by se musel hledat
    /// v diffu, a dvakrát stejný řádek (`}` na konci metody) by anotaci posadil k cizímu hunku.
    /// Index je proti tomu **poziční**, a právě proto je celý záznam klíčovaný hlavou — po pushi
    /// se hunky přečíslují a stará anotace by ukazovala vedle. Viz `StoredAnnotations`.
    let hunk: Int
    /// Jedna věta, česky. Proč je ta změna v PR — ne co je na ní špatně.
    let why: String
    /// Odkud to session ví: `z commitu …`, `popis PR to nezmiňuje`. `nil` = neřekla.
    ///
    /// Volitelné schválně, jako `failureScenario` u nálezu: anotace bez zdroje je pořád věta,
    /// kterou stojí za to mít, a zahodit ji kvůli chybějícímu poli by znamenalo tichou ztrátu.
    let source: String?
}

/// Druh změny u jednoho souboru (#524).
struct FileAnnotation: Hashable, Codable, Sendable {
    let file: String
    let kind: FileChangeKind
}

/// Pět slov, kterými se soubor v diffu popisuje (#524, zákres Z4).
///
/// **Výčet, ne volný slug** — a je to opačné rozhodnutí než u `ReportedFinding.category`, kde si
/// aplikace vlastní škálu schválně nevymýšlí. Důvod je v tom, k čemu ta hodnota je: kategorie
/// nálezu se váže na blokující sadu, kterou si píše člověk v nastavení, kdežto druh změny je to,
/// **podle čeho itinerář řadí a mapa barví** — a řadit se dá jedině podle uzavřeného výčtu.
/// Neznámá hodnota se proto nehádá, zůstane `nil` a soubor prostě druh nemá.
///
/// `rawValue` je anglicky, protože jde do promptu i na disk. **České popisky tu zatím nejsou
/// a je to schválně**: v #524 se druh změny nikde nekreslí (kreslí až #525), takže by to bylo pět
/// řetězců, které nikdo nečte. Znění je v zákresu — sekce 59 mockupu.
enum FileChangeKind: String, Codable, Hashable, Sendable, CaseIterable {
    case behaviour
    case refactor
    case test
    case configuration
    case generated
}
