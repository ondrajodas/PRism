import Foundation

/// Jedna položka konverzace v tabu `Přehled` — to, co se neváže k řádku v aktuálním diffu.
///
/// Tři různé věci v jednom seznamu, protože na GitHubu je člověk čte **za sebou**: schválení
/// kolegy, jeho poznámka pod PR a vlákno, které po novém commitu ztratilo kotvu. Rozdělit je
/// do tří sekcí by znamenalo skládat si časovou souslednost v hlavě.
enum ConversationEntry: Hashable, Sendable, Identifiable {
    /// Hotové review někoho jiného — verdikt, próza, nebo obojí.
    case review(SubmittedReview)
    /// Komentář pod PR, který nepatří k žádnému řádku.
    case comment(ThreadComment)
    /// Vlákno, které se v aktuálním diffu nemá kde ukázat (typicky zastaralé).
    case thread(ReviewThread)
    /// Co se na PR stalo (#171) — push, vyžádané review, merge.
    ///
    /// Patří do **téhož** seznamu, ne do vlastní sekce vedle: přehled odpovídá na „co se od
    /// minula stalo“ a push mezi dvěma komentáři je půlka té odpovědi.
    case event(TimelineEvent)

    /// Identita nese **typ**, ne jen `id` z GitHubu: review a komentář mají vlastní číselné
    /// řady a shoda mezi nimi by v `ForEach` zahodila jednu z položek.
    var id: String {
        switch self {
        case .review(let review): "r\(review.id)"
        case .comment(let comment): "c\(comment.id)"
        case .thread(let thread): "t\(thread.id)"
        case .event(let event): "e\(event.id)"
        }
    }

    /// Je to text, který si člověk **čte**?
    ///
    /// Události ne (#171): commit ani „vyžádal review“ není nic k přečtení, je to záznam děje.
    /// Na tom stojí odznak u záložky `Přehled`, který říká, kolik je toho k přečtení — bez
    /// tohohle rozdílu by na PR s dvaceti commity ukazoval třicet, tedy číslo, ze kterého se
    /// nedá poznat, že tam čekají tři komentáře.
    var isReadable: Bool {
        if case .event = self { false } else { true }
    }

    /// Kdy položka vznikla. `nil` = nevíme — rozdělané (`pending`) review datum odeslání
    /// nemá a vlákno bez komentářů se nemá čím datovat.
    var date: Date? {
        switch self {
        case .review(let review): review.submittedAt
        case .comment(let comment): comment.createdAt
        // Vlákno se datuje **prvním** komentářem, tedy tím, kdy se to téma otevřelo. Podle
        // poslední odpovědi by staré vlákno s novou odpovědí přeskočilo na konec a časová
        // souslednost by přestala platit.
        case .thread(let thread): thread.comments.items.first?.createdAt
        case .event(let event): event.at
        }
    }
}

/// Rozhodování nad konverzací. Čisté funkce, žádné I/O — testuje se bez mockování.
extension Policy {
    /// Co patří do tabu `Přehled`, chronologicky.
    ///
    /// Bere **jen** to, co u kódu nemá co dělat: vlákna bez kotvy v aktuálním diffu (ta
    /// s kotvou zůstávají bublinami), komentáře pod PR a review ostatních.
    ///
    /// **Review bez verdiktu a bez prózy se zahazuje.** Každý řádkový komentář na GitHubu
    /// patří do nějakého review, takže u PR s pěti komentáři u kódu přijdou i review, která
    /// nejsou tvrzením — jsou to obálky. Ukázat je jako „někdo napsal review: (nic)“ znamená
    /// seznam plný prázdných položek. Schválení s prázdným tělem se **nezahazuje**, to je
    /// plnohodnotný verdikt (čtvrtina vzorku u #63).
    ///
    /// Řadí se od nejstaršího, jako Overview na GitHubu. Položky bez data jdou **naspod** —
    /// nejsou součástí historie, protože se ještě nestaly (rozdělané review); při shodě
    /// rozhoduje `id`, ať je pořadí úplné a nepřeskakuje mezi překresleními.
    static func overview(of conversation: Conversation, renderedIn diff: Diff?) -> [ConversationEntry] {
        let reviews = conversation.reviews.items
            .filter { $0.isVerdict || !$0.body.isEmpty }
            .map { ConversationEntry.review($0) }
        let comments = conversation.comments.items.map { ConversationEntry.comment($0) }
        let threads = threadsOutsideTheDiff(conversation.threads.items, renderedIn: diff)
            .map { ConversationEntry.thread($0) }
        let events = displayableEvents(conversation.events.items).map { ConversationEntry.event($0) }

        return (reviews + comments + threads + events).sorted { first, second in
            switch (first.date, second.date) {
            case (let left?, let right?): left == right ? first.id < second.id : left < right
            case (nil, nil): first.id < second.id
            case (nil, _): false
            case (_, nil): true
            }
        }
    }
    /// Události, které se mají kreslit (#171).
    ///
    /// **Zavření se zahazuje, když je na PR i merge.** Mergnutím se pull request zavírá, takže
    /// GitHub kreslí jeden řádek — a dva („mergnul“ a pár sekund po něm „zavřel“) by tvrdily,
    /// že se staly dvě různé věci. Zavření **bez** mergnutí naopak zůstává: to je rozhodnutí
    /// PR nevzít, a to je zrovna informace, kterou je potřeba vidět.
    ///
    /// Nic dalšího se nefiltruje. Několik párů „vyžádal review / odebral“ za sebou je šum,
    /// který v provozu vzniká (`bin/copilot-review.sh`), ale je to **pravda o tom PR** —
    /// slévat je znamená rozhodovat, co je „tatáž“ událost, a to je rozhodnutí, které se dělá
    /// líp nad běžící aplikací než dopředu. Viz specifikace.
    static func displayableEvents(_ events: [TimelineEvent]) -> [TimelineEvent] {
        let isMerged = events.contains { if case .merged = $0.kind { true } else { false } }
        guard isMerged else { return events }
        return events.filter { $0.kind != .closed }
    }

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
