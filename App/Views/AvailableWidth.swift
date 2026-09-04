import SwiftUI

/// Konkrétní šířka, kterou má podstrom k dispozici (#220).
///
/// **Proč vůbec existuje.** `frame(maxWidth: .infinity)` na každé úrovni zanoření znamená, že
/// každá úroveň znovu vyjednává šířku s dětmi — a cena layoutu roste **5,5× na úroveň**. Naměřeno
/// u #220 offscreen renderem: hloubka 4 → 11 ms, hloubka 6 → 350 ms, hloubka 8 → 15 700 ms.
/// Okno se na velkém PR zaseklo na 20 minut a 100 % CPU právě v tomhle.
///
/// Jakmile podstrom svou šířku **zná**, vyjednávání skončí: tentýž strom v hloubce 8 spadl
/// z 15 700 ms na **2,2 ms** — tedy touhle cestou, přes environment. Zadrátovaný `frame(width:)`
/// na každé úrovni vyšel na 2,8 ms, takže předávání není o nic dražší než ta nejhrubší varianta.
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

/// Šířka, o kterou se dělí **levý sloupec, kolona kódu a okraj s kartami** (#506).
///
/// Vlastní hodnota, a ne `availableWidth`, protože se ptá na jinou plochu: `availableWidth` je to,
/// co podstrom **dostal**, kdežto tohle je to, o co se dělí — a od #506 to není totéž. Itinerář
/// stojí vedle **všech** tabů, takže ho odečítá rozvržení detailu PR a `DiffView` dostane
/// štěrbinu, ve které už není. Rozhodnutí `Policy.diffSideColumns` se ale musí ptát na tu
/// společnou šířku, jinak by se sloupec skládal podle toho, co po něm zbylo, tedy sám podle sebe.
///
/// **Předává se, nedopočítává.** Přičtení `treeColumnWidth` v `DiffView`u by v okně sedělo (sloupec
/// tam doopravdy stojí), ale kdokoli, kdo `DiffView` hostuje **bez** sloupce vedle sebe, by dostal
/// šířku o 260 bodů větší, než jakou má — a protože ta hodnota vstupuje do rozhodnutí, které pak
/// mění samo sebe, umí to v takovém hostu **kmitat** (rozložený sloupec složí kolonu, složený ji
/// rozloží). Odsud to nekmitá: hodnotu měří ten, kdo sloupec kreslí.
///
/// `nil` = **sloupec vedle téhle plochy nestojí** (diff commitu mimo záložku PR, náhledy, sondy),
/// takže se dělí jen tím, co dostala.
private struct SideColumnsWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var sideColumnsWidth: CGFloat? {
        get { self[SideColumnsWidthKey.self] }
        set { self[SideColumnsWidthKey.self] = newValue }
    }
}

extension View {
    /// Ustaví konkrétní šířku pro celý podstrom. Patří na **hranici obsahu**, kde se šířka dá
    /// změřit jednou — ne dovnitř seznamu, kde by `GeometryReader` byl na každé položce.
    func availableWidth(_ width: CGFloat?) -> some View {
        environment(\.availableWidth, width)
    }

    /// Ustaví šířku, o kterou se dělí postranní kolony (#506) — viz `SideColumnsWidthKey`.
    func sideColumnsWidth(_ width: CGFloat?) -> some View {
        environment(\.sideColumnsWidth, width)
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
