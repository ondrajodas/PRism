#!/usr/bin/env swift

// Vygeneruje katalog emotikonů do `App/Support/EmojiTable.swift` (#483).
//
//     swift bin/make-emoji.swift                              # ze zdroje v repu
//     swift bin/make-emoji.swift bin/emoji-sources/x.json     # z jiného souboru
//
// **Zdroj je `bin/emoji-sources/gemoji-emoji.json`**, tedy `db/emoji.json` z
// [github/gemoji](https://github.com/github/gemoji) (MIT), stažené z commitu
// `0eca75db9301421efc8710baf7a7576793ae452a`. Je to ten seznam, ze kterého GitHub své shortcody
// bere — `GET /emojis` je jeho obraz plus 23 vlastních obrázků. **Leží v repu schválně**: bez něj
// by se katalog nedal vygenerovat znovu a nešlo by ověřit, odkud se ta data vzala.
//
// Stáhnout znovu:
//
//     gh api repos/github/gemoji/contents/db/emoji.json --jq .content |
//         base64 -d > bin/emoji-sources/gemoji-emoji.json
//
// **Proč generovaný zdroják, a ne JSON v bundlu:** do `App/` patří jen zdrojáky — buildable folder
// zkopíruje všechno ostatní do `.app` jako resource (viz `CLAUDE.md`, *Konvence*).
//
// **Proč jeden velký řetězec, a ne pole 1870 struktur:** doslovné pole s tolika prvky by
// type-checker překládal minuty. Tabulka je jedna víceřádková konstanta a rozebere ji
// `EmojiCatalog` — jednou za běh procesu, líně.
//
// **Co se ze zdroje zahazuje:** položky bez znaku. V tomhle souboru žádné nejsou (změřeno: 1870
// z 1870 má `emoji`), a je to schválně — `:shipit:` a `:octocat:` jsou obrázky GitHubu, ne
// Unicode, takže by z nich v nabídce byl jediný řádek, který se chová jinak. Kontrola tady
// zůstává proto, aby se to nezměnilo potichu, kdyby zdroj někdy takovou položku dostal.
//
// **Řadí se abecedně podle prvního shortcodu**, ne v pořadí zdroje. Pořadí katalogu je totiž
// druhé kritérium řazení nabídky (při shodné váze shody rozhoduje), a zdroj je seskupený po
// kategoriích — na dotaz `:ta` by pak vyhrálo jídlo a `:tada:` by se do šesti řádků nevešlo.

import Foundation

// MARK: - Vstup

struct SourceEmoji: Decodable {
    let emoji: String?
    let aliases: [String]
}

let arguments = Array(CommandLine.arguments.dropFirst())
let sourcePath = arguments.first ?? "bin/emoji-sources/gemoji-emoji.json"
let outputPath = "App/Support/EmojiTable.swift"

guard let data = FileManager.default.contents(atPath: sourcePath) else {
    FileHandle.standardError.write(Data("make-emoji: nečitelný zdroj \(sourcePath)\n".utf8))
    exit(1)
}

let source: [SourceEmoji]
do {
    source = try JSONDecoder().decode([SourceEmoji].self, from: data)
} catch {
    FileHandle.standardError.write(Data("make-emoji: rozbitý JSON — \(error)\n".utf8))
    exit(1)
}

// MARK: - Výběr a řazení

struct Row {
    let character: String
    let names: [String]
}

var rows: [Row] = []
var withoutCharacter = 0

for item in source {
    guard let character = item.emoji, !character.isEmpty else {
        withoutCharacter += 1
        continue
    }
    let names = item.aliases.filter { !$0.isEmpty && !$0.contains(" ") }
    guard let first = names.first else { continue }
    // Znak nesmí obsahovat mezeru — tabulka dělí řádek na znak a jména právě na ní.
    guard !character.contains(" ") else {
        FileHandle.standardError.write(Data("make-emoji: znak s mezerou u :\(first):\n".utf8))
        exit(1)
    }
    rows.append(Row(character: character, names: names))
}

rows.sort { $0.names[0] < $1.names[0] }

let table = rows.map { "\($0.character) \($0.names.joined(separator: " "))" }.joined(separator: "\n")
let shortcodes = rows.reduce(0) { $0 + $1.names.count }

// MARK: - Výstup

let header = """
// Vygenerováno `swift bin/make-emoji.swift` ze `bin/emoji-sources/gemoji-emoji.json`
// (github/gemoji, MIT). **Needituj ručně** — příště se to přepíše.

/// Katalog emotikonů jako jedna tabulka (#483): řádek na znak, `znak jméno alias…`.
///
/// **Je to jeden řetězec, ne pole struktur, a je to podmínka překladu**: doslovné pole
/// \(rows.count) prvků by type-checker žvýkal minuty. Rozebírá to `EmojiCatalog`, líně a jednou
/// za běh procesu.
///
/// Řádky jsou **abecedně podle prvního shortcodu** — pořadí katalogu je druhé kritérium řazení
/// nabídky, takže musí být dané daty, ne kategoriemi ve zdroji.
///
/// \(rows.count) znaků, \(shortcodes) shortcodů. Shortcody bez Unicode (`:shipit:`, `:octocat:`)
/// v tabulce **nejsou** — nemají znak, který by se vložil.
enum EmojiTable {
    static let rows = \"\"\"

"""

let footer = """

\"\"\"
}

"""

let output = header + table + footer

do {
    try output.write(toFile: outputPath, atomically: true, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("make-emoji: nešlo zapsat \(outputPath) — \(error)\n".utf8))
    exit(1)
}

print("make-emoji: \(rows.count) znaků, \(shortcodes) shortcodů → \(outputPath)")
if withoutCharacter > 0 {
    print("make-emoji: \(withoutCharacter) položek bez znaku se zahodilo")
}
