import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// Sonda k #361: **kdy SwiftUI zavolá callback, ze kterého se v aplikaci zapisuje do stavu.**
///
/// Na téhle otázce stojí celá třída chyb z #358: hover update i rozvržení si SwiftUI plánuje po
/// každém přerovnání obsahu, takže **bezpodmínečný zápis** v takovém callbacku zavírá kolo
/// (zápis → neplatné tělo → přerovnání → další callback → zápis). U `onContinuousHover` je to
/// změřené. U `onGeometryChange` se to **předpokládalo** („akce chodí jen při změně hodnoty“)
/// a předpoklad nebyl ověřený ničím — přitom v aplikaci na něm visí šest míst, z toho tři
/// v seznamu řádků diffu, tedy přesně tam, kde #361 hoří.
///
/// Sonda proto počítá dvě věci zvlášť: kolikrát se spustí **výpočet hodnoty** (closure za `for:`)
/// a kolikrát **akce** (zápis). Ve vzorku ze ztuhlé aplikace je vidět jen ten první
/// (`closure #3 in DiffPairBlockRowView.body.getter`, 14 z 1992 vzorků), takže se z čísel dá
/// říct, jestli to sedí.
///
/// **Myš se nesahá.** Okno se staví **pod kurzor tam, kde právě je** (`NSEvent.mouseLocation`);
/// syntetická `.mouseMoved` hover responder nevyvolá vůbec (změřeno u #358), a warpovat kurzor
/// znamená sebrat myš člověku u stroje, což sonda dělat nemá (pravidlo z #350).
///
/// **Pouští se ručně**: `TEST_RUNNER_PRISM_MEASURE=1`.
@MainActor
@Suite(
    "Kdy chodí callbacky rozvržení (#361)",
    .enabled(if: ProcessInfo.processInfo.environment["PRISM_MEASURE"] != nil)
)
struct LayoutCallbackProbe {
    /// Počty se drží v **referenci mimo observable stav**: kdyby to byl `@State`, počítadlo samo
    /// by špinilo graf a sonda by měřila sebe.
    @MainActor final class Counter {
        var hover = 0
        var continuous = 0
        var transform = 0
        var action = 0
        var dirty = 0
        /// Časovač, který graf špiní. Drží se tady, aby ho měl kdo zastavit.
        var pump: Timer?
    }

    /// **Hlavní číslo sondy**: kolikrát se na jedno zašpinění grafu spustí výpočet hodnoty
    /// a kolikrát akce `onGeometryChange`.
    ///
    /// Dva scénáře, a ten druhý je kontrola měřidla (pravidlo „regrese se ověřuje vložením
    /// regrese“): při **měnící se** geometrii musí akce chodit, jinak sonda neumí počítat a nula
    /// v prvním scénáři nic netvrdí.
    @Test("Kolikrát se ozve onGeometryChange na jedno přerovnání")
    func geometryCallbackFrequency() throws {
        for moving in [false, true] {
            let counter = Counter()
            let window = show(rootView: GeometryProbeView(counter: counter, moving: moving))
            defer {
                counter.pump?.invalidate()
                window.orderOut(nil)
            }
            _ = spinMainRunLoop(seconds: 1.5)
            counter.transform = 0
            counter.action = 0
            counter.dirty = 0

            _ = spinMainRunLoop(seconds: 4)
            print("SONDA \(moving ? "měnící se" : "stálá") geometrie: \(counter.dirty)× zašpiněný graf,"
                + " výpočet hodnoty \(counter.transform)×, akce (zápis) \(counter.action)×")
            #expect(counter.dirty > 10, "špinění grafu neproběhlo, sonda nemá co měřit")
            if moving {
                #expect(counter.action > 0, "měřidlo nepočítá — u měnící se geometrie musí akce chodit")
            }
        }
    }

    /// Totéž pro hover. **Nedoběhne k číslu**, dokud není aplikace vpředu: tracking areas
    /// nedoručují pohyb myši aplikaci na pozadí, takže v testovacím hostu (vpředu je terminál)
    /// vyjde nula i nad kurzorem ležícím v okně. Sonda to **říká**, aby se nula nečetla jako
    /// „callback nechodí“.
    @Test("Kolikrát se ozve onHover a onContinuousHover na jedno přerovnání")
    func hoverCallbackFrequency() throws {
        let mouse = NSEvent.mouseLocation
        let counter = Counter()
        let side = 300.0
        let window = show(
            rootView: HoverProbeView(counter: counter, side: side),
            side: side,
            at: NSPoint(x: mouse.x - side / 2, y: mouse.y - side / 2)
        )
        defer {
            counter.pump?.invalidate()
            window.orderOut(nil)
        }
        let inside = window.frame.contains(mouse)
        print("SONDA myš \(mouse), okno \(window.frame), kurzor uvnitř: \(inside ? "ANO" : "NE")")
        _ = spinMainRunLoop(seconds: 1.5)
        counter.hover = 0
        counter.continuous = 0
        counter.dirty = 0

        _ = spinMainRunLoop(seconds: 4)
        print("SONDA za 4 s: \(counter.dirty)× zašpiněný graf,"
            + " onHover \(counter.hover)×, onContinuousHover \(counter.continuous)×")
        print("SONDA aplikace vpředu: \(NSApp.isActive ? "ANO" : "NE")"
            + " — na pozadí hover callbacky nechodí, takže nula nic netvrdí")
        #expect(counter.dirty > 10, "špinění grafu neproběhlo, sonda nemá co měřit")
    }

    private func show(rootView: some View, side: Double = 300, at origin: NSPoint = NSPoint(x: 40, y: 40)) -> NSWindow {
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        // Velikost až za kontrolérem — `contentViewController` přebije `contentRect` (past z #350).
        window.setContentSize(NSSize(width: side, height: side))
        window.setFrameOrigin(origin)
        window.level = .floating
        window.orderFrontRegardless()
        return window
    }
}

/// Pumpa, která **špiní graf zvenčí**: `Timer` na runloopu, ne `Task.sleep`.
///
/// Test drží hlavní actor po celou dobu (`RunLoop.run(until:)` v synchronní metodě), takže úloha
/// se Swift concurrency se ke slovu nedostane — změřeno: s `Task.sleep` se graf zašpinil
/// **nulakrát** a sonda neměřila vůbec nic.
private struct GraphPump: ViewModifier {
    let counter: LayoutCallbackProbe.Counter
    let tick: () -> Void

    func body(content: Content) -> some View {
        content.onAppear {
            let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
                MainActor.assumeIsolated {
                    tick()
                    counter.dirty += 1
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            counter.pump = timer
        }
    }
}

/// Plocha s `onGeometryChange`. `moving` mění rozměr o bod, takže se měřená hodnota **mění** —
/// to je kontrola měřidla; bez ní by nula u stálé geometrie mohla znamenat i rozbitou sondu.
private struct GeometryProbeView: View {
    let counter: LayoutCallbackProbe.Counter
    let moving: Bool
    @State private var tick = 0

    var body: some View {
        VStack(spacing: 0) {
            Color.blue
                // Špinění, které **nehýbe** měřenou plochou: krytí je kresba, ne rozvržení.
                .opacity(moving ? 1 : 0.2 + Double(tick % 2) * 0.1)
                .frame(width: moving ? 280 - Double(tick % 2) : 280, height: 120)
                .onGeometryChange(for: CGRect.self) { proxy in
                    counter.transform += 1
                    return proxy.frame(in: .named("probe"))
                } action: { _ in
                    counter.action += 1
                }
        }
        .frame(width: 300, height: 300, alignment: .topLeading)
        .coordinateSpace(.named("probe"))
        .modifier(GraphPump(counter: counter) { tick += 1 })
    }
}

/// Plocha s oběma hover callbacky a pumpou, která špiní graf.
private struct HoverProbeView: View {
    let counter: LayoutCallbackProbe.Counter
    let side: Double
    @State private var tick = 0

    var body: some View {
        Color.blue.opacity(0.25)
            .frame(width: side - Double(tick % 2), height: side)
            .onHover { _ in counter.hover += 1 }
            .onContinuousHover { _ in counter.continuous += 1 }
            .modifier(GraphPump(counter: counter) { tick += 1 })
    }
}
