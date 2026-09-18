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
    /// Má tenhle diff věty *proč* u hunků (#525)? `false` = přepínač v nabídce **není** — položka,
    /// po které se nic nestane, je tatáž vada jako zašedlé tlačítko.
    var hasAnnotations = false
    /// Kreslit věty u hunků (#525). **V nabídce, ne v liště**, a je to opačné rozhodnutí než
    /// u `Popsat změny` o kus vedle: tohle je volba pohledu, která se nastaví a nechá být, kdežto
    /// ta akce mění stav po každém kliknutí — a nabídka klik spolkne. Podrobněji u
    /// `DiffView.showAnnotations`.
    var showAnnotations: Binding<Bool> = .constant(true)

    var body: some View {
        // **Vlastní `Layout`, ne `HStack`** (#593). Do #593 rozhodovalo o tom, co v tísni
        // ustoupí, to, který prvek zapomněl `fixedSize()` — a lišta v plné výbavě přetéká
        // v podlahovém okně o víc než dvě stě bodů. Kdo v jakém pořadí ustupuje a na co se
        // srazí, je výčet v `Policy`; tenhle soubor kreslí obě podoby a `DiffToolbarLayout`
        // změří a **předá** šířku (#220, #236).
        DiffToolbarLayout {
            layoutPicker
            findingNavigation
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

    // MARK: - Pohled a procházení

    /// Pohled a procházení stojí vlevo: procházení je jediná věc v liště, která se používá při
    /// každém review, kdežto zbytek se nastaví a nechá být.
    ///
    /// **Přepínač ustupuje jako poslední** (`Policy.diffToolbarLadder`), a to na samotné ikony;
    /// popisky segmentů jsou celý důvod, proč to není `Picker(.segmented)` (#219).
    ///
    /// Není `private`, protože se na tomhle prvku **měří** (`DiffToolbarRoomTests`) — a měřit se
    /// musí to, co aplikace doopravdy kreslí (#236).
    @ViewBuilder var layoutPicker: some View {
        ViewThatFits(in: .horizontal) {
            DiffLayoutPicker(selection: $layout, form: .full)
            DiffLayoutPicker(selection: $layout, form: .icon)
        }
        .diffToolbarItem(.layout)
    }

    /// Procházení nálezů (#187) — **jediný prvek lišty, který neustoupí nikdy**
    /// (`Policy.diffToolbarFloor(.navigation) == .full`).
    @ViewBuilder var findingNavigation: some View {
        if let stepFinding, !navigation.isEmpty {
            FindingNavigationView(
                navigation: navigation,
                onlyBlocking: $onlyBlocking,
                step: stepFinding
            )
            .diffToolbarItem(.navigation)
        }
    }

    // MARK: - Hledání

    /// `⌕ Hledat ⌘F` (#152) — **popisek s kapslí klávesy, ne pole**: pole je v pruhu pod lištou,
    /// protože se počtem, šipkami a rozsahem je širší než všechny tři věci v liště dohromady
    /// (a lišta se u #219 schválně srazila právě proto, že se v užším okně nevešla).
    ///
    /// Existuje, aby se hledání dalo najít **myší**. Zkratku kreslí `Policy`, ne literál vedle
    /// klávesy (#441).
    ///
    /// **Sražená podoba je samotná lupa** (#593) — popisek se zkratkou ustupuje jako druhý
    /// v pořadí (`Policy.diffToolbarLadder`), protože hledání má zkratku `⌘F`: popisek je pomůcka
    /// k nalezení myší, ne jediná cesta. Lupa navíc nepotřebuje vysvětlení.
    @ViewBuilder var searchButton: some View {
        if let openSearch, !diff.files.isEmpty {
            Button(action: openSearch) {
                ViewThatFits(in: .horizontal) {
                    searchLabel(withText: true)
                    searchLabel(withText: false)
                }
                .foregroundStyle(isSearching ? Palette.accent : Palette.ink2)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(Policy.shortcutHelp("Hledat v diffu", .findInDiff))
            .accessibilityLabel("Hledat v diffu")
            .diffToolbarItem(.search)
        }
    }

    private func searchLabel(withText: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
            if withText {
                Text(verbatim: "Hledat")
                    .font(.system(size: 11.5))
                Text(verbatim: Policy.windowShortcut(.findInDiff).display)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                    .padding(.horizontal, 5)
                    .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line) }
            }
        }
        .lineLimit(1)
        .fixedSize()
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
    /// **A v úzkém okně ustoupí tenhle prvek první** — od #593 ne zápornou prioritou rozvržení,
    /// ale tím, že stojí v čele `Policy.diffToolbarLadder`: je to nejmladší přírůstek lišty,
    /// na jednom PR se pustí jednou a stav nese i samotná ikona. Sražená podoba je ta ikona
    /// (`Policy.diffToolbarFloor(.annotate) == .icon`), nese `help` a zůstává klikatelná. Čísla
    /// jsou v `docs/testovani.md`, sekce *Kolik si který prvek lišty bere*.
    @ViewBuilder var annotateButton: some View {
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
            .help(Self.annotateHelp(annotation.state))
            .accessibilityLabel(Self.annotateLabel(annotation.state))
            .diffToolbarItem(.annotate)
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
    /// Nabídka pod šipkou drží volby, které se nastaví a nechají být: bubliny nálezů pod řádky,
    /// věty u hunků (#525) a sbalení rozbaleného kontextu. V liště zabíraly místo, o které se
    /// v užším okně soutěží s věcmi, které se používají při každém review.
    ///
    /// **Když by nabídka byla prázdná, kreslí se obyčejné tlačítko.** Všechny položky jsou
    /// podmíněné (nálezy musí existovat, anotace taky, kontext musí být rozbalený), takže na PR,
    /// na kterém review neběželo a nikdo nic nerozbalil — tedy na tom, co člověk vidí jako
    /// první — by šipka otevírala prázdné okénko. Šipku si `Menu` kreslí samo, zakázat ji nejde.
    @ViewBuilder var foldMenu: some View {
        if !diff.files.isEmpty {
            let allFolded = diff.files.allSatisfy(folding.isFolded)
            if hasFindings || hasAnnotations || collapseExpansion != nil {
                // **`ViewThatFits` kolem celé nabídky, ne kolem jejího popisku** (#593), a je to
                // změřená oprava: `Menu` svému popisku šířku **nepředává**, takže `ViewThatFits`
                // uvnitř vybral vždycky tu první podobu (naměřeno `full 51, floor 50`, tedy
                // ustoupení o jediný bod). Dvě nabídky jako dvě podoby změří `ViewThatFits`
                // správně — vzniká z nich vždycky jen jedna.
                ViewThatFits(in: .horizontal) {
                    foldMenuButton(allFolded) { foldLabel(allFolded) }
                    foldMenuButton(allFolded) { foldIcon(allFolded) }
                }
                .diffToolbarItem(.fold)
            } else {
                Button { toggleFold(allFolded) } label: {
                    foldContent(allFolded).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(foldHelp(allFolded))
                .diffToolbarItem(.fold)
            }
        }
    }

    /// Nabídka pod šipkou s daným popiskem. **`fixedSize()` tu být musí** — bez něj si `Menu`
    /// neřekne ani o šipku, kterou si sám kreslí, a popisek se usekne.
    @ViewBuilder private func foldMenuButton(
        _ allFolded: Bool,
        @ViewBuilder label: () -> some View
    ) -> some View {
        Menu {
            if hasAnnotations {
                // Jmenuje se `Anotace u hunků`, ne `Popis změn`: tak se jmenuje **akce**
                // v liště, a jedno slovo pro akci i pro viditelnost jejího výsledku je
                // přesně ta záměna, kterou #219 z téhle lišty vyháněl (`Nálezy` vedle
                // `Nálezů`). `u hunků` říká, **kde** to je — na rozdíl od nálezů se
                // vypnutá anotace nikam nepřestěhuje, zmizí.
                Toggle("Anotace u hunků", isOn: showAnnotations)
            }
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
            label()
        } primaryAction: {
            toggleFold(allFolded)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(foldHelp(allFolded))
    }

    /// Popisek, nebo sražená ikona (#593) — podoba pro **obyčejné tlačítko**, tedy tam, kde
    /// nabídka pod šipkou není. Nabídka se sráží jinak, viz `foldMenu`.
    private func foldContent(_ allFolded: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            foldLabel(allFolded)
            foldIcon(allFolded)
        }
    }

    /// Sražená podoba `Sbalit vše` (#593) — **šipky, ne zkratka popisku**: stav nese směr stejně
    /// dobře jako slovo, kdežto `Sbalit…` by neslo půl slova. Celou větu drží `help`, který na
    /// tlačítku i na nabídce je tak jako tak.
    private func foldIcon(_ allFolded: Bool) -> some View {
        Image(systemName: allFolded
            ? "arrow.down.left.and.arrow.up.right"
            : "arrow.up.right.and.arrow.down.left")
            .font(.system(size: 11))
            .foregroundStyle(Palette.ink2)
            .fixedSize()
    }

    /// **Bez vlastní šipky**, i když ji návrh u popisku kreslí: `Menu` s primární akcí si vedle
    /// popisku vykreslí svoji a dvě šipky proti sobě (`⌃ Sbalit vše ⌄`) vypadaly jako porucha.
    /// Stav nese popisek, který se mění.
    private func foldLabel(_ allFolded: Bool) -> some View {
        Text(verbatim: allFolded ? "Rozbalit vše" : "Sbalit vše")
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.ink2)
            .lineLimit(1)
            .fixedSize()
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
    ///
    /// **Text skládá `Policy`, ne tenhle soubor** (#593): každé varování má vedle celé věty
    /// i sraženou podobu a nápovědu, protože v tísni se zkracuje — a co z lišty ubude, musí být
    /// v nápovědě. Do #593 měla varování `fixedSize()` a v tísni neustupovala vůbec, takže
    /// přetékala za hranu lišty.
    @ViewBuilder var warnings: some View {
        if let unreadable = Policy.unreadableLinesWarning(diff.unrecognizedLines) {
            warning(unreadable).diffToolbarItem(.unreadable)
        }
        if let missing = Policy.missingThreadsWarning(missingThreads) {
            warning(missing).diffToolbarItem(.missingThreads)
        }
        widthGauge
    }

    /// Kolik znaků se vejde na stranu (#188).
    ///
    /// Ukazuje se **jen tehdy, když je slib porušený** — nad 120 znaků je to číslo, které nikoho
    /// nezajímá, kdežto pod ním je to jediné vysvětlení, proč se řádky lámou. Měří se skutečné
    /// okno, ne tabulka ze zadání: ta platí pro jeden displej a jedno nastavení.
    @ViewBuilder var widthGauge: some View {
        let characters = Policy.charactersPerSide(
            contentWidth: contentWidth,
            characterWidth: Self.characterWidth,
            layout: layout,
            // Skutečná šířka sloupců vlevo, ne odhad — kreslí je `DiffLineView`.
            gutter: DiffLineView.contentInset(for: layout)
        )
        if let gauge = Policy.diffWidthWarning(characters: characters, contentWidth: contentWidth) {
            warning(gauge)
                .monospacedDigit()
                .diffToolbarItem(.width)
        }
    }

    /// Okrová, ne systémová oranžová (#216): je to upozornění bez naléhavosti, tedy tatáž
    /// kategorie jako zastarání. Vedle červeného blokujícího nálezu by se systémová oranžová
    /// četla jako druhý stupeň téže škály.
    ///
    /// **Tři podoby, ne dvě** (#593): celá věta, věta sražená na číslo (`Policy.diffToolbarFloor`
    /// u varování vydává `short`) a — až docela nakonec — **samotný trojúhelník**.
    ///
    /// Ta třetí je tu proto, že varování jsou jediné prvky, ze kterých `Policy` v největší tísni
    /// **ubírá** (obě vzácná varování naráz v podlahovém okně; viz `DiffToolbarRoomTests`). Bez
    /// ní by z `3 řádky` zbylo `3…`, tedy půl slova, které vypadá jako porucha — tatáž úvaha jako
    /// u `Popsat změny` (#524). Celou větu drží nápověda ve **všech třech** podobách, takže se
    /// zkrácením nic nezatají.
    private func warning(_ warning: Policy.DiffToolbarWarning) -> some View {
        ViewThatFits(in: .horizontal) {
            warningLabel(warning.full)
            warningLabel(warning.short)
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.stale)
                .fixedSize()
        }
        .help(warning.help)
        .accessibilityLabel(warning.full)
    }

    private func warningLabel(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.stale)
            .lineLimit(1)
            .fixedSize()
    }

    /// Šířka jednoho znaku písma, kterým se sází kód. Mono písmo má všechny znaky stejně široké,
    /// takže stačí změřit jeden — a metriku vydá `FontMetric` (#407), ne vlastní čtení.
    private static let characterWidth = FontMetric.shared.characterWidth(
        of: .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    )
}
