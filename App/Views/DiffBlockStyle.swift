import SwiftUI

/// Čím je vysázený text bloku obarvený — všechno, co v jeho **řádcích není** (#157, klíč od #393).
///
/// **Jedno místo pro obě podoby diffu.** Skládaly to `DiffCodeBlockView` (pod sebou)
/// i `DiffPairBlockView` (vedle sebe), každý svým řetězcem — a přitom to musí být tentýž vzorec.
/// Dvě kopie znamenají, že se příští oprava udělá jen v jedné.
struct DiffBlockStyle: Equatable {
    let language: Language?
    /// **Barevný režim je v klíči schválně a musí v něm zůstat.** Barvy jsou v tom vysázeném textu
    /// zapečené, takže bez režimu by se po přepnutí vzhledu (#278) sázení přeskočilo a v okně by
    /// zbyl kód obarvený podle předchozího režimu — a potichu, protože text ani jazyk se nezměnily.
    /// Je to tentýž požadavek jako u #153: pod klíčem smí být jen to, čeho je uložená hodnota
    /// funkcí.
    ///
    /// (`SyntaxRunCache` je jiná cache a barvy v ní nejsou, jen druhy run — tu tedy přepnutí
    /// režimu zneplatňovat nemusí, viz `App/Syntax/`.)
    let colorScheme: ColorScheme

    /// Paleta, kterou se text obarví. Bere se **odsud, ne od volajícího** (#393): jako parametr
    /// vedle režimu by to byly dvě hodnoty o jedné věci, a stráž nad tím klíčem by se dala obejít
    /// paletou, která k němu nepatří — přeskočená sazba by pak nechala v okně barvy z minula.
    var palette: SyntaxPalette { SyntaxPalette.forScheme(colorScheme) }
}

/// Vstupy, ze kterých je **nakreslený** blok kódu funkcí — klíč, podle kterého `updateNSView`
/// pozná, že nemá co dělat (#393).
///
/// **Proč to je potřeba.** SwiftUI si `updateNSView` volá pokaždé, když se přepočítá geometrie
/// bloku, ne když se změní blok: ve ztuhlém okně z #393 na to padlo **1 172 z 21 240** vzorků
/// hlavního vlákna, aniž by se v tom kole přeložilo jediné tělo. Cena jednoho takového průchodu
/// byla přitom lineární v délce bloku (hash všech řádků, dvě pole `DiffLine` navíc, dvě množiny,
/// `sizeToFit()` na oba sloupce, rámečky řádků), takže se platila znovu a znovu za nic.
///
/// **Porovnání celého bloku je v tom kole levné, hash jeho řádků nebyl.** Hodnota representable
/// leží v grafu, takže se při dalším průchodu porovnávají **tatáž** pole — a `Array.==` začíná
/// kontrolou identity úložiště, tedy `O(1)`. Hash naproti tomu přečte všechny znaky pokaždé.
/// Změřeno (`DiffPerformanceMeasurement.blockUpdateGuardCost`, 27 bloků po 60 řádcích): klíč
/// **0,013 ms**, hash s podpisem **0,530 ms**, a i porovnání po řádcích u čerstvých polí je s
/// **0,284 ms** levnější než hash. Stráž tedy nemá jak stát víc, než co ušetří.
///
/// **Šířka v klíči být musí, a to je ta past.** Rámečky řádků (`lineFrames()`) se z ní počítají
/// a ve split pohledu z nich vychází i hranice pravé poloviny (`DiffGutterGeometry.split`), takže
/// bez ní by po změně šířky okna svítila pilulka jinde, než se táhne rozsah. Do **sazby** naopak
/// nepatří (`DiffBlockStyle`): text se šířkou nemění, jen se jinak zalomí, a přesázení ruší
/// rozdělaný výběr — proto jsou to dva klíče, ne jeden.
struct DiffBlockDrawing<Block: Equatable>: Equatable {
    let block: Block
    let style: DiffBlockStyle
    /// Šířka view, na které se blok kreslí (`bounds.width`), ne šířka navržená rozvržením: rámečky
    /// se počítají z toho, co view **má**, takže se stráž musí ptát na tutéž hodnotu.
    let width: Double
}
