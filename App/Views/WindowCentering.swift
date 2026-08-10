import AppKit
import SwiftUI

/// Vystředění pomocného okna **v hlavním okně aplikace**, ne na obrazovce.
///
/// Vzniklo u nastavení, od #164 to používají obě pomocná okna: na velkém monitoru (nebo na
/// druhém, když hlavní okno stojí na prvním) by se okno otevřené z toolbaru objevilo o půl metru
/// vedle toho, kam se člověk zrovna kouká.
///
/// **SwiftUI to samo neumí.** `.defaultPosition(_:)` bere `UnitPoint` vztažený k **obrazovce**,
/// takže „vystředit v jiném okně“ se jím nedá vyjádřit — proto ta cesta přes `NSWindow`.
enum WindowCentering {
    /// Vystředí okno a **zapomene jeho uloženou pozici**.
    ///
    /// `setFrameAutosaveName("")` znamená, že okno odsunuté na stranu se **po restartu** vrátí do
    /// středu — proti zvyklosti systému, ale schválně a stejně u obou pomocných oken: jsou to okna
    /// na přečtení a na kliknutí, ne pracovní plocha, a dvě různá pravidla pro dvě podobná okna se
    /// nedají vysvětlit.
    ///
    /// **V rámci jednoho běhu se ta dvě okna liší, a je to vlastnost scény, ne rozhodnutí.**
    /// Změřeno na běžící aplikaci: `Settings` se zavřením zničí, takže se středí při každém
    /// otevření; `Window` (novinky) obsah zavřením nezahodí, takže se středí **jen při prvním**
    /// a pak si drží, kam ho člověk odsunul. Vyhnat okno do středu i tam by znamenalo středit na
    /// aktivaci nebo na `onAppear` — a to je zrovna ta cesta, po které okno **uskakuje pod rukama**
    /// (u novinek by ho posunulo i dotažení historie, protože obsah scény se tím mění). Okno mimo
    /// střed je z těch dvou to lepší.
    static func center(_ window: NSWindow) {
        window.setFrameAutosaveName("")
        window.setFrame(centered(window.frame, in: host(besides: window)), display: true)
    }

    /// Hlavní okno aplikace. Poznává se podle titulku — `WindowGroup(MainWindow.title)` mu ho
    /// dává a je to jediný stabilní znak, kterým se odliší od pomocných oken a od panelů.
    ///
    /// `nil` (zavřené, skryté) znamená **nedělat nic**: chování systému, tedy střed obrazovky,
    /// je správný fallback. Ne pád, ne dohad.
    static func host(besides window: NSWindow) -> NSRect? {
        NSApp.windows.first {
            $0 !== window && $0.isVisible && $0.title == MainWindow.title
        }?.frame
    }

    /// Vystředí rámec v hostiteli a zarovná ho zpátky na viditelnou plochu.
    ///
    /// To druhé je podstatné: hlavní okno může být zpola mimo viditelnou plochu a okno
    /// vystředěné v něm by skončilo za hranou, kde po něm není ani křížek.
    ///
    /// Pořadí ořezu je `max(min(…))`, ne naopak. U okna **širšího než obrazovka** vyjde
    /// `maxX - width` menší než `minX` a opačné pořadí by ho poslalo za levý okraj; takhle
    /// skončí zarovnané k němu. Je na to test — komentář sám tuhle vlastnost neudrží.
    static func centered(
        _ frame: NSRect,
        in host: NSRect?,
        on screens: [ScreenBounds] = ScreenBounds.current
    ) -> NSRect {
        guard let host else { return frame }
        var moved = frame
        moved.origin = CGPoint(x: host.midX - frame.width / 2, y: host.midY - frame.height / 2)

        guard let visible = screens
            .max(by: { $0.frame.intersection(host).area < $1.frame.intersection(host).area })?
            .visible
        else { return moved }
        moved.origin.x = max(visible.minX, min(moved.origin.x, visible.maxX - frame.width))
        moved.origin.y = max(visible.minY, min(moved.origin.y, visible.maxY - frame.height))
        return moved
    }
}

/// Hladina pomocného okna: **před ostatními okny aplikace, a jedině před nimi** (#243).
///
/// Do #243 se hladina nechávala normální a `.floating` bylo vyzkoušené a zamítnuté — s tím, že
/// kliknutí mimo okno ho má odklidit. V provozu se ukázalo, že to je něco jiného než odklidit:
/// okno se **nezavře** (`willClose` nepřijde nikdy), jen zaleze za hlavní okno — a protože se
/// středí v něm (#164), zmizí beze zbytku. Změřeno: hlavní okno 1296×1032, nastavení 900×452,
/// tedy schované celé. Vypadá to jako zavřené a `⌘,` to jen znovu vytáhne dopředu.
///
/// **Je to dvojice a nedá se rozdělit.** `.floating` samo by okno vyneslo i nad **cizí** aplikace,
/// takže z „v popředí aplikace“ by bylo „v popředí všeho“; `hidesOnDeactivate` ho drží v aplikaci
/// tím, že se okno s odchodem aplikace do pozadí skryje. Proto jsou obě hodnoty na jednom místě
/// a je na ně test — sama o sobě je každá z nich chyba.
///
/// **Skrytí není zavření.** Okno se jen odsune z obrazovky (`orderOut`), obsah scény žije dál,
/// takže se rozepsaná hodnota v nastavení neztratí a po návratu do aplikace je okno zpátky i s ní.
/// Zavřené okno se přitom nevrací: systém ukazuje jen ta, která schoval sám.
enum AuxiliaryWindowLevel {
    static func apply(to window: NSWindow) {
        window.level = .floating
        window.hidesOnDeactivate = true
    }
}

/// Obrazovka jen tolik, kolik středění potřebuje: celý rámec na to, aby se poznala ta, na které
/// hostitel převážně leží, a viditelná plocha na ořez.
///
/// Vlastní typ, ne `NSScreen`, kvůli testům — `NSScreen` se vyrobit nedá, takže by jinak zůstalo
/// neotestované zrovna zarovnávání zpátky na plochu.
struct ScreenBounds: Equatable, Sendable {
    let frame: NSRect
    /// Plocha bez menu baru a Docku.
    let visible: NSRect

    static var current: [ScreenBounds] {
        NSScreen.screens.map { ScreenBounds(frame: $0.frame, visible: $0.visibleFrame) }
    }
}

extension NSRect {
    /// Plocha průniku — podle ní se pozná, na které obrazovce okno převážně leží.
    var area: CGFloat { isNull ? 0 : width * height }
}

extension View {
    /// Vystředí okno, ve kterém tenhle kus UI běží, v hlavním okně aplikace.
    ///
    /// Středí se **při vzniku obsahu**, ne při každém vytažení okna dopředu: `openWindow(id:)`
    /// nad už otevřeným oknem ho jen aktivuje, a okno, které pod rukama uskočí, je horší než
    /// okno mimo střed. Drží to `WindowReader` tím, že hlásí okno z `makeNSView`.
    func centeredInMainWindow() -> some View {
        background(WindowReader(onWindow: WindowCentering.center))
    }

    /// Okno, ve kterém tenhle kus UI běží, zůstane **před ostatními okny aplikace** — a jedině
    /// před nimi (#243). Podrobnosti u `AuxiliaryWindowLevel`.
    ///
    /// Vlastní modifikátor vedle středění, ne přilepený k němu: jsou to dvě různé věci udělané
    /// témuž oknu a středění má svoje pravidlo (**při vzniku obsahu**), do kterého hladina nemá
    /// co mluvit. Nastavení proto hladinu dostává na **scéně** — platí i pro stav před
    /// preflightem, kde se formulář ještě nemá čím naplnit — a středění zůstává u formuláře.
    func keptInFrontOfApp() -> some View {
        background(WindowReader(onWindow: AuxiliaryWindowLevel.apply))
    }
}

/// Podá volajícímu okno, ve kterém tenhle kus UI běží.
///
/// Spolehlivější než `NSApp.keyWindow`: to je v `onAppear` klidně ještě hlavní okno,
/// a sáhnout omylem na cizí okno je horší než nesáhnout na žádné.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // `view.window` je `nil`, dokud se view nezasadí do hierarchie.
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
