import AppKit

@testable import PRism

extension NSView {
    /// Plocha obsahu diffu v hostované hierarchii — **největší `NSScrollView`, který není sloupec
    /// dvojice**.
    ///
    /// Rozlišovat je potřeba dvakrát: `DiffPairScrollView` je posuvná plocha **uvnitř** bloku kódu
    /// (#422) a strom souborů má vlastní plochu. Rozhodne dokument: obsah diffu je řádově vyšší než
    /// seznam souborů i než jeden blok.
    ///
    /// **Jedno místo, protože se to hledá pokaždé ze stejného důvodu** (tentýž záměr jako
    /// u `firstDescendant(ofType:)`): kolony diffu jsou SwiftUI a v hostovaném okně se z nich nedá
    /// přečíst nic než AppKitová plocha, na které stojí obsah. Čtou ji `DiffCodeColumnWidthTests`
    /// (#546) i `DiffBubbleDefaultTests` (#548), a kopie, které se neliší, jsou přesně to, co se
    /// při první opravě rozejde.
    func diffContentArea() -> NSScrollView? {
        var best: NSScrollView?
        if let scroller = self as? NSScrollView, !(scroller is DiffPairScrollView) {
            best = scroller
        }
        for child in subviews {
            guard let found = child.diffContentArea() else { continue }
            let height = found.documentView?.frame.height ?? 0
            if height > (best?.documentView?.frame.height ?? 0) { best = found }
        }
        return best
    }
}
