import SwiftUI

/// Malé tlačítko z návrhu (`.mini`, `.mini.pri`) — řada akcí u nálezu v diffu (#283).
///
/// **Proč vlastní styl, a ne `.link`.** Do #283 se akce u nálezu kreslily jako
/// `.buttonStyle(.link)`, tedy modrý systémový text bez plochy. Mělo to dvě vady: nedalo se poznat,
/// která z akcí je ta hlavní, a systémová modrá je jediná barva v okně, která z palety návrhu není.
/// Návrh má místo toho **řadu malých tlačítek** a hlavní akci odlišuje **plochou** — plné akcentové
/// proti obtaženému.
///
/// **Platí to jen o bublině.** V tabulce nálezů zůstávají akce holým textem, protože se tam opakují
/// na každém řádku — barvu ale mají mít stejnou, a od #298 ji drží `AccentLinkButtonStyle`. Zmínka
/// o `.link` výš je tedy záznam o tom, co v aplikaci bylo; v `App/` už systémový `.link` není nikde.
///
/// Rozměry jsou z CSS návrhu 1 : 1 a leží v `Metrics`, ne rozeseté v `makeBody`: jsou to čísla, na
/// která se dá napsat test, a shoda s návrhem je jediné, co je drží.
///
/// **Text plného tlačítka je `Palette.surface`, ne bílá** — návrh má `color: var(--panel)`. Ve
/// světlém režimu z toho vyjde bílá, v tmavém tmavá, takže kontrast drží v obou bez druhého
/// pravidla; zadrátovaná bílá by v tmavém režimu na světle fialovém akcentu byla slabší.
struct MiniButtonStyle: ButtonStyle {
    enum Emphasis {
        /// Obtažené — `.mini`.
        case secondary
        /// Plné akcentové — `.mini.pri`. V jedné řadě má být **jedno**; dvě plná tlačítka vedle
        /// sebe znamenají, že se hlavní akce nedá poznat, a to je zrovna to, co má plocha říct.
        case primary
    }

    /// Rozměry a mezery z CSS návrhu (`.mini`, `.inline-find footer`). Body 1 : 1 s pixely, jak to
    /// má tenhle repo zvykem — viz `docs/navrh.md`.
    enum Metrics {
        static let fontSize = 11.5
        static let horizontalPadding = 9.0
        static let verticalPadding = 3.0
        static let cornerRadius = 6.0
        /// `gap` mezi tlačítky v řadě akcí.
        static let spacing = 7.0
        /// Výška textového řádku — `font-size: 11.5px` × `line-height: 1.45` z rámu okna (`.win`).
        ///
        /// **Není to ozdoba, je to jediný rozměr, který se z CSS neopíše přímo.** Výška `.mini`
        /// v návrhu nikde nestojí: skládá se z paddingu a řádku, a ten je v CSS 16,7 bodu, kdežto
        /// SwiftUI dá pro tuhle velikost systémového fontu jen 12. Změřeno renderem vedle návrhu —
        /// bez tohohle bylo tlačítko **20 bodů proti 25 v návrhu**. A 25 je zrovna výška, kterou
        /// návrh dává i vstupu do palety v hlavičce (`.tbtn.key { height: 25px }`), takže malé
        /// ovladače mají v okně jednu výšku.
        static let lineHeight = fontSize * 1.45
        static let borderWidth = 1.0

        /// Odsazení textu od hrany tlačítka — **padding z CSS plus obtažení**.
        ///
        /// CSS obtažení připočítává k rámečku (`border` leží vně `padding`u), kdežto SwiftUI ho
        /// kreslí `overlay`em **dovnitř** rámce, takže samo nic nezvětší. Bez toho připočtení
        /// vycházelo tlačítko o dva body nižší než návrh — změřeno na renderu vedle sebe.
        static var insetHorizontal: Double { horizontalPadding + borderWidth }
        static var insetVertical: Double { verticalPadding + borderWidth }

        /// Celá výška tlačítka, jak vyjde v návrhu — 25 bodů, tedy tolik, kolik návrh dává i vstupu
        /// do palety v hlavičce okna (`.tbtn.key { height: 25px }`). Bere si ji `makeBody` jako
        /// `minHeight`, takže je to spočítané číslo, ne konstanta k opsání.
        static var height: Double { lineHeight + 2 * insetVertical }
    }

    let emphasis: Emphasis

    /// **`ButtonStyleConfiguration` vypsané celé, ne `Configuration`.** Aplikace má vlastní
    /// `Configuration` (nastavení), a ta jméno z protokolu přebije — konformance pak neprojde
    /// s hláškou o chybějícím `Body`, ze které se příčina nepozná.
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            // `font-weight: 560` u plného tlačítka — v repu se překládá na `.medium`, stejně jako
            // titulek řádku fronty.
            .font(.system(size: Metrics.fontSize, weight: emphasis == .primary ? .medium : .regular))
            .foregroundStyle(foreground)
            // Popisek jednoho tlačítka se **nezalamuje**, a když se nevejde, zkrátí se: dvouřádkové
            // tlačítko v řadě jednořádkových vypadá jako jiný prvek. Jak se zachová celá **řada**,
            // je věc volajícího — u nálezu se zlomí, viz `FindingBubbleView.footer(of:)`.
            .lineLimit(1)
            .padding(.horizontal, Metrics.insetHorizontal)
            .padding(.vertical, Metrics.insetVertical)
            // Výška z návrhu, ne ta, kterou dá font sám — viz `Metrics.height`. `minHeight`, aby si
            // delší popisek pořád rozhodl sám, a **před** pozadím, aby ho plocha vyplnila celé.
            .frame(minHeight: Metrics.height)
            .background(background, in: .rect(cornerRadius: Metrics.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                    .strokeBorder(border, lineWidth: Metrics.borderWidth)
            }
            .contentShape(.rect)
            // Zmáčknutí musí být vidět. Návrh stisknutý stav nekreslí, takže je to rozhodnutí:
            // ztlumení celé plochy, ne druhá barva — barva by na plném tlačítku znamenala třetí
            // odstín akcentu, který v paletě není.
            .opacity(configuration.isPressed ? 0.6 : 1)
    }

    // Tři barvy nejsou `private` schválně: čte je test, protože „plné tlačítko má text v barvě
    // panelu, ne bílý“ je pravidlo z návrhu, které se dá zjednodušit na `.white`, aniž by to bylo
    // ve světlém režimu vidět. Ven z aplikace se tím nic neotevírá — je to jeden modul.

    var foreground: Color {
        switch emphasis {
        case .secondary: Palette.ink2
        case .primary: Palette.surface
        }
    }

    var background: Color {
        switch emphasis {
        case .secondary: Palette.surface
        case .primary: Palette.accent
        }
    }

    var border: Color {
        switch emphasis {
        case .secondary: Palette.line
        case .primary: Palette.accent
        }
    }
}

extension ButtonStyle where Self == MiniButtonStyle {
    /// Obtažené malé tlačítko (`.mini` z návrhu).
    static var mini: MiniButtonStyle { MiniButtonStyle(emphasis: .secondary) }

    /// Plné akcentové malé tlačítko (`.mini.pri` z návrhu) — v jedné řadě jedno.
    static var miniPrimary: MiniButtonStyle { MiniButtonStyle(emphasis: .primary) }
}
