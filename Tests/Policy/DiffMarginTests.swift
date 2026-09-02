import Testing

@testable import PRism

/// **Které karty v okraji jsou a kde stojí** (#503).
///
/// Dvě rozhodnutí, obojí čistá funkce, obojí vyčerpané výčtem:
///
/// 1. `marginCards` — karta vznikne jedině tam, kde má **co k čemu zarovnat**. Nález bez řádku,
///    nález na řádku mimo diff a nález ve sbaleném souboru v okraji nejsou; ty zůstávají tam, kde
///    byly dneska (bublina u hlavičky souboru, počet v hlavičce sbaleného souboru). Tvrzení o tom,
///    že tam **nejsou**, je ta cennější polovina: kdyby se tam dostaly, neměly by se kde postavit
///    a stály by na sobě.
/// 2. `marginTops` — odstrčení. Tvrdí se **jedna karta, dvě sousední, tři a karta bez polohy**,
///    jak si to vyžádalo zadání #503.
@Suite("Okraj s kartami nálezů (#503)")
struct DiffMarginTests {
    // MARK: - Které karty v okraji jsou

    /// Nález na řádku, který se kreslí, kartu má — a nese **klíč složený z cesty, kterou zná blok
    /// kódu**, ne z té, pod kterou nález přišel.
    @Test("Nález na řádku v hunku dostane kartu")
    func theAnchoredFindingGetsACard() {
        let cards = Policy.marginCards(of: [group(line: 3)], in: [source()])
        #expect(cards.map(\.id) == ["src/Handler.swift|3"])
        #expect(cards.map(\.line) == [3])
        #expect(cards.map(\.path) == ["src/Handler.swift"])
    }

    /// **Nález bez řádku kartu nedostane.** Nemá se k čemu zarovnat, takže by v okraji stál na
    /// nule — a přesně kvůli němu zůstává bublina u hlavičky souboru (`DiffRow.rows` ho kreslí
    /// i s vypnutým přepínačem).
    @Test("Nález bez řádku v okraji není")
    func theFindingWithoutALineIsNotInTheMargin() {
        #expect(Policy.marginCards(of: [group(line: nil)], in: [source()]).isEmpty)
    }

    /// **Nález na řádku, který se nekreslí, kartu nedostane.** Reviewer čte celý pracovní strom,
    /// takže nález na řádku mimo hunky je normální stav — a v okraji by tvrdil polohu řádku,
    /// který nikdo nekreslí.
    @Test("Nález na řádku mimo diff v okraji není")
    func theFindingOutsideTheDiffIsNotInTheMargin() {
        #expect(Policy.marginCards(of: [group(line: 900)], in: [source()]).isEmpty)
    }

    /// **Odkrytý kontext se počítá.** Nález mimo hunky si svůj kód umí dotáhnout (#47), a jak je
    /// řádek jednou vykreslený, karta se na něj zarovnat **musí** — jinak by nález, který jsem si
    /// odkryl, zůstal jediný bez karty.
    @Test("Nález na odkrytém řádku kartu dostane")
    func theRevealedFindingGetsACard() {
        var revealed = RevealedLines()
        revealed.reveal(898...902)
        let cards = Policy.marginCards(of: [group(line: 900)], in: [source(revealed: revealed)])
        #expect(cards.map(\.line) == [900])
    }

    /// **Odkrytí bez načteného obsahu se nepočítá** — tatáž úvaha jako v `DiffRow.rows`: bez
    /// obsahu se odkrytý řádek nekreslí, takže by karta mířila do prázdna. Volající proto posílá
    /// prázdné `revealed`; tohle tvrdí, že se na tom nic nedomýšlí.
    @Test("Odkrytý řádek bez obsahu kartu nedostane")
    func theRevealWithoutContentGetsNoCard() {
        #expect(Policy.marginCards(of: [group(line: 900)], in: [source()]).isEmpty)
    }

    /// **Sbalený soubor karty nemá.** Jeho řádky se nekreslí vůbec, takže by karty visely nad
    /// hlavičkou. Je to totéž, co dnes dělají bubliny — sbalením zmizí a zbude počet v hlavičce.
    @Test("Sbalený soubor karty nemá")
    func theFoldedFileHasNoCards() {
        #expect(Policy.marginCards(of: [group(line: 3)], in: [source(isFolded: true)]).isEmpty)
    }

    /// **Přejmenovaný soubor se pozná i podle staré cesty**, stejně jako u bublin: reviewer ho umí
    /// nahlásit pod tou, kterou měl dřív. Klíč karty ale nese **novou** cestu, protože pod ní se
    /// blok kódu hlásí.
    @Test("Nález pod starou cestou přejmenovaného souboru kartu dostane")
    func theRenamedFileIsFoundByItsOldPath() {
        let file = Self.renamed()
        let cards = Policy.marginCards(
            of: [FindingGroup(file: "src/Old.swift", line: 3, findings: [Self.finding()])],
            in: [DiffMarginSource(file: file, revealed: RevealedLines(), isFolded: false)]
        )
        #expect(cards.map(\.id) == ["src/New.swift|3"])
    }

    /// Karty jsou **v pořadí obsahu**: po souborech, jak jsou v diffu, a v nich po řádcích. Na tom
    /// stojí odstrkování — z jiného pořadí by karty odstrkovaly nazpátek.
    @Test("Karty jdou po souborech a v nich po řádcích")
    func theCardsFollowTheContent() {
        let diff = DiffParser.parse(Self.twoFiles())
        let sources = diff.files.map {
            DiffMarginSource(file: $0, revealed: RevealedLines(), isFolded: false)
        }
        let groups = [
            FindingGroup(file: "src/Second.swift", line: 2, findings: [Self.finding()]),
            FindingGroup(file: "src/First.swift", line: 4, findings: [Self.finding()]),
            FindingGroup(file: "src/First.swift", line: 2, findings: [Self.finding()]),
        ]
        #expect(Policy.marginCards(of: groups, in: sources).map(\.id) == [
            "src/First.swift|2",
            "src/First.swift|4",
            "src/Second.swift|2",
        ])
    }

    /// Závažnost: blokující, platný a odmítnutý. **Odmítnutá skupina kartu neztrácí, jen ztichne**
    /// (#113) — schovaný nález se nedá přečíst a nedá se odlišit od neexistujícího.
    @Test(
        "Závažnost karty",
        arguments: [
            (category: "correctness", dismissed: false, expected: DiffMarginSeverity.blocking),
            (category: "style", dismissed: false, expected: .finding),
            (category: "correctness", dismissed: true, expected: .dismissed),
        ]
    )
    func theSeverityOfACard(sample: (category: String, dismissed: Bool, expected: DiffMarginSeverity)) {
        let finding = Self.finding(category: sample.category)
        var group = FindingGroup(file: "src/Handler.swift", line: 3, findings: [finding])
        if sample.dismissed {
            group.dismissals = [
                Policy.key(of: finding): FindingDismissal(reason: .invalid, dismissedAt: .now),
            ]
        }
        let cards = Policy.marginCards(of: [group], in: [source()])
        #expect(cards.map(\.severity) == [sample.expected])
    }

    /// Značky pro blok kódu jsou **klíčované novým číslem řádku** a filtrované na jeho soubor:
    /// blok o kartách nic neví, zná jen řádky.
    @Test("Značky se překládají na čísla řádků jednoho souboru")
    func theMarksTranslateToLineNumbers() {
        let cards = [
            DiffMarginCard(id: "a|3", group: group(line: 3), path: "a", line: 3, severity: .blocking),
            DiffMarginCard(id: "b|7", group: group(line: 7), path: "b", line: 7, severity: .finding),
        ]
        let marks = Policy.marginMarks(of: cards, in: "a")
        #expect(marks.keys.sorted() == [3])
        #expect(marks[3]?.id == "a|3")
        #expect(marks[3]?.severity == .blocking)
    }

    // MARK: - Co zmizí z diffu

    /// **Se zapnutým okrajem se zakotvený nález pod řádek nevěší** — kód zůstane souvislý, a to
    /// je celý #503. Tvrzení o tom, že se něco **nestalo**: kdyby bublina zůstala, byl by tentýž
    /// nález na obrazovce dvakrát a kód by se dál čtl přes díry.
    @Test("Bez bublin nemá diff řádek nálezu")
    func theMarginLeavesTheCodeContinuous() {
        let diff = DiffParser.parse(Self.material())
        let rows = DiffRow.rows(
            of: diff.files[0],
            findings: [group(line: 3)],
            inlineFindings: false
        )
        #expect(!rows.contains { if case .finding = $0 { true } else { false } })
        // A obráceně: se zapnutým přepínačem tam ten řádek **být musí**, jinak by tvrzení výš
        // platilo nad prázdnem.
        let inline = DiffRow.rows(
            of: diff.files[0],
            findings: [group(line: 3)],
            inlineFindings: true
        )
        #expect(inline.contains { if case .finding = $0 { true } else { false } })
    }

    /// **Nález bez řádku zůstává i bez bublin**, protože v okraji se nemá k čemu zarovnat: visí
    /// u hlavičky souboru a nabízí svůj řádek dotáhnout. Bez tohohle pravidla by se vypnutím
    /// přepínače tiše ztratil — a tiše zmizelý nález vypadá jako čistý PR.
    @Test("Nezakotvený nález zůstává u hlavičky i bez bublin")
    func theUnanchoredFindingSurvivesWithoutBubbles() {
        let diff = DiffParser.parse(Self.material())
        for group in [group(line: nil), group(line: 900)] {
            let rows = DiffRow.rows(of: diff.files[0], findings: [group], inlineFindings: false)
            let anchored = rows.compactMap { row -> Bool? in
                guard case .finding(_, _, let anchored) = row else { return nil }
                return anchored
            }
            #expect(anchored == [false], "nález \(group.line.map(String.init) ?? "bez řádku") zmizel")
        }
    }

    // MARK: - Zarovnání a odstrčení

    /// **Jedna karta stojí na výšce svého řádku** — přesně na ní, bez korekce.
    @Test("Jedna karta stojí na svém řádku")
    func oneCardStandsOnItsRow() {
        #expect(Policy.marginTops(desired: [420], heights: [96], gap: 8) == [420])
    }

    /// **Dvě karty, které se nepotkají, stojí každá na svém řádku.** Bez toho tvrzení by
    /// odstrkování mohlo být bezpodmínečné a karty by se vždycky slepily pod sebe.
    @Test("Karty daleko od sebe se neodstrkují")
    func distantCardsAreNotPushed() {
        #expect(Policy.marginTops(desired: [100, 400], heights: [96, 96], gap: 8) == [100, 400])
    }

    /// **Dvě karty na sousedních řádcích: druhá jde níž.** Tolik, aby se nepřekryly — o výšku
    /// první a mezeru.
    @Test("Druhá karta na sousedním řádku jde níž")
    func theSecondCardIsPushedDown() {
        #expect(Policy.marginTops(desired: [100, 118], heights: [96, 60], gap: 8) == [100, 204])
    }

    /// **A tři se odstrkují po řetězu** — třetí se posune o obě nad sebou, ne jen o tu poslední
    /// požadovanou polohu.
    @Test("Tři karty na sousedních řádcích se odstrkují po řetězu")
    func threeCardsPushInAChain() {
        #expect(Policy.marginTops(
            desired: [100, 118, 136],
            heights: [96, 60, 60],
            gap: 8
        ) == [100, 204, 272])
    }

    /// **Karta pod tou odstrčenou se vrátí ke svému řádku**, jak to jde: odstrčení je lokální,
    /// ne posun celého okraje.
    @Test("Odstrčení nepokračuje dál, než je potřeba")
    func thePushDoesNotLeak() {
        #expect(Policy.marginTops(
            desired: [100, 118, 900],
            heights: [96, 60, 60],
            gap: 8
        ) == [100, 204, 900])
    }

    /// **Karta bez polohy jde za předchozí, nezmizí.** Polohu řádku hlásí blok kódu, takže na
    /// první rozvržení (a u bloku, který se nikdy nekreslil) ji karta nemá — a „nevím kde“ je
    /// pořád lepší odpověď než „na nule“ nebo „nikde“.
    @Test("Karta bez ohlášené polohy jde za předchozí")
    func theCardWithoutASpotFollowsThePrevious() {
        #expect(Policy.marginTops(
            desired: [100, nil, nil],
            heights: [96, 60, 60],
            gap: 8
        ) == [100, 204, 272])
    }

    /// A první karta bez polohy stojí **na nule**, ne nad diffem: obsah začíná tam.
    @Test("První karta bez polohy stojí na začátku obsahu")
    func theFirstCardWithoutASpotStandsAtZero() {
        #expect(Policy.marginTops(desired: [nil], heights: [96], gap: 8) == [0])
    }

    /// **Nahoru se karta neodstrkuje.** Řádek, který je nad předchozí kartou, přijít nemůže
    /// (karty jsou v pořadí obsahu), ale kdyby se ta věta rozbila, mělo by to spadnout tady —
    /// karta nad předchozí by se překryla a čte se odshora.
    @Test("Karta se neodstrkuje nahoru")
    func theCardIsNeverPushedUp() {
        #expect(Policy.marginTops(desired: [400, 100], heights: [96, 60], gap: 8) == [400, 504])
    }

    /// **Nezměřená karta o sousedovi netvrdí nic** — chybějící výška se bere jako nula, takže
    /// odstrčení nepřežene. Vstup kratší než `desired` je stav z prvního rozvržení.
    @Test("Chybějící výška odstrkování nepřežene")
    func theMissingHeightDoesNotOverPush() {
        #expect(Policy.marginTops(desired: [100, 118], heights: [], gap: 8) == [100, 118])
    }

    @Test("Prázdný vstup dá prázdný výstup")
    func theEmptyInputStaysEmpty() {
        #expect(Policy.marginTops(desired: [], heights: [], gap: 8).isEmpty)
    }

    // MARK: - Postranní sloupce

    /// **Pohled vedle sebe složí oba sloupce** (#188) a **okraj s kartami složí panel** (#503):
    /// vpravo by jinak stály dvě třistabodové kolony o téže věci.
    @Test(
        "Které postranní sloupce jsou rozložené",
        arguments: [
            (layout: DiffLayout.unified, margin: false, tree: true, panel: true),
            (layout: .unified, margin: true, tree: true, panel: false),
            (layout: .split, margin: false, tree: false, panel: false),
            (layout: .split, margin: true, tree: false, panel: false),
        ]
    )
    func theSideColumns(sample: (layout: DiffLayout, margin: Bool, tree: Bool, panel: Bool)) {
        let columns = Policy.diffSideColumns(layout: sample.layout, hasMargin: sample.margin)
        #expect(columns.tree == sample.tree)
        #expect(columns.panel == sample.panel)
    }

    // MARK: - Materiál

    private func group(line: Int?) -> FindingGroup {
        FindingGroup(file: "src/Handler.swift", line: line, findings: [Self.finding()])
    }

    private func source(revealed: RevealedLines = RevealedLines(), isFolded: Bool = false) -> DiffMarginSource {
        let diff = DiffParser.parse(Self.material())
        return DiffMarginSource(file: diff.files[0], revealed: revealed, isFolded: isFolded)
    }

    private static func finding(category: String = "correctness") -> Finding {
        Finding(
            reported: ReportedFinding(
                file: "src/Handler.swift",
                line: 3,
                category: category,
                verdict: .confirmed,
                shortSummary: nil,
                summary: "Prázdný fallback schová chybějící hodnotu.",
                failureScenario: nil
            ),
            reviewer: "php-review",
            headSha: "aaaa1111"
        )
    }

    /// Jeden soubor, jeden hunk o pěti řádcích na začátku souboru — takže řádek 900 v diffu
    /// **není** a dá se na něm tvrdit ten druhý případ.
    private static func material() -> String {
        """
        diff --git a/src/Handler.swift b/src/Handler.swift
        index 1111111..2222222 100644
        --- a/src/Handler.swift
        +++ b/src/Handler.swift
        @@ -1,5 +1,5 @@ func handle()
         let a = 1
         let b = 2
        -let c = 3
        +let c = 4
         let d = 5

        """
    }

    private static func twoFiles() -> String {
        """
        diff --git a/src/First.swift b/src/First.swift
        index 1111111..2222222 100644
        --- a/src/First.swift
        +++ b/src/First.swift
        @@ -1,5 +1,5 @@ func first()
         let a = 1
         let b = 2
         let c = 3
         let d = 4
         let e = 5
        diff --git a/src/Second.swift b/src/Second.swift
        index 3333333..4444444 100644
        --- a/src/Second.swift
        +++ b/src/Second.swift
        @@ -1,3 +1,3 @@ func second()
         let x = 1
         let y = 2
         let z = 3

        """
    }

    private static func renamed() -> FileDiff {
        let diff = DiffParser.parse("""
        diff --git a/src/Old.swift b/src/New.swift
        similarity index 90%
        rename from src/Old.swift
        rename to src/New.swift
        index 1111111..2222222 100644
        --- a/src/Old.swift
        +++ b/src/New.swift
        @@ -1,5 +1,5 @@ func handle()
         let a = 1
         let b = 2
        -let c = 3
        +let c = 4
         let d = 5

        """)
        return diff.files[0]
    }
}
