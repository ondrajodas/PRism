import AppKit
import SwiftUI

/// Lišta nad diffem „co od minule přibylo“ (#284) — **co je pod ní a jak se z toho ven**.
///
/// Rozsahový diff vypadá jako celý diff, jen kratší, takže bez téhle lišty by se nedalo poznat,
/// že chybějící soubory nechybí omylem. Proto stojí nad ním a říká obojí: rozsah dvěma sha
/// a cestu zpátky tlačítkem.
///
/// **Návrh tuhle obrazovku nekreslí** — sekce 02 má tlačítko `Ukázat, co přibylo`, ne stav po
/// jeho stisknutí. Lišta si proto bere tvar hlavičky souboru v diffu (`.fhead`: odsazení 8/14,
/// linka pod sebou, mono 11,5) a barvu akcentu na tichém podkladu, protože je to **zapnutý
/// pohled**, ne zastaralý obsah — okrová `--stale` znamená v tomhle okně „platilo to, dneska už
/// ne“, a to o rozsahu neplatí. Zapsané rozhodnutí, viz specifikace.
struct IncrementalDiffBar: View {
    let range: IncrementalDiffRange
    let showAll: () -> Void

    /// Šířka tabu, ve kterém lišta stojí (#220). `nil` = nikdo ji nepředal, pak se kreslí celá.
    @Environment(\.availableWidth) private var available

    var body: some View {
        row(Self.layout(in: available))
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 8)
            // **Šířka se bere z prostředí, ne od sourozence** (#220). Pod lištou sedí `DiffView`,
            // který se v úzkém tabu roztáhne přes hranu a nechá se ořezat — a kdyby si lišta říkala
            // pružně (`maxWidth: .infinity`), `VStack` by jí tu přetečenou šířku předal.
            .filling()
            .background(Palette.accentWeak)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    /// Co z lišty zbyde, jak se tab zužuje. **Cesta ven přežije všechno** — lišta je jediné místo,
    /// odkud se z rozsahu vrátí na celý diff, takže tlačítko ustupuje poslední.
    enum Layout: CaseIterable {
        /// Jak to má být: ikona, věta, rozsah, tlačítko.
        case full
        /// Bez věty. Zkrácená na `Jen t…` by neřekla nic a zabrala totéž.
        case range
        /// Jen cesta ven; rozsah pak říká nápověda. Pod tuhle šířku se v tabu ořezává i lišta
        /// diffu pod ní, takže užší podoba nemá co zachraňovat.
        case wayOut
    }

    /// **Šířka se počítá, nevyjednává** (#220) — proč zrovna tak, je u `TextWidth`.
    static func layout(in available: CGFloat?) -> Layout {
        guard let available else { return .full }
        let content = available - 2 * horizontalPadding
        if content >= width(of: .full) { return .full }
        if content >= width(of: .range) { return .range }
        return .wayOut
    }

    /// Kolik ta která podoba potřebuje.
    static func width(of layout: Layout) -> CGFloat {
        let button = TextWidth.miniButton(wayOutLabel, emphasis: .secondary)
        switch layout {
        case .wayOut:
            return button
        case .range:
            return iconWidth + gap + shaWidth + gap + button
        case .full:
            return iconWidth + gap + labelWidth + gap + shaWidth + gap + button
        }
    }

    private func row(_ layout: Layout) -> some View {
        HStack(spacing: Self.gap) {
            if layout != .wayOut {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.accent)
                    .frame(width: Self.iconWidth)
            }
            if layout == .full {
                Text(verbatim: Self.label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            if layout != .wayOut {
                Text(verbatim: shas)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
            }
            Button(Self.wayOutLabel, action: showAll)
                .buttonStyle(.mini)
                // V nejužší podobě zbyde jen tohle tlačítko, takže rozsah musí říct nápověda —
                // jinak by se z lišty nedalo poznat, proti čemu se diff porovnává.
                .help("\(Self.label): \(shas)")
        }
    }

    private var shas: String { "\(Self.short(range.seen)) → \(Self.short(range.head))" }

    /// Popisky **nejsou `private`** ze stejného důvodu jako u pruhu: kontroluje je test proti
    /// tomu, co se nakreslí.
    static let label = "Jen to, co přibylo od tvé poslední návštěvy"
    static let wayOutLabel = "Ukázat celý diff"
    private static let horizontalPadding = 14.0
    private static let gap = 9.0
    /// Symbol se nekreslí do textového rámečku, takže se jeho šířka **ustaví**, ne měří — a je to
    /// zároveň to, co drží výpočet a kresbu na jednom čísle.
    private static let iconWidth = 14.0

    private static let labelWidth = TextWidth.of(label, font: .systemFont(ofSize: 11.5))
    /// Sedm znaků, šipka a sedm znaků — u monospace je to konstanta bez ohledu na to, jaké sha to
    /// zrovna jsou, takže stačí změřit jednu dvojici.
    private static let shaWidth = TextWidth.of(
        "0000000 → 0000000",
        font: .monospacedSystemFont(ofSize: 11, weight: .regular)
    )

    /// Sha na sedm znaků, jako `git`, GitHub a zbytek okna.
    private static func short(_ sha: String) -> String { String(sha.prefix(7)) }
}

#Preview {
    VStack(spacing: 0) {
        ForEach([620.0, 380.0, 200.0] as [CGFloat], id: \.self) { width in
            IncrementalDiffBar(
                range: IncrementalDiffRange(seen: "4f2ac9188cd", head: "9c1de0212ab"),
                showAll: {}
            )
            .availableWidth(width)
            .frame(width: width)
        }
    }
    .padding()
}
