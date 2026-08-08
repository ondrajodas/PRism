import SwiftUI

/// Barevný proužek s podílem reviewerů na výsledku (#172).
///
/// Odpovídá na otázku, kterou odznak s počtem nezodpoví: **odkud ty nálezy jsou.** Dva nálezy
/// od jednoho reviewera a dva od dvou různých znamenají něco jiného, a v řádku to jinak není
/// z čeho poznat.
///
/// Kreslí se jen tam, kde je co dělit — u PR, na kterém nic neběželo, by to byl prázdný obdélník
/// tvářící se jako údaj.
struct SpectrumBar: View {
    let shares: [ReviewerShare]
    var width: CGFloat = 74
    var height: CGFloat = 5

    /// Mezera mezi díly. Bez ní by dva sousední díly stejné barvy splynuly v jeden a proužek
    /// by tvrdil, že reviewer byl jeden.
    private let gap: CGFloat = 1

    var body: some View {
        HStack(spacing: gap) {
            ForEach(shares) { share in
                Rectangle()
                    .fill(ReviewStateAppearance.color(of: share.outcome))
                    .frame(width: segmentWidth(of: share))
            }
        }
        .frame(width: width, height: height)
        .clipShape(.capsule)
        // Barva sama nestačí — popis nese totéž, co proužek ukazuje.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Podíl reviewerů")
        .accessibilityValue(description)
        .help(description)
    }

    /// Díl podle váhy, ze šířky zbylé po mezerách. Kdyby se mezery neodečetly, proužek by
    /// s každým dalším reviewerem přerostl svůj rámec.
    private func segmentWidth(of share: ReviewerShare) -> CGFloat {
        let total = shares.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return 0 }
        let usable = width - gap * CGFloat(max(shares.count - 1, 0))
        return usable * CGFloat(share.weight) / CGFloat(total)
    }

    private var description: String {
        shares.map { "\($0.reviewer) — \(text(of: $0))" }.joined(separator: ", ")
    }

    private func text(of share: ReviewerShare) -> String {
        switch share.outcome {
        case .blocking: "blokující nález"
        case .findings: Plural.czech(share.weight, one: "nález", few: "nálezy", many: "nálezů")
        case .clean: "čisté"
        case .dismissed: "všechno odmítnuto"
        case .inconclusive: "nedá se z toho soudit"
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        SpectrumBar(shares: [
            ReviewerShare(reviewer: "php-review", outcome: .blocking, weight: 2),
            ReviewerShare(reviewer: "security-review", outcome: .findings, weight: 1),
            ReviewerShare(reviewer: "docs", outcome: .clean, weight: 1),
        ])
        SpectrumBar(shares: [
            ReviewerShare(reviewer: "code-review", outcome: .clean, weight: 1),
        ])
        SpectrumBar(shares: [
            ReviewerShare(reviewer: "php-review", outcome: .inconclusive, weight: 1),
            ReviewerShare(reviewer: "docs", outcome: .clean, weight: 1),
        ])
    }
    .padding()
}
