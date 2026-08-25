import SwiftUI

/// Prázdný nebo chybový stav — **jeden vzor pro celé okno** (#176).
///
/// Do #176 jich bylo **deset** a každý vznikl zvlášť — od prázdné fronty a zapnutého filtru přes
/// rate limit a selhané načtení až po prázdná místa v nastavení a v novinkách. Zadání jich
/// jmenovalo šest; zbytek se našel při přesazování. Vypadaly jinak, mluvily jinak a některé
/// neřekly, co s tím dělat.
///
/// **Povaha není kosmetika.** Ikona a její barva rozlišují klid od poruchy dřív, než se čte text
/// — a zelené „všechno vyřízeno“ nad zapnutým filtrem tvrdí opak toho, co je pravda. Proto má
/// filtr vlastní povahu i vlastní východ.
///
/// Rozměry jsou z návrhu (sekce 08) doslova: dlaždice 40 bodů s poloměrem 11, titulek 14,
/// vysvětlení 12,5 na šířku zhruba 34 znaků, mezera 8.
struct EmptyStateView: View {
    /// Co se stalo — určuje barvu a to, jak se stav čte.
    enum Nature {
        /// Nic nechybí, jen není co ukázat. Zelená.
        case calm
        /// Něco se děje nebo je něco zapnuté; čeká se, nebo je co vypnout. Fialová.
        case waiting
        /// Porucha. Červená.
        case failure
    }

    let nature: Nature
    let symbol: String
    let title: String
    let message: String
    /// Syrový text od `gh` nebo `gitu`. **Zůstává, jak přišel** — je to jediné, z čeho se pozná,
    /// co dělat dál, a přeložit ho vlastní větou znamená hádat příčinu.
    var detail: String?
    /// Hlavní akce a případná druhá. Prázdné, když se s tím v okně nedá nic dělat.
    var primary: Action?
    var secondary: Action?

    struct Action {
        let title: String
        let run: () -> Void
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.15), in: .rect(cornerRadius: 11))
                .padding(.bottom, 2)
            Text(verbatim: title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text(verbatim: message)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(verbatim: detail)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Palette.raised, in: .rect(cornerRadius: 6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if primary != nil || secondary != nil {
                HStack(spacing: 7) {
                    if let primary {
                        Button(primary.title, action: primary.run)
                            .buttonStyle(.borderedProminent)
                    }
                    if let secondary {
                        Button(secondary.title, action: secondary.run)
                    }
                }
                .font(.system(size: 11.5))
                .padding(.top, 4)
            }
        }
        // Šířka textu je z návrhu (`max-width: 34ch`): delší řádek se v prázdné ploše čte hůř
        // než dva krátké.
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(22)
    }

    private var color: Color {
        switch nature {
        case .calm: Palette.ok
        case .waiting: Palette.accent
        case .failure: Palette.crit
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        EmptyStateView(
            nature: .calm,
            symbol: "checkmark",
            title: "Žádné PR k review",
            message: "Až po tobě někdo bude chtít review, objeví se tady. Poslední tik v 9:41."
        )
        Divider()
        EmptyStateView(
            nature: .waiting,
            symbol: "line.3.horizontal.decrease",
            title: "Filtr schoval všechno",
            message: "5 pull requestů čeká na review, ale filtr je schovává.",
            primary: .init(title: "Vymazat filtr") {}
        )
        Divider()
        EmptyStateView(
            nature: .failure,
            symbol: "exclamationmark.triangle",
            title: "Seznam PR se nepodařilo načíst",
            message: "Zkusím to znovu při dalším tiku.",
            detail: "gh: failed to connect to api.github.com",
            primary: .init(title: "Zkusit znovu") {},
            secondary: .init(title: "Zdraví služeb") {}
        )
    }
    .frame(width: 520)
}
