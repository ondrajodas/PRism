import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Prstýnek běžícího review (#180) — a hlavně **čím se točí** (#350).
///
/// Do #350 se točil `withAnimation(.linear.repeatForever)` nad `@State` úhlem. Nekonečná animace ve
/// SwiftUI si ale vyžádá snímek při každém obtažení obrazovky a **každý snímek jde přes
/// `NSHostingView.layout()`, které rozvrhne celé okno** — nečinné okno s otevřeným PR na tom stálo
/// 99 % CPU hlavního vlákna (sonda `IdleWindowSpinProbe`) a nedalo se ovládat. Otáčení proto patří
/// do CoreAnimation, kde ho obslouží render server a hlavní vlákno o něm neví.
///
/// **Tenhle test je ta pojistka proti návratu.** Měřit CPU se tady nedá (strojově závislé číslo by
/// z toho udělalo test padající bez chyby v kódu), takže se ptá na to, co je ekvivalentní a
/// deterministické: **visí na oblouku animace CoreAnimation?** Když ji někdo vrátí do SwiftUI,
/// žádná tam nebude.
@MainActor
@Suite("Prstýnek běžícího review (#350)")
struct SpinningRingTests {
    /// Ptá se na obojí naráz, a je to schválně: že v hierarchii **je** AppKitové view, znamená, že
    /// se prstýnek nekreslí SwiftUI animací, a že na něm **visí** animace, znamená, že se doopravdy
    /// točí. Kdyby se ptalo jen na druhé, prošla by i verze, která si vedle CoreAnimation nechá
    /// `repeatForever` ve SwiftUI.
    @Test("Prstýnek se točí v CoreAnimation, ne ve SwiftUI")
    func spinsInCoreAnimation() throws {
        let hosting = NSHostingView(rootView: SpinningRing())
        hosting.frame = NSRect(x: 0, y: 0, width: 40, height: 40)
        // `layoutSubtreeIfNeeded()` tam být musí: otáčení se nasazuje v `layout()`, takže bez
        // vynuceného rozvržení by test tvrdil, že animace není, nad kódem, který ji přidá.
        hosting.layoutSubtreeIfNeeded()

        let ring = try #require(Self.descendant(of: hosting))
        #expect(ring.isSpinningInCoreAnimation)
    }

    /// Vypnutý pohyb v systému znamená **žádnou animaci**, ne pomalejší. Prstýnek zůstane
    /// nedokončený, takže je z něj pořád poznat, že se něco děje.
    ///
    /// Zkouší se na AppKitovém view, ne přes prostředí: `accessibilityReduceMotion` je
    /// v `EnvironmentValues` jen ke čtení, takže se v testu nedá nastavit.
    @Test("Při vypnutém pohybu se prstýnek netočí vůbec")
    func standsStillWithReducedMotion() {
        let ring = SpinningRingView(lineWidth: 2, isSpinning: false)
        ring.frame = NSRect(x: 0, y: 0, width: 11, height: 11)
        ring.layoutSubtreeIfNeeded()

        #expect(!ring.isSpinningInCoreAnimation)
    }

    /// Změna systémového akcentu se musí propsat do barvy. Ve SwiftUI to bylo zdarma (`.tint` se
    /// resolvovala sama), kdežto `CGColor` ve vrstvě zůstane ten, se kterým se nakreslila — takže by
    /// prstýnek držel starou barvu, dokud se nepřepne světlý/tmavý režim.
    ///
    /// Zkouší se **poslanou notifikací**, ne přehozením akcentu v systému: nastavení uživatele není
    /// testovací fixture. A tvrdí se to na **barvě oblouku**, ne na příznaku překreslení: příznaky
    /// bez okna na obrazovce nedrží (vyzkoušeno u obou — `NSView.needsDisplay` i
    /// `CALayer.needsDisplay()`), kdežto barva je ten výsledek, o který jde. Před notifikací je
    /// `nil`, protože kresba ještě neproběhla — a právě proto je z toho vidět, že ji vyžádala ta
    /// notifikace.
    @Test("Změna systémového akcentu se propíše do barvy oblouku")
    func resolvesColoursWhenTheAccentChanges() {
        let ring = SpinningRingView(lineWidth: 2, isSpinning: true)
        ring.frame = NSRect(x: 0, y: 0, width: 11, height: 11)
        ring.layoutSubtreeIfNeeded()
        #expect(ring.arcStrokeColour == nil)

        NotificationCenter.default.post(name: NSColor.systemColorsDidChangeNotification, object: nil)

        #expect(ring.arcStrokeColour == NSColor.controlAccentColor.cgColor)
    }

    /// Silnější tah znamená jinou cestu — kruh je o půl tahu zúžený dovnitř, aby se do rámu vešel
    /// celý. Kdyby se po změně šířky nevyžádalo rozvržení, zůstala by cesta pro starou šířku
    /// a tah by z prstýnku vyjel.
    @Test("Jiná šířka tahu si vyžádá nové rozvržení")
    func relayoutsWhenTheLineWidthChanges() {
        let ring = SpinningRingView(lineWidth: 2, isSpinning: true)
        ring.frame = NSRect(x: 0, y: 0, width: 40, height: 40)
        ring.layoutSubtreeIfNeeded()
        #expect(!ring.needsLayout)

        ring.apply(lineWidth: 8, isSpinning: true)

        #expect(ring.needsLayout)
    }

    private static func descendant(of view: NSView) -> SpinningRingView? {
        if let ring = view as? SpinningRingView { return ring }
        for child in view.subviews {
            if let ring = descendant(of: child) { return ring }
        }
        return nil
    }
}
