import SwiftUI

/// Sekce `Větev` v pravém panelu (#465) — **pod labely a reviewery**, jak to kreslí návrh
/// (sekce 36).
///
/// Nese **stav** (kam se to slévá, jestli je větev srovnaná a o kolik je pozadu, jak dopadly
/// checky) a k němu **obě akce, které z toho stavu plynou** — `Mergnout…` (#465) a `Srovnat
/// s main` (#466). Obě jsou vidět vždycky; mění se jen to, která z nich je hlavní.
///
/// **Nekreslí se na cizím PR** — rozhoduje o tom `Policy.branchSection`, které vrátí `nil`.
/// Mergnout cizí frontu se odsud nedělá nikdy, takže tam není ani nadpis, natož zašedlé tlačítko;
/// zašedlé s důvodem patří jedině tam, kde se stav **mění** (červený check, větev pozadu, vypnutá
/// brána). Tatáž hranice jako u labelů (#392).
struct PanelBranchView: View {
    let section: Policy.BranchSection
    /// Šířka, kterou má panel na obsah — **spočítaná, ne vyjednaná** (pravidlo #220).
    let contentWidth: Double
    /// Co se právě děje se srovnáním větve (#466). `nil` = nic se nedělo.
    var syncState: BranchSyncState?
    var actions = BranchActions()

    /// Odsazení bloku bere **z toho typu, který kreslí sekci nad ním**: dvě konstanty by
    /// znamenaly dvě pravdy o jedné šířce a rozešly by se při prvním doladění.
    private static var insetHorizontal: Double { PanelMetadataView.insetHorizontal }
    private static let insetVertical = 11.0
    /// `gap` mezi řádky stavu, výstrahou a řadou akcí — `.pl-sec` z návrhu má `gap: 6px`,
    /// tlačítka pod ním `margin-top: 2px`.
    private static let contentSpacing = 8.0
    private static let rowSpacing = 6.0
    private static let actionSpacing = 6.0

    var body: some View {
        PanelSection(caption: "Větev") {
            VStack(alignment: .leading, spacing: Self.contentSpacing) {
                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                    // Řádky jsou z `Policy` a je jich pevný počet, takže `id: \.offset` nekopíruje
                    // payload ani nesplácne dva stejné texty do jednoho (pravidlo #361).
                    ForEach(Array(section.facts.enumerated()), id: \.offset) { fact in
                        row(fact.element)
                    }
                }
                if !warnings.isEmpty { warning }
                actionRow
                if let syncState { syncNotice(syncState) }
            }
        }
        .padding(.horizontal, Self.insetHorizontal)
        .padding(.vertical, Self.insetVertical)
        .frame(width: contentWidth + 2 * Self.insetHorizontal, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
    }

    /// Řádek stavu: popis vlevo, odpověď vpravo.
    ///
    /// Když se panel zúží, ustoupí **popis** (ořeže se) a odpověď zůstává celá — tatáž úmluva
    /// jako u reviewera, a ze stejného důvodu: kvůli odpovědi se na sekci kouká. Drží to
    /// `fixedSize` na odpovědi.
    private func row(_ fact: Policy.BranchFact) -> some View {
        HStack(spacing: 7) {
            Text(verbatim: fact.text)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(fact.text)
            Spacer(minLength: 4)
            Text(verbatim: fact.answer)
                .font(.system(size: 11))
                .foregroundStyle(color(of: fact.tone))
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fact.text) — \(fact.answer)")
    }

    /// **Barva ze škály se bere z palety, nikdy ze systému** (#432) — `ok` a `crit` jsou tady
    /// text na tlumeném pozadí panelu, ne výplň ovládacího prvku.
    private func color(of tone: Policy.BranchFact.Tone) -> Color {
        switch tone {
        case .neutral: Palette.ink3
        case .done: Palette.ok
        case .blocked: Palette.crit
        }
    }

    /// Proč to nejde — **v panelu, ne jen v nápovědě pod kurzorem**.
    ///
    /// Zašedlé tlačítko bez věty je otázka, na kterou okno neodpovídá (tatáž úvaha jako u vypnuté
    /// brány, #392). Sazba je `.warnbox` z návrhu, tedy tatáž jako u věty o zastaralých nálezech.
    private var warning: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // **Ikona je jen vizuální**, takže se z accessibility stromu schová: bez toho ji čtečka
            // přečte jako jméno symbolu (`exclamationmark.triangle`) před větou, která to samé
            // říká slovy. Nález Copilota na #465.
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.stale)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                // Důvodů může být víc a **každý vede jinam**, takže se nesčítají do jedné věty:
                // „červený check“ se opraví pushem, „větev je pozadu“ srovnáním, vypnutá brána
                // v nastavení. Sjednocené je to už v `Policy`, tady se jen sází.
                //
                // **Věty jsou ze dvou výčtů**, protože akce jsou dvě — a co z nich do výstrahy
                // patří, rozhoduje `Policy`, ne view (`syncWarnings`): většina překážek srovnání
                // je v panelu napsaná už jinde, takže vypsat je všechny by znamenalo totéž
                // dvakrát. Řetězce jsou proto pole, ne dva `ForEach`e nad různými typy.
                ForEach(Array(warnings.enumerated()), id: \.offset) { warning in
                    Text(verbatim: warning.element)
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // `Spacer`, ne `frame(maxWidth: .infinity)` na textu — pružný rámec v zanořeném stromě
            // stojí ~5,5× na úroveň (#220) a tady stačí jedna mezera, která se roztáhne.
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Palette.stale.opacity(0.11), in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.stale.opacity(0.4))
        }
    }

    /// Řada akcí. **Obě tlačítka jsou vidět vždycky** (návrh, sekce 36) — mění se jen to, které
    /// z nich je hlavní: srovnat větev dává smysl i tehdy, když už mergnout jde, a schovávat akci
    /// podle stavu by znamenalo, že se tlačítko pod rukou stěhuje.
    private var actionRow: some View {
        HStack(spacing: Self.actionSpacing) {
            mergeButton
            syncButton
            Spacer(minLength: 0)
        }
    }

    /// `Mergnout…` — **tři tečky proto, že otevírá potvrzení**, ne proto, že to trvá.
    ///
    /// Zakázané tlačítko se kreslí dál, jen se do něj nedá kliknout: „tady se to dělá, jen teď ne“
    /// je u červeného checku i u vypnuté brány pravda, a chybějící tlačítko by vypadalo jako
    /// rozbitá aplikace. Důvod stojí v panelu nad ním; nápověda pod kurzorem ho **opakuje**, aby
    /// se dal přečíst i tam, kde je zrovna kurzor.
    private var mergeButton: some View {
        Button(Self.mergeTitle, action: actions.merge)
            .buttonStyle(isPrimary(.merge) ? .miniPrimary : .mini)
            .disabled(!section.merge.isAllowed)
            // `.disabled` u vlastního `ButtonStyle`u sám nic neztlumí — návrh má `opacity: 0.45`.
            .opacity(section.merge.isAllowed ? 1 : 0.45)
            .help(section.merge.isAllowed ? Self.mergeHelp : obstacleHelp)
    }

    /// `Srovnat s main` — **bez tří teček**, protože nic neotevírá: přehraje commity v kopii repa
    /// a přetlačí větev `--force-with-lease`. Co přesně se stane, stojí v nápovědě pod kurzorem
    /// (`Policy.branchSyncHelp`) — je to jediná cesta, kterou aplikace zapisuje do remote, takže
    /// „co se stane“ má být k přečtení **dřív**, než se to stane.
    ///
    /// Popisek nese **jméno základu**, ne slovo „základ“: cíl je vidět na tlačítku, ne až v textu
    /// vedle. Odkud se to jméno bere, rozhoduje `Policy.syncBase(of:)`, ne view.
    private var syncButton: some View {
        Button(syncTitle, action: actions.sync)
            .buttonStyle(isPrimary(.sync) ? .miniPrimary : .mini)
            .disabled(!section.sync.isAllowed)
            .opacity(section.sync.isAllowed ? 1 : 0.45)
            .help(syncHelp)
    }

    /// Hlavní je ta akce, která z návrhu plyne — a **jen když se do ní dá kliknout**: zvýrazněné
    /// tlačítko, které je zašedlé, by na sebe táhlo oči kvůli něčemu, co teď stejně nejde.
    private func isPrimary(_ action: Policy.BranchAction) -> Bool {
        guard section.primary == action else { return false }
        return action == .merge ? section.merge.isAllowed : section.sync.isAllowed
    }

    private var syncTitle: String { "Srovnat s \(Policy.syncBase(of: section))" }

    private var syncHelp: String {
        guard section.sync.isAllowed, let plan = section.syncPlan else {
            return section.sync.obstacles.map(\.sentence).joined(separator: " ")
        }
        return Policy.branchSyncHelp(for: plan)
    }

    /// Jak dopadlo srovnání větve — **věta v panelu, ne jen v logu**. Drží se, dokud ji člověk
    /// nezavře: hláška, která zmizí sama, je hláška, kterou nikdo nepřečte.
    ///
    /// **Rozdělaný rebase má vlastní tlačítko.** Je to stav, ne chyba — v kopii repa leží
    /// rozdělaná práce a musí jít zahodit odsud, jinak se příští akce nad tím PR zachová divně.
    @ViewBuilder private func syncNotice(_ state: BranchSyncState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: Self.noticeIcon(state))
                .foregroundStyle(Self.noticeTint(state))
                .accessibilityHidden(true)
            Text(verbatim: state.sentence)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if state.hasUnfinishedRebase {
                Button("Zahodit rebase", action: actions.discardRebase)
                    .buttonStyle(.mini)
                    .fixedSize()
            } else if !state.isBusy {
                Button("Zavřít", action: actions.clearSync)
                    .buttonStyle(.mini)
                    .fixedSize()
            }
        }
        // **Velikost vypsaná, ne `.caption`.** Celá sekce sází explicitními body (12 popis, 11
        // odpověď) a `.caption` je proti tomu systémová hodnota, která se s nimi rozejde při první
        // změně nastavení textu. Dvanáct je tatáž hodnota jako ve výstraze — je to tatáž třída
        // věty o stavu.
        .font(.system(size: Self.noticeFontSize))
    }

    private static let noticeFontSize = 12.0

    /// **Ikona ze stavu, ne z barvy** — a `checkmark` jedině u toho, co doopravdy doběhlo.
    private static func noticeIcon(_ state: BranchSyncState) -> String {
        switch state {
        case .rebasing, .pushing, .discarding: "arrow.triangle.2.circlepath"
        case .pushed, .alreadyInSync: "checkmark.circle"
        case .conflicted, .unfinished, .failed: "exclamationmark.triangle"
        }
    }

    /// **Barva ze škály se bere z palety, nikdy ze systému** (#432).
    private static func noticeTint(_ state: BranchSyncState) -> Color {
        switch state {
        case .rebasing, .pushing, .discarding: Palette.ink3
        case .pushed, .alreadyInSync: Palette.ok
        case .unfinished: Palette.stale
        case .conflicted, .failed: Palette.crit
        }
    }

    private static let mergeTitle = "Mergnout…"
    private static let mergeHelp = "Otevře potvrzení. Odešle se až z něj."

    private var obstacles: [Policy.MergeObstacle] { section.merge.obstacles }

    /// Věty do výstrahy — **z obou akcí**. Co z překážek srovnání si vlastní větu žádá, rozhoduje
    /// `Policy.syncWarnings`; ostatní jsou v panelu napsané jinde.
    private var warnings: [String] {
        obstacles.map(\.sentence) + Policy.syncWarnings(section.sync).map(\.sentence)
    }

    /// Nápověda pod kurzorem u zakázaného tlačítka — **tytéž věty jako v panelu**, na jednom
    /// řádku. Druhý text by znamenal dvě různá vysvětlení jednoho zašednutí.
    private var obstacleHelp: String {
        obstacles.map(\.sentence).joined(separator: " ")
    }
}
