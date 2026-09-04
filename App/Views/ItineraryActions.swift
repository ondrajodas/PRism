import Foundation

/// Zastávky itineráře a co se stane po kliknutí na ně (#506).
///
/// Tentýž vzorec jako `DiffReadActions` nebo `DiffSearchActions`: **stav skládá store, tudy jde
/// jen akce.** `DiffView` si zastávky nepočítá — jsou z nich vidět tři taby, o kterých diff nic
/// neví (`Přehled`, `Kontroly`, panel s verdiktem).
struct ItineraryActions {
    /// Zastávky v pořadí čtení — `Policy.itinerary`.
    var stops: [ItineraryStop] = []
    /// Počítadlo a odhad času do hlavičky — `Policy.itineraryProgress`.
    var progress = ItineraryProgress(done: 0, total: 0, minutes: nil)
    /// Klik na zastávku: přepne tab (`ItineraryStop.tab`) a u `Verdiktu` rozloží panel.
    var select: (ItineraryStop) -> Void = { _ in }
}
