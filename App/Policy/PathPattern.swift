import Foundation

extension Policy {
    /// Sedí cesta ze diffu na vzor z konfigurace? (#518)
    ///
    /// **Pravidla jsou gitignore, ne `fnmatch`**, a je to volba pro čtenáře konfigurace: kdo do ní
    /// píše `src/Auth/**` a `composer.lock`, má v ruce zkušenost z `.gitignore`, ne z `man 3
    /// fnmatch`. `fnmatch` navíc `**` nezná vůbec — s `FNM_PATHNAME` se zastaví na prvním lomítku
    /// a bez něj by `*` přeskakovalo hranice složek, takže `src/*` by sedělo na celý podstrom.
    ///
    /// Co vzor znamená:
    ///
    /// - **vzor bez lomítka** sedí na **jméno souboru** kdekoli v repu (`composer.lock`, `*.env*`);
    /// - **vzor s lomítkem** se čte od korene repa (`src/Auth/**`), takže `Auth/**` na
    ///   `src/Auth/User.php` **nesedí** — od korene tam žádné `Auth/` není;
    /// - **`**`** přeskočí libovolný počet znaků **včetně lomítek**, takže `src/Auth/**` sedí i na
    ///   `src/Auth/Token/Jwt.php`;
    /// - **`**/`** přeskočí i **žádnou** složku, takže `src/**/*.php` sedí i na `src/Cart.php`
    ///   (tohle je zrovna to, co se od gitignore čeká a co samotné „`**` je libovolný text“ nedá);
    /// - **`*`** přeskočí libovolný počet znaků **kromě lomítka**, tedy zůstane v jedné složce;
    /// - **`?`** je právě jeden znak kromě lomítka;
    /// - **vzor zakončený lomítkem** je složka, tedy `src/Auth/` znamená `src/Auth/**` — takhle ho
    ///   člověk zkopíruje z `.gitignore` a odmítnout mu ho by znamenalo pravidlo, které nikdy na nic
    ///   nesedí;
    /// - **úvodní lomítko** se zahazuje (`/composer.lock` je totéž jako `composer.lock` od korene).
    ///
    /// **Velikost písmen rozhoduje**, protože o ní rozhoduje `git`: cesta z diffu je ta, kterou
    /// verzuje repo.
    static func pathMatches(_ path: String, pattern: String) -> Bool {
        let cleaned = pattern.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, !path.isEmpty else { return false }

        var expression = cleaned.hasPrefix("/") ? String(cleaned.dropFirst()) : cleaned
        // Složka: `src/Auth/` je zápis, který se do konfigurace opisuje z `.gitignore`. Bez tohohle
        // doplnění by nesedělo nic, protože cesta souboru na lomítko nekončí.
        if expression.hasSuffix("/") { expression += "**" }
        guard !expression.isEmpty else { return false }

        // Vzor bez lomítka mluví o jménu souboru. Porovnává se **jen** s ním, ne s celou cestou:
        // `*.env*` by jinak sedělo i na `env/config.php`, tedy na složku, o které nikdo nemluvil.
        let subject = expression.contains("/") ? path : String(path.split(separator: "/").last ?? "")
        return matches(subject[...], expression[...])
    }

    /// Vlastní porovnání, rekurzivně. Vzory jsou ruční a krátké, cesty krátké taky, takže tady
    /// nehrozí kombinatorika, na kterou by byl potřeba automat s memoizací.
    private static func matches(_ path: Substring, _ pattern: Substring) -> Bool {
        guard let token = pattern.first else { return path.isEmpty }
        switch token {
        case "*":
            let rest = pattern.dropFirst()
            return rest.first == "*"
                ? matchesAcrossSlashes(path, rest.dropFirst())
                : matchesWithinSegment(path, rest)
        case "?":
            guard let head = path.first, head != "/" else { return false }
            return matches(path.dropFirst(), pattern.dropFirst())
        default:
            guard let head = path.first, head == token else { return false }
            return matches(path.dropFirst(), pattern.dropFirst())
        }
    }

    /// `**` — přes lomítka, a když za ním lomítko stojí, smí přeskočit i **žádnou** složku.
    private static func matchesAcrossSlashes(_ path: Substring, _ rest: Substring) -> Bool {
        // `**/x` sedí i na `x`: tohle je ta část gitignore, kvůli které se `**` nedá napsat jako
        // „libovolný text“ — bez ní by `src/**/*.php` minulo `src/Cart.php`.
        if rest.first == "/", matches(path, rest.dropFirst()) { return true }
        var index = path.startIndex
        while true {
            if matches(path[index...], rest) { return true }
            guard index < path.endIndex else { return false }
            index = path.index(after: index)
        }
    }

    /// `*` — jen v jedné složce, tedy zastaví se na lomítku.
    private static func matchesWithinSegment(_ path: Substring, _ rest: Substring) -> Bool {
        var index = path.startIndex
        while true {
            if matches(path[index...], rest) { return true }
            guard index < path.endIndex, path[index] != "/" else { return false }
            index = path.index(after: index)
        }
    }
}
