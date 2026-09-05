import AppKit
import Foundation

/// Předání adresy systému, aby ji otevřel zaregistrovaná aplikace (#530).
///
/// **Není to druhá cesta ven** (tvrdá podmínka č. 1): neodesílá se nic na GitHub ani do remote,
/// jde ven **adresa souboru v cache aplikace**. A není to ani spuštění podprocesu — aplikace
/// nehledá binárku editoru, jen předá URL schéma, které si editor v systému zaregistroval sám.
///
/// **Hranice, na které to celé stojí, je před tímhle typem, ne v něm**: cesta se ověřuje
/// `CacheFile.refusal` v `AppStore.openInEditor(…)`. Tenhle typ o cache nic neví a vědět nemá —
/// dostane hotovou adresu.
///
/// Za protokolem ze stejného důvodu jako zbytek `Environment/`: spuštěná cizí aplikace se v testu
/// nedá vzít zpátky, takže fake je jediný způsob, jak otestovat, že se **nic neotevřelo**.
protocol EditorOpening: Sendable {
    /// Otevře adresu. `false` = **systém ji nepřevzal** — typicky proto, že schéma nemá kdo
    /// obsloužit (editor není nainstalovaný).
    ///
    /// Vrací se `Bool`, ne `throws`: `NSWorkspace` důvod nesděluje, takže vymyšlená kategorie
    /// chyby by tvrdila víc, než co se dá vědět. Co s tím, rozhoduje volající — a **spolknout to
    /// nesmí**: výsledek téhle akce je mimo okno aplikace, takže neúspěch vypadá k nerozeznání
    /// od toho, že se nekliklo.
    func open(_ url: URL) async -> Bool
}

/// Systémové otevření přes `NSWorkspace`.
///
/// **Jedno volání a žádná konfigurace.** Který editor se přihlásí k `vscode://`, rozhoduje
/// systém podle toho, co je nainstalované; aplikace do toho nemluví a ani nemá jak.
struct WorkspaceEditor: EditorOpening {
    func open(_ url: URL) async -> Bool {
        NSWorkspace.shared.open(url)
    }
}
