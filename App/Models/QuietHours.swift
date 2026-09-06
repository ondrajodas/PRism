import Foundation

/// Tiché hodiny (#519) — kdy a od jaké velikosti automat velké PR odkládá.
///
/// **Pravidlo, ne stav.** Leží v `GlobalConfig`, protože je to odpověď na otázku „kdy chci, aby
/// se na mém stroji utrácely session“ — tedy vlastnost člověka a jeho noci, ne repozitáře. Per
/// repo se proto **nepřebíjí**, ze stejného důvodu jako `appearance` a `diffLayout`.
///
/// **Hodiny, ne minuty.** Okno se nastavuje na celé hodiny, protože přesnost pod hodinu tady nemá
/// co rozhodnout: rozdíl mezi 22:00 a 22:15 je u běhu, který trvá minuty a jehož výsledek se čte
/// ráno, neměřitelný. Zato by minuty zdvojnásobily počet polí i počet hraničních případů, které
/// se dají pokazit potichu (přechod přes půlnoc, letní čas).
struct QuietHours: Codable, Equatable, Sendable {
    /// **Výchozí vypnuto**, a je to schválně jiná strana než u `incrementalAfterPush` (#517).
    /// Přírůstek nic neztrácí — dělá totéž levněji. Odklad proti tomu **mění, kdy** se výsledek
    /// objeví: velké PR, na které nikdo nespěchá, se do rána nezreviduje. To je volba o denním
    /// režimu, a ta se nemá zapnout tím, že si někdo nainstaluje novou verzi.
    var isEnabled: Bool
    /// Nad kolik změněných řádků (`additions + deletions`) se odkládá. **Ostře nad**, takže PR
    /// přesně na prahu se pouští hned — práh je hranice velkého PR, ne jeho první hodnota.
    var lineThreshold: Int
    /// Začátek okna v místním čase, 0–23.
    var startHour: Int
    /// Konec okna v místním čase, 0–23. **Menší než začátek je normální stav** (`22`–`6`), ne
    /// chyba: okno přechází přes půlnoc a rozhoduje o tom `Policy.quietHours(contain:rules:)`.
    var endHour: Int

    init(
        isEnabled: Bool = false,
        lineThreshold: Int = 1500,
        startHour: Int = 22,
        endHour: Int = 6
    ) {
        self.isEnabled = isEnabled
        self.lineThreshold = lineThreshold
        self.startHour = startHour
        self.endHour = endHour
    }

    /// Tolerantně jako zbytek konfigurace: co v souboru chybí, se doplní výchozí hodnotou. Soubor
    /// se edituje ručně a čtyři klíče nikdo nenapíše všechny.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = QuietHours()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? standard.isEnabled
        lineThreshold = try container.decodeIfPresent(Int.self, forKey: .lineThreshold)
            ?? standard.lineThreshold
        startHour = try container.decodeIfPresent(Int.self, forKey: .startHour) ?? standard.startHour
        endHour = try container.decodeIfPresent(Int.self, forKey: .endHour) ?? standard.endHour
    }
}

/// Rozhodnutí o odkladu (#519) — **kdy se poběží a podle čeho se to rozhodlo**.
///
/// Vlastní typ, ne samotné `Date`: záznam odkladu nese i počet řádků a práh, a kdyby si je
/// volající dobíral z detailu a z nastavení sám, musel by u počtu řádků dosadit `?? 0` — tedy
/// číslo, které v okně stojí ve větě `0 řádků nad prahem 1 500`. Nedosažitelné dosazení je slabá
/// záruka; tady ta možnost prostě neexistuje, protože obojí vydává tatáž funkce, která odklad
/// povolila.
struct QuietHoursDeferral: Equatable, Sendable {
    /// Nejbližší začátek tichých hodin po okamžiku rozhodnutí.
    let runAt: Date
    /// Kolik řádků PR mění — hodnota, kterou se práh doopravdy poměřoval.
    let changedLines: Int
    /// Práh, který v tu chvíli platil.
    let threshold: Int
}
