import AppKit

/// Okno, které si test ukáže na obrazovce, se **nesmí objevit s animací** (#462).
///
/// `NSWindow.orderFront(_:)` na okně s výchozí `animationBehavior` spustí animaci objevení — a ta na
/// macOS běží jako `NSAnimation` v **threaded** režimu, tedy `-[NSAnimation _runBlocking]` na
/// **vlákně z globálního dispatch poolu**, které si na celou dobu animace drží a odpovídá z něj
/// display linku. Jedno okno je zanedbatelné; `Tests/Views/` jich ale ukazuje **48** a Swift Testing
/// pouští suity paralelně, takže se ta vlákna sčítají.
///
/// **Změřeno** (samostatná sonda mimo repo, 12 oken naráz, `sample` sám na sebe):
///
/// | co sonda udělá | vláken procesu | z toho v `_runBlocking` |
/// |---|---|---|
/// | 12× `orderFront(nil)`, výchozí `animationBehavior` | 25 | **14** |
/// | 12× totéž s `animationBehavior = .none` | 5 | **0** |
/// | 12× `NSHostingView` bez ukázání okna | 5 | 0 |
///
/// Rozhoduje tedy **ukázání okna**, ne SwiftUI a ne obsah: totéž vyjde i na `borderless` okně bez
/// jediného view (25 / 14). Zaplatí to ale někdo jiný — pool má na tomhle stroji strop **75
/// pracovních vláken** a `SubprocessRunner` z něj bere vlákna na blokující čtení pip. Když je
/// obsazený, čtení `gh` se nedostane na procesor a volání doběhne až timeoutem: změřeno, že při 80
/// obsazených vláknech (pool se zastaví na **76**) čeká práce na téže souběžné frontě **28 s** místo
/// **0,0001 s**. Odtud `PublishError.timedOut` **i** zaseknutý plný běh na těch třech suitách, které
/// `gh` spouštějí — je to jedna příčina a dva projevy.
///
/// Ukázat okno se proto v `Tests/` smí **jedině odsud** a hlídá to `UnanimatedWindowTests`.
/// Podrobnosti a čísla z plných běhů jsou v `docs/testovani.md`.
extension NSWindow {
    /// `orderFront(nil)` bez animace objevení.
    ///
    /// `animationBehavior` se nasazuje na okno, ne na jedno volání, takže z něj nemá animaci ani
    /// `orderOut(_:)` na konci testu — mizení okna je tatáž třída jako objevení.
    func orderFrontUnanimated() {
        animationBehavior = .none
        orderFront(nil)
    }

    /// `orderFrontRegardless()` bez animace objevení — okno nad ostatními, bez aktivace aplikace.
    func orderFrontRegardlessUnanimated() {
        animationBehavior = .none
        orderFrontRegardless()
    }
}
