import Foundation

/// Místo v kódu, na které odpověď ukázala (#452).
///
/// **Vždycky se souborem i řádkem.** Odkaz na soubor bez řádku by skočil na hlavičku souboru
/// v diffu, tedy nikam — a `→ SecretClient.php` v odpovědi vypadá jako slib, který klik nesplní.
/// Nález bez řádku má proti tomu kam spadnout (do tabulky nálezů), takže se ty dva případy
/// nemají čím řídit stejně.
struct AskReference: Equatable, Hashable, Sendable, Identifiable {
    let file: String
    let line: Int

    var id: String { "\(file):\(line)" }
    var label: String { "\(file):\(line)" }
}

extension Policy {
    /// Kolik odkazů se z jedné odpovědi vydá.
    ///
    /// Strop je tu proto, že odpověď na „co v tomhle PR nejvíc riskuje“ umí vyjmenovat dvacet
    /// míst — a dvacet kapslí pod bublinou přestane být odkazem a stane se tabulkou, kterou nikdo
    /// nečte. Šest je tolik, kolik se vejde do dvou řádků v tabu s panelem i bez něj.
    static let askReferenceLimit = 6

    /// Místa v kódu, na která odpověď ukázala.
    ///
    /// Hledá se `cesta/k/souboru.pripona:cislo`, tedy **přesně ten tvar, o který si prompt řekne**
    /// (`Policy.askPrompt`). Dvě věci se zahazují schválně:
    ///
    /// - **URL** (`https://host:8080/x`) — dvojtečka s číslem je v ní port, ne řádek. Pozná se
    ///   podle `//` v cestě.
    /// - **duplicity** — model tentýž řádek zmíní v odstavci i v shrnutí a dvě stejné kapsle pod
    ///   bublinou vypadají jako dvě různá místa. Pořadí zůstává v tom, v jakém se objevila
    ///   v textu, protože podle něj se odpověď čte.
    ///
    /// **Nekontroluje se, jestli ten soubor v diffu je.** Odpovídá na to až skok (`nil` kotva =
    /// nestane se nic) a rozhodovat o tom tady by znamenalo, že `Policy` potřebuje diff — tedy
    /// další vstup kvůli kapsli, která se v nejhorším nedá zmáčknout.
    static func askReferences(in text: String) -> [AskReference] {
        var found: [AskReference] = []
        var seen: Set<String> = []
        for match in text.matches(of: referencePattern()) {
            let path = String(match.output.1)
            // `//` v cestě znamená schéma URL nebo protokolový oddělovač — číslo za dvojtečkou
            // je pak port.
            guard !path.contains("//"), let line = Int(match.output.2), line > 0 else { continue }
            let reference = AskReference(file: path, line: line)
            guard seen.insert(reference.id).inserted else { continue }
            found.append(reference)
            if found.count == askReferenceLimit { break }
        }
        return found
    }

    /// `App/Views/Palette.swift:42`, `SecretClient.php:80`.
    ///
    /// Přípona je povinná: bez ní by se `#452:12` nebo `verze 1.2:3` četly jako cesta. A číslo
    /// musí být na konci tokenu (`\b`), aby se z `1.2.3:4` nebrala část.
    ///
    /// **Funkce, ne `static let`**: `Regex` není `Sendable`, takže uložený vzor by byl sdílený
    /// měnitelný stav — a `Policy` je čistá. Překlad literálu je při každém volání, ale volá se
    /// jednou na bublinu a jen u odpovědi, ne v kole.
    private static func referencePattern() -> Regex<(Substring, Substring, Substring)> {
        /([A-Za-z0-9_.\-\/]+\.[A-Za-z0-9]+):([0-9]{1,6})\b/
    }
}
