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

    /// Kde má v téhle ploše stát vodorovný pruh (#428) — `nil` je „tam, kam ho dá AppKit“, tedy na
    /// dolní hraně bloku jako do #422 včetně.
    ///
    /// **Je to tentýž `NSScroller`, jen jinde nakreslený**: mění se mu `frame.origin.y` a nic víc.
    /// Vlastní tenká lišta je zamítnutá — knob, tažení, klik do drážky i čtečka obrazovky jsou
    /// v `NSScroller` hotové a druhá drážka pro jeden posun by lhala o tom, kolik jich je.
    ///
    /// **Není to observable stav** a být nesmí: hodnota se mění při každém posunu výřezu, takže by
    /// z ní byl layout bloku při každém snímku (tatáž past jako u polohy bloku v #252 a u hoveru
    /// v #358). Je to obyčejná vlastnost `NSView`u, kterou nikdo nesleduje.
    var pinnedScrollerY: Double? {
        didSet {
            guard pinnedScrollerY != oldValue else { return }
            // Zpátky na `nil` znamená „vrať to, kam to patří“ — a to umí AppKit sám. Bez tohohle by
            // pruh zůstal viset tam, kde byl naposledy přišpendlený.
            if pinnedScrollerY == nil { tile() } else { placeScroller() }
        }
    }

    /// **Rozvržení plochy scroller vrací na dolní hranu**, takže se poloha musí zapsat znovu právě
    /// tady (změřeno: `tile()` i rozvržení nadřazeného view ho vrátí z 183 na 283). Je to jediné
    /// místo v aplikaci, které rámec scrolleru zapisuje — kdyby si ho psal i volající, rozešlo by se
    /// to při první změně šířky okna.
    override func tile() {
        super.tile()
        placeScroller()
    }

    /// Zápis rámce, **jen když se poloha doopravdy liší**. Redundantní zápis by nebyl chyba kresby,
    /// ale je to zpětná vazba z každého snímku — a ta se v tomhle repu nepíše bezpodmínečně (#358).
    private func placeScroller() {
        guard let scroller = horizontalScroller, let y = pinnedScrollerY else { return }
        guard Double(scroller.frame.origin.y) != y else { return }
        scroller.frame.origin.y = y
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
