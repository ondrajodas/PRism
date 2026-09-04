import Foundation

/// Co se počítá do odznaku v Docku (#529, návrh sekce 49).
///
/// Tři volby, ne přepínač zapnuto/vypnuto: dlaždice v Docku má **jeden kanál** (řetězec, nebo
/// nic), takže se do ní nedá napsat víc než jedno číslo — a otázka „které“ má dvě rozumné
/// odpovědi, protože fronta a blokující práce jsou dvě různá tvrzení.
///
/// `off` se nejmenuje `none` schválně: `Optional.none` je ve Swiftu v témže jmenném prostoru,
/// takže by `.none` u nepovinné hodnoty znamenalo něco jiného, než co se čte.
enum DockBadgeMode: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    /// Počet cizích PR ve frontě — **tatáž hodnota, jakou má odznak fronty v railu**.
    case waiting
    /// Z těch samých PR jen ta, na kterých leží platný blokující nález.
    case blocking
    /// Prázdná dlaždice.
    case off

    var id: String { rawValue }

    /// Popiska v přepínači. Malým písmenem, jako zbytek segmentů v nastavení.
    var title: String {
        switch self {
        case .waiting: "čekající"
        case .blocking: "blokující"
        case .off: "nic"
        }
    }
}
