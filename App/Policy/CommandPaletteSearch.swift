import Foundation

/// Hledání v paletě ⌘K (#184) — jediné místo, kde se rozhoduje, co na dotaz sedne, v jakém
/// pořadí to je a kolik z toho je vidět.
///
/// Je to čistá funkce nad hotovým katalogem (`[CommandPalette.Item]`), takže se testuje
/// vyčerpávajícím výčtem a bez kreslení. Ve view nesmí zůstat žádné `if` nad výsledky —
/// `CommandPaletteView` jen sází to, co odsud vypadne.
extension Policy {
    /// Kolik řádků se ukáže z jedné skupiny.
    ///
    /// Strop je na **skupinu, ne na celek**: bez něj by dvacet nálezů vytlačilo z okna soubory,
    /// pull requesty i akce, tedy zrovna to, kvůli čemu je paleta jedno pole na všechno.
    /// Šest je tolik, kolik se vejde, aniž by se ostatní skupiny odscrollovaly pod okraj.
    ///
    /// **Na tomhle stropu stojí i rozdělení pull requestů na dvě skupiny** (#336): ve společné
    /// skupině by při dvaceti cizích PR to moje nemuselo vyjít vůbec, protože šestý řádek je
    /// strop a řadí se podle váhy shody. Vlastní skupina má svých šest.
    static let paletteGroupLimit = 6

    /// Výsledky pro dotaz, po skupinách.
    ///
    /// Prázdný dotaz **není prázdný výsledek**: paleta se otevírá jako nabídka toho, co je po
    /// ruce, takže se ukáže začátek každé skupiny v pořadí, ve kterém katalog přišel (nálezy od
    /// nejvážnějšího, soubory v pořadí diffu, cizí i vlastní PR od naposledy změněného, akce
    /// v pevném pořadí).
    ///
    /// Skupina, ve které nic nesedlo, **vypadne celá** — nadpis nad prázdnem by tvrdil, že se
    /// hledalo a nic není, i tam, kde se hledat nemělo kde.
    static func paletteResults(
        of items: [CommandPalette.Item],
        query: String,
        limit: Int = paletteGroupLimit
    ) -> [CommandPalette.Section] {
        let tokens = paletteTokens(in: query)
        // Původní pořadí se nese s sebou jako `order`, protože Swiftové `sorted` **není
        // stabilní**: bez druhého kritéria by dvě položky se stejnou váhou přeskakovaly mezi
        // stisky klávesy.
        let ranked = items.enumerated().compactMap { order, item -> RankedHit? in
            guard let match = paletteMatch(item, tokens: tokens) else { return nil }
            return RankedHit(
                hit: CommandPalette.Hit(
                    item: item,
                    titleHighlight: match.title,
                    subtitleHighlight: match.subtitle
                ),
                rank: match.rank,
                order: order
            )
        }

        return CommandPalette.Group.allCases.compactMap { group in
            let hits = ranked
                .filter { $0.hit.item.group == group }
                .sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }
                .prefix(limit)
                .map(\.hit)
            return hits.isEmpty ? nil : CommandPalette.Section(group: group, hits: Array(hits))
        }
    }

    /// Dotaz rozsekaný na slova. Prázdné pole znamená „ber všechno“.
    ///
    /// Víc slov se bere jako **a zároveň**: `vault secret` má najít nález se slovem `secret`
    /// v repu `vault`, i když v titulku ani v podtitulku ta dvě slova vedle sebe nestojí.
    /// Jedno slovo jako celý řetězec by tuhle kombinaci nenašlo nikdy.
    static func paletteTokens(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Váha položky a místa shody. `nil` = nesedí.
    ///
    /// Váha je **nejlepší** ze slov dotazu: stačí, aby se jedno z nich potkalo s začátkem
    /// titulku, a řádek jde nahoru. Nejhorší z nich by naopak srazila silnou shodu kvůli slovu,
    /// které sedlo „jen“ na repo v podtitulku.
    private static func paletteMatch(
        _ item: CommandPalette.Item,
        tokens: [String]
    ) -> PaletteMatch? {
        guard !tokens.isEmpty else { return PaletteMatch(rank: paletteCatalogRank) }

        var best = Int.max
        var title: Range<String.Index>?
        var subtitle: Range<String.Index>?
        for token in tokens {
            guard let match = paletteMatch(token, in: item) else { return nil }
            best = min(best, match.rank)
            // Zvýrazní se **první** slovo, které se potkalo — v každém textu zvlášť, takže
            // `vault secret` umí zvýraznit repo v podtitulku i slovo v titulku. Víc úseků
            // v jednom textu by ho rozsekalo na skvrny; na jeden řádek je to šum.
            if title == nil { title = match.title }
            if subtitle == nil { subtitle = match.subtitle }
        }
        return PaletteMatch(rank: best, title: title, subtitle: subtitle)
    }

    /// Váha jednoho slova proti položce.
    ///
    /// Pořadí kritérií: začátek titulku, začátek slova v titulku, cokoli v titulku, podtitulek,
    /// klíčové slovo. Je to pořadí podle toho, jak **jistá** ta shoda je — `Secret` na začátku
    /// jména souboru znamená víc než `secret` uprostřed věty, a shoda v titulku znamená víc než
    /// shoda v autorovi nebo v repu. Bez toho by dotaz na slovo z titulku vytáhl nahoru cizí PR
    /// od stejně pojmenovaného autora.
    private static func paletteMatch(
        _ token: String,
        in item: CommandPalette.Item
    ) -> PaletteMatch? {
        if let range = paletteRange(of: token, in: item.title) {
            if range.lowerBound == item.title.startIndex { return PaletteMatch(rank: 0, title: range) }
            return PaletteMatch(rank: paletteStartsWord(at: range, in: item.title) ? 1 : 2, title: range)
        }
        // Podtitulek má **jednu** váhu, ne tři jako titulek. Je to výčet dvou souřadnic
        // (`vault#85 · sykora-ji`), takže „začátek“ v něm znamená repo a „vnitřek“ autora — a mezi
        // těmi dvěma se nemá rozhodovat podle pozice v řetězci. Váhy oddělují **druh** shody.
        if let subtitle = item.subtitle, let range = paletteRange(of: token, in: subtitle) {
            return PaletteMatch(rank: 3, subtitle: range)
        }
        if item.keywords.contains(where: { paletteRange(of: token, in: $0) != nil }) {
            return PaletteMatch(rank: 4)
        }
        return nil
    }

    /// Váha a místa shody jednoho slova (nebo celé položky, po sloučení přes slova dotazu).
    private struct PaletteMatch {
        let rank: Int
        /// Rozsahy jsou `var` kvůli implicitnímu `nil` v memberwise initu: shoda v klíčovém slově
        /// nemá kde zvýrazňovat, takže se `PaletteMatch` musí dát složit i bez nich.
        var title: Range<String.Index>?
        var subtitle: Range<String.Index>?
    }

    /// Váha položky bez dotazu — jedna pro všechny, takže rozhoduje pořadí katalogu.
    private static let paletteCatalogRank = 0

    /// Hledá se **bez ohledu na velikost písmen a na diakritiku**: aplikace je česká, takže
    /// `nalez` musí najít `nález` — jinak by se paleta dala používat jen s přepnutou klávesnicí.
    private static func paletteRange(of token: String, in text: String) -> Range<String.Index>? {
        text.range(of: token, options: [.caseInsensitive, .diacriticInsensitive])
    }

    /// Začíná shoda na hranici slova? Předchozí znak nesmí být písmeno ani číslice — `/`, `.`,
    /// `_` i mezera tedy hranice jsou, což u cest k souborům rozhoduje: `secret` má
    /// v `src/Vault/SecretClient.php` vážit víc než v `MySecretThing.php`.
    private static func paletteStartsWord(at range: Range<String.Index>, in text: String) -> Bool {
        let previous = text[text.index(before: range.lowerBound)]
        return !previous.isLetter && !previous.isNumber
    }

    private struct RankedHit {
        let hit: CommandPalette.Hit
        let rank: Int
        let order: Int
    }
}

extension Policy {
    /// Akce, které mají **teď** co dělat — obsah skupiny `Akce`.
    ///
    /// Rozhoduje se to tady, ne ve storu: je to výčet podmínek („běží review?“, „je otevřený
    /// PR?“), a ten se má dát projít testem bez okna. Řádek, který by nic neudělal, se
    /// nenabízí — tatáž zásada jako u bloku `Co teď` na dashboardu.
    ///
    /// - Parameters:
    ///   - open: PR v otevřené záložce. `nil` = je vidět domácí záložka, takže akce vázané na
    ///     pull request (review, pohled na diff, panel) se nenabízejí — neměly by na čem
    ///     zabrat.
    ///   - hasRun: leží na PR uložený záznam z nějakého předchozího běhu? Podle toho se review
    ///     „pouští“, nebo „pouští znovu“ — text má říkat, co se stane. **Ne „jsou nálezy“**:
    ///     doběhlé review bez nálezů je pořád běh, který se dalším spuštěním přepíše, takže
    ///     chybějící „znovu“ by to zamlčelo. Pojmenované takhle proto, že jako `hasFindings` se
    ///     to při review PR přečetlo obráceně.
    ///   - isPanelExpanded: je panel s mým review rozložený? **`nil` znamená, že v otevřeném tabu
    ///     není vůbec** (#294) — pak se položka nenabízí, protože „složit panel“ by slibovalo něco,
    ///     co se nemá kde stát. Není to totéž jako `false`: složený panel v okně je, jen jako
    ///     proužek.
    ///   - section: která sekce railu je vidět. Nabízí se **jen ta, která něco změní**: nad
    ///     otevřeným PR změní všechny (přepnou i záložku), v domácí záložce ta právě viditelná ne.
    static func paletteActions(
        open: PRIdentifier?,
        isReviewing: Bool = false,
        hasRun: Bool = false,
        layout: DiffLayout = .unified,
        isPanelExpanded: Bool? = true,
        section: RailSection = .overview
    ) -> [CommandPalette.Item] {
        var items: [CommandPalette.Item] = []

        if let open {
            items.append(isReviewing ? cancelReviewItem(open) : runReviewItem(open, hasRun: hasRun))
            // Pohled na diff se nabízí i mimo tab `Změněné soubory`: je to **nastavení diffu**,
            // což mu říká i titulek, takže se z něj pozná, kde zabere. Panel je proti tomu věc na
            // obrazovce, a ta se v tabech bez panelu nenabízí.
            items.append(diffLayoutItem(from: layout))
            if let isPanelExpanded {
                items.append(reviewPanelItem(isExpanded: isPanelExpanded))
            }
        }
        items += RailSection.allCases
            .filter { open != nil || $0 != section }
            .map(sectionItem)
        items.append(refreshItem)
        items.append(settingsItem)
        return items
    }

    private static func runReviewItem(_ pr: PRIdentifier, hasRun: Bool) -> CommandPalette.Item {
        action(
            id: "run-review",
            // „Znovu“ jen tam, kde se opravdu opakuje: nad PR bez záznamu by to tvrdilo, že už
            // něco běželo, a nad PR se záznamem by chybějící slovo zamlčelo, že se přepíše.
            title: hasRun
                ? "Pustit review znovu na \(paletteLabel(of: pr))"
                : "Pustit review na \(paletteLabel(of: pr))",
            symbol: "play.circle",
            keywords: ["review", "spustit", pr.repo.description],
            action: .runReview(pr)
        )
    }

    private static func cancelReviewItem(_ pr: PRIdentifier) -> CommandPalette.Item {
        action(
            id: "cancel-review",
            title: "Zrušit běžící review na \(paletteLabel(of: pr))",
            symbol: "stop.circle",
            keywords: ["review", "zrušit", pr.repo.description],
            action: .cancelReview(pr)
        )
    }

    /// Přepnutí pohledu na diff. V titulku je pohled, který **nastane** — ne ten, ve kterém
    /// se zrovna je.
    private static func diffLayoutItem(from layout: DiffLayout) -> CommandPalette.Item {
        let next: DiffLayout = layout == .unified ? .split : .unified
        return action(
            id: "diff-layout",
            title: "Přepnout diff na „\(next.displayName.lowercased())“",
            symbol: next.symbol,
            keywords: ["diff", "pohled", next.rawValue],
            action: .setDiffLayout(next)
        )
    }

    /// Panel s mým review. Zkratka `⌘2` je **skutečná** (registruje ji detail PR), takže se
    /// smí nakreslit.
    private static func reviewPanelItem(isExpanded: Bool) -> CommandPalette.Item {
        action(
            id: "review-panel",
            title: isExpanded ? "Složit panel s mým review" : "Rozložit panel s mým review",
            symbol: "sidebar.right",
            shortcut: "⌘2",
            keywords: ["panel", "review", "nálezy"],
            action: .setReviewPanel(expanded: !isExpanded)
        )
    }

    private static func sectionItem(_ section: RailSection) -> CommandPalette.Item {
        action(
            id: "section-\(section.rawValue)",
            title: "Otevřít \(paletteTitle(of: section))",
            symbol: section.symbol,
            keywords: [section.title],
            action: .openSection(section)
        )
    }

    /// Sekce ve čtvrtém pádě. Nebere se z `RailSection.title` (ten je nadpis, tedy první pád) —
    /// „Otevřít Rozdělaná“ je věta, kterou by nikdo nenapsal.
    ///
    /// **Sekce se do palety berou z `allCases`**, takže nová se v ní objeví sama (#331) — dopsat
    /// se musí jedině tvar jejího jména. Od #336 má paleta i **druhou skupinu** řádků
    /// (`Moje PR`), ale s tímhle výčtem to nesouvisí: tady jsou akce „otevři sekci railu“,
    /// kdežto skupiny nese `CommandPalette.Group`.
    private static func paletteTitle(of section: RailSection) -> String {
        switch section {
        case .overview: "přehled"
        case .queue: "frontu"
        case .mine: "moje pull requesty"
        case .drafts: "rozdělaná review"
        }
    }

    private static var refreshItem: CommandPalette.Item {
        action(
            id: "refresh",
            title: "Obnovit seznam pull requestů",
            symbol: "arrow.clockwise",
            keywords: ["obnovit", "polling", "github"],
            action: .refresh
        )
    }

    private static var settingsItem: CommandPalette.Item {
        action(
            id: "settings",
            title: "Otevřít nastavení",
            symbol: "gearshape",
            shortcut: "⌘,",
            keywords: ["nastavení", "config", "zdroje", "skilly"],
            action: .openSettings
        )
    }

    private static func action(
        id: String,
        title: String,
        symbol: String,
        shortcut: String? = nil,
        keywords: [String],
        action: CommandPalette.Action
    ) -> CommandPalette.Item {
        CommandPalette.Item(
            id: "action:\(id)",
            group: .actions,
            title: title,
            mark: .action(symbol: symbol),
            shortcut: shortcut,
            keywords: keywords,
            target: .action(action)
        )
    }

    /// Jak se PR jmenuje v řádku palety — `vault#85`, jak ho má návrh. Bez ownera: v paletě jde
    /// o rozlišení mezi několika PR na obrazovce, ne o kanonický identifikátor. Podle celého
    /// `owner/repo` se dá hledat, viz `keywords`.
    static func paletteLabel(of pr: PRIdentifier) -> String {
        "\(pr.repo.name)#\(pr.number)"
    }
}
