import Foundation
import Testing

@testable import PRism

/// Sazba v číslech — škála nadpisů a rytmus bloků (#279). Čisté funkce, vyčerpávající výčet.
@Suite("MarkdownTypography")
struct MarkdownTypographyTests {
    /// To hlavní z #279: **šest úrovní, šest velikostí.** Do té doby byly dvě
    /// (`level <= 2 ? .headline : .subheadline`), takže `#` a `##` vypadaly stejně a `###`–`######`
    /// taky — a v dlouhém popisu PR nebylo v čem vidět strukturu.
    @Test("Každá úroveň nadpisu je menší než ta nad ní")
    func scalesEveryHeadingLevel() {
        let sizes = (1...6).map { MarkdownTypography.heading(level: $0, base: 12.5).size }

        #expect(Set(sizes).count == 6, "šest různých velikostí, ne \(sizes)")
        #expect(sizes == sizes.sorted(by: >), "monotónně klesající, ne \(sizes)")
    }

    /// Úroveň mimo rozsah nesmí spadnout na jinou škálu ani na nulovou velikost: parser sice
    /// hlídá 1–6, ale sazba stojí sama za sebe.
    @Test("Úroveň mimo rozsah se přiklopí ke krajní")
    func clampsTheLevel() {
        #expect(MarkdownTypography.heading(level: 0, base: 12.5) == MarkdownTypography.heading(level: 1, base: 12.5))
        #expect(MarkdownTypography.heading(level: 9, base: 12.5) == MarkdownTypography.heading(level: 6, base: 12.5))
    }

    @Test("Linka je pod `#` a `##`, dál ne")
    func drawsARuleUnderTheTopTwoLevels() {
        #expect((1...6).map { MarkdownTypography.heading(level: $0, base: 12.5).hasRule } == [
            true, true, false, false, false, false,
        ])
    }

    /// Šestka je „skoro popisek“ a od pětky se velikostí (11 proti 11,75) sama nepozná.
    @Test("Tlumená je jen šestá úroveň")
    func mutesOnlyTheLastLevel() {
        #expect((1...6).map { MarkdownTypography.heading(level: $0, base: 12.5).isMuted } == [
            false, false, false, false, false, true,
        ])
    }

    /// Škála je poměrová, protože tentýž Markdown se sází v komentáři (12,5) i v okně s novinkami
    /// (13). Pevná tabulka by znamenala buď dvě tabulky, nebo jednu, která nikde nesedí.
    @Test("Větší próza dá větší nadpisy")
    func scalesWithTheBaseSize() {
        for level in 1...6 {
            let small = MarkdownTypography.heading(level: level, base: 12.5).size
            let large = MarkdownTypography.heading(level: level, base: 16).size
            #expect(large > small, "úroveň \(level): \(large) není víc než \(small)")
        }
    }

    @Test("Kód je menší než próza, ale ne pod devět bodů")
    func keepsCodeReadable() {
        #expect(MarkdownTypography.codeSize(base: 12.5) == 11)
        #expect(MarkdownTypography.codeSize(base: 8) == 9)
    }

    // MARK: - Rytmus

    /// Mezera se řídí **přechodem**, ne blokem: nadpis začíná něco nového (volně), text pod ním
    /// k němu patří (těsně) a dvě položky seznamu jsou jeden celek (nejtěsněji).
    @Test("Nadpis má nad sebou nejvíc místa, položky seznamu nejméně")
    func spacesBlocksByTransition() {
        let paragraph = MarkdownBlock.paragraph("text")
        let heading = MarkdownBlock.heading(level: 2, text: "nadpis")
        let item = MarkdownBlock.listItem(marker: .bullet, indent: 0, text: "a")

        let beforeHeading = MarkdownTypography.spacing(after: paragraph, before: heading)
        let afterHeading = MarkdownTypography.spacing(after: heading, before: paragraph)
        let betweenParagraphs = MarkdownTypography.spacing(after: paragraph, before: paragraph)
        let betweenItems = MarkdownTypography.spacing(after: item, before: item)

        #expect(beforeHeading > betweenParagraphs)
        #expect(afterHeading < betweenParagraphs)
        #expect(betweenItems < betweenParagraphs)
    }

    /// První blok mezeru nad sebou mít nesmí — jinak se sazba odlepí od horní hrany karty
    /// a odsazení kolem přestane platit.
    @Test("První blok nemá mezeru nad sebou")
    func startsWithoutSpacing() {
        #expect(MarkdownTypography.spacing(after: nil, before: .paragraph("text")) == 0)
        #expect(MarkdownTypography.spacing(after: nil, before: .heading(level: 1, text: "nadpis")) == 0)
    }

    /// Žádný přechod nesmí vyjít nula (kromě prvního bloku) — slepené bloky by v okně vypadaly
    /// jako jeden.
    @Test("Mezi dvěma bloky je vždycky mezera")
    func neverCollapsesTwoBlocks() {
        let kinds: [MarkdownBlock] = [
            .heading(level: 1, text: "n"),
            .paragraph("p"),
            .listItem(marker: .bullet, indent: 0, text: "i"),
            .code(language: nil, lines: ["k"]),
            .quote([.paragraph("c")]),
            .alert(kind: .note, blocks: []),
            .rule,
            .table(["| a |"]),
            .details(summary: "s", blocks: []),
            .htmlComment(["<!-- x -->"]),
        ]

        for previous in kinds {
            for block in kinds {
                #expect(
                    MarkdownTypography.spacing(after: previous, before: block) > 0,
                    "\(previous) → \(block)"
                )
            }
        }
    }
}
