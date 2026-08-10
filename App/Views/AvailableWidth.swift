import SwiftUI

/// Konkrétní šířka, kterou má podstrom k dispozici (#220).
///
/// **Proč vůbec existuje.** `frame(maxWidth: .infinity)` na každé úrovni zanoření znamená, že
/// každá úroveň znovu vyjednává šířku s dětmi — a cena layoutu roste **5,5× na úroveň**. Naměřeno
/// u #220 offscreen renderem: hloubka 4 → 11 ms, hloubka 6 → 350 ms, hloubka 8 → 15 700 ms.
/// Okno se na velkém PR zaseklo na 20 minut a 100 % CPU právě v tomhle.
///
/// Jakmile podstrom svou šířku **zná**, vyjednávání skončí: tentýž strom v hloubce 8 spadl
/// z 15 700 ms na 2,8 ms.
///
/// **Hranice na každé čtvrté úrovni nestačí** — změřeno taky (930 ms). Proto se šířka předává
/// po celé délce cesty, ne jen na jejím začátku.
///
/// `nil` je schválně a znamená „nikdo ji nenastavil“ — pak se `filling()` chová jako dnes
/// (`maxWidth: .infinity`). Views se tak dají použít i mimo tu cestu, kde se šířka měří, a mimo
/// ni se nic nemění; kdyby default byla nula, zmizel by obsah.
private struct AvailableWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var availableWidth: CGFloat? {
        get { self[AvailableWidthKey.self] }
        set { self[AvailableWidthKey.self] = newValue }
    }
}

extension View {
    /// Ustaví konkrétní šířku pro celý podstrom. Patří na **hranici obsahu**, kde se šířka dá
    /// změřit jednou — ne dovnitř seznamu, kde by `GeometryReader` byl na každé položce.
    func availableWidth(_ width: CGFloat?) -> some View {
        environment(\.availableWidth, width)
    }

    /// Zúží šířku pro děti o vlastní odsazení. Bez toho by dítě dostalo šířku rodiče a přeteklo
    /// by o padding — a přetečení je horší než vyjednávání, protože je vidět.
    func narrowingWidth(by inset: CGFloat) -> some View {
        transformEnvironment(\.availableWidth) { width in
            guard let current = width else { return }
            width = max(current - inset, 0)
        }
    }

    /// Roztáhne se na dostupnou šířku — **konkrétně**, když ji zná, jinak pružně jako dřív.
    ///
    /// Používá se místo `frame(maxWidth: .infinity, alignment:)` na horkých cestách. `grep`
    /// na `maxWidth: .infinity` proto v `App/Views/` už nesmí vracet nic z řetězce
    /// detail → tab → osa → uzel → bublina.
    func filling(alignment: Alignment = .leading) -> some View {
        modifier(FillingWidth(alignment: alignment))
    }
}

private struct FillingWidth: ViewModifier {
    @Environment(\.availableWidth) private var width
    let alignment: Alignment

    func body(content: Content) -> some View {
        if let width {
            content.frame(width: width, alignment: alignment)
        } else {
            content.frame(maxWidth: .infinity, alignment: alignment)
        }
    }
}
