import Foundation

/// Trvalé předvolby aplikace — to, co si pamatuje mezi spuštěními a co **není** `config.json`.
///
/// Rozdíl proti konfiguraci: tohle je **stav aplikace**, ne nastavení, které si někdo edituje.
/// Výška spodního panelu, poslední viděné vydání (#127). Do `config.json` takové věci nepatří,
/// protože v něm nikomu nic neříkají a dají se rozbít.
///
/// Za protokolem ze stejného důvodu jako `ProcessRunning` nebo `HTTPGetting`: `UserDefaults`
/// je přístup ke stroji. Bez něj by testy psaly buď rovnou do předvoleb aplikace, nebo do
/// vlastní suite — a ta po sobě **nechává soubor** v `~/Library/Preferences`. Změřeno:
/// `removePersistentDomain(forName:)` ani `synchronize()` to nespraví, z jedenácti souborů
/// jich po běhu testů zůstalo šest.
///
/// Metody se jmenují jinak než na `UserDefaults` schválně — `string(forKey:)` a `set(_:forKey:)`
/// tam už jsou a přetěžovat je v extension znamená hádat, která se zavolá.
protocol PreferenceStoring {
    func preference(forKey key: String) -> String?
    func setPreference(_ value: String, forKey key: String)
}

extension UserDefaults: PreferenceStoring {
    func preference(forKey key: String) -> String? { string(forKey: key) }

    func setPreference(_ value: String, forKey key: String) { set(value, forKey: key) }
}
