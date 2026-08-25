import SwiftUI

/// Rozbalovací řádek mezi hunky: šipky vlevo v místě čísel řádků, za nimi kolik je
/// skrytých řádků.
///
/// Šipka ukazuje směr, kterým se vidět toho bude víc: `⌄` dolů od hunku nad mezerou,
/// `⌃` nahoru od hunku pod ní. Stejně jako na GitHubu.
struct DiffExpanderView: View {
    let expander: DiffExpander
    let isLoading: Bool
    let failure: String?
    let reveal: (ClosedRange<Int>) -> Void

    /// O kolik řádků se posune jedno kliknutí.
    private static let step = 20

    var body: some View {
        HStack(spacing: 8) {
            controls
                // Stejná šířka jako obě čísla řádků dohromady, ať šipky sedí do sloupce
                // a řádek nepodskakuje.
                .frame(width: 104, alignment: .leading)
            label
            Spacer()
            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(Palette.find)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.trailing, 16)
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25))
    }

    @ViewBuilder private var controls: some View {
        if isLoading {
            ProgressView().controlSize(.small).padding(.leading, 16)
        } else if let whole = expander.whole, whole.count <= Self.step {
            // Kratší úsek než krok — směr nemá co rozlišovat, rozbalí se celý.
            HStack(spacing: 2) {
                arrow("chevron.up.chevron.down", range: whole, help: "zobrazit zbytek úseku")
            }
            .padding(.leading, 16)
        } else {
            HStack(spacing: 2) {
                arrow("chevron.down", range: expander.stepDown(Self.step), help: "o \(Self.step) řádků dolů")
                if let up = expander.stepUp(Self.step) {
                    arrow("chevron.up", range: up, help: "o \(Self.step) řádků nahoru")
                }
            }
            .padding(.leading, 16)
        }
    }

    private func arrow(_ symbol: String, range: ClosedRange<Int>, help: String) -> some View {
        Button {
            reveal(range)
        } label: {
            Image(systemName: symbol)
                .font(.caption2)
                .frame(width: 22, height: 16)
                .background(.quaternary, in: .rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Počet je zároveň zkratka na celý úsek — bez ní by se pět set řádků rozbalovalo
    /// po dvaceti.
    @ViewBuilder private var label: some View {
        if let whole = expander.whole, whole.count > Self.step {
            Button { reveal(whole) } label: {
                Text(verbatim: text).font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("zobrazit celý úsek")
        } else {
            Text(verbatim: text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var text: String {
        guard let hidden = expander.hiddenCount else { return "další řádky" }
        return Plural.czech(hidden, one: "skrytý řádek", few: "skryté řádky", many: "skrytých řádků")
    }
}
