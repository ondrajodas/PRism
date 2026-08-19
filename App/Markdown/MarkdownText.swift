import SwiftUI

/// Vykreslí Markdown z GitHubu — popis PR, komentáře, těla review.
///
/// Bloky (nadpisy, seznamy, kód, citace, výstrahy, `<details>`) skládá `MarkdownParser`,
/// **formátování uvnitř řádku dělá systém** (`MarkdownInlineText` nad `AttributedString`) a inline
/// HTML strhává `MarkdownHTML`. Dělí se to takhle proto, že systémový parser inline zvládá dobře,
/// ale bloky ve `Text`u tiše spolkne: `## Popis` vyjde jako „Popis“ obyčejným písmem a odrážky
/// ztratí odrážku.
///
/// **Rozložení na bloky i inline sazba se pamatují** (`MarkdownRenderCache`, #279): sází se
/// v `body`, tedy při každém vykreslení. Text komentáře se přitom nemění, takže výsledek je jeho
/// funkce — pravidlo #224. Změřeno: u zprávy od bota o 12 kB 1,91 ms rozklad a 1,81 ms inline.
struct MarkdownText: View {
    let text: String
    /// Velikost prózy. Nadpisy, kód i mezery se od ní odvozují (`MarkdownTypography`), takže sazba
    /// v okně s novinkami může být o půl bodu větší než v komentáři, aniž by se to nastavovalo po
    /// blocích.
    ///
    /// **Číslo, ne `Font`** (#279): ze `Font`u se velikost nedá přečíst, takže by z něj škála
    /// nadpisů neměla z čeho vyjít — a přesně proto měly nadpisy do #279 dvě velikosti na šest
    /// úrovní.
    var size: Double = 12.5

    var body: some View {
        let _ = RenderDiagnostics.pass(Self.self)
        MarkdownBlocksView(blocks: MarkdownRenderCache.shared.blocks(of: text), size: size)
    }
}

/// Seznam bloků pod sebou, s mezerami podle toho, co po čem jde.
///
/// Vlastní typ, ne metoda: citace, výstraha i `<details>` mají vnořené bloky, takže se vykreslování
/// volá samo — a rekurze přes `some View` je typ definovaný sám sebou, což Swift odmítne. Nominální
/// typ tenhle problém nemá.
struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    var size: Double = 12.5

    var body: some View {
        // `spacing: 0` a mezera na každém bloku zvlášť: rytmus se řídí **přechodem** mezi dvěma
        // bloky (`MarkdownTypography.spacing`), a jednu mezeru pro všechno stačí nastavit tady,
        // aby dlouhý popis PR vyšel jako jednolitá plocha.
        VStack(alignment: .leading, spacing: 0) {
            // `id: \.offset`, ne obsah: dva stejné odstavce v jednom komentáři jsou možné
            // a `ForEach` by z nich udělal jeden.
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                MarkdownBlockView(block: block, size: size)
                    .padding(.top, MarkdownTypography.spacing(
                        after: index == 0 ? nil : blocks[index - 1],
                        before: block
                    ))
            }
        }
        .filling(alignment: .leading)
    }
}

/// Jeden blok Markdownu.
struct MarkdownBlockView: View {
    let block: MarkdownBlock
    var size: Double = 12.5

    var body: some View {
        switch block {
        case .heading(let level, let text):
            heading(level: level, text: text)
        case .paragraph(let text):
            // Odstavec, ze kterého po strhnutí tagů nic nezbylo (`<p>`, `</ul>`), se
            // nekreslí — jinak by po každém takovém řádku zůstala mezera.
            paragraph(text)
        case .listItem(let marker, let indent, let text):
            item(marker: marker, indent: indent, text: text)
        case .code(_, let lines):
            code(lines)
        case .quote(let blocks):
            quote(blocks)
        case .alert(let kind, let blocks):
            alert(kind: kind, blocks: blocks)
        case .rule:
            Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 2)
        case .table(let rows):
            table(rows)
        case .details(let summary, let blocks):
            details(summary: summary, blocks: blocks)
        // `<!-- … -->` je značka pro stroje, ne text pro člověka — GitHub taky nekreslí nic.
        case .htmlComment:
            EmptyView()
        }
    }

    // MARK: - Bloky

    /// Nadpis podle úrovně — šest velikostí, u `#` a `##` s linkou pod sebou.
    ///
    /// Do #279 tu stálo `level <= 2 ? .headline : .subheadline`, tedy dvě velikosti na šest úrovní:
    /// `Description` a `Release Notes` v popisu PR vypadaly jako tučný odstavec a po struktuře se
    /// nedalo skákat.
    private func heading(level: Int, text: String) -> some View {
        let style = MarkdownTypography.heading(level: level, base: size)
        return VStack(alignment: .leading, spacing: 3) {
            Text(inline(text))
                .font(.system(size: style.size, weight: style.isBold ? .bold : .semibold))
                // Barvu si nadpis **nebere**, jen tlumená šestka: uvnitř citace platí ztlumení
                // celého podstromu a explicitní inkoust by ho přebil, takže by nadpis v citaci
                // svítil víc než text kolem něj.
                .foregroundStyle(style.isMuted ? AnyShapeStyle(Palette.ink2) : AnyShapeStyle(.primary))
                .fixedSize(horizontal: false, vertical: true)
                .filling(alignment: .leading)
            if style.hasRule {
                Rectangle().fill(Palette.lineSoft).frame(height: 1)
            }
        }
    }

    @ViewBuilder private func paragraph(_ text: String) -> some View {
        let rendered = inline(text)
        if !rendered.characters.isEmpty {
            Text(rendered)
                .font(.system(size: size))
                .fixedSize(horizontal: false, vertical: true)
                .filling(alignment: .leading)
        }
    }

    /// Položka seznamu: značka ve **sloupci o pevné šířce** a text vedle ní.
    ///
    /// Sloupec je pevný proto, aby šla šířka textu **spočítat** (#220 — předává se, nevyjednává):
    /// odsazení zanoření plus sloupec plus mezera. Se šířkou podle glyfu by ta aritmetika platila
    /// pro `•`, ale ne pro `10.`, a text by přetekl o rozdíl — a přetečení je horší než vyjednávání,
    /// protože je vidět. `minWidth` schválně, ne `width`: číslovaný seznam nad sto položek si
    /// sloupec rozšíří, a to je pořád lepší než osekané číslo.
    private func item(marker: MarkdownBlock.Marker, indent: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.markerGap) {
            bullet(marker)
                .frame(minWidth: Self.markerColumn, alignment: .leading)
            Text(inline(text))
                .font(.system(size: size))
                .fixedSize(horizontal: false, vertical: true)
                .filling(alignment: .leading)
        }
        .padding(.leading, Double(indent) * 16)
        .narrowingWidth(by: Double(indent) * 16 + Self.markerColumn + Self.markerGap)
    }

    /// Šířka sloupce se značkou a mezera za ním. Osmnáct bodů unese `•`, zaškrtávátko i `99.`
    /// při dvanáctibodové próze.
    private static let markerColumn: Double = 18
    private static let markerGap: Double = 6

    @ViewBuilder private func bullet(_ marker: MarkdownBlock.Marker) -> some View {
        switch marker {
        // Odrážka i číslo jdou **hierarchicky** (`.secondary`), ne konkrétní barvou z palety:
        // uvnitř citace je celý podstrom ztlumený, takže absolutní inkoust by tam odrážku
        // zesvětlil na stejnou hodnotu jako text a přestala by být tišší než on.
        case .bullet:
            Text(verbatim: "•").font(.system(size: size)).foregroundStyle(.secondary)
        case .number(let number):
            // `verbatim` a ruční tečka: `Text("\(number).")` protáhne číslo přes locale.
            Text(verbatim: "\(number).")
                .font(.system(size: size))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        case .task(let isDone):
            // Zaškrtnutí je **jen obrázek**, ne přepínač: je to cizí text, ne můj formulář.
            // Hotová položka bere **akcent z palety**, ne systémový `.tint` (#180).
            Image(systemName: isDone ? "checkmark.square.fill" : "square")
                .font(.system(size: size - 1.5))
                .foregroundStyle(isDone ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.secondary))
        }
    }

    /// Blok kódu monospace a s podkladem. Neobarvuje se: jazyk z fence je volný řetězec
    /// (`sh`, `zsh`, `console`) a `Syntax.Language` se pozná z **cesty k souboru** — mapovat
    /// jedno na druhé znamená hádat, a špatně obarvený cizí kód je horší než neobarvený.
    ///
    /// Tagy se v něm **nestrhávají**: `<T>` uvnitř kódu je kód, ne HTML.
    private func code(_ lines: [String]) -> some View {
        Text(verbatim: lines.joined(separator: "\n"))
            .font(.system(size: MarkdownTypography.codeSize(base: size), design: .monospaced))
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .filling(alignment: .leading)
            // Tentýž podklad jako inline `kód` (#279) — do té doby to byla `.quaternary`, tedy
            // druhá „skoro stejná“ šedá vedle palety.
            .background(Palette.codeFill, in: .rect(cornerRadius: 6))
    }

    /// Citace jako **vysázené bloky**, ne slepené řádky (#279).
    ///
    /// Do #279 z ní byl jeden `Text`, takže `## nadpis` ani `- [ ]` uvnitř `> …` se nevysázely
    /// a v okně stál zdroj — což byla celá jedna polovina toho, co #279 řešilo.
    private func quote(_ blocks: [MarkdownBlock]) -> some View {
        // Pruh je `ink3`, ne `line`: linka je na obrysy ploch a na tři body široký pruh uvnitř
        // karty je tak slabá, že citaci od odstavce nerozezná — na vyrendrované ukázce nebyla
        // **vnořená** citace poznat vůbec. `ink3` je tichý inkoust, tedy pořád ne akcent.
        indented(by: Palette.ink3) {
            MarkdownBlocksView(blocks: blocks, size: size)
                .foregroundStyle(Palette.ink2)
        }
    }

    /// GitHubová výstraha: barevný pruh, ikona, titulek a pod tím vysázený obsah.
    private func alert(kind: MarkdownBlock.Alert, blocks: [MarkdownBlock]) -> some View {
        let style = MarkdownAlertStyle.of(kind)
        return indented(by: style.color) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: style.symbol).font(.system(size: size - 1))
                    Text(style.title).font(.system(size: size, weight: .semibold))
                }
                .foregroundStyle(style.color)
                // Výstraha bez obsahu je jen titulek — `> [!NOTE]` samo na řádku se stane.
                if !blocks.isEmpty {
                    MarkdownBlocksView(blocks: blocks, size: size)
                }
            }
        }
    }

    /// Obsah za svislým pruhem — citace i výstraha. Šířka se dětem **předává zúžená** o pruh
    /// a mezeru (#220), ne dovyjednává.
    ///
    /// Pruh je `overlay`, ne první prvek `HStack`u, a to je oprava, ne kosmetika: v `HStack`u se
    /// výška pruhu řídila **návrhem** rodiče, kdežto obsah si spočítal svou vlastní — u citace
    /// s nadpisem a zaškrtávátkem tak pruh sahal do poloviny a zbytek citace stál bez značky.
    /// `overlay` má velikost obsahu z definice, takže se pruh nemá s čím rozejít.
    private func indented<Content: View>(
        by color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.leading, 11)
            .narrowingWidth(by: 11)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 3)
            }
    }

    /// Tabulka jako monospace řádky se svislítky. Vykreslit ji doopravdy (sloupce, zarovnání)
    /// je vlastní úloha; takhle je aspoň čitelná a **nic z ní nechybí**, což je to hlavní.
    private func table(_ rows: [String]) -> some View {
        ScrollView(.horizontal) {
            Text(verbatim: rows.joined(separator: "\n"))
                .font(.system(size: MarkdownTypography.codeSize(base: size), design: .monospaced))
                .fixedSize(horizontal: true, vertical: true)
        }
        .scrollIndicators(.automatic)
    }

    /// `<details>` jako rozbalovátko — sbalené, jako na GitHubu.
    ///
    /// Popisek bez `<summary>` má vlastní text: prázdné rozbalovátko se nedá ani rozbalit,
    /// protože není na co kliknout.
    private func details(summary: String, blocks: [MarkdownBlock]) -> some View {
        DisclosureGroup {
            MarkdownBlocksView(blocks: blocks, size: size)
                .padding(.top, 4)
        } label: {
            Text(summary.isEmpty ? AttributedString("Podrobnosti") : inline(summary))
                .font(.system(size: size))
        }
        // Rozbalovátko si na svůj trojúhelníček bere místo zleva, takže obsah uvnitř má k dispozici
        // méně, než co dostalo samo.
        .narrowingWidth(by: 20)
        .filling(alignment: .leading)
    }

    // MARK: - Inline

    /// Inline sazba **z cache** (#279): `AttributedString(markdown:)` je nad bloky jedné zprávy od
    /// bota 1,81 ms a tohle se volá z `body`, tedy při každém překreslení. Vlastní pravidla jsou
    /// v `MarkdownInlineText`, cache je jen před nimi.
    private func inline(_ source: String) -> AttributedString {
        MarkdownRenderCache.shared.inline(source, size: size)
    }
}

#Preview {
    ScrollView {
        MarkdownText(text: """
            # První úroveň
            ## Druhá úroveň
            ### Třetí
            #### Čtvrtá
            ##### Pátá
            ###### Šestá

            Tohle je **odstavec** s `kódem` a [odkazem](https://github.com).

            - odrážka
            - [x] hotová položka
            - [ ] nehotová
              - zanořená

            1. první
            2. druhá

            > citace od kolegy
            > ## nadpis v citaci
            > - [ ] a zaškrtávátko
            >
            > > a vnořená citace

            > [!NOTE]
            > Poznámka od bota.

            > [!TIP]
            > Rada, kterou dá `coderabbitai`.

            > [!IMPORTANT]
            > ## Review skipped
            >
            > - [ ] 🔍 Trigger review

            > [!WARNING]
            > Upozornění — **ne** okrová jako zastarání.

            > [!CAUTION]
            > Pozor — **ne** červená jako blokující nález.

            > [!NEZNÁMÉ]
            > Neznámý druh zůstane obyčejnou citací, ne prázdnem.

            ```swift
            let x = 1  // # tohle není nadpis
            ```

            <!-- linear-linkback -->
            <details>
            <summary><a href="https://linear.app">AJDA-2222 Update Doctrine</a></summary>
            <p>
            Text uvnitř rozbalovátka.
            </p>
            </details>

            | a | b |
            |---|---|
            | 1 | 2 |
            """)
        .padding()
    }
    .frame(width: 460, height: 700)
}
