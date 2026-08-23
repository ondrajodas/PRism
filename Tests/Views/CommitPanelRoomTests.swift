import AppKit
import Foundation
import Testing

@testable import PRism

/// **Kolik místa zbude na diff commitu, když v `Commitech` stojí panel** (#392) — a co z toho
/// snese pohled *Vedle sebe*.
///
/// Zadání #392 to žádá změřit, protože na tom stojí jediné rozhodnutí: **vynucovat se nebude nic.**
/// Strom souborů se složí ⌘1, panel ⌘2 — ale kdyby se ukázalo, že se do rozloženého panelu vejde
/// i split se slibem 120 znaků, nebylo by o čem mluvit.
///
/// Počítá se **produkční funkcí** (`Policy.charactersPerSide`) a **skutečnými** rozměry: šířka
/// znaku z mono písma, kterým se kód sází, a `gutter` z `DiffLineView.contentInset(for:)`. Vlastní
/// aritmetika v testu by měřila svoji kopii pravidla.
@Suite("Místo na diff commitu vedle panelu (#392)")
struct CommitPanelRoomTests {
    /// Plocha tabu na výchozím okně: 1100 minus rail 52. Tatáž hodnota, ze které počítá zákres.
    private let tabWidth = 1047.0
    /// Strom souborů, když je rozložený (`FileTreeView`).
    private let tree = 210.0
    /// Panel: proužek, výchozí a strop. Rozložený si bere i šestibodový úchyt.
    private let strip = 38.0
    private let panelDefault = 306.0
    private let panelFloor = 246.0

    /// Šířka znaku mono písma, kterým se kód sází — **jedna hodnota na celý proces** (#367,
    /// dotaženo u #327).
    ///
    /// Původně to byla computed property, takže se v jednom testu čítala dvakrát a mohla vyjít
    /// dvakrát jinak: v plném paralelním běhu z toho bylo `both → 0` proti `treeOnly → 35`, tedy
    /// **víc místa a méně znaků**, což z monotónní funkce vyjít nemůže. #367 z ní udělalo `let`
    /// instance, tedy jedno čtení **na test** — a to nestačilo: Swift Testing staví na každý test
    /// vlastní instanci, takže se pod souběžným buildem několika slotů pořád trefil běh, ve kterém
    /// `maximumAdvancement` vyšlo **nulové** a spadl jeden ze čtyř poměrů (`pod sebou: 0, vedle
    /// sebe: 0`). Falešně červený `main` je horší než chybějící test, takže:
    ///
    /// - hodnota je **`static`**, tedy jedno čtení na proces — všechna tvrzení suity pak porovnávají
    ///   čísla z jednoho měřidla;
    /// - a když metrika nevyjde, **změří se text**, ne aby se dělilo nulou. Že se náhradou nezmění
    ///   čísla v dokumentaci, hlídá `theMeasuredCharacterWidthHoldsTheNumbers` — je to jediné místo,
    ///   které tu hodnotu tvrdí.
    private static let measuredCharacterWidth: Double = {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let advance = font.maximumAdvancement.width
        guard advance <= 0 else { return advance }
        return NSAttributedString(string: "0", attributes: [.font: font]).size().width
    }()

    private var characterWidth: Double { Self.measuredCharacterWidth }

    private func charactersPerSide(_ width: Double, layout: DiffLayout) -> Int {
        Policy.charactersPerSide(
            contentWidth: width,
            characterWidth: characterWidth,
            layout: layout,
            gutter: DiffLineView.contentInset(for: layout)
        )
    }

    /// **Se stromem i rozloženým panelem zbude na diff ~531 bodů** — zákres mluví o ~537, rozdíl je
    /// šestibodový úchyt panelu. To je to číslo, na kterém stojí zbytek suity.
    @Test("Se stromem a panelem zbude na diff kolem 530 bodů")
    func measuresWhatIsLeftForTheDiff() {
        #expect(tabWidth - tree - panelDefault == 531)
        // Se složeným proužkem je to 799, bez stromu a s proužkem 1009 — čísla, na kterých stojí
        // tvrzení níž.
        #expect(tabWidth - tree - strip == 799)
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
    @Test("Dokumentovaná čísla platí pro změřenou šířku znaku")
    func theMeasuredCharacterWidthHoldsTheNumbers() {
        #expect(abs(characterWidth - 8.04) < 0.5, "šířka znaku: \(characterWidth)")
        #expect(DiffLineView.contentInset(for: .split) == 84)
        #expect(DiffLineView.contentInset(for: .unified) == 136)
    }

    /// **Složený proužek je ta odpověď na úzké okno**: 799 bodů místo 531, tedy skoro dvojnásobek
    /// znaků na stranu ve splitu. Kdyby proužek nepomohl, nestačilo by u commitu složit panel a #392
    /// by musela panel v `Commitech` schovávat podle šířky.
    @Test("Složený proužek přidá skoro dvojnásobek znaků na stranu")
    func theCollapsedStripHelps() {
        let expanded = charactersPerSide(tabWidth - tree - panelDefault, layout: .split)
        let collapsed = charactersPerSide(tabWidth - tree - strip, layout: .split)

        #expect(collapsed > expanded * 3 / 2, "proužek: \(collapsed), panel: \(expanded)")
    }

    /// A druhá cesta: **složit strom** (⌘1) přidá 210 bodů. Obojí naráz (strom i panel složené) dá
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
    /// mez v aplikaci, je to číslo do dokumentace: `2 × (120 × 8,04 + 84) + 210 + 306 + 52`.
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
