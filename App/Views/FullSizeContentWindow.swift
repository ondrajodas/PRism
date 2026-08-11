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
///
/// Od #245 tady bydlí i **vypnutí systémových záložek oken**. Je to tentýž druh věci — chrome
/// hlavního okna, které scéna nepopíše — a hlavně tentýž důvod: okno má záložky vlastní, takže
/// systémová titulková lišta i systémový pruh záložek jsou zdvojený pojem.
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
        // **Systémové záložky oken se vypínají** (#245). Hlavní scéna je `WindowGroup`, takže
        // macOS nabízí *Nové okno* a dvě taková okna by se dala sloučit do záložek AppKitu — a v nich
        // je `⌃Tab` jeho, ne náš. Aplikace kreslí vlastní pruh záložek, takže systémové jsou
        // zdvojený pojem: dvě řady záložek nad sebou, z nichž každá znamená něco jiného.
        //
        // **Dnes to sama o sobě nerozhoduje, a je to změřené.** Nad dvěma otevřenými okny jsou
        // všechny položky nabídky `Okno` (`Sloučit všechna okna`, `Zobrazit další panel`, …)
        // zakázané **i bez téhle řádky** — schovaná titulková lišta výš dělá okno netabovatelným
        // (v samostatném pokusu má takové okno `tabGroup == nil` hned po vzniku, kdežto obyčejné
        // titulkové okno ho má). A obráceně: `addTabbedWindow(_:ordered:)` okna sloučí **i se
        // `.disallowed`**, takže tvrdá záruka to není. Zůstává tu jako **vyslovený záměr** —
        // uživatelskou cestu k systémovým záložkám zavírá a přežije to, kdyby se titulková lišta
        // někdy vrátila; jinak by se `⌃Tab` začal přetahovat s AppKitem.
        window.tabbingMode = .disallowed
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
