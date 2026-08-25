import SwiftUI

extension View {
    /// Vyplní místo, které dostane — ale **velikost si nechá změřit**, místo aby ji vyjednával
    /// s okolím (#361).
    ///
    /// Patří na `ScrollView` s líným seznamem, který stojí v `VStack`u nebo `HStack`u.
    ///
    /// ## Co to řeší
    ///
    /// Stack rozděluje místo mezi děti, takže se každého dítěte **při každém rozvržení** ptá, jak
    /// je pružné — a ptá se toho hodně: naměřeno (`LazyIdealSizeProbe`) **29–33 dotazů na velikost**
    /// na jedno rozvržení (přesný počet se mezi běhy o pár liší, druh dotazů ne), z toho `nil×nil`
    /// (ideál), `0×0`, `0×∞`, `∞×0`, `∞×∞`, `520×0`, `520×∞` — a jen **4** se skutečnou velikostí.
    /// Pružný rámec nad `ScrollView`em všechny ty dotazy **předá dolů**, takže na každý z nich
    /// odpovídá líný seznam:
    ///
    /// ```
    /// StackLayout.UnmanagedImplementation.prioritize(_:proposedSize:)
    ///   _FlexFrameLayout.sizeThatFits(in:context:child:)
    ///     ScrollViewLayoutComputer.Engine.sizeThatFits(_:)
    ///       LazyVStackLayout.sizeThatFits(proposedSize:subviews:context:cache:)
    ///         LazyStack<>.measureEstimates(updatingPosition:index:minor:subviews:cache:)
    /// ```
    ///
    /// To je řada z **hořícího** kola u #361 (devátý záchvat, 1524 z 13 479 vzorků hlavního
    /// vlákna; v sedmém 4274 z 19 930). Podstatná na ní není cena, ale poslední jméno:
    /// `measureEstimates(updatingPosition:)` do líného seznamu **zapisuje** — sahá na tutéž
    /// měnitelnou krabici (`_LazyLayoutViewCache.withMutableCacheState`) jako `placeSubviews`,
    /// a změněné fáze položek z ní jdou do grafu **zvenčí**
    /// (`LazyLayoutViewCache.updateItemPhases` → `AG::Graph::value_set` → `propagate_dirty`,
    /// jediný externí zápis v celém vzorku). Dva zapisovatelé jedné krabice se v jednom kole
    /// nemusí shodnout — a pak se to kolo nemá kde zastavit.
    ///
    /// S měřenou velikostí dostane líný seznam **jen tu jednu, skutečnou**: ~30 dotazů → **4**,
    /// z toho tři se skutečnou velikostí. `GeometryReader` totiž svoje dítě na velikost neptá
    /// vůbec — vrací, co se navrhlo —, takže ty průzkumné dotazy končí u něj.
    ///
    /// ## Kolo z #361 to ale nezastavilo, a je to změřené (třinácté kolo)
    ///
    /// Tenhle modifikátor je **zlevnění, ne oprava** a text výš se dá číst jako opak, takže tady je
    /// to naměřené doslova. `measureEstimates` z hořícího kola **neodešel**: podíl na vzorcích
    /// hlavního vlákna byl **11,3 %** v devátém záchvatu (1524 z 13 479, ještě pružný rámec),
    /// **11,2 %** v jedenáctém (1046 z 9330, už s `fillingSlot()`) a **13,2 %** ve dvanáctém
    /// (2173 z 16 486). Co spadlo, je cena: dotazů na `ConversationRow.id` bylo 7,1 M → 3,6 M
    /// → 2,3 M.
    ///
    /// Zbývající dotaz **nejde odstranit žádným tvarem téhle štěrbiny**, protože o velikost si říká
    /// `ScrollView` sám: `ScrollViewUtilities.sizeThatFits(in:contentComputer:axes:)` se ptá svého
    /// obsahu, aby zjistil svou šířku. Změřeno na třech podobách (`LazySelfReferenceProbe`) —
    /// pružný rámec, `fillingSlot()` i `GeometryReader` **bez** vnitřního rámce mají ten dotaz
    /// všechny; **zarovnání v tom tedy nehraje roli**. Mění se jen to, odkud se ptá: pružný rámec
    /// si ho odpovídá jako **kořen** aktualizace (30 z 30 vzorků), měřená štěrbina **vnořeně**
    /// uvnitř cizí aktualizace (18 z 18).
    ///
    /// ## Zamítnutá varianta: vyplněný ideál
    ///
    /// Nabízelo se nechat pružný rámec a jen mu vyplnit `idealWidth`/`idealHeight` na nulu, aby
    /// na „jak velký bys chtěl být“ odpověděl sám. **Změřeno, nestačí to:** dotaz `nil×nil`
    /// zmizel, ale průzkum `0`/`∞` zůstal celý — 29 dotazů proti 29–33, tedy nic. Zápis do líného
    /// seznamu tedy zůstal, jen s jinými argumenty; do repa se to nedostalo právě proto. Sonda ten
    /// scénář měří dál (`TimelineShape.declaredIdeal`), aby to nebyl dohad.
    ///
    /// ## Kde to naopak nepatří
    ///
    /// Kde `ScrollView` velikost **už** dostává rámcem (`frame(width:height:)` u obsahu záložky,
    /// `frame(height:)` u živého výpisu kroků z #325), se nikdo na ideál neptá a modifikátor by
    /// jen přidal úroveň zanoření. Ověřeno tou samou sondou: `frame(width:height:)` průzkumné
    /// dotazy neposílá.
    func fillingSlot(alignment: Alignment = .center) -> some View {
        modifier(FillingSlot(alignment: alignment))
    }
}

private struct FillingSlot: ViewModifier {
    let alignment: Alignment

    func body(content: Content) -> some View {
        // Rozměr se předává **oběma** směry: `GeometryReader` je sám pružný (co se navrhne, to
        // vrátí), takže si od stacku vezme tolik místa jako `frame(maxWidth:maxHeight:)` dřív,
        // a dolů pošle konkrétní čísla.
        GeometryReader { proxy in
            content.frame(width: proxy.size.width, height: proxy.size.height, alignment: alignment)
        }
    }
}
