import SwiftUI

/// Seznam položek zadání v sheetu (#377) — zaškrtávátko u **každé**, seskupené po druzích.
///
/// Bydlí v sheetu, ne v panelu: panel má 240–520 bodů a čtyřicet položek s autorem a místem se do
/// něj nevejde, kdežto sheet je široký 840–1080. V panelu proto zůstávají volby po druzích jako
/// hrubý filtr (#333) a **tady se zapíná a vypíná položka**.
///
/// Kreslí jen to, co rozhodla `Policy`: co je vybrané (`AgentPromptPick.isIncluded`), proč ne
/// (`exclusion`) a co je rozbalené (`Policy.pickDisclosure(of:toggled:)`). Žádné `if` nad nálezy
/// tady není a být nemá — jinak by se seznam rozešel s textem pod ním.
struct AgentPromptPickList: View {
    let groups: [AgentPromptGroup]
    /// Které položky jsou rozbalené. Odchylka od výchozího stavu, o zbytku rozhoduje `Policy`.
    var expanded: Set<String> = []
    /// Zapnout a vypnout položku.
    var toggle: (AgentPromptPick) -> Void = { _ in }
    /// Rozbalit a sbalit text položky.
    var toggleExpansion: (AgentPromptPick) -> Void = { _ in }

    var body: some View {
        // Ne líný seznam: položek jsou desítky, ne tisíce, a rozbalený text si žádá výšku podle
        // obsahu — v `LazyVStack`u by to byla přesně ta pružná výška, kterou zakazuje #375.
        VStack(spacing: 0) {
            ForEach(groups) { group in
                if group.id != groups.first?.id { separator }
                header(group)
                ForEach(group.picks) { pick in
                    separator
                    row(pick)
                    if case .expanded = Policy.pickDisclosure(of: pick, toggled: expanded) {
                        separator
                        PickBodyView(pick: pick)
                    }
                }
            }
        }
        .background(Palette.chrome)
        .clipShape(.rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line) }
    }

    /// Linka mezi řádky (`border-bottom: 1px solid var(--line-soft)` z návrhu). Kreslí se **nad**
    /// každým prvkem kromě prvního, což je totéž rozdělení s jedním pravidlem místo dvou.
    private var separator: some View {
        Rectangle().fill(Palette.lineSoft).frame(height: 1)
    }

    // MARK: - Hlavička grupy

    /// `NÁLEZY … 2 Z 3` (`.pickgroup`) — druh a **kolik z něj je vybrané**.
    ///
    /// Verzálky má i počet, protože `text-transform: uppercase` v návrhu leží na celé hlavičce.
    /// Je to sazba, ne text: `2 Z 3` se čte jako součást hlavičky, kdežto `2 z 3` v ní vypadá jako
    /// vsuvka z jiného písma.
    private func header(_ group: AgentPromptGroup) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: group.kind.title.uppercased())
            Spacer(minLength: 8)
            Text(verbatim: group.countLabel.uppercased())
                .monospacedDigit()
        }
        .font(.system(size: 10.5, design: .monospaced))
        .tracking(0.63)
        .foregroundStyle(Palette.ink3)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised)
    }

    // MARK: - Řádek položky

    private func row(_ pick: AgentPromptPick) -> some View {
        let disclosure = Policy.pickDisclosure(of: pick, toggled: expanded)
        return HStack(alignment: .top, spacing: 9) {
            checkbox(pick)
            switch disclosure {
            // **Rozbalit není co, takže tam není ani tlačítko a šipka** (schválení s prázdným
            // tělem): kliknutí, po kterém se nic nestane, je k nerozeznání od rozbité aplikace.
            case .none:
                label(pick, arrow: nil)
            case .collapsed, .expanded:
                Button { toggleExpansion(pick) } label: {
                    label(pick, arrow: disclosure == .expanded ? "⌃" : "⌄")
                }
                .buttonStyle(.plain)
                .help(disclosure == .expanded ? "Sbalit text položky" : "Ukázat celý text položky")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        // `.pick.open` z návrhu — 5 % akcentu pod rozbaleným řádkem, ať je vidět, ke které
        // položce ten text pod ním patří.
        .background(disclosure == .expanded ? Palette.accent.opacity(0.05) : .clear)
    }

    /// Text řádku: titulek s místem, autor, důvod vypnutí a šipka.
    ///
    /// **Autor drží šířku, titulek se krátí** (`flex: none` u `.who` a `.why` z návrhu): podle
    /// autora se pozná, co je signál, kdežto celý text položky je v rozkliku. `Spacer` je jen
    /// u řádku s důvodem (`margin-left: auto` u `.why`) — bez něj se řádek nesnaží plnit šířku
    /// a šipka zůstane u autora, přesně jak to kreslí návrh.
    private func label(_ pick: AgentPromptPick, arrow: String?) -> some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: pick.title)
                    .font(.system(size: 12))
                    .foregroundStyle(pick.isIncluded ? Palette.ink : Palette.ink3)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let place = pick.place {
                    Text(verbatim: place)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Text(verbatim: pick.author)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Palette.ink2)
                .fixedSize()
            if let why = pick.exclusion?.label {
                Spacer(minLength: 10)
                Text(verbatim: why)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.ink3)
                    .fixedSize()
            }
            if let arrow {
                Text(verbatim: arrow)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.ink3)
                    .fixedSize()
                    .padding(.leading, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// Čtvereček z návrhu (`.pick .box`): 14 bodů, poloměr 4, zapnutý plnou akcentovou barvou
    /// s fajfkou v barvě plochy. **Vlastní tlačítko**, ne celý řádek: řádek rozbaluje, tohle
    /// vybírá, a jedno kliknutí nemůže znamenat obojí.
    private func checkbox(_ pick: AgentPromptPick) -> some View {
        Button { toggle(pick) } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(pick.isIncluded ? Palette.accent : Palette.chrome)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(pick.isIncluded ? Palette.accent : Palette.line)
                }
                .overlay {
                    if pick.isIncluded {
                        Text(verbatim: "✓")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Palette.surface)
                    }
                }
                .frame(width: 14, height: 14)
                .padding(.top, 1)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(Self.checkboxHelp(pick))
        .accessibilityLabel(pick.title)
        .accessibilityAddTraits(pick.isIncluded ? .isSelected : [])
    }

    /// Nápověda u zaškrtávátka — u vypnuté položky **s důvodem**, protože bez něj je předvybrání
    /// aplikace k nerozeznání od chyby.
    ///
    /// Všechny tři věty mluví o **položce**, tedy v ženském rodě: `ho` z první verze se nevázalo
    /// na nic, co je v okně napsané (nález, vlákno, komentář a souhrn mají tři různé rody), a v UI
    /// textu to čte jako chyba. Nálezem Copilota na #380.
    nonisolated static func checkboxHelp(_ pick: AgentPromptPick) -> String {
        guard !pick.isIncluded else { return "V textu je — kliknutím ji odškrtneš" }
        guard let exclusion = pick.exclusion else { return "Odškrtnul jsi ji — kliknutím ji vrátíš" }
        return "Vypnuto (\(exclusion.label)) — kliknutím ji přibereš"
    }
}

/// Rozbalený text položky (`.pickbody`) — **celý**, s hlavičkou `druh · autor · čas · velikost`.
///
/// Vlastní view kvůli měření výšky: `max-height: 168` z návrhu znamená „vysoký jako obsah, nejvýš
/// 168 bodů“, kdežto `ScrollView` je ve svém směru hltavý — bez měření by jednořádkový komentář
/// zabral stejných 168 bodů jako čtyřkilobajtové release notes. Krátit se text **nesmí** (zkrácený
/// rozklik je druhý náhled téhož problému), takže se dlouhý roluje.
///
/// Měří se `onGeometryChange`, které se při nezměněné hodnotě **nezapisuje** (změřeno u #361),
/// takže kolo z #358 tohle neotevírá: výška obsahu závisí na šířce, kterou dává rozvržení nad
/// tím, ne na výšce, která se z měření vypočítá.
private struct PickBodyView: View {
    let pick: AgentPromptPick

    @State private var height: CGFloat?

    /// Strop z návrhu. Nad ním se roluje.
    private static let maxHeight: CGFloat = 168

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: pick.meta)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                Text(verbatim: pick.text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink2)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        // Dokud se obsah nezměřil, drží se strop: krabice, která se otevře prázdná a pak naroste,
        // vypadá jako blikající chyba, kdežto naopak se jen zkrátí na svou výšku.
        .frame(height: min(height ?? Self.maxHeight, Self.maxHeight))
        .padding(.leading, 35)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
    }
}
