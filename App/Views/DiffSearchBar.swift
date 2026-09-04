import SwiftUI

/// Pruh hledání pod lištou diffu (`.findbar`, #152, návrh sekce 39).
///
/// **Druhá řádka chromu, ne pole v liště a ne překryv nad kódem.** Lišta se u #219 schválně srazila
/// na tři věci a v užším okně se nevešla ani tak; pole s počtem, šipkami a rozsahem je širší než
/// všechny tři dohromady. Překryv by zakryl pravý horní kout, a ten drží ukotvená hlavička souboru —
/// tedy to, podle čeho se pozná, kde v PR člověk je. Pruh proto existuje **jen otevřený** a lišta
/// nad ním zůstává, jaká byla.
///
/// Co v něm je: pole, počet výskytů, kapsle rozsahu, šipky (`⌘G` / `⌘⇧G`), kapsle `Aa` a vpravo
/// věta o rozsahu se zavíracím `✕`.
///
/// **`⎋` zavírá odsud, ne z katalogu zkratek**, a je to tentýž vzorec jako `⌘⏎` v composeru tabu
/// `Zeptat se` (#452): tlačítko existuje jedině s otevřeným pruhem, takže se s ničím nesrazí —
/// a zkratka **okna**, která tu klávesu jinak má (`⎋` zavírá diff commitu), se zakáže
/// (`Policy.canCloseCommit`). Nad otevřenou paletou ⌘K vyhraje ta, protože se registruje později;
/// je to správné pořadí — paleta leží nad oknem.
struct DiffSearchBar: View {
    let search: DiffSearchState
    let actions: DiffSearchActions
    /// Skok na výskyt. Kotvu si skládá diff (zná pohled i rozbalený kontext), tudy jde jen směr.
    let step: (NavigationStep) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink3)
            field
            report
            Spacer(minLength: 9)
            scopeSummary
            close
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Palette.chrome)
        // **Ne `Divider()`** — ten si orientaci bere z okolní osy a v `overlay` žádná není, takže
        // by se vykreslil svisle. Tatáž past jako u lišty diffu a hlaviček souborů.
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hledání v diffu")
    }

    // MARK: - Pole

    private var field: some View {
        TextField("Hledat v diffu", text: query)
            .textFieldStyle(.plain)
            .font(.system(size: 11.5, design: .monospaced))
            .frame(minWidth: 160, idealWidth: 220, maxWidth: 260)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Palette.surface, in: .rect(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line) }
            .focused($isFocused)
            // Fokus se hlásí do okna (#507): mezerník patří tomu, kdo do pole píše.
            .reportsTextFieldFocus(isFocused)
            // `↵` = další výskyt, `⇧↵` = předchozí. Na **poli**, ne jako zkratka okna: fokus je
            // v něm, takže by ho okno nedostalo. Jeden handler na obojí, protože
            // `onKeyPress(_:modifiers:)` bere `modifiers` jako množinu, ve které stisk **smí**
            // ležet, ne jako množinu, která musí sednout přesně (nález z #413).
            //
            // **Klávesa s `⌘`, `⌃` nebo `⌥` se propustí dál** (nález z revize #152): `onKeyPress`
            // dostane `↵` **se všemi modifikátory**, takže bezpodmínečné `.handled` by spolklo
            // i `⌘↵` a `⌃↵` — a ty v tomhle okně otevírají **potvrzení odeslání review** (#151).
            // Rozhoduje `Policy.searchStepKey`, tedy tatáž třída jako `claimsReturnShortcut`.
            .onKeyPress(keys: [.return]) { press in
                guard let direction = Policy.searchStepKey(modifiers: ShortcutModifiers(press.modifiers))
                else { return .ignored }
                step(direction)
                return .handled
            }
            // Fokus **o průchod později** (#184): přiřazení ve stejném průchodu, ve kterém pole
            // vzniká, SwiftUI zahodí — změřeno accessibilitou u palety ⌘K (`onAppear`, `task` bez
            // yieldu i `defaultFocus` daly `AXFocused = false` navždycky). Rozhoduje **počet
            // průchodů, ne čas**, takže tady není žádná pauza a nic, co by si plánovalo další kolo
            // (#350).
            //
            // Věší se to na **počítadlo žádostí**, ne na vznik view: druhé ⌘F nad otevřeným pruhem
            // má fokus vrátit do pole, a to je změna hodnoty, ne nový view.
            .task(id: search.focusRequests) {
                await Task.yield()
                isFocused = true
            }
            .accessibilityLabel("Hledaný text")
    }

    /// Pole čte a zapisuje **přes store** (`DiffSearchActions`), ne do objektu přímo: se zápisem se
    /// musí přeskládat výskyty, a to umí jedině ten, kdo drží diff a rozbalený kontext.
    private var query: Binding<String> {
        Binding(get: { search.query }, set: { actions.setQuery($0) })
    }

    // MARK: - Počet, rozsah a šipky

    @ViewBuilder private var report: some View {
        switch search.report {
        case .idle:
            // Než se něco napíše, nemá pruh co tvrdit — kapsle rozsahu ani počet by neměly
            // o čem mluvit. Zbývá jen `Aa`, aby se dalo přepnout ještě před psaním.
            caseToggle
        case .hits(let position, let total):
            counter(position: position, total: total)
            scopePill
            divider
            arrows(hasHits: true)
            hitKey
            hitShortcuts
            caseToggle
        case .empty:
            // **Prázdný stav neříká „nic nenalezeno“**: to by tvrdilo něco o celém souboru,
            // a přitom se mimo hunky nehledalo (`Policy.searchEmptyNote`). Pole se u toho
            // **neobarvuje** — nic se nepokazilo, vstup je v pořádku.
            Text(verbatim: Policy.searchEmptyNote)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.stale)
                .lineLimit(1)
                .fixedSize()
                .help(Policy.searchScopeHelp)
            divider
            arrows(hasHits: false)
            caseToggle
        }
    }

    /// `4 z 17 výskytů` — pozice tučně, jak to má návrh.
    ///
    /// **`monospacedDigit` je podmínka, ne ozdoba**: bez něj se při přeskoku z `9 z 17` na
    /// `10 z 17` změní šířka čísla a šipky se uhnou zpod myši zrovna ve chvíli, kdy se na ně
    /// kliká. Tentýž požadavek jako u procházení nálezů.
    private func counter(position: Int?, total: Int) -> some View {
        let counter = Policy.searchCounter(position: position, total: total)
        return (Text(verbatim: counter.position).fontWeight(.semibold)
            + Text(verbatim: counter.rest))
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.ink)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }

    /// Rozsah jako kapsle **u počtu**, ne věta v liště: je to údaj k tomu číslu. Celá věta je
    /// v nápovědě a v prázdném stavu, kde na ní záleží.
    private var scopePill: some View {
        Text(verbatim: Policy.searchScopeNote)
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.ink2)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Palette.raised, in: .capsule)
            .help(Policy.searchScopeHelp)
            .accessibilityLabel("Rozsah hledání")
            .accessibilityValue(Policy.searchScopeHelp)
    }

    /// Zkrácená věta o rozsahu vpravo. **Odchází první, když se okno zúží** — kapsle `jen v diffu`
    /// zůstává, protože bez ní by počet tvrdil víc, než ví.
    private var scopeSummary: some View {
        Text(verbatim: search.report == .idle ? Policy.searchScopeSummary : summaryText)
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.ink3)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(Policy.searchScopeHelp)
    }

    private var summaryText: String {
        search.report == .empty ? Policy.searchEmptyHint : Policy.searchScopeSummary
    }

    private var divider: some View {
        Rectangle().fill(Palette.line).frame(width: 1, height: 15)
    }

    /// Šipky **zhasnou, nezmizí**: tlačítko, které se ztratí, vypadá jako porucha a ruší rozvržení
    /// pruhu pod rukama. Tentýž vzorec jako u procházení nálezů.
    private func arrows(hasHits: Bool) -> some View {
        HStack(spacing: 1) {
            arrow(.backward, symbol: "chevron.up", enabled: hasHits)
            arrow(.forward, symbol: "chevron.down", enabled: hasHits)
        }
    }

    private func arrow(_ direction: NavigationStep, symbol: String, enabled: Bool) -> some View {
        Button { step(direction) } label: {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(enabled ? Palette.accent : Palette.ink3.opacity(0.35))
                .frame(width: 21, height: 20)
                .background(enabled ? Palette.accentWeak : .clear, in: .rect(cornerRadius: 5))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(direction == .forward
            ? Policy.shortcutHelp("Další výskyt", .nextSearchHit)
            : Policy.shortcutHelp("Předchozí výskyt", .previousSearchHit))
        .accessibilityLabel(direction == .forward ? "Další výskyt" : "Předchozí výskyt")
    }

    /// Kapsle klávesy u šipek, jak ji má zákres. **Popiska se odvozuje z katalogu** (#441), nikdy
    /// se nepíše vedle klávesy jako literál — jinak se změna klávesy s kresbou potichu rozejde.
    /// Kreslí se jen ta dopředná; `⌘⇧G` se člověk domyslí a dvě kapsle vedle sebe by z pruhu
    /// udělaly nápovědu.
    private var hitKey: some View {
        Text(verbatim: Policy.windowShortcut(.nextSearchHit).display)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Palette.ink3)
            .padding(.horizontal, 5)
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line) }
            .accessibilityHidden(true)
    }

    /// `⌘G` a `⌘⇧G` **registruje pruh**, ne diff: existují jedině tehdy, když je kam skákat.
    /// Schovaná tlačítka, protože zkratka musí platit i s fokusem v poli.
    private var hitShortcuts: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .hiddenShortcuts {
                WindowShortcutButtons(action: .nextSearchHit) { step(.forward) }
                WindowShortcutButtons(action: .previousSearchHit) { step(.backward) }
            }
    }

    /// Rozlišování velikosti je kapsle **uvnitř pruhu**, jako `jen blokující` u procházení nálezů:
    /// platí jen pro tohle hledání a nikde jinde v okně nic nepřepíná.
    private var caseToggle: some View {
        Button { actions.setCaseSensitive(!search.isCaseSensitive) } label: {
            Text(verbatim: "Aa")
                .font(.system(size: 10.5, design: .monospaced))
                .fontWeight(search.isCaseSensitive ? .semibold : .regular)
                .foregroundStyle(search.isCaseSensitive ? Palette.accent : Palette.ink2)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(
                    search.isCaseSensitive ? AnyShapeStyle(Palette.accentWeak) : AnyShapeStyle(Palette.raised),
                    in: .capsule
                )
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(search.isCaseSensitive ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel("Rozlišovat velikost písmen")
        .help("Rozlišovat velká a malá písmena")
    }

    /// `✕` a `⎋`. Zavření pruh **zavře, nevyprázdní pole** — druhé ⌘F pokračuje tam, kde první
    /// skončilo; zvýraznění zhasne tím, že je pruh zavřený.
    private var close: some View {
        Button(action: actions.close) {
            HStack(spacing: 5) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                Text(verbatim: "esc")
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 5)
                    .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line) }
            }
            .foregroundStyle(Palette.ink2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help("Zavřít hledání (esc)")
        .accessibilityLabel("Zavřít hledání")
    }
}
