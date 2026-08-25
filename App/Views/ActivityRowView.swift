import SwiftUI

/// Jeden řádek dění (#414).
///
/// **Bez pružné výšky** (#220, #375): puntík má rám 24 × 24 a obsah si výšku navrhuje sám. Klikatelný
/// je celý řádek — cíl je v něm napsaný, takže by tlačítko jen na šipce znamenalo cíl, na který se
/// nedá kliknout.
///
/// **Jedna podoba pro sekci i pro dashboard** (#443). Vyčleněné ze `ActivityFeedView` proto, že
/// blok na dashboardu kreslí **týž** řádek: dvě podoby jedné události by se rozešly stejně, jako by
/// se rozešly dvě podoby řádku fronty. Liší se jediná věc, a je to `showsDay` — viz níž.
struct ActivityRowView: View {
    let event: ActivityEvent
    /// Hodiny obrazovky, ne `Date()` — viz `ActivityFeedView.now`.
    let now: Date
    /// Nese si řádek **den** u času? (#443)
    ///
    /// V sekci ne: den nese hlavička bloku (`Dnes`, `Včera`, `čtvrtek 20. srpna`). Na dashboardu je
    /// blok jeden a bez dělení po dnech, takže by `v 07:58` u včerejší události tvrdilo, že to bylo
    /// dneska ráno. Rozhodnutí, co z toho plyne za text, je v `Policy.activityTime` — tady se jen
    /// říká, jestli den někdo nese za řádek.
    var showsDay = false
    let open: (ActivityEvent) -> Void
    /// Odkaz ven otevírá **view**, ne store — jako v paletě ⌘K. Store se o prohlížeči nemá co
    /// dozvědět a jediný řádek, který ho potřebuje, je ten, který v okně nemá kam vést.
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: activate) { face }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help(help)
            .accessibilityLabel(accessibilityLabel)
    }

    private func activate() {
        guard case .gitHub = Policy.destination(of: event.kind) else {
            open(event)
            return
        }
        guard let url = Policy.gitHubURL(of: event.pullRequest) else { return }
        openURL(url)
    }

    private var face: some View {
        HStack(alignment: .top, spacing: 8) {
            dot
            line
        }
    }

    private var dot: some View {
        Image(systemName: Policy.symbol(of: event.kind))
            .font(.system(size: 11))
            .foregroundStyle(tone)
            .frame(width: 24, height: 24)
            .background(Palette.chrome, in: .circle)
            .overlay { Circle().strokeBorder(tone, lineWidth: 1) }
    }

    /// Obsah řádku. **Zalomí se, když se nevejde** (`.tl-line` má `flex-wrap: wrap`), takže se
    /// dlouhý titulek PR nezkrátí na nic — ale cíl vpravo se od něj musí umět odtrhnout, jinak by
    /// se šipka zalomila doprostřed textu.
    private var line: some View {
        HStack(alignment: .center, spacing: 7) {
            FlowRow(spacing: 7, lineSpacing: 4) {
                Text(verbatim: event.headline)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isDimmed ? Palette.ink2 : Palette.ink)
                if let detail = event.detail {
                    Text(verbatim: "· \(detail)")
                        .font(.system(size: 12))
                        .foregroundStyle(isDimmed ? Palette.ink3 : Palette.ink2)
                        .lineLimit(1)
                }
                if let head = event.head {
                    ShaChip(sha: head)
                }
                if Policy.showsSilentChip(event.kind, announced: event.wasAnnounced) {
                    SilentChip()
                }
                // PR a autor jedním prvkem: `.tl-line` má mezeru 7 bodů, takže by tečku mezi nimi
                // odsadila od obojího a vypadala by jako oddělovač celého řádku.
                Text(verbatim: [event.pullRequest.description, event.author]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                time
            }
            Spacer(minLength: 8)
            destination
        }
        .frame(minHeight: 24, alignment: .center)
    }

    /// Čas u řádku. Relativní stáří skládá **view**, protože se v okně přepočítává samo; hotový
    /// text hodin (i se dnem, když si ho řádek nese) skládá `Policy.activityTime`.
    @ViewBuilder private var time: some View {
        Group {
            switch Policy.activityTime(of: event.at, now: now, carriesDay: showsDay) {
            case .relative: Text(event.at, format: .relative(presentation: .named))
            case .absolute(let label): Text(verbatim: label)
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Palette.ink3)
    }

    /// Kam řádek vede. **Napsané, ne šipka bez obsahu** — a řádek, který vede jen ven, to přiznává
    /// i barvou (návrh, poznámka 92).
    private var destination: some View {
        Text(verbatim: destinationLabel)
            .font(.system(size: 11.5))
            .foregroundStyle(isDimmed ? Palette.ink3 : Palette.accent)
            .lineLimit(1)
    }

    private var destinationLabel: String {
        switch Policy.destination(of: event.kind) {
        case .tab(let tab): "→ \(tab.czechLabel)"
        case .gitHub: "GitHub ↗"
        }
    }

    /// Řádek, který do okna nevede, je celý ztlumený: PR z fronty odešel, takže se v seznamu
    /// nedohledá a fialový cíl by slíbil něco, co se nestane.
    private var isDimmed: Bool {
        Policy.destination(of: event.kind) == .gitHub
    }

    private var tone: Color {
        switch Policy.tone(of: event.kind) {
        case .neutral: Palette.line
        case .ok: Palette.ok
        case .critical: Palette.crit
        case .stale: Palette.stale
        case .accent: Palette.accent
        }
    }

    private var help: String {
        switch Policy.destination(of: event.kind) {
        case .tab(let tab): "Otevře \(event.pullRequest) a v něm záložku \(tab.czechLabel)"
        case .gitHub: "Otevře \(event.pullRequest) v prohlížeči — z fronty už odešel"
        }
    }

    /// Pro čtečku obrazovky celá věta: řádek se skládá z kusů, které samostatně neříkají nic.
    private var accessibilityLabel: String {
        [
            event.headline,
            event.detail,
            event.head,
            event.pullRequest.description,
            event.author,
            destinationLabel
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

/// Osa dění (#414) — svislá čára a na ní puntíky řádků.
///
/// Čára je **na pozadí**, ne prvek v každém řádku: `.tl::before` z návrhu jde přes celý blok
/// a prvek na řádek by znamenal jeden prvek navíc na položku (#252 — co se dá spočítat, se
/// nevyjednává).
///
/// **Sdílená sekcí i dashboardem** (#443): odsazení drží čáru **pod** puntíkem, ne vedle, takže dvě
/// kopie by se rozešly zrovna v tom jediném, na čem osa stojí. Co se do ní pokládá, se ale liší —
/// sekce mezi řádky vkládá pruh `Tady jsem skončil`, dashboard nic.
struct ActivityTimeline<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) { content }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .background(alignment: .topLeading) { rail }
    }

    /// `left: 30px` z návrhu je střed puntíku (18 odsazení + 12 poloviny dvacetičtyřky), takže se
    /// čára kreslí pod ním, ne vedle.
    private var rail: some View {
        Rectangle()
            .fill(Palette.line)
            .frame(width: 2)
            .padding(.vertical, 8)
            .padding(.leading, 29)
    }
}

/// Pilulka se sha (`.tl-line .sha`) — hlava, na které PR stojí teď.
private struct ShaChip: View {
    let sha: String

    var body: some View {
        // Zkrácená na sedm znaků jako všude jinde v okně; plná je v tooltipu, ať se dá porovnat.
        Text(verbatim: String(sha.prefix(7)))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, 5)
            .background(Palette.raised, in: .rect(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.lineSoft, lineWidth: 1) }
            .help(sha)
    }
}

/// Chip `bez banneru` (`.tl-line .botchip`).
///
/// **Půlka hodnoty téhle obrazovky.** Záznam se plní i tehdy, když je aplikace mlčící — a tenhle
/// chip je to, co dělá z „nepřišlo mi to“ odpověď, ne domněnku.
private struct SilentChip: View {
    var body: some View {
        Text("bez banneru")
            .font(.system(size: 10))
            .foregroundStyle(Palette.ink3)
            .padding(.horizontal, 5)
            .background(Palette.raised, in: .rect(cornerRadius: 20))
            .help("O téhle události nedorazila notifikace — v záznamu je stejně.")
    }
}
