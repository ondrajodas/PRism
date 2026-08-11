import SwiftUI

/// Pruh záložek nad obsahem okna (#180).
///
/// Domácí záložka plus otevřená review. Tečka u záložky nese **stav toho review**, takže je
/// z pruhu vidět, co běží a kde leží rozdělaná práce, aniž by se na tu záložku muselo přepnout —
/// a přesně to bylo do #180 neviditelné.
struct ReviewTabsView: View {
    @Binding var active: WindowTab
    let tabs: [PullRequestSummary]
    /// Stav review pro tečku. Bere ho volající, protože ho počítá store.
    let state: (PRIdentifier) -> ReviewState
    /// Leží na PR rozdělané review?
    let hasDraft: (PRIdentifier) -> Bool
    /// Běží na PR zrovna review? Bere se ze **store**, ne ze `state`: `ReviewState.running`
    /// vzniká z fáze běhu, ale u PR, kde se zrovna klonuje, je stav `cloning` — a točit se má
    /// v obou případech, protože obojí je „něco se právě děje“.
    let isRunning: (PRIdentifier) -> Bool
    let close: (PRIdentifier) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                homeTab
                ForEach(tabs, id: \.id) { tab($0) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Domácí záložka **se jménem**, ne jen s ikonou: je to jediná záložka, která neukazuje
    /// pull request, takže by z domečku mezi `repo#číslo` nebylo poznat, co za ní je.
    private var homeTab: some View {
        Button { active = .home } label: {
            HStack(spacing: 8) {
                Image(systemName: "house")
                    .font(.system(size: 11))
                Text("Přehled")
                    .font(.system(size: 12.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .chrome(isActive: active == .home)
        }
        .buttonStyle(.plain)
        // Nese i **zkratky pruhu** (#245), protože `⌃Tab` po sobě v okně nenechává žádnou
        // viditelnou stopu — bez tohohle by se dala najít jedině v release notes. Sedí to na
        // domácí záložce ze dvou důvodů: v pruhu je **vždycky** a jako jediná mluví o pruhu, ne
        // o pull requestu (u těch je v nápovědě titulek, který je tam potřebnější).
        //
        // **Na samotném pruhu to nejde** — `.help` nad `ScrollView`em se nikde neprojeví;
        // změřeno na běžící aplikaci: `AXScrollArea` hlavičky zůstal bez `AXHelp`, kdežto
        // tlačítka záložek svoje nápovědy nesou.
        .help("Fronta a rozdělaná review — mezi záložkami přepíná ⌃Tab a ⌃⇧Tab")
    }


    private func tab(_ summary: PullRequestSummary) -> some View {
        let item = WindowTab.pullRequest(summary.id)
        let isActive = active == item
        return HStack(spacing: 8) {
            dot(for: summary.id)
            // `verbatim`: `repo#číslo` není věta a číslo PR není množství k formátování.
            Text(verbatim: "\(summary.repo.name)#\(summary.number)")
                .font(.system(size: 11.5, design: .monospaced))
                .lineLimit(1)
            Button { close(summary.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.ink3)
            .help("Zavřít záložku — nic se tím nezahodí")
            .accessibilityLabel("Zavřít \(summary.repo.name)#\(summary.number)")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .chrome(isActive: isActive)
        .contentShape(.rect)
        .onTapGesture { active = item }
        .help(summary.title)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary.title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    /// Značka stavu, ve třech patrech podle toho, co se s PR zrovna děje.
    ///
    /// **Běh přebíjí všechno**: je to jediný stav, který se mění sám, a kolečko je jediná věc
    /// v pruhu, ze které je vidět, že aplikace pracuje, aniž by se na tu záložku přepnulo.
    /// Pod ním je **rozdělané review**, protože to je věc, která čeká na mě. Teprve pak barevná
    /// tečka s výsledkem.
    @ViewBuilder private func dot(for id: PRIdentifier) -> some View {
        if isRunning(id) {
            SpinningRing()
                .help("Review běží")
                .accessibilityLabel("Review běží")
        } else if hasDraft(id) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 9))
                .foregroundStyle(.tint)
                .help("Leží tu rozdělané review")
        } else {
            Circle()
                .fill(ReviewStateAppearance.color(of: state(id)))
                .frame(width: 6, height: 6)
                .help(ReviewStateAppearance.label(of: state(id)))
        }
    }

}

private extension View {
    /// Vzhled záložky. **Aktivní má výplň i obrys**, ne jen jinou barvu textu: v titulkové liště
    /// jsou záložky blízko u sebe a bez ohraničení splynou v jednu řádku slov — a nedá se pak
    /// poznat, kde jedna končí. Obrys drží i to, že je aktivní záložka vidět na tmavém i světlém
    /// pozadí lišty, kde samotná výplň skoro zmizí.
    func chrome(isActive: Bool) -> some View {
        background(
            isActive ? AnyShapeStyle(Palette.raised) : AnyShapeStyle(.clear),
            in: .rect(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                // Obrys z palety, ne `.separator`: systémový oddělovač je v tmavé liště tak
                // jemný, že aktivní záložka splyne s pozadím a pruh se čte jako řada slov.
                .strokeBorder(Palette.line, lineWidth: isActive ? 1 : 0)
        }
        .foregroundStyle(isActive ? Palette.ink : Palette.ink2)
    }
}

/// Kroužek s rotujícím obloukem — značka běžícího review v záložce (#180).
///
/// **Ne `ProgressView`.** Systémový spinner na macOS je paprskové kolečko a v pruhu záložek
/// vypadá jako ozubené kolo mezi tečkami stavů; návrh má prstýnek, který se točí. Vedle toho je
/// `ProgressView` řízený AppKitem, takže se nedá zmenšit na velikost tečky, aniž by zhrubl.
///
/// Barva je **systémový akcent**, ne fialová z návrhu: fialová je v mockupu proto, že HTML žádný
/// systémový akcent nemá, kdežto v okně by byla jediná barva, která se neřídí nastavením systému —
/// a ikona rozdělaného review hned vedle ho používá taky.
struct SpinningRing: View {
    var size: CGFloat = 11
    var lineWidth: CGFloat = 2

    @State private var angle = 0.0
    /// Vypnutý pohyb v systému. Prstýnek pak **stojí** — je nedokončený, takže je z něj pořád
    /// poznat, že se něco děje, jen se netočí.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.3)
            .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(angle))
            .background {
                Circle().stroke(.tint.opacity(0.25), lineWidth: lineWidth)
            }
            .frame(width: size, height: size)
            .onAppear {
                // Točit se něčím, co si člověk v systému vypnul, je horší než nehybná značka —
                // a `repeatForever` se sám nezastaví, takže se nesmí spustit vůbec.
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
