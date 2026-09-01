import Foundation
import Testing

@testable import PRism

/// Procházení výskytů a to, co pruh hledání říká (#152).
///
/// `Policy` je čistá funkce, takže se testuje **vyčerpávajícím výčtem**. Cenné jsou dvě věci:
/// že se `idle` a `empty` **neslijí** (prázdné pole není prázdný výsledek) a že prázdný stav
/// nikde neřekne „nic nenalezeno“ — nad nenačteným kódem to nemá čím podložit.
@Suite("Hledání v diffu — procházení a věty")
struct DiffSearchNavigationTests {
    // MARK: - Skok

    @Test("Bez výskytů není kam skočit")
    func noHitsNoStep() {
        #expect(Policy.searchStep(current: nil, total: 0, .forward) == nil)
        #expect(Policy.searchStep(current: nil, total: 0, .backward) == nil)
        #expect(Policy.searchStep(current: 3, total: 0, .forward) == nil)
    }

    /// Dokud se nikam neskočilo, míří `↓` na **první** výskyt a `↑` na **poslední**. Ne na nultý:
    /// než se skočí, člověk nikde nestojí.
    @Test("První skok jde na kraj, podle směru")
    func firstStepGoesToTheEdge() {
        #expect(Policy.searchStep(current: nil, total: 5, .forward) == 0)
        #expect(Policy.searchStep(current: nil, total: 5, .backward) == 4)
    }

    @Test("Krok jde po jednom")
    func stepsOneByOne() {
        #expect(Policy.searchStep(current: 0, total: 3, .forward) == 1)
        #expect(Policy.searchStep(current: 1, total: 3, .forward) == 2)
        #expect(Policy.searchStep(current: 2, total: 3, .backward) == 1)
    }

    /// Cyklení je rozhodnutí: hledání je průchod celým diffem, takže zastavit se na konci znamená,
    /// že se člověk musí vracet ručně.
    @Test("Na konci se cyklí dokola")
    func wrapsAround() {
        #expect(Policy.searchStep(current: 2, total: 3, .forward) == 0)
        #expect(Policy.searchStep(current: 0, total: 3, .backward) == 2)
    }

    /// Index mimo rozsah znamená „seznam se přeskládal“ — a pak platí totéž jako pro nikde:
    /// jde se na kraj, ne o jeden dál od hodnoty, která už nic neznamená.
    @Test("Index mimo seznam se bere jako nikde")
    func staleIndexIsNowhere() {
        #expect(Policy.searchStep(current: 9, total: 3, .forward) == 0)
        #expect(Policy.searchStep(current: -1, total: 3, .backward) == 2)
    }

    @Test("Jeden výskyt se skokem nehýbe")
    func singleHitStaysPut() {
        #expect(Policy.searchStep(current: 0, total: 1, .forward) == 0)
        #expect(Policy.searchStep(current: 0, total: 1, .backward) == 0)
    }

    // MARK: - Počítadlo

    /// **Ne `0 z 17`** — nula by tvrdila, že stojím na nultém výskytu.
    @Test("Před prvním skokem se píše jen počet")
    func counterBeforeTheFirstStep() {
        #expect(Policy.searchCounter(position: nil, total: 17) == ("17", " výskytů"))
        #expect(Policy.searchCounter(position: nil, total: 1) == ("1", " výskyt"))
        #expect(Policy.searchCounter(position: nil, total: 3) == ("3", " výskyty"))
    }

    /// Za `z` je druhý pád, samotný počet první — proto dvě různé sady tvarů, ne jedna.
    @Test("Po skoku se píše pozice i počet, česky")
    func counterAfterAStep() {
        #expect(Policy.searchCounter(position: 4, total: 17) == ("4", " z 17 výskytů"))
        #expect(Policy.searchCounter(position: 1, total: 1) == ("1", " z 1 výskytu"))
        #expect(Policy.searchCounter(position: 2, total: 3) == ("2", " z 3 výskytů"))
    }

    // MARK: - Stav pruhu

    @Test("Prázdné pole je `idle`, ne prázdný výsledek")
    func idleIsNotEmpty() {
        let empty = DiffSearchQuery(text: "")
        #expect(Policy.searchReport(query: empty, total: 0, current: nil) == .idle)
        // I kdyby v seznamu něco viselo, prázdné pole netvrdí nic.
        #expect(Policy.searchReport(query: empty, total: 5, current: 1) == .idle)
    }

    @Test("Dotaz bez výskytu je `empty`")
    func emptyResult() {
        #expect(Policy.searchReport(query: DiffSearchQuery(text: "nikde"), total: 0, current: nil) == .empty)
    }

    @Test("Pozice se počítá od jedničky")
    func positionIsOneBased() {
        let query = DiffSearchQuery(text: "x")
        #expect(Policy.searchReport(query: query, total: 3, current: 0) == .hits(position: 1, total: 3))
        #expect(Policy.searchReport(query: query, total: 3, current: 2) == .hits(position: 3, total: 3))
        #expect(Policy.searchReport(query: query, total: 3, current: nil) == .hits(position: nil, total: 3))
    }

    /// Stará pozice po přeskládání seznamu **nesmí ukazovat na cizí výskyt** — pruh pak řekne
    /// jen počet, jako před prvním skokem.
    @Test("Pozice mimo seznam se zapomíná")
    func stalePositionIsDropped() {
        let query = DiffSearchQuery(text: "x")
        #expect(Policy.searchReport(query: query, total: 3, current: 7) == .hits(position: nil, total: 3))
    }

    // MARK: - `↵` v poli

    /// **Nález z revize #152.** `onKeyPress(keys:)` dostane klávesu se **všemi** modifikátory, takže
    /// bezpodmínečné `.handled` by v poli spolklo i `⌘↵` a `⌃↵` — a ty v tomhle okně otevírají
    /// potvrzení odeslání review (#151, #441). Tvrdí se to výčtem, protože je to tvrzení o kolizi
    /// zkratek, ne o hledání.
    @Test("Čisté ↵ skáče, ⇧↵ zpátky, cokoli s ⌘/⌃/⌥ se propustí")
    func returnKeyYieldsToWindowShortcuts() {
        #expect(Policy.searchStepKey(modifiers: []) == .forward)
        #expect(Policy.searchStepKey(modifiers: .shift) == .backward)

        for modifiers: ShortcutModifiers in [
            .command, .control, .option,
            [.command, .shift], [.control, .shift], [.option, .shift],
            [.command, .option],
        ] {
            #expect(
                Policy.searchStepKey(modifiers: modifiers) == nil,
                "\(modifiers.glyphs)↵ si pruh nesmí vzít"
            )
        }
    }

    // MARK: - Věty o rozsahu

    /// **Tohle je to tvrzení, které chrání uživatele**: prázdný výsledek nesmí říct „nic
    /// nenalezeno“, protože mimo hunky se nehledalo. Kdyby někdo tu větu zjednodušil, spadne to
    /// tady, ne až u někoho v okně.
    @Test("Prázdný stav nikdy neřekne „nic nenalezeno“")
    func emptyNoteNeverOverclaims() {
        #expect(!Policy.searchEmptyNote.localizedCaseInsensitiveContains("nic nenalezeno"))
        #expect(Policy.searchEmptyNote.contains("mimo hunky"))
        #expect(Policy.searchEmptyHint.contains("kontext"))
    }

    @Test("Nápověda říká, co se hledá i co se nehledá")
    func scopeHelpSaysBothHalves() {
        #expect(Policy.searchScopeHelp.contains("hunkách"))
        #expect(Policy.searchScopeHelp.contains("rozbaleném kontextu"))
        #expect(Policy.searchScopeHelp.contains("nenačítá"))
        // Kapsle je krátká schválně — je to údaj k počtu, ne věta.
        #expect(Policy.searchScopeNote.count <= 14)
    }

    @Test("Kapsle v hlavičce souboru se skloňuje a bez výskytů se nekreslí")
    func fileLabel() {
        #expect(Policy.fileSearchLabel(0) == nil)
        #expect(Policy.fileSearchLabel(1) == "1 výskyt")
        #expect(Policy.fileSearchLabel(3) == "3 výskyty")
        #expect(Policy.fileSearchLabel(11) == "11 výskytů")
    }

    // MARK: - Zvýraznění

    @Test("Prázdný dotaz nezvýrazňuje nic")
    func noHighlightWithoutQuery() {
        let highlight = Policy.searchHighlight(query: DiffSearchQuery(text: ""), current: nil, in: "a.php")
        #expect(highlight == .none)
        #expect(!highlight.isActive)
    }

    /// **Aktuální výskyt se propouští jen do svého souboru.** `DiffLine` se mezi dvěma soubory umí
    /// shodovat (`}` s týmiž čísly), takže bez téhle podmínky by sytější podklad svítil na dvou
    /// místech naráz — a to je zrovna ta vada, kterou v okně nikdo nepřičte hledání.
    @Test("Aktuální výskyt patří jen svému souboru")
    func currentHitStaysInItsFile() {
        let line = DiffLine(kind: .context, oldNumber: 42, newNumber: 42, text: "}")
        let hit = DiffSearchHit(path: "a.php", line: line, occurrence: 0)
        let query = DiffSearchQuery(text: "}")

        let mine = Policy.searchHighlight(query: query, current: hit, in: "a.php")
        #expect(mine.current == hit)
        #expect(mine.isCurrent(line, occurrence: 0))

        let foreign = Policy.searchHighlight(query: query, current: hit, in: "b.php")
        #expect(foreign.current == nil)
        #expect(!foreign.isCurrent(line, occurrence: 0))
        // Zvýraznění ostatních výskytů ale platí i v cizím souboru — hledá se v celém diffu.
        #expect(foreign.isActive)
    }

    @Test("Aktuální je jen ten jeden výskyt na řádku")
    func onlyOneOccurrenceIsCurrent() {
        let line = DiffLine(kind: .added, oldNumber: nil, newNumber: 3, text: "$key = $key;")
        let highlight = Policy.searchHighlight(
            query: DiffSearchQuery(text: "$key"),
            current: DiffSearchHit(path: "a.php", line: line, occurrence: 1),
            in: "a.php"
        )
        #expect(!highlight.isCurrent(line, occurrence: 0))
        #expect(highlight.isCurrent(line, occurrence: 1))
    }

    // MARK: - Komu patří `⎋`

    /// `⎋` zavírá diff commitu (#317), ale s otevřeným pruhem hledání patří **pruhu** (#152).
    /// Vzorec je tentýž jako u `⌘⏎` v tabu `Zeptat se`: zkratka okna se zakáže a klávesa propadne.
    @Test("Esc ustoupí pruhu hledání")
    func escYieldsToTheSearchBar() {
        #expect(Policy.claimsCancelShortcut(diffSearchOpen: true))
        #expect(!Policy.claimsCancelShortcut(diffSearchOpen: false))

        #expect(Policy.canCloseCommit(
            tab: .commits,
            hasOpenedCommit: true,
            isSubmitting: false,
            isPaletteOpen: false,
            isDiffSearchOpen: false
        ))
        #expect(!Policy.canCloseCommit(
            tab: .commits,
            hasOpenedCommit: true,
            isSubmitting: false,
            isPaletteOpen: false,
            isDiffSearchOpen: true
        ))
    }

    /// Výčet zbylých podmínek — do #152 byly ve view jako `&&` a nešly projít testem.
    @Test("Esc zavírá commit jedině tehdy, když není komu jinému patřit")
    func closingTheCommitIsFenced() {
        #expect(!Policy.canCloseCommit(
            tab: .filesChanged, hasOpenedCommit: true, isSubmitting: false,
            isPaletteOpen: false, isDiffSearchOpen: false
        ))
        #expect(!Policy.canCloseCommit(
            tab: .commits, hasOpenedCommit: false, isSubmitting: false,
            isPaletteOpen: false, isDiffSearchOpen: false
        ))
        #expect(!Policy.canCloseCommit(
            tab: .commits, hasOpenedCommit: true, isSubmitting: true,
            isPaletteOpen: false, isDiffSearchOpen: false
        ))
        #expect(!Policy.canCloseCommit(
            tab: .commits, hasOpenedCommit: true, isSubmitting: false,
            isPaletteOpen: true, isDiffSearchOpen: false
        ))
    }
}
