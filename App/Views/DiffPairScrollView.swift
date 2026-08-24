import AppKit

/// Rolovací plocha jednoho sloupce dvojice — ta, ve které je vodorovný pruh **vidět pořád** (#422).
///
/// Vlastní typ existuje kvůli jedné vlastnosti: `scrollerStyle` se drží na `.legacy`, ať ho někdo
/// přiřadí jakkoli. Overlay scroller se totiž bez rolování **nenakreslí vůbec** — změřeno u #422,
/// že `autohidesScrollers = false` na něm nakreslí **0 pixelů**, ačkoli API v obou nastaveních
/// tvrdí `isHidden = false`, `alphaValue = 1.0` a `knobProportion = 0.333` —, takže trvalý pruh jde
/// jedině legacy stylem.
///
/// **Přiřazení v `init` samo nestačí a nejde o naši vlastní chybu.** `scrollerStyle` je hodnota,
/// kterou `NSScrollView` sám srovnává se systémovou volbou *Zobrazovat posuvníky*
/// (`NSScroller.preferredScrollerStyle`, přes `NSPreferredScrollerStyleDidChangeNotification`),
/// takže je to hodnota **do příštího přepnutí té volby**. Setter proto vede zpátky na `.legacy`.
///
/// **Není to lhoucí getter, a to je podstatné**: getter vrací `super`, takže se to, co si AppKit
/// pamatuje, s tím, co kreslí, nemá jak rozejít — kdyby getter vracel `.legacy` nad ivarem
/// s `.overlay`, tiluje se plocha podle jednoho a čte podle druhého. Test je z obou stran
/// (`DiffPairScrollerTests`): přiřazení `.overlay` i notifikace o změně systémového nastavení
/// nechají styl `.legacy` a pás výšky si plocha bere dál.
///
/// **Jen tyhle dvě plochy, ne globálně.** `NSScroller.preferredScrollerStyle` se nepřebíjí —
/// trvalý pruh je zadání jednoho pohledu, ne preference celého systému, takže zbytek okna
/// (nálezy, konverzace, log) zůstává na tom, co si člověk nastavil.
final class DiffPairScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        super.scrollerStyle = .legacy
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("jen z kódu") }

    override var scrollerStyle: NSScroller.Style {
        get { super.scrollerStyle }
        set { super.scrollerStyle = .legacy }
    }

    /// Výška pásu, který si legacy scroller bere z bloku. **Je to výška, ne šířka** — vodorovný
    /// scroller sloupec nezúží, takže znaků na stranu je stejně jako bez pruhu (změřeno u #422:
    /// 22 ve výchozím okně s otevřenými panely, před i po).
    ///
    /// Bere se z AppKitu, ne jako konstanta 17: `DiffPairScrollerTests` k tomu tvrdí, že se ta
    /// hodnota rovná pásu, který si plocha po layoutu doopravdy vzala (`frame.height −
    /// contentSize.height`) — jinak by rezervace výšky mohla být o bod vedle, a to je přesně ten
    /// překryv, kvůli kterému #236 vzniklo.
    ///
    /// **Typ je `Double`, ne `CGFloat`, a je to podmínka testovatelnosti** (#422): `CGFloat` je
    /// vlastní typ a implicitní převod na `Double` se v rozkladu `#expect` ztratí — `17.0 == 17.0`
    /// pak spadne s tím, že se dvě identická čísla nerovnají. Zbytek geometrie v repu je `Double`
    /// taky, takže se tím nic nevymyká.
    static let scrollerHeight = Double(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
}
