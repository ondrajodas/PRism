import SwiftUI

/// Kus kódu, ke kterému se vlákno váže (#158) — pás uvnitř bubliny na ose konverzace.
///
/// Je to **snímek z minulosti** (`diffHunk` z GitHubu), ne dnešní kód. Kreslí ho `DiffLineView`,
/// tedy tentýž řádek jako v diffu: druhý renderer úryvku by se s diffem rozešel a barvy by na
/// dvou místech okna znamenaly něco jiného.
///
/// Jen na ose (`ThreadBubbleView.Placement.timeline`), ne u kódu: vlákno **s kotvou** visí pod
/// svým řádkem, kde je ten kód nad ním vidět, takže úryvek by ho kreslil dvakrát.
struct ThreadSnippetView: View {
    let snippet: ThreadSnippet
    /// Cesta souboru — z ní se pozná jazyk na obarvení. Bere se z vlákna, protože hunk sám
    /// o sobě neříká, čeho je.
    let path: String

    var body: some View {
        // Jazyk **jednou na úryvek**, ne u každého řádku — `DiffView` ho ze stejného důvodu
        // počítá jednou na soubor. `nil` u souboru, kterému nerozumíme: obarvit ho podle cizích
        // pravidel je horší než neobarvit vůbec.
        let language = Language(path: path)

        VStack(alignment: .leading, spacing: 0) {
            if snippet.isTruncated { truncationMark }
            // Klíčem je pořadí, ne řádek: dva prázdné řádky za sebou jsou si jako `DiffLine`
            // rovné a `ForEach` by z nich udělal jeden.
            // **Barví se jen komentovaný řádek** (#216), ostatní jsou kontext. Úryvek na ose
            // má ukázat *místo*, ne diff — s celým zeleným blokem se čte jako změna, o které
            // vlákno není. Komentovaný je ten poslední: `Policy.snippet` končí právě jím.
            ForEach(Array(snippet.lines.enumerated()), id: \.offset) { index, line in
                DiffLineView(
                    line: index == snippet.lines.count - 1 ? line : line.asContext,
                    language: language
                )
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        // **Pás přes celou kartu, ne zaoblený blok uvnitř ní** (#216). Úryvek je od #216 jeden
        // z pruhů bubliny (hlavička / kód / komentář), oddělený linkou jako ostatní — vlastní
        // rámeček by uvnitř rámečku dělal druhou kartu. Plocha je `surface`, tedy o patro níž
        // než `chrome` karty: kód se tím odliší od prózy kolem.
        .background(Palette.surface)
        // **Vybírat se nedá**, i když `Přehled` má selekci jinak zapnutou: `DiffLineView` nese
        // gesto tažení pro rozsahy komentářů, takže by tažení přes kód selekci spolklo a
        // vypadalo by to jako rozbité okno. Kopírování z diffu řeší #157 — na jednom místě pro
        // obojí, ne polovičatě tady.
        .textSelection(.disabled)
    }

    /// Že úryvek není celý hunk. Značka, ne počet: přesné číslo zahozených řádků nedává důvod
    /// nic udělat, kdežto „tady to začíná dřív“ ano.
    ///
    /// Nápověda **netvrdí, že je hunk delší** — `isTruncated` je i tehdy, když z něj parser něco
    /// nepoznal, a to není totéž. Platí v obou případech: vidět není všechno.
    private var truncationMark: some View {
        Text(verbatim: "⋯ zkráceno")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .help("Z hunku není vidět všechno — ukazuje se jeho konec po komentovaný řádek. Celý je na GitHubu.")
    }
}
