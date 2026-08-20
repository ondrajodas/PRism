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

    private var characterWidth: Double {
        NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            .maximumAdvancement.width
    }

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
    /// šířce jich vyjde **22**. Proto se nic nevynucuje: pohled si vybírá člověk a složit jde strom
    /// i panel.
    @Test("Vedle sebe se do zbylé šířky slib 120 znaků nevejde")
    func sideBySideCannotKeepThePromise() {
        let left = tabWidth - tree - panelDefault
        let split = charactersPerSide(left, layout: .split)

        #expect(split < Policy.promisedCharactersPerSide)
        // Naměřená hodnota, ne odhad — a kus pod ní strop, ať sada spadne na zhoršení, ne na
        // zaokrouhlení písma.
        #expect(split >= 20 && split <= 24, "vedle sebe: \(split) znaků na stranu")
    }

    /// Pod sebou je to **49 znaků**, tedy pořád málo na slib, ale čitelný kód — a to je ten důvod,
    /// proč se u commitu vystačí s `⌘1`/`⌘2` a nemusí se nic zakazovat.
    @Test("Pod sebou zbylá šířka na čitelný kód stačí")
    func unifiedStaysReadable() {
        let unified = charactersPerSide(tabWidth - tree - panelDefault, layout: .unified)

        #expect(unified >= 45 && unified <= 53, "pod sebou: \(unified) znaků")
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
    /// 1009 bodů, tedy **52 znaků** na stranu ve splitu — pořád méně než slíbených 120.
    @Test("Složení stromu i panelu dá nejvíc místa")
    func foldingBothGivesTheMostRoom() {
        let both = charactersPerSide(tabWidth - strip, layout: .split)
        let treeOnly = charactersPerSide(tabWidth - panelDefault, layout: .split)

        #expect(both > treeOnly)
        #expect(both >= 50 && both <= 55, "bez stromu se složeným proužkem: \(both) znaků")
    }

    /// Jak široké okno by slib 120 znaků na stranu **doopravdy** uneslo se stromem i panelem. Není to
    /// mez v aplikaci, je to číslo do dokumentace: `2 × (120 × 8,04 + 84) + 210 + 306 + 52`.
    @Test("Slib 120 znaků na stranu chce okno kolem 2700 bodů")
    func measuresTheWindowThePromiseWouldNeed() {
        let perSide = Double(Policy.promisedCharactersPerSide) * characterWidth
            + DiffLineView.contentInset(for: .split)
        let window = 2 * perSide + tree + panelDefault + 52

        #expect(window > 2600 && window < 2800, "okno: \(Int(window)) bodů")
    }

    /// **Podlaha panelu na podlaze okna** — nejužší stav, do kterého se aplikace dostane: okno 700,
    /// rail 52, panel 246. Na diff zbude 402 bodů, a i tam se musí sázet bez přetečení (hlídá to
    /// `PanelFreeTabWidthTests` v pásmu od 402).
    @Test("Nejužší stav dá na diff 402 bodů")
    func measuresTheNarrowestState() {
        #expect(700 - 52 - panelFloor == 402)
    }
}
