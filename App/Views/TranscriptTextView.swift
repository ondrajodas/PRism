import AppKit
import SwiftUI

/// Přepis surové session jako **jeden** `NSTextView` (#327).
///
/// Je to tentýž vzor jako u konce logu (`LogTailTextView`) a u hunku v sheetu
/// (`SelectableCodeView`) — a **třetí view to je schválně**, ne z lenosti:
///
/// - **`LogTailTextView`** nezalamuje, skáče na konec dokumentu a bere **jednolitý** `String`
///   s jednou barvou. Přepis potřebuje pravý opak: zalamovat (próza je to hlavní, kvůli čemu se
///   sem chodí), otevřít se **na začátku okna** (okno už *je* konec souboru, takže druhý skok na
///   konec by přepis začínal poslední událostí) a mít **vysázené hlavičky**, tedy atributy.
/// - **`SelectableCodeView`** zalamuje a atributy má, ale sází kód podle jazyka a nemá žádnou
///   stráž — což mu stačí, protože nad ním nic netiká.
///
/// **Stráž tady být musí, a je to konkrétní důvod, ne pojistka** (#393). Patička sheetu hlásí, kolik
/// od otevření přibylo, takže se `body` sheetu přepočítává **při každém dotazu na velikost souboru**
/// — a bez stráže by se při každém takovém tiknutí sázel znovu celý přepis, tedy až megabajty.
/// Klíčem je **celý snímek**, ne jeho hash: hodnota leží v grafu, takže `Array.==` skončí na
/// identitě úložiště (u bloku diffu změřeno 0,013 ms proti 0,530 ms za hash).
///
/// **Šířka v klíči není**, a je to rozdíl proti `DiffBlockDrawing`: přepis si o vlastní velikost
/// neříká (`sizeThatFits` nemá, plochu dostane od sheetu) a zalamuje ho `widthTracksTextView`, takže
/// při změně šířky se nesází znovu — jen se přeláme. Přesázení by naopak zrušilo rozdělaný výběr.
struct TranscriptTextView: NSViewRepresentable {
    let transcript: RawTranscript
    /// Kreslí se z něj barvy. Nese se **jako hodnota**, aby se přepis přesázel při přepnutí režimu:
    /// `NSColor(Color)` z palety si dynamický provider drží, ale klíč stráže by se jinak nezměnil.
    let colorScheme: ColorScheme

    /// Odsazení textu od hran — dovnitř `NSTextView`u, ne paddingem ve SwiftUI, aby scroller
    /// nejezdil po prázdném pruhu. Vodorovně 12 bodů jako `.rawtx .ev` v návrhu.
    private static let inset = NSSize(width: 12, height: 8)

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isEditable = false
        // Read-only, ale **vybíratelné** — přepis je k přečtení a k vykopírování řádku, ne k psaní.
        // Vestavěný terminál to není a nemá být: řeší **zásah**, tohle **čtení**.
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = Self.inset
        // **Zalamuje se**, na rozdíl od konce logu — a je to vědomá odchylka od návrhu, který má
        // `white-space: pre` u těla události. V jednom textovém kontejneru nejde mít zalamované
        // odstavce vedle nezalamovaných (`lineBreakMode` v odstavci text neuzalomí, ale **usekne**),
        // takže se vybírá z dvou možností: próza uteče doprava, nebo dlouhý řádek výstupu zabere
        // víc řádků sazby. Próza je to, kvůli čemu se sem chodí, a strop 8 kB na událost drží
        // zalomený výstup v mezích.
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        // **Fokus musí dostat text, jinak mu nechodí klávesy** — ⌘A ani ⌘C (změřeno u #157).
        // Odloženě, protože v `makeNSView` view ještě žádné okno nemá.
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
        return scroll
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Co už je nasázené. Viz stráž v dokumentaci typu.
    @MainActor
    final class Coordinator {
        var shown: RawTranscript?
        var shownScheme: ColorScheme?
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView,
              Self.needsTypesetting(context.coordinator, transcript: transcript, scheme: colorScheme)
        else { return }

        textView.textStorage?.setAttributedString(
            RawSessionScript.attributed(RawSessionScript.lines(of: transcript))
        )
    }

    /// Má se sázet znovu? **Vlastní funkce, aby se dala otestovat** — `NSViewRepresentableContext`
    /// se v testu nepostaví, takže by stráž schovaná v `updateNSView` šla ověřit jedině okem.
    ///
    /// Zapisuje do koordinátoru **jen tehdy, když se doopravdy sází**: jinak by druhé volání se
    /// stejnou hodnotou stráž nahlásilo jako změnu.
    @MainActor
    static func needsTypesetting(
        _ coordinator: Coordinator,
        transcript: RawTranscript,
        scheme: ColorScheme
    ) -> Bool {
        guard coordinator.shown != transcript || coordinator.shownScheme != scheme else { return false }
        coordinator.shown = transcript
        coordinator.shownScheme = scheme
        return true
    }
}
