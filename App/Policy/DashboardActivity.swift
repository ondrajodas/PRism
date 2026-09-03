import Foundation

/// Blok `Dění` na dashboardu (#443) — pět nejnovějších řádků a cesta do sekce.
///
/// Do #443 nebylo na dashboardu o dění ani řádka: sekce v railu (#414) je dobré místo, **když se
/// do ní jde** — jenže napřed se musí vědět, že je do čeho koukat, a odznak v railu říká počet, ne
/// co se stalo. Dashboard je jediná obrazovka, na kterou se člověk podívá, aniž by se ptal.
///
/// **Ukázka a rozcestník, ne druhé místo, kde se dá v dění zůstat** (návrh, sekce 31, poznámka 98).
/// Proto tentýž strop pěti řádků jako u obou front (#371), proto patka se zbytkem — a proto blok
/// nemá **vlastní prázdné obrazovky, vlastní pruh poslední návštěvy ani vlastní řádek**. Kdyby si
/// je pořídil, jsou to dvě dění.
struct DashboardActivity: Hashable, Sendable {
    /// Nadpis bloku — `Dění`, nebo `Dění · 3 nové`.
    ///
    /// Počet je **nepřečtených v celém záznamu**, ne v nakreslených řádcích: je to totéž číslo,
    /// jaké nese odznak sekce v railu (`Policy.activityBadge`), takže by dvě čísla o jedné věci
    /// stála vedle sebe a lišila se.
    let title: String
    /// Řádky, které se doopravdy nakreslí — nejvýš `Policy.activityRowLimit`, od nejnovějšího.
    let rows: [ActivityEvent]
    /// Věta místo řádků. `nil` = řádky jsou.
    ///
    /// **Jedna věta, ne díra a ne obrazovka ze sekce**: prázdný blok vypadá jako chybějící údaj,
    /// kdežto prázdné obrazovky sekce (#414) mají u sebe tlačítka a ta patří tam, kam jsem přišel
    /// schválně.
    let emptyExplanation: String?
    /// Patka se zbytkem záznamu. `nil` = pod pěti řádky už nic neleží, takže „zobrazit celé“ je
    /// akce, po které se nic nezmění — tatáž úvaha jako u pruhů desky.
    let footer: BlockFooter?
}

extension Policy {
    /// Blok `Dění` na dashboardu (#443) — nadpis s počtem nepřečtených, pět řádků a patka.
    ///
    /// **Strop je `activityRowLimit`, od #515 osm řádků** (do té doby pět, tehdy tolik co bloky
    /// front): domov je jedna
    /// obrazovka bez rolování, takže blok, který roste s daty, položí ten pod sebou pod hranu okna.
    /// Co se nevešlo, nese patka **číslem**, ne mlčením — bez ní je to useknutý seznam, ze kterého
    /// se nepozná, jestli se za posledním řádkem nic nestalo, nebo se to tam jen nevešlo.
    ///
    /// **Pořadí se srovná znovu**, ze stejného důvodu jako v `activityFeed`: „pět nejnovějších“ je
    /// řez, a řez nad špatně seřazeným vstupem tiše ukáže pět jiných. Cena je jedno seřazení nejvýš
    /// dvou set položek na průchod tělem — strop záznamu je právě to, co ji ohraničuje.
    ///
    /// - Parameters:
    ///   - since: značka poslední návštěvy. Blok ji **nikdy neposouvá** — to smí jedině odchod ze
    ///     sekce (`AppStore.syncActivityVisit()`), jinak by se nepřečtené vynulovalo tím, že jsem se
    ///     podíval na domácí záložku, a odznak v railu by zmizel, aniž bych něco přečetl.
    ///   - empty: proč je prázdno, když je. Rozhoduje o tom `activityEmptyState` — jedno místo pro
    ///     sekci i pro blok, takže se nemají čím rozejít.
    static func dashboardActivity(
        _ events: [ActivityEvent],
        since: Date?,
        empty: ActivityEmptyState?
    ) -> DashboardActivity {
        let ordered = activityLog([], adding: events, limit: max(events.count, 1))
        let rows = Array(ordered.prefix(activityRowLimit))
        return DashboardActivity(
            title: dashboardActivityTitle(unread: unreadActivity(ordered, since: since)),
            rows: rows,
            emptyExplanation: rows.isEmpty ? dashboardActivitySentence(of: empty) : nil,
            footer: dashboardActivityFooter(rest: ordered.count - rows.count)
        )
    }

    /// `Dění` nebo `Dění · 3 nové`. Nula se **nepíše**: „0 nových“ je hlášení o ničem a nadpis má
    /// být krátký — tatáž úvaha jako u odznaku v railu, který se nad nulou nekreslí.
    private static func dashboardActivityTitle(unread: Int) -> String {
        guard unread > 0 else { return RailSection.activity.title }
        // Tatáž slova jako v nadpisu bloku dne v sekci (`Dnes · 4 nové`) — jeden počet, jedno znění.
        let count = Plural.czech(unread, one: "nová", few: "nové", many: "nových")
        return "\(RailSection.activity.title) · \(count)"
    }

    /// `Zobrazit celé dění +37 →`. `nil`, když se celý záznam vešel do bloku.
    private static func dashboardActivityFooter(rest: Int) -> BlockFooter? {
        guard rest > 0 else { return nil }
        return BlockFooter(
            title: "Zobrazit celé dění",
            rest: "+\(rest)",
            section: .activity
        )
    }

    /// Věta, která na dashboardu zbude z prázdné sekce (#443).
    ///
    /// Z prázdných obrazovek sekce zůstává **důvod**; tlačítka, kterými se to spraví (zapnout
    /// hlášení, otevřít Nastavení systému), patří do sekce a cesta k nim vede odkazem v hlavičce
    /// bloku. Věty jsou kratší než v sekci schválně: je to jeden řádek v bloku, ne prázdná obrazovka
    /// s nadpisem a odstavcem.
    ///
    /// `nil` znamená klid. `activityEmptyState` nad prázdným záznamem jiný stav nevydá, takže je to
    /// obrana proti němému bloku, ne druhé rozhodování o tom, proč je prázdno.
    private static func dashboardActivitySentence(of state: ActivityEmptyState?) -> String {
        switch state {
        case .calm, nil: "Od tvé poslední návštěvy se na pull requestech nic nestalo."
        // **Porucha, ne klid** — soubor tam byl a nepřečetl se, takže je historie ztracená.
        case .unreadable: "Záznam dění se nepodařilo přečíst — co se stalo dřív, je ztracené."
        case .notificationsDenied:
            "Notifikace jsou zakázané v Nastavení systému. Záznam se plní dál, zatím je prázdný."
        case .notificationsOff:
            "Hlášení jsou v nastavení vypnutá. Záznam se plní dál, zatím je prázdný."
        }
    }
}
