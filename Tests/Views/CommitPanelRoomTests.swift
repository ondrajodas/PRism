import AppKit
import Foundation
import Testing

@testable import PRism

/// **Kolik místa zbude na diff commitu, když v `Commitech` stojí panel** (#392) — a co z toho
/// snese pohled *Vedle sebe*.
///
/// Zadání #392 to žádá změřit, protože na tom stojí jediné rozhodnutí: **vynucovat se nebude nic.**
/// Itinerář review se složí ⌘1, panel ⌘2 — ale kdyby se ukázalo, že se do rozloženého panelu vejde
/// i split se slibem 120 znaků, nebylo by o čem mluvit.
///
/// Počítá se **produkční funkcí** (`Policy.charactersPerSide`) a **skutečnými** rozměry: šířka
/// znaku z mono písma, kterým se kód sází, a `gutter` z `DiffLineView.contentInset(for:)`. Vlastní
/// aritmetika v testu by měřila svoji kopii pravidla.
@Suite("Místo na diff commitu vedle panelu (#392)")
struct CommitPanelRoomTests {
    /// Plocha tabu na výchozím okně: 1100 minus rail 52. Tatáž hodnota, ze které počítá zákres.
    private let tabWidth = 1047.0
    /// Levý sloupec, když je rozložený (`ReviewItineraryView`) — od #506 260 bodů, ne 210.
    private let tree = 260.0
    /// Panel: proužek, výchozí a strop. Rozložený si bere i šestibodový úchyt.
    private let strip = 38.0
    private let panelDefault = 306.0
    private let panelFloor = 246.0

    /// Šířka znaku mono písma, kterým se kód sází — **z `FontMetric`** (#407).
    ///
    /// Tahle jedna hodnota má za sebou tři léčby a je to celý příběh #407. Původně to byla computed
    /// property, takže se v jednom testu čítala dvakrát a mohla vyjít dvakrát jinak: v plném
    /// paralelním běhu z toho bylo `both → 0` proti `treeOnly → 35`, tedy **víc místa a méně
    /// znaků**, což z monotónní funkce vyjít nemůže. #367 z ní udělalo `let` instance (jedno čtení
    /// **na test**), #327 `static let` s náhradním měřením (jedno čtení **na proces**) — a pořád to
    /// byla léčba **v téhle sadě**, kterou si musela pamatovat i každá další. `LogTailHeightTests`
    /// a `DesignPillTests` si ji pamatovaly každá po svém.
    ///
    /// Odsud už je to **jedno volání**: měřidlo si hodnotu drží na proces, nikdy si nezapamatuje
    /// nulu a má na ni tři nezávislé cesty. Sada tedy o metrice **nemusí vědět nic** — a to je ten
    /// rozdíl mezi opravou třídy a opravou výskytu.
    ///
    /// **A od #550 se na ni ještě počká.** #407 zavedlo jedno měřidlo, ale nepovedené měření z něj
    /// vypadlo jako **nula** — takže tahle sada padala na `šířka znaku: 0`, zatímco hlášku k tomu
    /// pádu měřidlo o zlomek sekundy později skládalo už z 8,036. Nula tady není tvrzení
    /// o aplikaci, je to tvrzení o tom, co se v tu sekundu dělo v procesu, a to je zrovna ta
    /// třída pádů, kterou #367 zakazuje. `TestWait.settledFontMetric` se proto metriky **dočká**,
    /// a když ne, řekne to větou o metrice, ne číslem o šířce.
    private var characterWidth: Double {
        TestWait.settledFontMetric(
            .characterWidth,
            of: .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        )
    }

    private func charactersPerSide(_ width: Double, layout: DiffLayout) -> Int {
        Policy.charactersPerSide(
            contentWidth: width,
            characterWidth: characterWidth,
            layout: layout,
            gutter: DiffLineView.contentInset(for: layout)
        )
    }

    /// **S levým sloupcem i rozloženým panelem zbude na diff ~481 bodů.** To je to číslo, na kterém
    /// stojí zbytek suity — a **od #506 je o 50 bodů menší** (do té doby 531, se sloupcem 210
    /// z #197; zákres tehdy mluvil o ~537, rozdíl byl šestibodový úchyt panelu).
    @Test("Se sloupcem a panelem zbude na diff kolem 480 bodů")
    func measuresWhatIsLeftForTheDiff() {
        // **Ruční šířka se pinuje produkční funkcí** (tatáž oprava jako v render sondě, nález
        // Copilota na PR #558): čísla níž jsou napsaná ručně schválně (jsou to čísla do
        // dokumentace), ale rozejít se s aplikací potichu nesmí — po #506 by jinak celá suita
        // měřila sloupec, který v okně není.
        #expect(tree == Policy.treeColumnWidth(expanded: true))
        #expect(tabWidth - tree - panelDefault == 481)
        // Se složeným proužkem je to 749, bez sloupce a s proužkem 1009 — čísla, na kterých stojí
        // tvrzení níž. To poslední se #506 **nedotklo**: sloupec v něm složený není.
        #expect(tabWidth - tree - strip == 749)
        #expect(tabWidth - strip == 1009)
    }

    /// **Split to neunese, a je to změřené.** Slib z `CLAUDE.md` je 120 znaků na stranu; v téhle
    /// šířce jich při změřené šířce znaku vyjde **22**. Proto se nic nevynucuje: pohled si vybírá
    /// člověk a složit jde strom i panel.
    ///
    /// Tvrdí se **nerovnost proti slibu**, ne konkrétní počet: absolutní číslo závisí na šířce
    /// znaku, a tu drží vlastní tvrzení níž (`theMeasuredCharacterWidthHoldsTheNumbers`). Do prvního
    /// běhu tady stálo `split >= 20 && split <= 24` a v **plném paralelním běhu** to jednou spadlo —
    /// šířka znaku se v procesu, kde zároveň vzniká několik `NSHostingView`ů, může vyřešit jinak.
    /// Číslo, které se v harnessu pod zátěží mění, nesmí být tvrzením: mění se měřidlo, ne aplikace.
    @Test("Vedle sebe se do zbylé šířky slib 120 znaků nevejde")
    func sideBySideCannotKeepThePromise() {
        let left = tabWidth - tree - panelDefault
        let split = charactersPerSide(left, layout: .split)

        #expect(split < Policy.promisedCharactersPerSide, "vedle sebe: \(split) znaků na stranu")
        // A ještě daleko pod ním — kdyby se slib najednou plnil, bylo by to na tuhle šířku
        // podezřelé dřív, než by se to dalo přičítat písmu.
        #expect(split * 3 < Policy.promisedCharactersPerSide)
    }

    /// Pod sebou je toho **dvakrát tolik** než vedle sebe: řádek se nedělí na dvě strany. Pořád je
    /// to málo na slib, ale čitelný kód — a to je ten důvod, proč se u commitu vystačí s `⌘1`/`⌘2`
    /// a nemusí se nic zakazovat.
    ///
    /// Tvrdí se **poměr**, ne počet, ze stejného důvodu jako výš.
    @Test("Pod sebou je místa víc než vedle sebe")
    func unifiedStaysReadable() {
        let left = tabWidth - tree - panelDefault
        let unified = charactersPerSide(left, layout: .unified)
        let split = charactersPerSide(left, layout: .split)

        #expect(unified > split * 2, "pod sebou: \(unified), vedle sebe: \(split)")
        #expect(unified < Policy.promisedCharactersPerSide)
    }

    /// **Čísla v dokumentaci platí pro změřenou šířku znaku** (8,04 bodu). Je to jediné místo, kde
    /// se ta hodnota tvrdí — když se písmo v systému změní, spadne tenhle jeden test a řekne proč,
    /// místo aby se rozsypaly počty znaků v půlce suity.
    ///
    /// **Ve zprávě je i počet měření** (#407): kdyby se tahle třída měla ještě jednou vrátit, je
    /// z pádu vidět, jestli metrika sáhla po náhradní cestě, nebo jestli se nepovedla vůbec — bez
    /// toho je „šířka znaku: 0“ příznak bez příčiny, a přesně tak to u #327 vypadalo.
    @Test("Dokumentovaná čísla platí pro změřenou šířku znaku")
    func theMeasuredCharacterWidthHoldsTheNumbers() {
        #expect(abs(characterWidth - 8.04) < 0.5, "šířka znaku: \(characterWidth), \(FontMetric.shared.tally)")
        #expect(DiffLineView.contentInset(for: .split) == 84)
        #expect(DiffLineView.contentInset(for: .unified) == 136)
    }

    /// **Složený proužek je ta odpověď na úzké okno**: 749 bodů místo 481, tedy skoro dvojnásobek
    /// znaků na stranu ve splitu. Kdyby proužek nepomohl, nestačilo by u commitu složit panel a #392
    /// by musela panel v `Commitech` schovávat podle šířky.
    @Test("Složený proužek přidá skoro dvojnásobek znaků na stranu")
    func theCollapsedStripHelps() {
        let expanded = charactersPerSide(tabWidth - tree - panelDefault, layout: .split)
        let collapsed = charactersPerSide(tabWidth - tree - strip, layout: .split)

        #expect(collapsed > expanded * 3 / 2, "proužek: \(collapsed), panel: \(expanded)")
    }

    /// A druhá cesta: **složit levý sloupec** (⌘1) přidá 260 bodů (do #506 jich bylo 210). Obojí
    /// naráz (sloupec i panel složené) dá
    /// 1009 bodů, tedy při změřené šířce znaku **52** na stranu ve splitu — pořád méně než slíbených
    /// 120. Tvrdí se ta nerovnost a to, že je toho víc než při složeném stromu samotném.
    @Test("Složení stromu i panelu dá nejvíc místa")
    func foldingBothGivesTheMostRoom() {
        let both = charactersPerSide(tabWidth - strip, layout: .split)
        let treeOnly = charactersPerSide(tabWidth - panelDefault, layout: .split)

        #expect(both > treeOnly)
        #expect(both < Policy.promisedCharactersPerSide, "bez stromu se složeným proužkem: \(both)")
    }

    /// Jak široké okno by slib 120 znaků na stranu **doopravdy** uneslo se stromem i panelem. Není to
    /// mez v aplikaci, je to číslo do dokumentace: `2 × (120 × 8,04 + 84) + 260 + 306 + 52`.
    @Test("Slib 120 znaků na stranu chce okno kolem 2700 bodů")
    func measuresTheWindowThePromiseWouldNeed() {
        let perSide = Double(Policy.promisedCharactersPerSide) * characterWidth
            + DiffLineView.contentInset(for: .split)
        let window = 2 * perSide + tree + panelDefault + 52

        // Široké pásmo schválně: je to číslo do dokumentace, ne mez v aplikaci, a závisí na šířce
        // znaku — tu drží `theMeasuredCharacterWidthHoldsTheNumbers`.
        #expect(window > 2400 && window < 3000, "okno: \(Int(window)) bodů")
    }

    /// **Podlaha panelu na podlaze okna** — nejužší stav, do kterého se aplikace dostane: okno 700,
    /// rail 52, panel 246. Na diff zbude 402 bodů, a i tam se musí sázet bez přetečení (hlídá to
    /// `PanelFreeTabWidthTests` v pásmu od 402).
    @Test("Nejužší stav dá na diff 402 bodů")
    func measuresTheNarrowestState() {
        #expect(700 - 52 - panelFloor == 402)
    }
}
