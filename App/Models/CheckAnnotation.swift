import Foundation

/// Anotace check-runu (#214) — `soubor:řádek` a věta od CI.
///
/// **Není to nález z review, a nesmí s ním splynout.** Nález má revieweera, dá se odmítnout (#113)
/// a počítá se do počtu nálezů; anotace je **cizí fakt**, se kterým se nedá dělat nic než opravit
/// kód. Proto se kreslí jinou barvou i jiným tvarem než bublina nálezu a **nepočítá se nikde** —
/// ani v řádku fronty, ani v panelu, ani v odznaku tabu. Číslo, které se mění tím, jestli workflow
/// emituje problem matcher, o review nevypovídá.
///
/// **Není `Codable`**, protože se neukládá: platí k jednomu běhu CI, ne k `headSha`, a příště se
/// stáhne znovu — stejně jako log (#214).
struct CheckAnnotation: Hashable, Sendable, Identifiable {
    /// Jak to CI označilo. Tři úrovně, jak je dává GitHub; neznámá se bere jako `notice`, protože
    /// to je jediná, která netvrdí, že je něco špatně.
    enum Level: Hashable, Sendable {
        case failure
        case warning
        case notice

        init(rawValue: String) {
            switch rawValue {
            case "failure": self = .failure
            case "warning": self = .warning
            default: self = .notice
            }
        }

        /// Štítek u anotace — `error` / `warning` / `notice`, jak ho má návrh (`.ann .lvl`).
        ///
        /// **Anglicky, na rozdíl od zbytku okna**: je to hodnota, kterou vypsalo CI, ne náš popis —
        /// tatáž úvaha jako u jména jobu nebo kategorie nálezu.
        var label: String {
            switch self {
            case .failure: "error"
            case .warning: "warning"
            case .notice: "notice"
            }
        }
    }

    /// Cesta k souboru, jak ji hlásí CI. Může ukazovat i mimo diff (typicky `.github/workflows/…`).
    let path: String
    /// První řádek, ke kterému se anotace váže. `nil` = anotace bez místa v souboru.
    let line: Int?
    let level: Level
    let message: String

    /// Identita z místa **a zprávy**: jeden řádek může mít víc anotací (phpstan jich na jednom
    /// řádku hlásí i několik) a jen `path:line` by je slil do jedné.
    var id: String { "\(path):\(line.map(String.init) ?? "-"):\(message)" }
}

/// Anotace jednoho check-runu i s tím, kolik se jich nevešlo (#214).
///
/// Tichý ořez by tvrdil, že CI nahlásilo jen tolik, kolik je vidět — proto se to, co chybí, nese
/// spolu s tím, co je. **Dvě různá „chybí“**, protože se o nich ví různě moc:
///
/// - `missing` je **přesný počet** anotací, které jsme stáhli a nekreslíme (sto anotací pod řádkem
///   checku je stěna, ne detail);
/// - `mayHaveMore` je „stránka přišla plná, takže **možná** jsou další“ — bez počtu, protože ho
///   neznáme. Je to tentýž případ jako `ConversationShortfall.events` (#171): mlčet nejde, ale
///   číslo si vymyslet nesmíme.
struct CheckAnnotations: Hashable, Sendable {
    var items: [CheckAnnotation] = []
    /// Kolik jich je stažených nad rámec toho, co se kreslí. `0` = kreslí se všechny stažené.
    var missing = 0
    /// Přišla stránka plná? Pak jich na GitHubu může být víc, než jsme viděli.
    var mayHaveMore = false

    var isEmpty: Bool { items.isEmpty }

    /// Kolik anotací se pod řádkem checku vypíše. Zbytek se schová za počet — u `phpstan`u na
    /// velkém PR jich bývá desítky a detail checku se má číst, ne scrollovat.
    static let displayLimit = 20

    /// Ořeže na to, co se kreslí, a **zapamatuje si, kolik zbylo**.
    init(fetched: [CheckAnnotation], pageWasFull: Bool) {
        items = Array(fetched.prefix(Self.displayLimit))
        missing = max(0, fetched.count - items.count)
        mayHaveMore = pageWasFull
    }

    init(items: [CheckAnnotation] = [], missing: Int = 0, mayHaveMore: Bool = false) {
        self.items = items
        self.missing = missing
        self.mayHaveMore = mayHaveMore
    }
}
