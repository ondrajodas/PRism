import Foundation
import Testing

@testable import PRism

/// **Uzel osy konverzace nesmí mít zpětnou vazbu z rozvržení** (#361, třinácté kolo).
///
/// Kolo z #361 hořelo v posledních třech záchvatech vždycky nad tabem `Konverzace` a pořád platí, že
/// se v harnessu vyrobit nedá — třináctý pokus je `LazySelfReferenceProbe`. Co se z něj **dá**
/// vytáhnout, je vylučování: tři třídy zpětné vazby z rozvržení do stavu (nebo do výběru varianty)
/// jsou v tomhle repu už popsané a **v podstromu uzlu osy ani jedna není**:
///
/// | Vzor | Proč by to bylo podezřelé |
/// |---|---|
/// | `onGeometryChange`, `onContinuousHover`, `.onHover` | zpětná vazba z každého snímku do `@State` (#358) |
/// | `GeometryReader` | měřená hodnota, která ovlivní to, co se měřilo |
/// | `ViewThatFits` | výběr varianty **podle šířky**, takže hodina o bod jinde je jiná výška |
/// | `ScrollViewReader` / `scrollTo` | kolo „posun → přeměření → posun“ (#325) |
///
/// Test to drží proto, aby to **nepřestalo platit potichu**. Kdyby čtrnácté kolo hledalo pohon
/// znovu, vyloučení z tohohle je platné jedině tehdy, když v ose od té doby žádný z těch vzorů
/// nepřibyl — a přibýt může docela nevinně (odznak, který se v úzkém uzlu nevejde, si o
/// `ViewThatFits` řekne sám).
///
/// **Osa je čtyři soubory, ne celý tab.** `ConversationView` sám `GeometryReader` **má** —
/// `fillingSlot()` je jím postavený a je tam schválně (#435). A `ThreadSnippetView` kreslí
/// `DiffLineView`, který `onGeometryChange` **v souboru pořád má**; do tohohle výčtu ale nepatří,
/// protože od #438 se ta closure na ose **nepřipojuje** — úryvek nedostane ani identitu řádku,
/// ani krabici pro tažení, takže se rámeček nepočítá vůbec (změřeno: 242 zásahů → 0). Hlídá to
/// `DiffLineGeometryTests`; tady se hlídají ty soubory, které skládají **uzel**.
///
/// Konstrukce je tatáž jako u `SingleWayOutTests` a `GraphSiteWiringTests`: tvrdí se to nad
/// zdrojáky a řádkové komentáře se zahazují, protože zrovna o těch vzorech se v repu píše v próze
/// (i v hlavičce tohohle testu).
@Suite("Osa konverzace bez zpětné vazby z rozvržení (#361)")
struct ConversationAxisFeedbackTests {
    /// Soubory, které skládají uzel osy — od uzlu dolů, bez `ConversationView` a `ThreadSnippetView`
    /// (důvod je v hlavičce suity).
    static let axis = [
        "ConversationNodeView",
        "ConversationEntryView",
        "ThreadBubbleView",
        "ConversationComposerView",
    ]

    /// Vzory, které v uzlu osy nesmí být. Každý je **vyjmenovaný**, ne odvozený z regexu nad vším:
    /// výčet je to, co se v hlášení dá přečíst.
    static let forbidden = [
        "onGeometryChange",
        "onContinuousHover",
        // **`onHover` je ve výčtu, i když je u něj gatování jen předpokládané** (#358): právě proto
        // tam patří. `onContinuousHover` ho jako podřetězec neobsahuje, takže jsou to dvě různá
        // tvrzení, ne jedno napsané dvakrát.
        "onHover",
        "GeometryReader",
        "ViewThatFits",
        "ScrollViewReader",
        "scrollTo(",
    ]

    @Test("V uzlu osy není žádná zpětná vazba z rozvržení")
    func theAxisHasNoLayoutFeedback() throws {
        for view in Self.axis {
            let code = try source(of: view)
            for pattern in Self.forbidden {
                #expect(
                    !code.contains(pattern),
                    "\(view) má \(pattern) — vyloučení z třináctého kola #361 tím přestalo platit"
                )
            }
        }
    }

    /// Kontrola měřidla: bez ní by prázdný nález mohl znamenat i „soubor se nenačetl“.
    ///
    /// Hledá se `HStack`, protože **uzel je `HStack`** (puntík a obsah) a právě jeho layout computer
    /// je v hořícím vzorku vidět jako `DynamicLayoutComputer<_HStackLayout>` — pětkrát, tedy jednou
    /// za viditelný uzel.
    @Test("Zdrojáky uzlu se doopravdy čtou")
    func theSourcesAreActuallyRead() throws {
        for view in Self.axis {
            let code = try source(of: view)
            #expect(code.count > 500, "\(view) vyšel prázdný, test netvrdí nic")
        }
        #expect(try source(of: "ConversationNodeView").contains("HStack"))
    }

    /// Zdroják view bez řádkových komentářů — tatáž konstrukce jako `LazyIdealSizeTests.source(of:)`.
    private func source(of view: String) throws -> String {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "App/Views/\(view).swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        return TextLines.content(text)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}
