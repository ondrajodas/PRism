import Foundation

extension Policy {
    /// Prvek lišty nad diffem, o kterém se v tísni rozhoduje (#593).
    ///
    /// Lišta rostla po kusech (#98, #187, #188, #197, #219, #524) a v podlahovém okně přetéká:
    /// v plné výbavě si říká o **923 bodů** do štěrbiny **572**. Do #593 ustupoval jediný prvek —
    /// `Popsat změny`, protože byl jako jediný bez `fixedSize()` —, takže o pořadí ustupování
    /// rozhodovalo to, v jakém pořadí se prvky do lišty přidávaly. **Tady je to výčet**: každý
    /// prvek má svou **sraženou podobu** (`diffToolbarFloor`), svou **stranu**
    /// (`diffToolbarSide`) a své **místo v pořadí** (`diffToolbarLadder`).
    ///
    /// Co si který bere, je změřené — tabulka je v `docs/testovani.md`, sekce *Kolik si který
    /// prvek lišty bere*.
    enum DiffToolbarItem: String, CaseIterable, Sendable {
        /// Přepínač pohledu `Vedle sebe` / `Pod sebou` (#98, #219).
        case layout
        /// Procházení nálezů (#187) — **jediný prvek, který neustoupí nikdy.**
        case navigation
        /// Varování o řádcích diffu, které se nepodařilo přečíst.
        case unreadable
        /// Varování o vláknech konverzace, která se nevešla k řádku.
        case missingThreads
        /// Ukazatel `98 znaků na stranu` (#188).
        case width
        /// `Popsat změny` (#524).
        case annotate
        /// `Hledat ⌘F` (#152).
        case search
        /// `Sbalit vše` / `Rozbalit vše` i s nabídkou pod šipkou (#219).
        case fold
    }

    /// Jak je prvek nakreslený, když se místa nedostává.
    ///
    /// Tři podoby, ne dvě — a je to ta část rozhodnutí, která se dá přečíst bez kreslení:
    /// **co se skládá na ikonu, co se zkracuje a co zůstane celé.**
    enum DiffToolbarForm: String, Sendable {
        /// Zůstane celý, ať je místa kolik chce.
        case full
        /// Zkrátí se text a zbytek věty se přesune do nápovědy — číslo v něm **zůstane**.
        case short
        /// Zbude ikona s nápovědou. Klikatelná dál; popisek by useknutý nesl půl slova
        /// a vypadal jako porucha (#524).
        case icon
    }

    /// Na které straně lišty prvek stojí. Rozhoduje o tom, **kdo se nikdy neusekává**: levá
    /// strana drží pohled a procházení, tedy to, čím se diff obsluhuje.
    enum DiffToolbarSide: String, Sendable {
        case leading
        case trailing
    }

    /// Na co se prvek srazí. `full` = neustoupí vůbec.
    ///
    /// - `navigation` je `full`, a je to jediný takový: je to **jediná věc v liště, která se
    ///   používá při každém review** (#219), a srazit se dá jedině tak, že se ubere počitadlo
    ///   nebo kapsle `jen blokující` — tedy že přestane dělat to, proč tam je.
    /// - `layout` se srazí na **ikony bez popisků**, a je až na konci pořadí: popisky jsou celý
    ///   důvod, proč to není `Picker(.segmented)` (#219).
    /// - `unreadable`, `missingThreads` a `width` se **zkracují**. Varování musí zůstat vidět
    ///   i s číslem; věta k němu se dá přečíst z nápovědy.
    /// - `annotate`, `search` a `fold` se skládají na **ikonu**: dvě z nich mají zkratku nebo
    ///   obecně známý symbol a třetí nese stav popiskem, který ikona unese taky (šipka nahoru
    ///   proti šipce dolů).
    static func diffToolbarFloor(_ item: DiffToolbarItem) -> DiffToolbarForm {
        switch item {
        case .navigation: .full
        case .unreadable, .missingThreads, .width: .short
        case .layout, .annotate, .search, .fold: .icon
        }
    }

    static func diffToolbarSide(_ item: DiffToolbarItem) -> DiffToolbarSide {
        switch item {
        case .layout, .navigation: .leading
        case .unreadable, .missingThreads, .width, .annotate, .search, .fold: .trailing
        }
    }

    /// **Pořadí ustupování**: kdo se srazí první, když se lišta nevejde.
    ///
    /// Vede ho jedna věta: **akce ustupují dřív než informace a věta ustupuje dřív než číslo.**
    ///
    /// 1. `annotate` — nejmladší přírůstek (#524), na jednom PR se pustí jednou a stav nese
    ///    i ikona (prstýnek za běhu, trojúhelník po selhání);
    /// 2. `search` — má zkratku (`⌘F`), takže popisek je pomůcka k nalezení myší, ne jediná
    ///    cesta; lupa je navíc symbol, který se nemusí vysvětlovat;
    /// 3. `fold` — pohodlí, které se použije jednou za PR, a stav unese šipka;
    /// 4. `width` — číslo zůstane, ubude `na stranu`;
    /// 5. `missingThreads`, 6. `unreadable` — nejdřív ta delší z obou vět (ta má i pokyn
    ///    `otevři PR na GitHubu`, který patří do nápovědy stejně dobře);
    /// 7. `layout` — **poslední**, protože popisky segmentů jsou to, co #219 z lišty vydobylo.
    ///
    /// `navigation` v pořadí **není**, a je to tvrzení, ne opomenutí.
    static let diffToolbarLadder: [DiffToolbarItem] = [
        .annotate, .search, .fold, .width, .missingThreads, .unreadable, .layout,
    ]

    /// Kolik místa musí prvku zůstat, i když se lišta nevejde ani po celém ustoupení.
    ///
    /// Je to **mez proti zmizení**: ikona `Popsat změny` je změřených 13 bodů, takže 22 nechá
    /// ikonu i s dechem a zaručí, že se na prvek dá pořád kliknout. Prvek, který se scvrkne na
    /// nulu, je prvek, který se ztratil — a přesně to se tady nesmí stát.
    static let diffToolbarItemFloor = 22.0

    /// Co si který prvek řekne a co z toho zbude (#593).
    ///
    /// **Rozměry se předávají změřené, nedohadují se** (#220, #236): `full` a `floor` měří ten,
    /// kdo kreslí (`DiffToolbarLayout` nad svými podviews), tahle funkce z nich jen **vybírá**.
    struct DiffToolbarMeasure: Equatable, Sendable {
        let item: DiffToolbarItem
        /// Co si prvek řekne celý.
        let full: Double
        /// Co si řekne ve své sražené podobě. Když se srazit neumí, je to totéž jako `full`.
        let floor: Double

        init(_ item: DiffToolbarItem, full: Double, floor: Double) {
            self.item = item
            self.full = full
            self.floor = floor
        }
    }

    /// Jak lišta vyjde: šířka pro každý prvek, kdo ustoupil a kdo se musel useknout.
    struct DiffToolbarRoom: Equatable, Sendable {
        /// Šířka, kterou se prvek nabídne. Klíčem je prvek, ne pořadí.
        let widths: [DiffToolbarItem: Double]
        /// Prvky kreslené ve sražené podobě.
        let conceded: Set<DiffToolbarItem>
        /// Prvky, kterým se ubralo **i pod** sraženou podobu — tedy useknuté. Prázdná množina je
        /// normální stav; neprázdná znamená, že se lišta nevejde ani po celém ustoupení.
        let truncated: Set<DiffToolbarItem>
        /// Kolik bodů zbylo. Nula znamená „vejde se přesně, nebo se nevejde vůbec“.
        let slack: Double

        func width(of item: DiffToolbarItem) -> Double { widths[item] ?? 0 }
    }

    /// Rozdělení místa v liště nad diffem.
    ///
    /// - Parameters:
    ///   - available: kolik místa zbývá **na prvky** — tedy bez odsazení lišty a bez mezer mezi
    ///     prvky. Počítá ho ten, kdo kreslí.
    ///   - measures: změřené šířky prvků, které se zrovna kreslí. Prvek, který v liště není,
    ///     v seznamu nebude — nabídka se skládá z toho, co na obrazovce je.
    ///
    /// Tři kroky, a každý se dá ověřit zvlášť:
    /// 1. **Vejde se to celé?** Pak se nic nesráží a `conceded` je prázdná.
    /// 2. **Pořadí ustupování** (`diffToolbarLadder`) — sráží se po jednom a **přestane se, jak
    ///    to stačí**. Prvek, který se srazit neumí (`floor == full`), se přeskočí, takže
    ///    nespotřebuje krok.
    /// 3. **Zbytek se usekne**, a jedině na pravé straně a nikdy pod `diffToolbarItemFloor`:
    ///    nejširší první, aby o tom, kdo přišel o body, nerozhodovalo pořadí kresby.
    static func diffToolbarRoom(available: Double, measures: [DiffToolbarMeasure]) -> DiffToolbarRoom {
        var widths: [DiffToolbarItem: Double] = [:]
        var floors: [DiffToolbarItem: Double] = [:]
        for measure in measures {
            widths[measure.item] = measure.full
            floors[measure.item] = measure.floor
        }
        var total = widths.values.reduce(0, +)

        var conceded: Set<DiffToolbarItem> = []
        for item in diffToolbarLadder where total > available {
            guard let full = widths[item], let floor = floors[item], floor < full else { continue }
            widths[item] = floor
            conceded.insert(item)
            total -= full - floor
        }

        var truncated: Set<DiffToolbarItem> = []
        while total > available {
            let cuttable = widths.filter { item, width in
                diffToolbarSide(item) == .trailing && width > diffToolbarItemFloor
            }
            // Nejširší první; při shodě rozhoduje jméno, ať je výsledek na pořadí kresby
            // nezávislý. Když už není odkud ubrat, lišta se nevejde a je to vidět — potichu
            // zmizet nesmí nic.
            guard let widest = cuttable.max(by: { ($0.value, $0.key.rawValue) < ($1.value, $1.key.rawValue) })
            else { break }
            let cut = min(total - available, widest.value - diffToolbarItemFloor)
            widths[widest.key] = widest.value - cut
            truncated.insert(widest.key)
            total -= cut
        }

        return DiffToolbarRoom(
            widths: widths,
            conceded: conceded,
            truncated: truncated,
            slack: max(available - total, 0)
        )
    }
}
