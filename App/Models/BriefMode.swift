import Foundation

/// Kdy se skládá brief na domově (#516).
///
/// **Tři stavy, ne přepínač**, protože se tu rozhodují dvě různé věci: jestli se brief smí
/// skládat vůbec, a jestli ho smí spustit **aplikace sama**. Přepínač by ty dvě otázky slil do
/// jedné a „zapnuto“ by znamenalo obojí — tedy session za peníze při každém ránu, aniž by si o to
/// někdo řekl.
///
/// **Výchozí je `off`**, a je to tatáž třída jako `allowsPublishing` a `autoAgent` (#510): brief
/// stojí peníze a `firstTickOfDay` ho pouští **bez kliknutí**, takže vlastnost „samo nic nezačne“
/// drží jedině výchozí vypnuto.
enum BriefMode: String, Codable, Hashable, Sendable, CaseIterable {
    /// Brief se neskládá a **blok na desce se nekreslí vůbec**. Ne zašedle — vypnutý brief se
    /// nedělá nikdy, takže zašedlé tlačítko by tvrdilo „tady se to dělá, jen teď ne“.
    case off
    /// Jedině na kliknutí. Blok je na desce a čeká s tlačítkem.
    case onDemand
    /// Na kliknutí **a k tomu jednou za den** — při prvním úspěšném tiku, kdy je fronta načtená.
    case firstTickOfDay

    /// Smí se brief skládat vůbec?
    var isOn: Bool { self != .off }

    /// Smí ho spustit **aplikace sama**, bez kliknutí?
    ///
    /// Vlastní hodnota, ne `self == .firstTickOfDay` u volajícího: je to zrovna ta mez, na které
    /// stojí „samo nic nezačne“, a ta má být pojmenovaná.
    var startsByItself: Bool { self == .firstTickOfDay }

    /// Popisek v nastavení.
    var title: String {
        switch self {
        case .off: "Vypnuto"
        case .onDemand: "Na požádání"
        case .firstTickOfDay: "Při prvním tiku dne"
        }
    }
}
