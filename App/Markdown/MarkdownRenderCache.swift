import Foundation
import Synchronization
import SwiftUI

/// Zapamatovaná sazba Markdownu (#279, pravidlo #224).
///
/// `MarkdownText` sází **v `body`**, tedy při každém vykreslení, a jsou v tom dvě drahé věci:
/// rozložení textu na bloky (od #279 s rekurzí v citacích) a inline sazba každého bloku
/// (`AttributedString(markdown:)`). Změřeno na skutečné zprávě od bota o 12 kB (Debug):
/// **1,91 ms** rozklad a **1,81 ms** inline nad jejími 44 bloky. Konverzace má desítky zpráv,
/// takže je to na každé překreslení desítky milisekund.
///
/// Obojí je přitom **funkce vstupu**: text komentáře se nemění a inline výsledek závisí jen na
/// textu a velikosti prózy. Vejde se to proto do téhož vzoru jako `SyntaxRunCache` — klíčem je
/// vstup, hodnotou hotový výsledek.
///
/// **Jedna cache na obojí, ne dvě.** Meze a jejich vyprazdňování jsou to, co se dá pokazit, a to
/// patří na jedno místo; dvě třídy by znamenaly dvě kopie téže disciplíny a příští oprava jen
/// v jedné z nich.
///
/// **Klíčem je celý text**, ne hash ani `(id komentáře, délka)`: klíč, ze kterého by dva různé
/// texty vyšly stejně, znamená vysázet cizí komentář — a potichu. U inline je součástí klíče
/// **i velikost**, protože v ní je zapečené písmo inline kódu; bez ní by komentář v okně
/// s novinkami dostal kód o půl bodu menší, a taky potichu.
///
/// **Barvy v tom nejsou zapečené.** `Palette.codeFill` je dynamický `NSColor`, který se vyhodnotí
/// až při kreslení, takže přepnutí světlého a tmavého režimu cache **nezneplatňuje** — tatáž
/// vlastnost, jakou má `SyntaxRunCache` díky tomu, že drží druh a ne `Color`.
///
/// **Co ji vyprazdňuje.** Po jednotlivých položkách nic; záznam nemůže zastarat, protože klíčem je
/// vstup. Drží ji dvě hranice a při překročení kterékoli se zahodí **celá** (je to O(1) a stojí
/// jeden přepočet toho, co je zrovna vidět): počet zapamatovaných záznamů (`capacity`) a součet
/// délek vstupů (`budget`). Dvě proto, že každá chytá jiný způsob, jak přetéct: dlouhé sezení nad
/// desítkami PR, nebo jeden komentář od bota s vygenerovanou tabulkou na sto kilobajtů. Vstup
/// delší než celý rozpočet se nepamatuje vůbec.
final class MarkdownRenderCache: Sendable {
    /// Cache, kterou používá `MarkdownText`. Sdílená schválně: tentýž popis PR se sází v přehledu
    /// i v potvrzení a tentýž komentář v konverzaci i v bublině u kódu.
    static let shared = MarkdownRenderCache()

    /// Kolik záznamů si cache nejvýš pamatuje — bloky a inline dohromady. Konverzace mívá desítky
    /// zpráv a každá zpráva desítky bloků, takže 4000 je řádově jedno dlouhé sezení.
    let capacity: Int
    /// Kolik bajtů vstupu si cache nejvýš pamatuje. Sčítá se **délka vstupů**, ne skutečná paměť;
    /// je to horní odhad toho, co z nich vzniklo, protože výsledek nese tentýž text jinak
    /// rozdělený.
    let budget: Int

    private let storage = Mutex(Storage())

    init(capacity: Int = 4000, budget: Int = 4 * 1024 * 1024) {
        self.capacity = capacity
        self.budget = budget
    }

    /// Bloky textu — zapamatované, nebo spočítané a zapamatované.
    func blocks(of text: String) -> [MarkdownBlock] {
        if let cached = storage.withLock({ $0.blocks[text] }) { return cached }

        let blocks = MarkdownParser.parse(text)
        remember(size: text.utf8.count) { $0.blocks[text] = blocks }
        return blocks
    }

    /// Inline sazba jednoho bloku — zapamatovaná, nebo spočítaná a zapamatovaná.
    func inline(_ source: String, size: Double) -> AttributedString {
        let key = InlineKey(source: source, size: size)
        if let cached = storage.withLock({ $0.inline[key] }) { return cached }

        let rendered = MarkdownInlineText.rendered(source, size: size)
        remember(size: source.utf8.count) { $0.inline[key] = rendered }
        return rendered
    }

    /// Kolik záznamů je zapamatovaných. Čte to test meze — v aplikaci se na to nikdo neptá.
    var count: Int {
        storage.withLock { $0.blocks.count + $0.inline.count }
    }

    /// Uloží záznam a přitom udrží meze. Zápis je zvlášť od obou cest schválně: hranice a jejich
    /// vyprazdňování je to, co se dá pokazit, takže má být jen jedno.
    private func remember(size: Int, _ insert: (inout Storage) -> Void) {
        // Vstup delší, než je celý rozpočet, se nepamatuje vůbec. Uložit ho znamená přetéct hned
        // a při dalším zápisu zahodit všechno — z cache by byla přihrádka na jeden komentář.
        guard size <= budget else { return }

        storage.withLock { storage in
            let before = storage.count
            // Meze se počítají **včetně toho, co se právě vkládá** — jinak by cache po vložení
            // stála nad rozpočtem až do příštího zápisu.
            if before + 1 > capacity || storage.bytes + size > budget { storage.clear() }
            insert(&storage)
            // Tentýž vstup můžou spočítat **dvě vlákna naráz** (obě minou nahlédnutí výš a obě
            // dojdou sem). To druhé už nic nepřidalo, takže se jeho délka nesmí započítat podruhé —
            // objem se proto zvedá podle skutečného přírůstku, ne podle toho, že se zapisovalo.
            // Jednovláknový test to nechytí: na druhé volání se vrací výsledek už z nahlédnutí, takže
            // sem nedojde. Je to tedy pojistka podle vzoru `SyntaxRunCache`, ne tvrzení s testem.
            if storage.count > before { storage.bytes += size }
        }
    }

    private struct Storage {
        var blocks: [String: [MarkdownBlock]] = [:]
        var inline: [InlineKey: AttributedString] = [:]
        /// Součet délek zapamatovaných vstupů, ne počet položek — viz `budget`.
        var bytes = 0

        var count: Int { blocks.count + inline.count }

        mutating func clear() {
            // `keepingCapacity`, protože přihrádky slovníku jsou zrovna to, co se za chvíli zase
            // zaplní; strop paměti drží `capacity`, ne uvolnění pole.
            blocks.removeAll(keepingCapacity: true)
            inline.removeAll(keepingCapacity: true)
            bytes = 0
        }
    }

    /// Velikost je v klíči, protože z ní vychází písmo inline kódu.
    private struct InlineKey: Hashable {
        let source: String
        let size: Double
    }
}
