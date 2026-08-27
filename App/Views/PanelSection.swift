import SwiftUI

/// Sekce pravého panelu s nadpisem (`.pl-sec > .cap` z návrhu) — `Labely`, `Reviewery`, `Větev`.
///
/// **Jedno místo pro tři sekce**, ne tři kopie čtyř modifikátorů. Nadpis je monospace 10 s
/// prostrkáním a verzálkami, tedy sazba, která se v panelu opakuje a při doladění by se jinak
/// rozešla — a rozejitý nadpis se pozná až vedle sebe na obrazovce.
///
/// Ta věta **musí platit doslova**: když #465 tenhle typ zaváděla, `PanelMetadataView` si vedle něj
/// dál kreslil vlastní `section(_:content:)` se stejným tělem, takže „jedno místo“ byla dvě —
/// nález Copilota nad #471. `Labely` i `Reviewery` proto chodí tudy; druhý zapisovatel téhle sazby
/// se pozná jedině tím, že se `grep`em nenajde nic dalšího s `tracking(1)` a `textCase(.uppercase)`
/// v panelu.
struct PanelSection<Content: View>: View {
    let caption: String
    @ViewBuilder let content: Content

    /// `gap: 6px` mezi nadpisem a obsahem, z návrhu.
    private static var spacing: Double { 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Text(verbatim: caption)
                .font(.system(size: 10, design: .monospaced))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Palette.ink3)
            content
        }
    }
}
