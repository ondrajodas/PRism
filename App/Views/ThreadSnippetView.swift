import SwiftUI

/// Kus kódu, ke kterému se vlákno váže (#158) — v `Přehledu` nad bublinou.
///
/// Je to **snímek z minulosti** (`diffHunk` z GitHubu), ne dnešní kód. Kreslí ho `DiffLineView`,
/// tedy tentýž řádek jako v diffu: druhý renderer úryvku by se s diffem rozešel a barvy by na
/// dvou místech okna znamenaly něco jiného.
///
/// Jen v `Přehledu`, ne v bublině: vlákno **s kotvou** visí u kódu, kde je ten kód nad ním
/// vidět, takže úryvek v bublině by ho kreslil dvakrát.
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
            ForEach(Array(snippet.lines.enumerated()), id: \.offset) { _, line in
                DiffLineView(line: line, language: language)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: .rect(cornerRadius: 6))
        // Barevná pozadí přidaných a odebraných řádků jdou přes celou šířku, takže se musí
        // zarovnat s rohy rámečku.
        .clipShape(.rect(cornerRadius: 6))
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
