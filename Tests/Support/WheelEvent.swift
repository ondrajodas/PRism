import AppKit
import CoreGraphics
import Testing

/// Kolečko složené pro test — **jediné místo, kde se v `Tests/` skládá `CGEvent`** (#490).
///
/// `CGEvent(scrollWheelEvent2Source: nil, …)` si stav vstupu **domyslí ze živého systému**: `nil`
/// zdroj znamená kombinovaný stav sezení, takže vyrobená událost nese modifikátory, které měl
/// člověk v tu sekundu doopravdy zmáčknuté. Vstup testu tím přestává být funkcí toho, co test
/// nastavil, a stane se funkcí toho, co se zrovna dělo na klávesnici. Je to tentýž kořen jako
/// globální `NSApp.appearance` (#367), `UserDefaults` sdílené napříč procesy (#411), okno
/// s animací proti stropu dispatch poolu (#462) a metrika písma pod zátěží (#407) — jen ve čtvrté
/// podobě: **test tvrdí něco o prostředí, místo o kódu**.
///
/// Vyrobit se to dá **oběma směry naráz**, a nestojí to nic: zdroj je `privateState` (vlastní stav,
/// ne stav sezení) a `flags` se navíc nasadí **na hodnotu z argumentu**, takže o modifikátorech
/// rozhoduje zápis v testu, i kdyby si privátní zdroj někdy začal domýšlet cokoli.
///
/// **Co dvě zděděné klávesy udělaly** dvěma suitám (změřeno #490, ploška 800×300, 400 nakrmených
/// řádků, kolečko o 3 řádky nahoru):
///
/// | zděděný modifikátor | `deltaY` | `yDisp` po knihovním `scrollWheel` | hlášení myši |
/// |---|---|---|---|
/// | žádný | 3,0 | 380 → 377 | `ESC[<64;` |
/// | `control` | 3,0 | 380 → 377 | **`ESC[<80;`** |
/// | `shift` | **0,0** (delta přeskočí na `deltaX`) | **380 → 380** | **nic** |
/// | `option` | 3,0 | 380 → 377 | **`ESC[<72;`** |
/// | `command`, `capslock`, `fn` | 3,0 | 380 → 377 | `ESC[<64;` |
///
/// Držený `Control` tedy shodí `TerminalWheelTests` (tvrdí tlačítko 64) a držený `Shift` shodí
/// **obojí** — `TerminalScrollProbe` na tom, že se výřezem nepohnulo, a hlášení se nepošle vůbec.
/// Osový překlop u `Shift`u dělá AppKit, ne naše kód: `deltaY` je nula a delta je v `deltaX`,
/// takže knihovní `scrollWheel` skončí na prvním `if` a `Policy.terminalWheelReport` nedostane, co
/// by hlásila.
///
/// Hlídá to `WheelEventTests` — stráž nad zdrojáky, jako u `UnanimatedWindowTests`.
enum WheelEvent {
    /// Klasické kolečko myši, `deltaY` **v řádcích**. Kladné je nahoru.
    static func line(lines: Int32, modifiers: CGEventFlags = []) throws -> NSEvent {
        let wheel = try #require(
            composed(units: .line, wheel1: lines, modifiers: modifiers),
            "kolečko o \(lines) řádků se nepodařilo složit"
        )
        return try #require(NSEvent(cgEvent: wheel), "z `CGEvent` nevznikl `NSEvent`")
    }

    /// Surová událost k dalšímu doplnění — fáze, setrvačnost, poloha (`WheelGesture`).
    ///
    /// Vrací `CGEvent`, ne `NSEvent`, schválně: pole se dá dopsat jedině do něj a převod na
    /// `NSEvent` je jednosměrný.
    static func composed(
        units: CGScrollEventUnit,
        wheel1: Int32,
        modifiers: CGEventFlags = []
    ) -> CGEvent? {
        // **`privateState`, nikdy `nil`.** `nil` je kombinovaný stav sezení, tedy živá klávesnice.
        guard let source = CGEventSource(stateID: .privateState),
              let wheel = CGEvent(
                  scrollWheelEvent2Source: source,
                  units: units,
                  wheelCount: 1,
                  wheel1: wheel1,
                  wheel2: 0,
                  wheel3: 0
              )
        else { return nil }
        // **Nasazuje se bezpodmínečně, ne jen když se o modifikátory někdo řekl**: prázdná sada je
        // taky rozhodnutí testu a jedině zápisem se z `flags` stane funkce argumentu.
        wheel.flags = modifiers
        return wheel
    }
}
