import AppKit

extension NSView {
    /// První potomek daného typu, do hloubky — a `self`, když sedí sám.
    ///
    /// **Jedno místo, protože se to hledá pokaždé ze stejného důvodu**: tvrzení „v hostované
    /// hierarchii **je** AppKitové view“ (tedy že se ta věc nekreslí SwiftUI, viz #350) se nedá
    /// napsat jinak než průchodem stromem. Do #442 byla tatáž šestiřádková procházka opsaná ve
    /// třech souborech (`SpinningRingTests`, `IdleWindowSpinProbe`, tlačítko obnovení) — a kopie,
    /// které se neliší, jsou přesně to, co se při první opravě rozejde.
    func firstDescendant<V: NSView>(ofType type: V.Type) -> V? {
        if let match = self as? V { return match }
        for child in subviews {
            if let match = child.firstDescendant(ofType: type) { return match }
        }
        return nil
    }
}
