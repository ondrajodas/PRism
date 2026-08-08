import AppKit
import SwiftUI

/// Roztáhne obsah okna **pod titulkovou lištu** (#180).
///
/// `.windowStyle(.hiddenTitleBar)` samo nestačí: titulek schová, ale lišta si výšku nechá, takže
/// vlastní hlavička skončí **pod** semaforem a okno má nahoře prázdný pruh. Doložené na běžící
/// aplikaci — semafor v jednom pruhu, záložky v druhém.
///
/// Roztažení dělá `fullSizeContentView` na `NSWindow`, ke kterému se ze SwiftUI jinak nedostaneme.
/// Je to tatáž cesta jako u `WindowCentering`: co scéna neumí vyjádřit, se dořeší na `NSWindow`.
struct FullSizeContentWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // Až po vložení do hierarchie — dřív `view.window` ještě není.
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        apply(to: view.window)
    }

    /// `nil` okno znamená **nedělat nic**: view může být mimo hierarchii (náhled, offscreen
    /// render) a hádat okno by znamenalo sáhnout na cizí.
    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Lišta se nesmí schovat celá — semafor v ní bydlí a bez něj by okno nešlo zavřít.
        window.standardWindowButton(.closeButton)?.superview?.superview?.isHidden = false
    }
}

extension View {
    /// Obsah okna se kreslí od horní hrany, včetně místa pod semaforem.
    func fullSizeContentWindow() -> some View {
        background(FullSizeContentWindow().frame(width: 0, height: 0))
    }
}
