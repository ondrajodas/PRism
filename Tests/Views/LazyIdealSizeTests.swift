import AppKit
import Foundation
import SwiftUI
import Testing

@testable import PRism

/// **Líný seznam ve `ScrollView`u nesmí dostávat průzkumné dotazy na velikost** (#361).
///
/// Kolo z #361 se v harnessu nepodařilo vyrobit ani jednou za devět záchvatů, takže test „už to
/// netuhne“ napsat nejde. Tvrdí se proto **vazba, ze které to kolo vzniká**: `VStack` a `HStack`
/// zjišťují pružnost dětí tím, že se jich ptají na velikost s `nil`, `0` a `∞`, a pružný rámec ty
/// dotazy nad `ScrollView`em **předá dolů** — takže na každý z nich odpovídá `LazyVStack`
/// funkcí `measureEstimates(**updatingPosition**:…)`, tedy zápisem do téže měnitelné krabice,
/// ze které kreslí `placeSubviews`. Dva zapisovatelé jedné krabice se v jednom kole nemusí
/// shodnout; v hořícím vzorku je tahle řada 1524 z 13 479 vzorků hlavního vlákna (a 4274
/// z 19 930 v sedmém záchvatu).
///
/// Testuje se to na scéně **stejného tvaru jako osa konverzace** (`TimelineShapedList`) a tím
/// **modifikátorem z aplikace** (`fillingSlot()`), ne jeho kopií — kdyby se `fillingSlot()`
/// vrátil k pružnému rámci, druhý test spadne. **Ověřeno vložením regrese**: s
/// `frame(maxWidth: .infinity, maxHeight: .infinity)` v `FillingSlot` spadne na `520×∞` a na
/// počtu dotazů (6 proti 3).
///
/// Pozn. k `nil×nil`: v harnessu **nepřijde** ani u pružného rámce, protože scéna je rozvržená
/// jednou a na konkrétní velikost. V okně přijde (sonda ho vidí 2×, `fittingSize` hostitele),
/// takže se na něj nedá tvrdit nic, co by platilo vždycky — hlídá se proto průzkum `0`/`∞`, a to
/// je i ten důležitější z těch dvou: vyplněný ideál `nil×nil` odstraní a průzkum ne (změřeno).
///
/// Čísla samotná (33 dotazů proti 4, histogram navržených velikostí) měří `LazyIdealSizeProbe`;
/// tady se tvrdí jen to, co má platit vždycky.
@MainActor
@Suite("Líný seznam a dotazy na velikost (#361)")
struct LazyIdealSizeTests {
    /// Kontrola měřidla: bez ní by nula ve druhém testu mohla znamenat i „sonda nic nevidí“.
    @Test("Pružný rámec posílá líným seznamem průzkumné dotazy")
    func flexibleFrameForwardsTheProbes() throws {
        let counter = try layout(shape: .flexible)
        #expect(
            counter.proposals.contains(where: { $0.contains("inf") }),
            "měřidlo nepočítá — pružný rámec průzkum s nekonečnem předat musí: \(counter.proposalSummary)"
        )
        #expect(
            counter.proposals.contains(where: { $0.hasSuffix("×0.0") }),
            "měřidlo nepočítá — pružný rámec průzkum s nulovou výškou předat musí: \(counter.proposalSummary)"
        )
    }

    /// **Hlavní tvrzení.** Nejen že nepřijde dotaz na ideál — nepřijde ani průzkum `0`/`∞`, tedy
    /// nic, na co by líný seznam odpovídal o jiné velikosti, než na jaké se doopravdy kreslí.
    @Test("fillingSlot() pošle líným seznamem jen skutečnou velikost")
    func fillingSlotForwardsOnlyTheRealSize() throws {
        let counter = try layout(shape: .declaredIdeal)
        #expect(
            !counter.proposals.contains(where: { $0.contains("nil") }),
            "dotaz na ideální velikost prošel k línému seznamu: \(counter.proposalSummary)"
        )
        #expect(
            !counter.proposals.contains(where: { $0.contains("inf") }),
            "průzkumný dotaz s nekonečnem prošel k línému seznamu: \(counter.proposalSummary)"
        )
        #expect(counter.idealHeight == 0)
        #expect(counter.idealWidth == 0)
        #expect(
            counter.proposals.count < 6,
            "dotazů je pořád moc, průzkum se jen převlékl: \(counter.proposalSummary)"
        )
    }

    /// **Výčet míst, kde ta vazba v aplikaci je.** Chování se dá otestovat jen na scéně, kterou
    /// si test postaví sám; že modifikátor doopravdy sedí tam, kde má, je vlastnost **struktury
    /// kódu** — a ta se tvrdí nad zdrojáky, jako u `SingleWayOutTests` a `GraphSiteWiringTests`.
    ///
    /// Výčet je šest líných seznamů ve `ScrollView`u, které stojí v `VStack`u nebo `HStack`u.
    /// Zbylé tři (`CommitListView`, `ReviewProgressView`, `StepFeedView`) v něm **nejsou
    /// schválně**: jejich `ScrollView` je korunou svého view a rozměr dostává rámcem, takže se
    /// nikdo na ideál neptá. Kdyby nad ně někdo vložil stack, patří tam modifikátor taky.
    @Test("Líné seznamy ve stacku mají fillingSlot()")
    func lazyListsInStacksCarryTheModifier() throws {
        let views = [
            "ConversationView",
            "DiffView",
            "FileTreeView",
            "ActivityFeedView",
            "ReviewPanel",
            "FindingsTableView",
        ]
        for view in views {
            let code = try source(of: view)
            #expect(
                code.contains("fillingSlot()"),
                "\(view) drží líný seznam ve stacku, ale rozměr si nenechává změřit"
            )
        }
    }

    /// Zdroják view bez řádkových komentářů — o modifikátoru se v repu mluví i v próze,
    /// a vysvětlení nemá test brát za doklad (tatáž konstrukce jako `GraphSiteWiringTests`).
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

    /// Rozvrhne scénu offscreen a vrátí, na co se během toho někdo ptal.
    ///
    /// **Okno drží tenhle scope**, ne pomocná funkce — tatáž úvaha jako u
    /// `DashboardFooterSeparatorTests`: `NSHostingView` bez okna nedostane rozvržení.
    private func layout(shape: TimelineShape) throws -> LazySizeCounter {
        let counter = LazySizeCounter()
        let width = 520.0
        let height = 380.0
        let hosting = NSHostingView(
            rootView: TimelineShapedList(counter: counter, shape: shape)
                .frame(width: width, height: height)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        #expect(counter.proposals.count > 0, "scéna se vůbec nerozvrhla, není co tvrdit")
        return counter
    }
}
