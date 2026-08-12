import Foundation

/// Co se z řádku diffu dá zkopírovat a pod jakým názvem (#157).
///
/// Nese **hotový text**, ne odkaz do diffu: menu se staví až při pravém kliknutí, takže se text
/// složí jednou a view už jen rozhoduje, co vykreslit.
struct DiffCopyTarget: Identifiable, Hashable, Sendable {
    /// Klíč do `ForEach` a zároveň to, co odlišuje položky menu mezi sebou.
    let id: String
    /// Titulek položky v menu.
    let title: String
    let text: String
}

/// Skládání kódu z diffu pro schránku. Čisté funkce, žádné I/O.
extension Policy {
    /// **Kód, ne diff.** Vedoucí `+`/`-` ani čísla řádků do schránky nepatří — text se vkládá do
    /// terminálu nebo do komentáře jako kód, kde by z nich byl syntaktický nesmysl.
    ///
    /// Poznámky `git`u (`\ No newline at end of file`) se vynechávají: nejsou obsah souboru.
    ///
    /// **Kopie nese `LF`, i když soubor měl `CRLF`** (#295, vědomé rozhodnutí). `CR` sundá už
    /// `DiffParser`, protože ho bere jako součást zakončení řádku, ne jako obsah — a je to tak
    /// schválně: kdyby v textu řádku zůstal, obarvení, word-level rozdíl a klíče do `SyntaxRunCache`
    /// (#153, #224) by nesly neviditelný znak, a v sazbě by z něj byl prázdný řádek pod každým
    /// řádkem kódu. Cena rozhodnutí, ať je zapsaná: úryvek vložený zpátky do souboru s `CRLF`
    /// přinese `LF`. Unese to, protože tenhle text jde do terminálu nebo do komentáře jako **kód**,
    /// aplikace do souborů nezapisuje (tvrdá podmínka č. 1) a zakončení řádku není to, o čem se
    /// v review mluví.
    static func code(of lines: [DiffLine]) -> String {
        lines
            .filter { $0.kind != .meta }
            .map(\.text)
            .joined(separator: "\n")
    }

    /// Kód rozsahu, **v pořadí, jak stojí v souboru**. `nil` = rozsah v souboru není.
    ///
    /// **Která verze se kopíruje, rozhoduje strana rozsahu.** U rozsahu přes obě strany (odebrané
    /// i přidané řádky naráz) se bere **nová**: o té je při review řeč a je to ta, která
    /// v souboru po mergi zůstane. Rozsah čistě na levé straně naopak kopíruje odebrané řádky —
    /// tam je ten starý kód to jediné, o čem se mluví.
    static func code(of anchor: DraftAnchor, in file: FileDiff) -> String? {
        let lines = rangeLinesInOrder(of: anchor, in: file)
        guard !lines.isEmpty else { return nil }
        return code(of: lines.filter { belongs($0, to: copiedSide(of: anchor)) })
    }

    /// Kód celého hunku — jednoznačný celek, na rozdíl od „celého souboru“, který v diffu není
    /// (mezi hunky chybí řádky, takže slepený soubor by tvrdil, že kód je souvislý).
    ///
    /// Bere **novou** verzi ze stejného důvodu jako u rozsahu přes obě strany.
    static func code(of hunk: DiffHunk) -> String {
        code(of: hunk.lines.filter { belongs($0, to: .right) })
    }

    /// Rozsah mého rozdělaného komentáře, který tenhle řádek pokrývá. `nil` = řádek v žádném
    /// neleží, nebo leží jen v jednořádkovém — u toho by „kopírovat rozsah“ neřeklo nic navíc
    /// proti „kopírovat řádek“.
    ///
    /// Bere **první** takový komentář. Dva rozsahy přes tentýž řádek jsou možné a nabízet dvě
    /// položky, které se od sebe v menu nedají odlišit, je horší než nabídnout ten, který se
    /// v diffu kreslí první.
    static func range(covering line: DiffLine, in comments: [ReviewDraftComment], of file: FileDiff) -> DraftAnchor? {
        self.comments(of: file, from: comments)
            .lazy
            .map(\.anchor)
            .filter { $0.start != nil }
            .first { rangeLines(of: $0, in: file).contains(line) }
    }

    /// Položky, které má nabídnout kontextové menu řádku.
    ///
    /// Skládá se **až při otevření menu**, ne při vykreslení řádku: text rozsahu se hledá přes
    /// všechny hunky souboru a po řádcích by to bylo zbytečně drahé u operace, která se odehraje
    /// jednou za pravé kliknutí.
    static func copyTargets(for line: DiffLine, in file: FileDiff, comments: [ReviewDraftComment]) -> [DiffCopyTarget] {
        var targets: [DiffCopyTarget] = []
        if line.kind != .meta {
            targets.append(DiffCopyTarget(id: "line", title: "Kopírovat řádek", text: line.text))
        }
        if let anchor = range(covering: line, in: comments, of: file),
           let text = code(of: anchor, in: file) {
            // Počítá se **hotový text, který půjde do schránky**, ne řádky diffu, ze kterých se
            // složil: popisek slibuje, kolik se toho zkopíruje. Přes `TextLines` (#295), aby to
            // platilo i tehdy, kdyby text nesl `CRLF` — `split(separator: "\n")` by na něm
            // nerozdělil a v menu by stálo „1 řádek“ nad celým rozsahem.
            let count = TextLines.all(text).count
            targets.append(DiffCopyTarget(
                id: "range",
                // Počet **je** v popisku, na rozdíl od značky u zkráceného úryvku (#158): tady
                // říká, kolik se toho zkopíruje, a to je rozdíl mezi „to je ono“ a „to je něco
                // jiného“ — rozsah není celý vidět, když přesahuje obrazovku.
                title: "Kopírovat rozsah (\(Plural.czech(count, one: "řádek", few: "řádky", many: "řádků")))",
                text: text
            ))
        }
        return targets
    }

    /// Hunk, ve kterém tenhle řádek leží. `nil` = řádek k žádnému nepatří.
    ///
    /// Slouží k tomu, aby se dal z kontextového menu řádku otevřít **celý jeho hunk** jako text
    /// k vybírání (#157) — v diffu jde vybrat jen v rámci bloku, který u bubliny končí, viz
    /// `CodeTextSheet`.
    static func hunk(containing line: DiffLine, in file: FileDiff) -> DiffHunk? {
        file.hunks.first { $0.lines.contains(line) }
    }

    /// Strana, ze které se kopíruje. Rozsah přes obě strany dává **novou** verzi.
    private static func copiedSide(of anchor: DraftAnchor) -> DiffSide {
        guard let start = anchor.start, start.side != anchor.side else { return anchor.side }
        return .right
    }

    /// Patří řádek ke kopírované straně? Odebraný řádek v nové verzi neexistuje a přidaný ve
    /// staré, takže se z opačné strany vynechají — kontextový řádek stojí na obou.
    private static func belongs(_ line: DiffLine, to side: DiffSide) -> Bool {
        switch side {
        case .right: line.kind != .removed
        case .left: line.kind != .added
        }
    }
}
