import SwiftUI

/// Lišta nad diffem (`.difftools`, #219).
///
/// Rostla po kusech — pohled vedle sebe (#98), procházení nálezů (#187), strom (#197), šířka
/// (#188) — a nikdy se neposadila podle návrhu jako celek. Bylo z toho sedm prvků, ve kterých
/// se přepínač pohledu ztrácel mezi dvěma checkboxy, a v užším okně se lišta nevešla.
///
/// Zbyly v ní tři věci: **pohled** vlevo, **procházení nálezů** hned vedle (jediná věc, která se
/// používá při každém review) a vpravo `Rozbalit vše` s nabídkou pro volby, které se nastaví
/// a nechají být.
///
/// **Souhrn `1 soubor · +4 −2` v ní není** (do #219 stál vlevo): počet souborů je v hlavičce
/// stromu vedle a rozsah změny v řadě záložek nad ním, takže lišta o něj přišla, aniž by ten
/// údaj z okna zmizel.
///
/// **Přepínače sloupců v ní taky nejsou**, i když je návrh kreslí (`◧ Strom ⌘1`, `◨ Moje review ⌘2`).
/// Strom i panel mají složení **u sebe** — tlačítko v hlavičce sloupce a proužek, kterým se zase
/// otevřou — takže tady by to byly třetí dveře k témuž a v úzkém okně by se o místo praly
/// s procházením. Zkratky zůstávají (`⌘1` v `DiffView`, `⌘2` v detailu PR) a jsou napsané
/// v nápovědě u těch tlačítek, tedy tam, kde se na sloupec sahá.
struct DiffToolbar: View {
    let diff: Diff
    @Binding var layout: DiffLayout
    let navigation: FindingNavigation
    @Binding var onlyBlocking: Bool
    let stepFinding: ((NavigationStep) -> Void)?
    /// Kreslit bubliny nálezů u řádků. V nabídce, ne v liště: do #219 to byl checkbox `Nálezy`
    /// vedle přepínače panelu, který se jmenuje **taky** `Nálezy` — dvě různé věci pod jedním
    /// slovem v jedné liště.
    @Binding var showBubbles: Bool
    let hasFindings: Bool
    let folding: DiffFoldingActions
    /// Sbalení rozbaleného kontextu zpátky na samotný diff. `nil` = není co sbalit.
    let collapseExpansion: (() -> Void)?
    let missingThreads: Int
    /// Šířka, kterou má diff k dispozici. Z ní se počítá, kolik znaků se vejde na stranu (#188).
    let contentWidth: Double
    /// Hledání v diffu (#152). Popisek `Hledat ⌘F` je jediné, co v liště přibylo — pole samotné
    /// je v pruhu pod ní. `nil` = v tomhle diffu se nehledá, takže se nekreslí ani popisek.
    var openSearch: (() -> Void)?
    /// Je pruh hledání otevřený? Popisek pak svítí akcentem, aby bylo poznat, odkud se pruh vzal.
    var isSearching = false
    /// Popsat změny sedmou session (#524). `nil` = **nekreslí se nic** — session není zapojená,
    /// nebo se neví, nad kterou hlavou by běžela. Zašedlé by slibovalo akci, která se zapíná
    /// jinde; je to tatáž úvaha jako u `Otevřít v editoru` (#530).
    var annotation: DiffAnnotationActions?

    var body: some View {
        HStack(spacing: 9) {
            DiffLayoutPicker(selection: $layout)
            // Procházení stojí **hned vedle pohledu**, tedy vlevo: je to jediná věc v liště,
            // která se používá při každém review, kdežto zbytek se nastaví a nechá být.
            if let stepFinding, !navigation.isEmpty {
                FindingNavigationView(
                    navigation: navigation,
                    onlyBlocking: $onlyBlocking,
                    step: stepFinding
                )
            }
            Spacer(minLength: 9)
            warnings
            annotateButton
            searchButton
            foldMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Palette.chrome)
        // **Ne `Divider()`.** Ten si orientaci bere z okolní osy a v `overlay` žádná není,
        // takže se vykreslí svisle — tatáž past jako u hlaviček souborů a záložek PR.
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
    }

    // MARK: - Hledání

    /// `⌕ Hledat ⌘F` (#152) — **popisek s kapslí klávesy, ne pole**: pole je v pruhu pod lištou,
    /// protože se počtem, šipkami a rozsahem je širší než všechny tři věci v liště dohromady
    /// (a lišta se u #219 schválně srazila právě proto, že se v užším okně nevešla).
    ///
    /// Existuje, aby se hledání dalo najít **myší**. Zkratku kreslí `Policy`, ne literál vedle
    /// klávesy (#441).
    @ViewBuilder private var searchButton: some View {
        if let openSearch, !diff.files.isEmpty {
            Button(action: openSearch) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                    Text(verbatim: "Hledat")
                        .font(.system(size: 11.5))
                    Text(verbatim: Policy.windowShortcut(.findInDiff).display)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.ink3)
                        .padding(.horizontal, 5)
                        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line) }
                }
                .foregroundStyle(isSearching ? Palette.accent : Palette.ink2)
                .lineLimit(1)
                .fixedSize()
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(Policy.shortcutHelp("Hledat v diffu", .findInDiff))
            .accessibilityLabel("Hledat v diffu")
        }
    }

    // MARK: - Popis změn

    /// `Popsat změny` (#524) — **v liště, ne v nabídce pod šipkou**.
    ///
    /// Do prvního proklikání to byla položka v nabídce `Sbalit vše ▾` s odůvodněním, že se na
    /// jednom PR pustí jednou a nemá se prát o místo. Vyžádané při zkoušení a je to správně ze
    /// dvou důvodů: akce, kterou nikdo nevidí, se **nepoužije** (nabídka se jmenuje `Sbalit vše`,
    /// takže pod ní akci nikdo nehledá), a nabídka navíc ten klik **spolkne** — zavře se dřív,
    /// než se cokoli změní, takže z ní žádný stav vidět nebyl.
    ///
    /// **Tři stavy, ne dva**, a to je ta oprava: v klidu spouští, za běhu **ruší** a po selhání
    /// zkouší znovu — tedy po každém kliknutí se na tomtéž místě něco změní. Do které z těch tří
    /// větví se patří, rozhoduje `Policy`, ne tenhle soubor.
    ///
    /// **Popisek `Popisuji…` a `Popis selhal` je kratší než `Popsat změny`**, takže se lišta
    /// spuštěním nerozšíří — ať se v úzkém okně nezačne pod rukou lámat něco jiného.
    ///
    /// **A v úzkém okně ustoupí tenhle prvek, ne ty, které tu byly dřív** — proto jako jediný
    /// v liště **nemá `fixedSize()`** a má **zápornou prioritu rozvržení**. Změřeno: lišta v plné
    /// výbavě (procházení nálezů, varování o šířce, hledání, sbalení) si v podlahovém okně říká
    /// o **819 bodů** a má **572**, takže **přetéká už dneska, i bez popisu změn** — je to známá
    /// vlastnost z #219, ne něco, co přineslo #524. Bez té priority by ale zmizelo `Sbalit vše`,
    /// tedy věc, která tu byla; s ní se srazí **popisek téhle akce** až na samotnou ikonu, která
    /// nese `help` a zůstává klikatelná. Čísla a kresba jsou v `docs/testovani.md`, sekce
    /// *Kolik místa v liště stojí `Popsat změny`*.
    @ViewBuilder private var annotateButton: some View {
        if let annotation, !diff.files.isEmpty {
            Button(action: annotation.state == .running ? annotation.cancel : annotation.start) {
                // **`ViewThatFits`, ne useknutý popisek**: `Popsat…` je horší než samotná ikona —
                // nese půl slova a vypadá jako porucha. Buď se vejde celý popisek, nebo zbude
                // ikona, která má `help` a kliká se stejně.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        annotateIcon(annotation.state)
                        Text(verbatim: Self.annotateLabel(annotation.state))
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    annotateIcon(annotation.state)
                }
                .foregroundStyle(annotateTint(annotation.state))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .layoutPriority(-1)
            .help(Self.annotateHelp(annotation.state))
            .accessibilityLabel(Self.annotateLabel(annotation.state))
        }
    }

    /// Ikona stavu. Za běhu **týž prstýnek jako všude jinde v okně** (`SpinningRing`, #350, #442),
    /// ne systémový `ProgressView`: nekonečná animace ve SwiftUI si vyžádá průchod při každém
    /// obtažení obrazovky, a druhá kresba téhož by k tomu znamenala, že se „pracuje se“ čte
    /// v jednom okně dvěma tvary.
    @ViewBuilder private func annotateIcon(_ state: Policy.AnnotationControl) -> some View {
        switch state {
        case .idle:
            Image(systemName: "text.alignleft").font(.system(size: 11))
        case .running:
            SpinningRing(size: 11, lineWidth: 1.6)
        case .failed:
            Image(systemName: "exclamationmark.triangle").font(.system(size: 11))
        }
    }

    private func annotateTint(_ state: Policy.AnnotationControl) -> Color {
        switch state {
        case .idle: Palette.ink2
        case .running: Palette.accent
        // Okrová, ne systémová červená: popis změn není nález a jeho selhání nic neblokuje —
        // tatáž kategorie jako zbytek varování v téhle liště.
        case .failed: Palette.stale
        }
    }

    private static func annotateLabel(_ state: Policy.AnnotationControl) -> String {
        switch state {
        case .idle: "Popsat změny"
        case .running: "Popisuji…"
        case .failed: "Popis selhal"
        }
    }

    /// Nápověda nese **celou větu o tom, co se stalo**. Krátký popisek v liště říká jen stav;
    /// důvod se musí dát přečíst, a druhé místo, kde stojí celý, je dráha `anotace` v tabu
    /// `Průběh` — proto na ni tahle věta ukazuje.
    private static func annotateHelp(_ state: Policy.AnnotationControl) -> String {
        switch state {
        case .idle:
            "Popsat změny — jedna session napíše ke každému hunku větu proč a k souboru druh změny."
        case .running:
            "Popis změn běží. Kliknutím ho zrušíš; průběh je v tabu Průběh."
        case .failed(let detail):
            "\(detail) Kliknutím to zkusíš znovu; totéž stojí v tabu Průběh."
        }
    }

    // MARK: - Sbalení a co zbylo

    /// Jedno tlačítko, ne dvě. Který ze dvou stavů dává smysl, plyne z toho, co je zrovna
    /// na obrazovce — dvě tlačítka by znamenala, že je jedno z nich pořád k ničemu.
    ///
    /// Nabídka pod šipkou drží volby, které se nastaví a nechají být: bubliny nálezů pod řádky
    /// a sbalení rozbaleného kontextu. V liště zabíraly místo, o které se v užším okně soutěží
    /// s věcmi, které se používají při každém review.
    ///
    /// **Když by nabídka byla prázdná, kreslí se obyčejné tlačítko.** Obě položky jsou
    /// podmíněné (nálezy musí existovat, kontext musí být rozbalený), takže na PR, na kterém
    /// review neběželo a nikdo nic nerozbalil — tedy na tom, co člověk vidí jako první — by
    /// šipka otevírala prázdné okénko. Šipku si `Menu` kreslí samo, zakázat ji nejde.
    @ViewBuilder private var foldMenu: some View {
        if !diff.files.isEmpty {
            let allFolded = diff.files.allSatisfy(folding.isFolded)
            if hasFindings || collapseExpansion != nil {
                Menu {
                    if hasFindings {
                        // Jmenuje se `Nálezy pod řádky`, ne `Bubliny`: schovává **jen** nálezy,
                        // kdežto „bubliny“ jsou od #64 i vlákna konverzace. A ne holé `Nálezy` —
                        // tak se jmenuje přepínač panelu o kus vedle. **Nápověda tu není**:
                        // položky menu na macOS tooltip neukazují, takže by to byl mrtvý text.
                        //
                        // **`pod` místo `u`** (#503): od té doby je to volba **místa**, ne
                        // viditelnosti — vypnuté nálezy nezmizí, stojí v okraji vpravo vedle
                        // svého řádku. `u řádků` by o tom lhalo, protože v okraji jsou u řádků
                        // taky.
                        Toggle("Nálezy pod řádky", isOn: $showBubbles)
                    }
                    if let collapseExpansion {
                        Button("Zobrazit jen diff", systemImage: "arrow.down.right.and.arrow.up.left") {
                            collapseExpansion()
                        }
                    }
                } label: {
                    foldLabel(allFolded)
                } primaryAction: {
                    toggleFold(allFolded)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(foldHelp(allFolded))
            } else {
                Button { toggleFold(allFolded) } label: {
                    foldLabel(allFolded).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(foldHelp(allFolded))
            }
        }
    }

    /// **Bez vlastní šipky**, i když ji návrh u popisku kreslí: `Menu` s primární akcí si vedle
    /// popisku vykreslí svoji a dvě šipky proti sobě (`⌃ Sbalit vše ⌄`) vypadaly jako porucha.
    /// Stav nese popisek, který se mění.
    private func foldLabel(_ allFolded: Bool) -> some View {
        Text(verbatim: allFolded ? "Rozbalit vše" : "Sbalit vše")
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.ink2)
            .lineLimit(1)
    }

    private func foldHelp(_ allFolded: Bool) -> String {
        allFolded ? "Rozbalit diffy všech souborů" : "Sbalit diffy všech souborů"
    }

    private func toggleFold(_ allFolded: Bool) {
        if allFolded { folding.unfoldAll() } else { folding.foldAll(diff.files) }
    }

    // MARK: - Varování

    /// Tři věci, které se hlásí jen tehdy, když nesedí. Stojí vpravo za mezerou, jak je má
    /// návrh — ne vlevo mezi akcemi.
    @ViewBuilder private var warnings: some View {
        if diff.unrecognizedLines > 0 {
            warning(
                "\(Plural.czech(diff.unrecognizedLines, one: "řádek", few: "řádky", many: "řádků")) "
                    + "diffu se nepodařilo přečíst"
            )
        }
        if missingThreads > 0 {
            // Sloveso je **v tvarech**: „2 vlákna se nevešlo“ je špatně česky.
            let count = Plural.czech(
                missingThreads,
                one: "vlákno konverzace se nevešlo",
                few: "vlákna konverzace se nevešla",
                many: "vláken konverzace se nevešlo"
            )
            warning("\(count) — otevři PR na GitHubu")
        }
        widthGauge
    }

    /// Kolik znaků se vejde na stranu (#188).
    ///
    /// Ukazuje se **jen tehdy, když je slib porušený** — nad 120 znaků je to číslo, které nikoho
    /// nezajímá, kdežto pod ním je to jediné vysvětlení, proč se řádky lámou. Měří se skutečné
    /// okno, ne tabulka ze zadání: ta platí pro jeden displej a jedno nastavení.
    @ViewBuilder private var widthGauge: some View {
        let characters = Policy.charactersPerSide(
            contentWidth: contentWidth,
            characterWidth: Self.characterWidth,
            layout: layout,
            // Skutečná šířka sloupců vlevo, ne odhad — kreslí je `DiffLineView`.
            gutter: DiffLineView.contentInset(for: layout)
        )
        if contentWidth > 0, characters < Policy.promisedCharactersPerSide {
            warning("\(characters) znaků na stranu")
                .monospacedDigit()
                .help("Aplikace slibuje \(Policy.promisedCharactersPerSide) znaků. Pomůže složit sloupce nebo přepnout na pohled pod sebou.")
        }
    }

    /// Okrová, ne systémová oranžová (#216): je to upozornění bez naléhavosti, tedy tatáž
    /// kategorie jako zastarání. Vedle červeného blokujícího nálezu by se systémová oranžová
    /// četla jako druhý stupeň téže škály.
    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.stale)
            .lineLimit(1)
    }

    /// Šířka jednoho znaku písma, kterým se sází kód. Mono písmo má všechny znaky stejně široké,
    /// takže stačí změřit jeden — a metriku vydá `FontMetric` (#407), ne vlastní čtení.
    private static let characterWidth = FontMetric.shared.characterWidth(
        of: .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    )
}
