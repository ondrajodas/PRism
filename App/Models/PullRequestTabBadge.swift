import Foundation

/// Odznak u záložky PR (#242).
///
/// Do #242 to bylo `Int?` a odznak byl vždycky tlumená kapsle s číslem. Nestačí to na dvě věci,
/// které přišly s novými taby: **blokující nález** má být vidět jako červený (jinak by se počet
/// nálezů četl jako neškodný údaj o množství) a **běžící review** není množství, ale stav — puntík,
/// ne číslo. Kdyby se „běží“ hlásilo počtem, ukazoval by se u dvou reviewerů dvojkou, což o průběhu
/// neříká nic.
///
/// Výčtem, ne strukturou s příznaky: kombinace „puntík s počtem“ ani „blokující bez počtu“ nemá
/// význam, takže se nemá dát napsat.
enum PullRequestTabBadge: Hashable, Sendable {
    /// Kolik je toho v tabu k přečtení. Nikdy nula — „nic“ znamená žádný odznak.
    case count(Int)
    /// Počet, ve kterém **něco blokuje**. Kreslí se červeně.
    case blocking(Int)
    /// Něco běží. Stav, ne množství.
    case live
}
