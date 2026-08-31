import Foundation
import Testing

@testable import PRism

/// **Katalog emotikonů** (#483) — vygenerovaná tabulka a její rozbor.
///
/// Rozbíjí se to potichu: kdyby se generátor rozešel s tabulkou, vyjde v okně nabídka bez řádků
/// a nikdo se nedozví proč. Čísla se proto tvrdí **literálem** — ne `> 0`, ale kolik toho v tabulce
/// je, aby se rozdíl proti zdroji poznal z hlášky.
@Suite("Katalog emotikonů (#483)")
struct EmojiCatalogTests {
    /// Kolik znaků a shortcodů vydal `bin/emoji-sources/gemoji-emoji.json`. **Literál schválně**:
    /// je to jediné místo, kde je vidět, že se tabulka vygenerovala z toho, z čeho měla.
    @Test("Tabulka nese celý zdroj")
    func carriesTheWholeSource() {
        #expect(EmojiCatalog.all.count == 1870)
        #expect(EmojiCatalog.all.reduce(0) { $0 + $1.names.count } == 1913)
    }

    /// **Každý řádek má znak i jméno.** Řádek bez znaku by v nabídce vypadal jako emotikon, který se
    /// nedá vložit — a přesně proto se shortcody bez Unicode do tabulky negenerují.
    @Test("Každý znak má neprázdný znak a jméno")
    func hasACharacterAndANameEverywhere() {
        for emoji in EmojiCatalog.all {
            #expect(!emoji.character.isEmpty)
            #expect(!emoji.name.isEmpty)
            // Znak je jeden `Character`, i u složených (👨‍👩‍👦, 🏴 s tagy). Kdyby jich bylo víc,
            // rozešla by se poloha kurzoru po vložení s tím, co se do textu doopravdy dostalo.
            #expect(emoji.character.count == 1, "„\(emoji.name)“ má \(emoji.character.count) znaků")
            #expect(!emoji.name.contains(":"), "„\(emoji.name)“ nese dvojtečku")
            #expect(!emoji.name.contains(" "), "„\(emoji.name)“ nese mezeru")
        }
    }

    /// **Obrázkové shortcody GitHubu v katalogu nejsou.** Byl by z nich jediný řádek, který se chová
    /// jinak (vloží text místo znaku) a který se navíc nedá ukázat.
    @Test("Shortcody bez Unicode chybí", arguments: ["shipit", "octocat", "trollface", "bowtie"])
    func leavesOutTheImageOnlyShortcodes(name: String) {
        #expect(!EmojiCatalog.all.contains { $0.names.contains(name) })
    }

    /// **Jeden znak = jeden řádek.** Aliasy jsou u něj, ne jako druhá položka — na tom stojí celé
    /// rozhodnutí „řádek je na znak, ne na jméno“.
    @Test("Znak je v katalogu jednou")
    func keepsOneRowPerCharacter() throws {
        var seen: Set<String> = []
        for emoji in EmojiCatalog.all {
            #expect(seen.insert(emoji.character).inserted, "„\(emoji.name)“ je druhý řádek téhož znaku")
        }

        let thumb = try #require(EmojiCatalog.all.first { $0.character == "👍" })
        #expect(thumb.name == "+1")
        #expect(thumb.aliases == ["thumbsup"])
    }

    /// **Řádky jsou abecedně podle prvního shortcodu**, a je to podmínka, ne úklid: pořadí katalogu
    /// je druhé kritérium řazení nabídky, takže seskupení po kategoriích ze zdroje by na dotaz `:ta`
    /// vyhrálo jídlo a `:tada:` by se do šesti řádků nevešlo.
    @Test("Katalog je seřazený")
    func staysSorted() {
        let names = EmojiCatalog.all.map(\.name)
        #expect(names == names.sorted())
    }

    /// Rozbor je totální: **vadný řádek se zahodí, nepoloží celou tabulku.** Prázdná nabídka v okně
    /// kvůli jednomu řádku by byla ta horší polovina téhož problému.
    @Test("Rozbor zahodí vadný řádek a zbytek unese")
    func skipsBrokenLines() {
        let table = """
            🎉 tada
            bezmezery
            👍 +1 thumbsup

            🌮 taco
            """

        let parsed = EmojiCatalog.parse(table)

        #expect(parsed.map(\.name) == ["tada", "+1", "taco"])
        #expect(parsed[safely: 1]?.aliases == ["thumbsup"])
    }

    /// **Věty o zalamování stojí na dvou číslech z katalogu, takže se tvrdí, ne opisují.**
    ///
    /// Nejdelší jméno se do nabídky **nevejde** a musí se zalomit (`EmojiSuggestionMenuTests`), kdežto
    /// nejdelší úsek **mezi oddělovači** se vejít musí — jinak by zlomy z
    /// `Policy.emojiShortcodeLabel(of:)` nestačily a jméno by přeteklo i s nimi. Kdyby zdroj někdy
    /// dostal dlouhé jméno bez podtržítka, spadne to tady, ne v kresbě.
    @Test("Nejdelší jméno a nejdelší úsek mezi oddělovači")
    func measuresTheLongestNameAndChunk() throws {
        let names = EmojiCatalog.all.flatMap(\.names)
        let longest = try #require(names.max { $0.count < $1.count })
        let chunks = names.flatMap { $0.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == "+" }) }
        let longestChunk = try #require(chunks.max { $0.count < $1.count })

        print("MĚŘENÍ nejdelší jméno: :\(longest): (\(longest.count + 2) znaků), "
            + "nejdelší úsek: \(longestChunk) (\(longestChunk.count))")
        #expect(longest == "hand_with_index_finger_and_thumb_crossed")
        #expect(longest.count + 2 == 42)
        #expect(longestChunk.count == 16, "úsek bez zlomu má \(longestChunk.count) znaků")
    }

    /// **Rozbor stojí jeden průchod za běh procesu, ne jeden za úhoz** — `static let` je líné, takže
    /// se změří, co ten průchod dělá, a vypíše se to. Kdyby to jednou začalo být drahé, je z čeho
    /// vyjít; strop se netvrdí, protože číslo z testovacího hosta pod zátěží nic neznamená (#296).
    @Test("Rozbor tabulky se změří")
    func measuresTheParse() {
        let start = ContinuousClock.now
        let parsed = EmojiCatalog.parse(EmojiTable.rows)
        let elapsed = ContinuousClock.now - start

        print("MĚŘENÍ rozbor katalogu: \(parsed.count) znaků za \(elapsed)")
        #expect(parsed.count == EmojiCatalog.all.count)
    }

    /// A druhá polovina téhož: **kolik stojí jeden dotaz**, tedy to, co se platí při každém úhozu
    /// s otevřenou nabídkou. Taky se jen vypisuje.
    @Test("Jeden dotaz nad katalogem se změří")
    func measuresOneQuery() {
        let start = ContinuousClock.now
        let rows = Policy.emojiSuggestions(for: "ta")
        let elapsed = ContinuousClock.now - start

        print("MĚŘENÍ dotaz „ta“ nad 1870 znaky: \(rows.count) řádků za \(elapsed)")
        #expect(rows.count == Policy.emojiSuggestionLimit)
    }
}
