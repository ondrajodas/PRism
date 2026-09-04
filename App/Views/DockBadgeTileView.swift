import AppKit

/// Odznak v Docku si aplikace **kreslí sama** (#529, oprava po proklikání).
///
/// Do #529 to zkoušel `NSApp.dockTile.badgeLabel`, což je zápis jedné hodnoty a v testech projde
/// — jenže v Docku **nic nenakreslí**, a to potichu. Změřeno na `com.ondrajodas.prism.d`:
/// hodnota se nasadí, přečte se zpátky, `display()` se zavolá, Dock se restartuje, a odznak
/// pořád nikde. Tentýž bundle a tentýž kód s **jiným bundle ID** odznak nakreslí; rozhoduje
/// tedy identita aplikace, ne kód. `badgeSetting` u té aplikace stojí na `notSupported`,
/// protože o `.badge` se v `requestAuthorization` nikdy nežádalo — a `badgeLabel` je na macOS
/// pod tím přepínačem `Odznaky` v Oznámeních. Čísla jsou
/// v [`docs/testovani.md`](../../docs/testovani.md).
///
/// Kresba do `dockTile.contentView` pod ten přepínač **nespadá** — vyzkoušeno na téže aplikaci,
/// tedy nad bundle ID, kterému `badgeLabel` nekreslí, a **přežije i restart Docku**. Je to proto
/// jediná cesta, kterou uživatel to číslo doopravdy uvidí, a k tomu ta jediná, o které se dá
/// tvrdit test: bitmapa téhle třídy se dá porovnat, kdežto „Dock to zahodil“ se z procesu
/// nepozná.
///
/// **Ikona se předává, nebere se z `NSApp`** — jinak by render v testech kreslil ikonu hostitele
/// testů a tvrzení o bitmapě by záviselo na tom, co si zrovna nainstaloval Xcode. Je to tentýž
/// důvod, proč je `dock` ve storu nepovinný (#367 a pět dalších podob téhož kořene).
final class DockBadgeTileView: NSView {
    /// Ikona aplikace pod odznakem. `contentView` **nahrazuje** kresbu dlaždice, takže si ikonu
    /// musí nakreslit i ta vrstva, která ji jen chce nechat, jak byla.
    var icon: NSImage? {
        didSet { needsDisplay = true }
    }

    /// Co stojí na odznaku. `nil` = jen ikona, žádný odznak — tedy tatáž věta jako
    /// `Policy.dockBadge` vracející `nil`: prázdná dlaždice, ne nula.
    var label: String? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        icon?.draw(in: bounds)
        guard let label, !label.isEmpty else { return }

        let layout = Policy.dockBadgeLayout(characters: label.count, in: bounds)
        // Hexy, ne tokeny `Palette` — tatáž úmluva jako v sekci 49 návrhu: dlaždice leží na ploše
        // Docku, kterou si kreslí systém a v obou motivech stejně, takže by paletový token tvrdil
        // o té ploše něco, co o ní neplatí. `#FF3B30` je systémová červená odznaků.
        NSColor(srgbRed: 1, green: 0.231, blue: 0.188, alpha: 1).setFill()
        NSBezierPath(roundedRect: layout.pill, xRadius: layout.pill.height / 2, yRadius: layout.pill.height / 2)
            .fill()

        // **Písmo se měří na tom, na čem se kreslí** (pravidlo od #236): `fontSize` z `Policy` je
        // odvozený od výšky odznaku, kdežto jestli se do něj text vejde, ví jedině sazba. Tři
        // číslice se do pilulky vejdou, sto tisíc PR ve frontě ne — a ořezané číslo v Docku by
        // lhalo o počtu.
        let text = attributed(label, size: layout.fontSize, fitting: layout.pill)
        let size = text.size()
        text.draw(
            at: NSPoint(x: layout.pill.midX - size.width / 2, y: layout.pill.midY - size.height / 2)
        )
    }

    /// Text odznaku, zmenšený tak, aby se do pilulky vešel.
    private func attributed(_ label: String, size: CGFloat, fitting pill: CGRect) -> NSAttributedString {
        // Vodorovná vata na obou stranách, aby se číslo nedotýkalo obrysu pilulky.
        let room = pill.width - pill.height * 0.3
        let full = string(label, size: size)
        guard room > 0, full.size().width > room else { return full }
        // **Zmenšení se spočítá, nehádá v kolech**: šířka textu roste s velikostí písma lineárně,
        // takže jeden podíl trefí správnou velikost. Druhé kolo je proto, že hinting výsledek
        // o zlomek bodu posune — a **jen jedno**, protože po něm už je odchylka pod pixelem.
        var scale = size * room / full.size().width
        var candidate = string(label, size: scale)
        if candidate.size().width > room {
            scale *= room / candidate.size().width
            candidate = string(label, size: scale)
        }
        return candidate
    }

    private func string(_ label: String, size: CGFloat) -> NSAttributedString {
        NSAttributedString(
            string: label,
            attributes: [
                // `semibold` a tabulkové číslice ze sekce 49 návrhu (`font-weight: 600`,
                // `font-variant-numeric: tabular-nums`) — bez nich mění pětka a jednička šířku
                // odznaku a ten při každém tiku poskočí.
                .font: NSFont.systemFont(ofSize: size, weight: .semibold).tabular,
                .foregroundColor: NSColor.white,
            ]
        )
    }
}

extension NSFont {
    /// Totéž písmo s tabulkovými číslicemi.
    ///
    /// Vlastnost, ne volání v kresbě: `NSFontDescriptor` se skládá při každém překreslení
    /// dlaždice a je to jediné místo, kde tuhle úpravu potřebujeme — kdyby přišlo druhé, má být
    /// vidět, že jde o tutéž.
    fileprivate var tabular: NSFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [
                [
                    NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
                ]
            ]
        ])
        // `?? self` není spolknutá chyba: `NSFont(descriptor:size:)` vrací `nil`, když systém tu
        // variantu písma nemá, a proporcionální číslice jsou pořád čitelný odznak.
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
