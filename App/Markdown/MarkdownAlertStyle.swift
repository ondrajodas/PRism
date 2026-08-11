import SwiftUI

/// Jak se kreslí GitHubová výstraha: titulek, ikona, barva (#279).
///
/// Model nese **jen druh** (`MarkdownBlock.Alert`), protože ve zdroji není nic než `[!NOTE]`.
/// Titulek a ikona jsou tedy tvrzení aplikace, ne text z GitHubu — a proto jsou **česky**, jako
/// všechny ostatní popisky v okně.
///
/// Barvy jsou z `Palette` a **`[!CAUTION]` ani `[!WARNING]` nesmí splynout** s `crit` a `stale`;
/// důvod i čísla jsou u tokenů v `Palette`. Význam přitom nestojí jen na barvě: titulek a ikona
/// ho řeknou i tomu, kdo si režim přepnul nebo barvy nerozlišuje.
struct MarkdownAlertStyle {
    let title: String
    /// SF Symbol. Vyplněné varianty schválně — obrys je při 12 bodech vedle textu skoro nevidět.
    let symbol: String
    let color: Color

    static func of(_ kind: MarkdownBlock.Alert) -> MarkdownAlertStyle {
        switch kind {
        case .note:
            MarkdownAlertStyle(title: "Poznámka", symbol: "info.circle.fill", color: Palette.alertNote)
        case .tip:
            MarkdownAlertStyle(title: "Tip", symbol: "lightbulb.fill", color: Palette.ok)
        case .important:
            MarkdownAlertStyle(title: "Důležité", symbol: "exclamationmark.bubble.fill", color: Palette.accent)
        case .warning:
            MarkdownAlertStyle(title: "Upozornění", symbol: "exclamationmark.triangle.fill", color: Palette.alertWarning)
        case .caution:
            MarkdownAlertStyle(title: "Pozor", symbol: "exclamationmark.octagon.fill", color: Palette.alertCaution)
        }
    }
}
