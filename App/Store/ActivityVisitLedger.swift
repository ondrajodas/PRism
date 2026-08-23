import Foundation

/// Kdy jsem naposledy odešel ze sekce `Dění` (#414) — značka poslední návštěvy.
///
/// **Značka, ne příznak u položky** (návrh, poznámka 87). Jeden časový údaj na celou sekci a nad
/// ním pruh `Tady jsem skončil` — tedy tentýž mechanismus, jakým se čte konverzace
/// (`VisitLedger`, `Policy.conversationRows`, #183 a #361), jen s vlastním klíčem. Příznak
/// u každé položky by byl druhá odpověď na tutéž otázku a zápis na každý řádek.
///
/// **Posouvá se při odchodu ze sekce, ne při vstupu.** Kdyby se přepsala vstupem, přestalo by být
/// nové zrovna to, na co se koukám — je to tatáž nesymetrie jako u `seedVisitBaseline(for:)`
/// (#335), kde dotažení konverzace návštěva **není**.
///
/// **V předvolbách, ne v cache**, ze stejného důvodu jako návštěvy PR: je to jedno datum, ne
/// materiál review. Vlastní typ vedle `VisitLedger` proto, že ten je klíčovaný pull requestem —
/// jeden slovník se dvěma významy znamená, že se ta dvě data dají posunout omylem naráz.
struct ActivityVisitLedger {
    private let preferences: any PreferenceStoring

    private static let key = "activity.lastVisit"

    init(preferences: any PreferenceStoring) {
        self.preferences = preferences
    }

    /// Kdy jsem tu byl naposledy. `nil` = nikdy — a to znamená, že je **nové všechno**
    /// (`Policy.unreadActivity`), protože záznam vzniká teprve za běhu aplikace.
    ///
    /// **Retence tady není** a je to schválně: je to jedna hodnota, ne rostoucí slovník, takže
    /// nemá co uklízet. Lhůta jako u návštěv PR (90 dní) by značku po dovolené zahodila a z celého
    /// záznamu by naráz udělala novinku.
    func lastVisit() -> Date? {
        guard let raw = preferences.preference(forKey: Self.key) else { return nil }
        // Nečitelná hodnota se bere jako „nikdy“, ne jako pád. Je to odvozený stav, který se
        // prvním odchodem ze sekce obnoví.
        return try? Date(raw, strategy: .iso8601)
    }

    /// Posune značku. Volá se **při odchodu ze sekce**, viz `AppStore.syncActivityVisit()`.
    func record(_ at: Date) {
        preferences.setPreference(at.formatted(.iso8601), forKey: Self.key)
    }
}
