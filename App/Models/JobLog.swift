import Foundation

/// Celý log jobu, připravený k zobrazení v sheetu (#417).
///
/// **ANSI se sundá, timestampy zůstanou** (sekce 28 návrhu). Sundá se, co se nedá nakreslit;
/// nechá se, co se dá přečíst: `^[[36;1m` uprostřed věty je rozbitý log, kdežto timestamp je
/// jediné, čím se řádek přiváže k době běhu jobu. Cena je změřená — 29 znaků timestampu stojí
/// 240 bodů šířky, ale 1 360 bodů bez nich zalamuje stejně jako 1 600 s nimi. Konec logu v tabu
/// `Kontroly` je proti tomu sundává (`Policy.strippingTimestamps`), a je to v pořádku: tam má
/// řádek 34 bodů odsazení a pár set bodů šířky, kdežto sheet je ta obrazovka, kde se člověk ptá
/// po *úplném* textu.
///
/// **Počet řádků a velikost se nesou s textem**, i když by se z něj daly spočítat: hlavička sheetu
/// je oboje vypisuje, takže by se scan megabajtů dělal při každém překreslení — a to je zrovna to,
/// co zakazuje #224. Tady je to zdarma, protože příprava textu si řádky stejně dělí.
struct JobLog: Hashable, Sendable {
    /// Log bez ANSI sekvencí, **s timestampy a bez ořezu na řádky**.
    let text: String
    /// Kolik řádků `text` má.
    let lineCount: Int
    /// Jak velký byl log, jak přišel — tedy velikost, kterou má `job.log` na GitHubu.
    let byteCount: Int
    /// Kdy se stáhl. **Není to čas kliknutí na `Ukázat celý log`** a ten rozdíl je celý důvod, proč
    /// se to nese: u běžícího jobu hlavička sheetu říká `Snímek z HH:MM:SS`, a snímek je z chvíle
    /// **stažení**, ne z chvíle otevření — log leží v paměti od rozbalení checku a od té doby na
    /// GitHubu narostl. Čas z kliknutí by tvrdil, že je text novější, než jaký je.
    let fetchedAt: Date
}
