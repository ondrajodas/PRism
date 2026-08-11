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
    static let paletteGroupLimit = 6

    /// Výsledky pro dotaz, po skupinách.
    ///
    /// Prázdný dotaz **není prázdný výsledek**: paleta se otevírá jako nabídka toho, co je po
    /// ruce, takže se ukáže začátek každé skupiny v pořadí, ve kterém katalog přišel (nálezy od
    /// nejvážnějšího, soubory v pořadí diffu, PR od naposledy změněného, akce v pevném pořadí).
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
                hit: CommandPalette.Hit(item: item, highlight: match.highlight),
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

    /// Váha položky a místo shody v titulku. `nil` = nesedí.
    ///
    /// Váha je **nejlepší** ze slov dotazu: stačí, aby se jedno z nich potkalo s začátkem
    /// titulku, a řádek jde nahoru. Nejhorší z nich by naopak srazila silnou shodu kvůli slovu,
    /// které sedlo „jen“ na repo v podtitulku.
    private static func paletteMatch(
        _ item: CommandPalette.Item,
        tokens: [String]
    ) -> (rank: Int, highlight: Range<String.Index>?)? {
        guard !tokens.isEmpty else { return (paletteCatalogRank, nil) }

        var best = Int.max
        var highlight: Range<String.Index>?
        for token in tokens {
            guard let match = paletteMatch(token, in: item) else { return nil }
            best = min(best, match.rank)
            // Zvýrazní se **první** slovo, které se potkalo v titulku. Zvýraznit jich víc by
            // znamenalo dělit titulek na libovolně mnoho úseků; na jeden řádek je to šum.
            if highlight == nil { highlight = match.highlight }
        }
        return (best, highlight)
    }

    /// Váha jednoho slova proti položce.
    ///
    /// Pořadí kritérií: začátek titulku, začátek slova v titulku, cokoli v titulku, podtitulek,
    /// klíčové slovo. Je to pořadí podle toho, jak **jistá** ta shoda je — `Secret` na začátku
    /// jména souboru znamená víc než `secret` uprostřed věty.
    private static func paletteMatch(
        _ token: String,
        in item: CommandPalette.Item
    ) -> (rank: Int, highlight: Range<String.Index>?)? {
        if let range = paletteRange(of: token, in: item.title) {
            if range.lowerBound == item.title.startIndex { return (0, range) }
            return (paletteStartsWord(at: range, in: item.title) ? 1 : 2, range)
        }
        if let subtitle = item.subtitle, paletteRange(of: token, in: subtitle) != nil {
            return (3, nil)
        }
        if item.keywords.contains(where: { paletteRange(of: token, in: $0) != nil }) {
            return (4, nil)
        }
        return nil
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
    ///   - hasFindings: leží na PR uložený záznam? Podle toho se review „pouští“, nebo „pouští
    ///     znovu“ — text má říkat, co se stane.
    ///   - section: která sekce railu je vidět. Nabízí se **jen ta, která něco změní**: nad
    ///     otevřeným PR změní všechny (přepnou i záložku), v domácí záložce ta právě viditelná ne.
    static func paletteActions(
        open: PRIdentifier?,
        isReviewing: Bool = false,
        hasFindings: Bool = false,
        layout: DiffLayout = .unified,
        isPanelExpanded: Bool = true,
        section: RailSection = .overview
    ) -> [CommandPalette.Item] {
        var items: [CommandPalette.Item] = []

        if let open {
            items.append(isReviewing ? cancelReviewItem(open) : runReviewItem(open, hasFindings: hasFindings))
            items.append(diffLayoutItem(from: layout))
            items.append(reviewPanelItem(isExpanded: isPanelExpanded))
        }
        items += RailSection.allCases
            .filter { open != nil || $0 != section }
            .map(sectionItem)
        items.append(refreshItem)
        items.append(settingsItem)
        return items
    }

    private static func runReviewItem(_ pr: PRIdentifier, hasFindings: Bool) -> CommandPalette.Item {
        action(
            id: "run-review",
            // „Znovu“ jen tam, kde se opravdu opakuje: nad PR bez záznamu by to tvrdilo, že už
            // něco běželo, a nad PR se záznamem by chybějící slovo zamlčelo, že se přepíše.
            title: hasFindings
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
    private static func paletteTitle(of section: RailSection) -> String {
        switch section {
        case .overview: "přehled"
        case .queue: "frontu"
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
