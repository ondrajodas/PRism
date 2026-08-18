import AppKit
import Foundation

/// Gesto kolečkem nad `NSScrollView` — **jediné místo, kde se v testech skládá `scrollWheel`**
/// (#361).
///
/// Proč to musí být skutečná událost a ne `contentView.scroll(to:)`: programový posun je pro
/// `NSScrollView` obyčejná změna počátku, takže **neproběhne živé scrollování**. Nepošle se
/// `willStartLiveScroll`/`didLiveScroll`/`didEndLiveScroll`, nezapne se setrvačnost a SwiftUI se
/// nedozví, že se scrolluje — a zrovna na tom visí `LazyLayoutViewCache`, který si při
/// scrollování říká o předběžné načtení (`signalPrefetch` je jediný re-arm ve vzorcích u #361).
/// Změřeno: `scroll(to:)` dá tutéž cenu s regresí i bez ní (1,30 s proti 1,28 s u #375).
///
/// **Události se scroll view předávají přímo** (`scrollWheel(with:)`), ne přes `CGEvent.post`:
/// synteticky poslaná událost se do procesu nedoručí (změřeno u #252 — `postToPid` selže
/// potichu) a skutečnou myš si sonda brát nesmí (#350).
@MainActor
enum WheelGesture {
    /// Jedno gesto: `began`, řada `changed` po `step` bodech, `ended` a k tomu setrvačnost.
    ///
    /// Vrací, kam se seznam dostal — bez toho čísla sonda netvrdí nic: gesto, které nikam
    /// neposunulo, je měření nad nehybným oknem.
    static func scroll(
        over scroller: NSScrollView,
        in window: NSWindow,
        steps: Int,
        step: Double
    ) -> Double {
        // **Bod se bere z `bounds` a převádí do okna**, ne z `frame`: `frame` je v souřadnicích
        // nadřazeného view, takže by se událost hlásila jinam, než kam ve okně míří — a poloha
        // není dekorace, jde do `mouseEventWindowUnderMousePointer` i do `location`.
        // (Nález Copilota na #379.)
        let middle = NSPoint(x: scroller.bounds.midX, y: scroller.bounds.midY)
        let point = scroller.convert(middle, to: nil)
        send(phase: .began, momentum: .none, delta: 0, to: scroller, in: window, at: point)
        for _ in 0..<steps {
            send(phase: .changed, momentum: .none, delta: -step, to: scroller, in: window, at: point)
            // Kolo runloopu po každé události: bez něj se rozvržení odloží a naměřilo by se
            // jedno přerovnání místo všech (tatáž past jako hustota kroků u #252).
            _ = spinMainRunLoop(seconds: 0.016)
        }
        send(phase: .ended, momentum: .none, delta: 0, to: scroller, in: window, at: point)
        // Setrvačnost je součást gesta na trackpadu, ne ozdoba: `NSScrollView` v ní scrolluje
        // dál sám a lazy layout si při ní říká o předběžné načtení.
        send(phase: nil, momentum: .begin, delta: -step, to: scroller, in: window, at: point)
        for _ in 0..<12 {
            send(phase: nil, momentum: .continuous, delta: -step / 4, to: scroller, in: window, at: point)
            _ = spinMainRunLoop(seconds: 0.016)
        }
        send(phase: nil, momentum: .end, delta: 0, to: scroller, in: window, at: point)
        _ = spinMainRunLoop(seconds: 0.1)
        return scroller.documentVisibleRect.origin.y
    }

    private static func send(
        phase: CGScrollPhase?,
        momentum: CGMomentumScrollPhase,
        delta: Double,
        to scroller: NSScrollView,
        in window: NSWindow,
        at point: NSPoint
    ) {
        guard let event = event(phase: phase, momentum: momentum, delta: delta, in: window, at: point) else {
            // Nepovedená událost se **hlásí**: mlčky přeskočená znamená gesto o krok krátší
            // a číslo, o kterém nikdo neví, že je z jiného scénáře.
            print("SONDA událost kolečka se nepodařilo složit")
            return
        }
        scroller.scrollWheel(with: event)
    }

    private static func event(
        phase: CGScrollPhase?,
        momentum: CGMomentumScrollPhase,
        delta: Double,
        in window: NSWindow,
        at point: NSPoint
    ) -> NSEvent? {
        guard let source = CGEventSource(stateID: .privateState),
              let wheel = CGEvent(
                  scrollWheelEvent2Source: source,
                  units: .pixel,
                  wheelCount: 1,
                  wheel1: Int32(delta),
                  wheel2: 0,
                  wheel3: 0
              )
        else { return nil }
        // Trackpad hlásí **přesné delty a fázi**; bez obojího to `NSScrollView` vezme jako
        // klasické kolečko myši a živé scrollování nezačne.
        wheel.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        // `nil` fáze **není chybějící hodnota**, je to setrvačnost: prst už na trackpadu neleží,
        // takže událost nese jen `momentumPhase` a `scrollPhase` je nula. Proto `0`, ne default
        // za neúspěch.
        wheel.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase?.rawValue ?? 0))
        wheel.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue))
        wheel.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(delta))
        wheel.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
        wheel.location = window.convertPoint(toScreen: point)
        return NSEvent(cgEvent: wheel)
    }
}
