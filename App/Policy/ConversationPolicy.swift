import Foundation

/// Rozhodování nad konverzací. Čisté funkce, žádné I/O — testuje se bez mockování.
extension Policy {
    /// Je vlákno rozbalené?
    ///
    /// Výchozí stav se **odvozuje z vlákna**: nevyřešené je rozbalené, vyřešené sbalené.
    /// Množina drží jen ta vlákna, u kterých si to uživatel překlikl — kdyby se držel
    /// rovnou seznam rozbalených, muselo by se plnit při každém načtení konverzace a ruční
    /// obnovení by uživateli zahodilo, co si zavřel.
    static func isThreadExpanded(_ thread: ReviewThread, toggled: Set<String>) -> Bool {
        let flipped = toggled.contains(thread.id)
        return thread.isResolved ? flipped : !flipped
    }

    /// Vlákna, která se v diffu **nemají kde ukázat** — jejich řádek v aktuálním diffu není.
    ///
    /// Typicky zastaralá (`isOutdated`, tedy `line == nil`). Do bubliny nepatří, protože
    /// jejich čísla platila pro **starý head**: zakotvit je do aktuálního kódu by ukazovalo
    /// cizí řádky. Je to opačně než u nálezů, které se mimo diff ukazují u hlavičky souboru
    /// — nález je hlášený proti **současnému** commitu, takže jeho číslo pořád platí.
    ///
    /// Domov mají v tabu `Overview` (#72); tady se jen vyberou, ať se na ně nezapomene.
    static func threadsOutsideTheDiff(_ threads: [ReviewThread], renderedIn diff: Diff?) -> [ReviewThread] {
        threads.filter { !isAnchorable($0, in: diff) }
    }

    /// Vlákna, která v diffu kotvu mají — ta se kreslí jako bubliny.
    static func threadsInTheDiff(_ threads: [ReviewThread], renderedIn diff: Diff?) -> [ReviewThread] {
        threads.filter { isAnchorable($0, in: diff) }
    }

    /// Kotvit se dá jen podle **aktuálního** čísla řádku, ne podle `anchorLine`.
    ///
    /// `originalLine` je pravda o starém headu a slouží k tomu, aby se vlákno dalo pojmenovat
    /// v `Overview`. Kdyby se podle něj kreslila bublina, sedla by na řádek, který dnes
    /// obsahuje něco jiného.
    private static func isAnchorable(_ thread: ReviewThread, in diff: Diff?) -> Bool {
        guard thread.line != nil, let diff else { return false }
        guard let file = diff.files.first(where: { $0.newPath == thread.path || $0.oldPath == thread.path })
        else { return false }
        return file.hunks.contains { hunk in
            hunk.lines.contains { matches(thread, $0) }
        }
    }

    /// Patří vlákno k tomuhle řádku diffu?
    ///
    /// **Rozhoduje `side`.** U `right` se číslo porovnává s novým, u `left` se **starým** —
    /// komentář k odebranému řádku má číslo ze staré verze souboru. Porovnávat vždycky
    /// s novým znamená, že vlákno na smazaném řádku 26 sedne na **nový** řádek 26, tedy na
    /// jiný kód. Přesně kvůli tomu je `side` v modelu.
    ///
    /// Chybějící `side` se bere jako `right`: je to výchozí strana GitHubu a vlákno spíš
    /// ukázat u nového kódu než nikde.
    ///
    /// Je to **jediné místo**, kde se tohle rozhoduje — `DiffRow` ho používá při zavěšování
    /// bublin, takže se výběr a umístění nemůžou rozejít.
    static func matches(_ thread: ReviewThread, _ line: DiffLine) -> Bool {
        guard let number = thread.line else { return false }
        return switch thread.side ?? .right {
        case .right: line.newNumber == number
        case .left: line.oldNumber == number
        }
    }

    /// Vlákna, která patří tomuhle souboru, v pořadí podle řádku.
    ///
    /// Slovník pořadí nemá, takže bez toho by bubliny mezi překresleními poskakovaly —
    /// stejná past jako u nezakotvených nálezů. Při shodě řádku rozhoduje `id`, ať je
    /// pořadí úplné.
    ///
    /// Vlákno **bez** řádku (zastaralé) se řadí na začátek. Do bublin se nedostane, ale
    /// tahle funkce ho vrací taky — použije ji i `Overview` (#72), kde jsou zastaralá
    /// vlákna to hlavní.
    static func threads(of file: FileDiff, from threads: [ReviewThread]) -> [ReviewThread] {
        threads
            .filter { $0.path == file.newPath || $0.path == file.oldPath }
            .sorted { ($0.line ?? 0, $0.id) < ($1.line ?? 0, $1.id) }
    }
}
