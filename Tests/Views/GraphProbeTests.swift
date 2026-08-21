import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Dvířka do AttributeGraphu (#361) — **ověřená spuštěním, ne přečtená z dokumentace.**
///
/// `GraphProbe` volá privátní `AGGraphDescription`, takže tenhle test je jediné, co drží tvrzení
/// z jeho dokumentace: že se z háků v aplikaci doopravdy dá dostat na evaluační zásobník a že
/// odjinud vrátí **nil**, ne nesmysl. Až systém tu funkci přejmenuje, spadne tady — a to je celý
/// smysl: diagnostika, která tiše přestane odpovídat, je horší než žádná.
///
/// Scéna je `ScrollView` + `LazyVStack` schválně: hledá se kolo v **líném seznamu**, takže háky
/// musí umět odpovědět zrovna z něj.
@MainActor
@Suite("Zásobník AttributeGraphu (#361)")
struct GraphProbeTests {
    /// Mimo aktualizaci grafu **není co vracet** — a to platí i pro test, který o graf nikdy
    /// nepožádal. Kdyby tady něco přišlo, znamenalo by to, že `stack()` čte cizí stav.
    @Test("Mimo aktualizaci grafu vrátí nil")
    func nilOutsideUpdate() {
        #expect(GraphProbe.prepare())
        #expect(GraphProbe.isAvailable)
        #expect(GraphProbe.stack() == nil)
    }

    /// **Zevnitř háku je zásobník vidět.** Tři místa, ze kterých se v aplikaci ptáme: průchod
    /// tělem, `of:` closure u `onGeometryChange` a getter identity, který si čte `ForEach`.
    @Test("Z těla, z geometrie i z identity přijde skutečný zásobník")
    func stackFromHookSites() throws {
        // **Otevřít framework se musí napřed** — v aplikaci to dělá `RenderDiagnostics.start()`,
        // tady to musí říct test, protože `stack()` se sám nezapíná (viz `GraphProbe`).
        #expect(GraphProbe.prepare())
        let seen = SeenStacks()
        let scene = hosted(ProbeList(seen: seen))
        defer { scene.orderOut(nil) }

        for site in ["tělo", "geometrie", "identita"] {
            let text = try #require(seen.stack(of: site), "z „\(site)“ nepřišel zásobník")
            // Formát je cizí, takže se tvrdí jen to, na čem rozbor stojí: rámce a šipka.
            #expect(text.contains("  #0: "), "z „\(site)“ přišlo: \(text.prefix(200))")
            let stack = Policy.graphStack(from: text)
            #expect(stack.top != nil)
            #expect(stack.root != nil)
        }
    }

    /// **Líný seznam je v zásobníku pojmenovaný.** Tohle je ten atribut, o kterém #361 celou dobu
    /// je (`LazySubviewPlacements.updateValue()` v každém vzorku ztuhlé aplikace) — a instrumentace
    /// má cenu jen tehdy, když se v odebraném zásobníku dá najít.
    @Test("V zásobníku z líného seznamu je vidět jeho umisťování")
    func lazyListIsNamed() throws {
        #expect(GraphProbe.prepare())
        let seen = SeenStacks()
        let scene = hosted(ProbeList(seen: seen))
        defer { scene.orderOut(nil) }
        let joined = ["tělo", "geometrie", "identita"].compactMap { seen.stack(of: $0) }
        #expect(!joined.isEmpty)
        // **Jmenovitě `LazySubviewPlacements`**, ne obecné `Lazy` (nález Copilota na #397): kdyby
        // z výpisu zmizel právě tenhle rámec a zůstal třeba `LazyPreference`, test by prošel a
        // nehlídal by to, co o sobě tvrdí.
        #expect(
            joined.contains { $0.contains("LazySubviewPlacements") },
            "v žádném ze \(joined.count) zásobníků není umisťování líného seznamu"
        )
    }

    /// **Z cizího vlákna nic.** Zapisovací vlákno diagnostiky (#391) proto zásobník brát nesmí
    /// a vzorek se odebírá tam, kde kolo běží — na hlavním vlákně zevnitř háku.
    @Test("Z cizího vlákna vrátí nil, ne nesmysl")
    func nilFromOtherThread() async throws {
        #expect(GraphProbe.prepare())
        let seen = SeenStacks()
        let scene = hosted(ProbeList(seen: seen))
        defer { scene.orderOut(nil) }
        let value: String? = await withCheckedContinuation { continuation in
            let thread = Thread { continuation.resume(returning: GraphProbe.stack()) }
            thread.start()
        }
        #expect(value == nil)
    }

    // MARK: - Scéna

    /// Zásobníky odebrané z jednotlivých míst. **Není to observable stav** (#252) a nezapisuje se
    /// do něj z `body` nic, co by průchod tělem vyvolalo znovu.
    final class SeenStacks: @unchecked Sendable {
        private let lock = NSLock()
        private var stacks: [String: String] = [:]

        func note(_ site: String) {
            guard let text = GraphProbe.stack() else { return }
            lock.withLock { if stacks[site] == nil { stacks[site] = text } }
        }

        func stack(of site: String) -> String? {
            lock.withLock { stacks[site] }
        }
    }

    struct ProbeRow: Identifiable {
        let id: Int
        let seen: SeenStacks

        /// Tatáž konstrukce jako `diagnosedID` v aplikaci: identita, kterou si `ForEach` čte při
        /// každém přerovnání obsahu, a u ní hák.
        var probedID: Int {
            seen.note("identita")
            return id
        }
    }

    struct ProbeRowView: View {
        let row: ProbeRow

        var body: some View {
            row.seen.note("tělo")
            return Text("řádek \(row.id)")
                .frame(height: 24)
                .onGeometryChange(for: CGRect.self) {
                    row.seen.note("geometrie")
                    return $0.frame(in: .named("obsah"))
                } action: { _ in }
        }
    }

    struct ProbeList: View {
        let seen: SeenStacks

        var body: some View {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach((0..<80).map { ProbeRow(id: $0, seen: seen) }, id: \.probedID) {
                        ProbeRowView(row: $0)
                    }
                }
                .coordinateSpace(.named("obsah"))
            }
            .frame(width: 400, height: 300)
        }
    }

    /// Scéna v okně **mimo obrazovku** — tatáž cesta jako u ostatních sond (#291): bez okna se
    /// hierarchie nedoskládá a líný seznam by nic neumístil.
    private func hosted(_ content: some View) -> NSWindow {
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        let window = NSWindow(
            contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        _ = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        return window
    }
}
