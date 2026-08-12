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

    /// Skládá se v `DiffTextView.wrappingBlock()`, ne tady: kdo drží šířku kontejneru, ten musí
    /// držet i to, na jaké šířce se měří výška (#236) — a to je textové view.
    func makeNSView(context: Context) -> DiffTextView {
        DiffTextView.wrappingBlock()
    }

    func updateNSView(_ textView: DiffTextView, context: Context) {
        textView.gutterWidth = DiffLineView.contentInset(for: .unified)
        // Podpis obsahu, ne rovnou text: `setAttributedString` ruší výběr, a tahle metoda chodí
        // i při pouhém přejezdu myší (mění se, u kterého řádku svítí pilulka). Viz `show(…)`.
        textView.show(
            block,
            language: language,
            palette: SyntaxPalette.forScheme(colorScheme),
            signature: DiffBlockSignature.of(
                blockHash: block.hashValue,
                language: language,
                colorScheme: colorScheme
            ),
            // Word-level rozdíl (#153) se počítá **až uvnitř** — `show` se z něj hned vrátí, když
            // se obsah nezměnil, a tahle metoda chodí i při pouhém přejezdu myší. Do podpisu
            // přidávat nic netřeba: zvýraznění je funkce obsahu bloku, a ten v podpisu už je.
            words: { WordDiff.spans(in: block.lines) }
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
    ///
    /// **Počítá si ji view samo** (#236). Dokud se šířka kontejneru skládala tady, dala se složit
    /// jinak než při kreslení — a taky se lišila o šířku gutteru, takže blok kreslil víc řádků, než
    /// na kolik si řekl, a přetékal do bubliny nálezu pod sebou.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DiffTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0, let height = nsView.height(forWidth: width) else { return nil }
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
