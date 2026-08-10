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

    // MARK: - Sbalení a co zbylo

    /// Jedno tlačítko, ne dvě. Který ze dvou stavů dává smysl, plyne z toho, co je zrovna
    /// na obrazovce — dvě tlačítka by znamenala, že je jedno z nich pořád k ničemu.
    ///
    /// Nabídka pod šipkou drží volby, které se nastaví a nechají být: bubliny nálezů u řádků
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
                        // Jmenuje se `Nálezy u řádků`, ne `Bubliny`: schovává **jen** nálezy,
                        // kdežto „bubliny“ jsou od #64 i vlákna konverzace. A ne holé `Nálezy` —
                        // tak se jmenuje přepínač panelu o kus vedle. **Nápověda tu není**:
                        // položky menu na macOS tooltip neukazují, takže by to byl mrtvý text.
                        Toggle("Nálezy u řádků", isOn: $showBubbles)
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
    /// takže stačí změřit jeden — a `maximumAdvancement` u něj vrací tutéž hodnotu.
    private static let characterWidth = NSFont.monospacedSystemFont(
        ofSize: NSFont.systemFontSize,
        weight: .regular
    ).maximumAdvancement.width
}
