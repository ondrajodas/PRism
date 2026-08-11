import SwiftUI

/// Jeden řádek command palette (#184) — `.pal-row` z návrhu.
///
/// Nerozhoduje nic: co je vidět a v jakém pořadí, spočítala `Policy.paletteResults`, a co je ten
/// řádek za věc, nese `CommandPalette.Mark`. Tady se jen sází symbol, barva a text.
struct CommandPaletteRowView: View {
    let hit: CommandPalette.Hit
    /// Řádek pod kurzorem — ten, na který zabere `↵`.
    let isSelected: Bool
    let run: () -> Void

    var body: some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: markFontSize))
                    .foregroundStyle(markColor)
                    .frame(width: 15)
                title
                    .font(.system(size: 12.5))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.ink2)
                    .lineLimit(1)
                    .truncationMode(titleTruncation)
                if let subtitle = hit.item.subtitle {
                    Text(verbatim: subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1)
                        // **Podtitulek se o místo hlásí první**, i když je za titulkem. Je krátký
                        // a strukturovaný (`prism-review-sandbox#4 · Cart.php:26`), takže zkrácení
                        // z něj udělá nesmysl — kdežto věta v titulku se zkrátit dá a pořád se
                        // přečte. Naměřeno na skutečném okně: bez priority z něj vycházelo
                        // `…m-review-sandbox#4` a `…-queue#725`.
                        .layoutPriority(1)
                }
                Spacer(minLength: 8)
                if let shortcut = hit.item.shortcut {
                    keyCap(shortcut)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .filling()
            .background(isSelected ? Palette.accentWeak : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// Titulek se zvýrazněnou shodou, jak ho má návrh (`src/Vault/<b>Secret</b>Client.php`).
    ///
    /// Skládá se ze tří `Text`ů, ne z `AttributedString`u: rozsah přišel jako `Range<String.Index>`
    /// nad tímhle řetězcem, takže rozdělení je přesné a nepřevádí se mezi dvěma indexovými světy.
    private var title: Text {
        let text = hit.item.title
        guard let range = hit.highlight else { return Text(verbatim: text) }
        return Text(verbatim: String(text[text.startIndex..<range.lowerBound]))
            + Text(verbatim: String(text[range])).bold()
            + Text(verbatim: String(text[range.upperBound...]))
    }

    /// Popiska klávesy (`.kbd`) — obtažený rámeček, ne plná plocha: je to informace, ne tlačítko.
    private func keyCap(_ shortcut: String) -> some View {
        Text(verbatim: shortcut)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Palette.ink3)
            .padding(.horizontal, 5)
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line, lineWidth: 1) }
    }

    /// Cesta k souboru se zkracuje **vpředu** (jméno souboru je to, čím se řádek pozná, `src/…`
    /// mají všechny stejné), věta v titulku **vzadu** — jako každá jiná próza.
    private var titleTruncation: Text.TruncationMode {
        switch hit.item.mark {
        case .file: .head
        default: .tail
        }
    }

    private var symbol: String {
        switch hit.item.mark {
        case .blockingFinding, .finding: "circle.fill"
        case .pullRequest: PullRequestStateAppearance.symbol
        case .file: "doc.text"
        case .action(let symbol): symbol
        }
    }

    /// Puntík nálezu je menší než ikony — v návrhu je to `●` v textu, ne symbol.
    private var markFontSize: Double {
        switch hit.item.mark {
        case .blockingFinding, .finding: 7
        default: 12
        }
    }

    private var markColor: Color {
        switch hit.item.mark {
        // Tatáž dvojice jako u bublin a odznaků: červená blokuje, `find` „něco našel“.
        case .blockingFinding: Palette.crit
        case .finding: Palette.find
        case .pullRequest(let state): PullRequestStateAppearance.color(of: state)
        case .file, .action: Palette.ink3
        }
    }

    /// VoiceOver čte řádek jako jednu věc — bez podtitulku by z `SecretClient.php` nebylo
    /// poznat, ke kterému pull requestu patří.
    private var accessibilityLabel: String {
        [hit.item.title, hit.item.subtitle].compactMap { $0 }.joined(separator: ", ")
    }
}
