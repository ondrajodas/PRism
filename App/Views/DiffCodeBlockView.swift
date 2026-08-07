import AppKit
import SwiftUI

/// Blok řádků diffu jako **jeden text**, ve kterém jde vybírat přes řádky (#157).
///
/// Nahrazuje `DiffLineView` v pohledu pod sebou. Řádky se do bloku slily proto, že selekce přes
/// víc řádků se ve SwiftUI udělat nedá — každý `Text` je vlastní selekce. Blok končí tam, kde do
/// diffu něco vstoupí (bublina, hlavička hunku, expander), takže vybírat jde přes celý úsek kódu
/// mezi nimi.
///
/// **Co si bere na sebe `NSTextView`** (`DiffTextView`): text, obarvení, pozadí podle druhu řádku,
/// pruh rozsahu, čísla řádků a znak změny. **Co zůstává SwiftUI**: pilulka na komentář a tažení
/// rozsahu — jsou v overlay nad blokem a pozicují se podle rámečků řádků, které textové view hlásí.
struct DiffCodeBlockView: NSViewRepresentable {
    let block: DiffBlock
    var language: Language?
    let colorScheme: ColorScheme
    /// Řádky (podle pořadí v bloku), které leží v rozsahu některého mého komentáře.
    var commentRangeLines: Set<Int> = []
    /// Totéž pro rozsah, který se právě táhne.
    var draggedLines: Set<Int> = []
    /// Rámečky řádků po layoutu — z nich se staví overlay s pilulkou a hlásí se do `DiffRowFrames`.
    var noteFrames: ([DiffBlockLineFrame]) -> Void = { _ in }

    /// Poslední ohlášené rámečky. Bez nich se hlášení a překreslení honí dokola: `updateNSView`
    /// ohlásí rámečky → SwiftUI překreslí → `updateNSView` ohlásí zase → **problikávání** (nahlášené
    /// při zkoušení #157). Koordinátor je jediné místo, kde si representable může něco pamatovat.
    final class Coordinator {
        var frames: [DiffBlockLineFrame] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> DiffTextView {
        // **Ručně složený TextKit 1.** `NSTextView(frame:)` dostane na dnešním macOS TextKit 2,
        // kde je `layoutManager` nil — a bez něj se nedá zjistit, kde který řádek leží, tedy ani
        // nakreslit čísla a pozadí.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let textView = DiffTextView(frame: NSRect.zero, textContainer: container)
        textView.isEditable = false
        // Read-only, ale **vybíratelné** — o tohle celé #157 je.
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        // Zalamování místo vodorovného scrollu, jako dosud v diffu. Zalomení není znak, takže se do
        // vybraného textu nedostane.
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        // **Výběr má být modrý i tehdy, když je fokus jinde.** AppKit u neaktivního textu kreslí
        // šedou (`unemphasizedSelectedTextBackgroundColor`), což u diffu znamená, že vybraný kód
        // zešedne, jak myš odjede — a vypadá to, že výběr zmizel. Vyžádané při zkoušení #157.
        textView.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]
        return textView
    }

    func updateNSView(_ textView: DiffTextView, context: Context) {
        textView.gutterWidth = DiffLineView.contentInset(for: .unified)
        // Podpis obsahu, ne rovnou text: `setAttributedString` ruší výběr, a tahle metoda chodí
        // i při pouhém přejezdu myší (mění se, u kterého řádku svítí pilulka). Viz `show(…)`.
        textView.show(
            block,
            language: language,
            palette: SyntaxPalette.forScheme(colorScheme),
            signature: "\(block.hashValue)|\(language?.name ?? "")|\(colorScheme)"
        )
        // Pruhy rozsahu se překreslují **jen když se změnily** — jinak by každý pohyb myši
        // překresloval celý blok.
        if textView.commentRangeLines != commentRangeLines || textView.draggedLines != draggedLines {
            textView.commentRangeLines = commentRangeLines
            textView.draggedLines = draggedLines
            textView.needsDisplay = true
        }

        // Rámečky se hlásí **po** layoutu (jinak vyjdou nulové) a **jen když se změnily** — viz
        // `Coordinator`.
        let frames = textView.lineFrames().map {
            DiffBlockLineFrame(index: $0.index, line: $0.line, rect: $0.rect)
        }
        guard frames != context.coordinator.frames else { return }
        context.coordinator.frames = frames
        DispatchQueue.main.async { noteFrames(frames) }
    }

    /// Výška bloku — SwiftUI ji z `NSTextView` sám nezjistí, protože ten si ji uvnitř `LazyVStack`
    /// nenavrhne. Počítá se z layout manageru nad **navrženou šířkou**, takže po zúžení okna
    /// vyjde vyšší.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DiffTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0, let layout = nsView.layoutManager, let container = nsView.textContainer else { return nil }

        container.size = NSSize(
            width: width - nsView.textContainerInset.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        layout.ensureLayout(for: container)
        let height = layout.usedRect(for: container).height + nsView.textContainerInset.height * 2
        return CGSize(width: width, height: height)
    }
}

/// Kde v bloku leží jeden řádek. Z toho se staví overlay s pilulkou na komentář a hlásí se
/// rámečky do `DiffRowFrames` pro tažení rozsahu.
struct DiffBlockLineFrame: Identifiable, Equatable {
    let index: Int
    /// Řádek na téhle pozici. Čte ho **pohled pod sebou**, kde je řádek jeden; ve split pohledu si
    /// ho `DiffPairBlockRowView` bere z bloku podle strany, protože tam jsou dva.
    let line: DiffLine
    let rect: CGRect

    var id: Int { index }
}
