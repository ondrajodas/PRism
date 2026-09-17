import Foundation

/// Skupina pull requestů, kde jeden stojí na větvi druhého (#513).
///
/// **Členové jsou od základu nahoru**, tedy v tom pořadí, v jakém se budou mergovat: první je ten,
/// jehož base větev v sérii nikdo nedrží, poslední ten, na kterém nestojí nikdo. Pořadí je celý
/// smysl typu — review spodního PR dřív než horního je práce, která se stejně musí udělat, takže
/// se fronta má přestat tvářit, že jsou to dva nesouvisející řádky.
///
/// **Sérií jsou aspoň dva.** Jeden PR není série a `Policy.series(in:refs:)` takovou skupinu
/// nevydá; kdyby ano, kreslila by se pilulka `1. v sérii` u každého řádku fronty.
struct PullRequestSeries: Hashable, Sendable {
    /// Členové **od základu nahoru**. Vždycky aspoň dva.
    let members: [PRIdentifier]
}

/// Kde v sérii jeden pull request stojí (#513) — podklad pilulky v řádku a řetězu v hlavičce.
///
/// **Vlastní typ, ne dvojice `(Int, Int)`**: nese k tomu i to, **na čem** ten PR stojí a jaká je
/// base větev toho spodního, protože z obojího se skládá řetěz `větev → větev (#726) → main`.
/// Čtveřice v podpisu by se nedala přečíst a kresba by si z ní skládala věty po svém.
struct SeriesPlacement: Hashable, Sendable {
    /// Pořadí od základu, počítáno od jedničky.
    let position: Int
    /// Kolik je v sérii členů celkem.
    let count: Int
    /// Pull request, na jehož větvi tenhle stojí. `nil` právě u základu série.
    let standsOn: PRIdentifier?
    /// Base větev toho spodního PR — pokračování řetězu. `nil` u základu a tehdy, když se větve
    /// spodního PR nepodařilo zjistit.
    let standsOnBase: String?
}

extension Policy {
    // MARK: - Rozpoznání

    /// Série pull requestů v seznamu (#513) — **jedno porovnání nad větvemi, žádný dotaz navíc**.
    ///
    /// PR je v sérii tehdy, když je jeho **base větev** hlavou jiného otevřeného PR **v tomtéž
    /// repozitáři**. Větve nese `BranchRefs`; do fronty se dostanou dávkovým dotazem na hlavy
    /// (#420, rozšířeným u #513), u otevřené záložky a u vlastních PR z načteného detailu.
    ///
    /// Pět věcí, které funkce **netvrdí**, a každá z nich je rozhodnutí:
    ///
    /// 1. **Bez větví se nespojuje nic.** `refs` vrací `nil` u PR, na které se rozhlídka ještě
    ///    nedostala — a „nevíme“ nesmí vyjít jako „nestojí na ničem“ ani jako série.
    /// 2. **Fork nikdy nedrží základ.** `headRefName` u PR z forku pojmenovává větev cizího
    ///    repozitáře, takže by se shodou jmen (`main`, `develop`) spárovala s kdekým. `nil`
    ///    u `isCrossRepository` je proto **zákaz, ne povolení** (`BranchRefs.livesInBaseRepository`)
    ///    — tatáž škola jako u guardu force pushe.
    /// 3. **Napříč repozitáři série není.** Větve se párují jedině uvnitř jednoho repa.
    /// 4. **Dvě otevřená PR na téže hlavě základ nedrží.** GitHub to dovolí (tatáž větev proti dvěma
    ///    základům), a která z nich je „ta“ spodní, se z dat říct nedá — nejednoznačnost se proto
    ///    nespojuje vůbec.
    /// 5. **Mergnuté ani zavřené PR v sérii nejsou.** Série zaniká sama tím, že GitHub po mergi
    ///    spodního přepne base horního na `main`; do té chvíle by mergnutý člen držel skupinu
    ///    pohromadě kolem řádku, se kterým se nedá nic dělat.
    ///
    /// - Parameters:
    ///   - pullRequests: seznam z tiku — **celý**, ne zúžený filtrem ani odložením. Stát na cizí
    ///     větvi je vlastnost pull requestu, ne toho, co je zrovna vidět; co se kreslí, rozhoduje
    ///     `seriesCaptions(in:series:)` nad tím, co v seznamu doopravdy zbylo.
    ///   - refs: větve toho PR, nebo `nil` (nevíme).
    static func series(
        in pullRequests: [PullRequestSummary],
        refs: (PRIdentifier) -> BranchRefs?
    ) -> [PullRequestSeries] {
        let open = pullRequests.filter { $0.state == .open || $0.state == .draft }
        let heads = headIndex(of: open, refs: refs)
        var parents: [PRIdentifier: PRIdentifier] = [:]
        for summary in open {
            guard let base = refs(summary.id)?.base,
                  let parent = heads[BranchKey(repo: summary.repo, branch: base)],
                  parent != summary.id
            else { continue }
            parents[summary.id] = parent
        }
        guard !parents.isEmpty else { return [] }

        var children: [PRIdentifier: [PRIdentifier]] = [:]
        var roots: [PRIdentifier] = []
        var known: Set<PRIdentifier> = []
        for summary in open {
            // Řetěz, který se kouše do ocasu, **nevydá kořen** — a pak se z něj nebere ani hrana:
            // kdo je spodní, se z takových dat říct nedá.
            guard let root = root(of: summary.id, parents: parents) else { continue }
            if let parent = parents[summary.id] { children[parent, default: []].append(summary.id) }
            guard known.insert(root).inserted else { continue }
            roots.append(root)
        }
        // Kořeny se sbírají ze **vstupního pořadí**, takže je pořadí sérií stabilní mezi tiky.
        return roots
            .map { PullRequestSeries(members: chain(from: $0, children: children)) }
            .filter { $0.members.count > 1 }
    }

    /// Kde v sérii ten PR stojí (#513). `nil` = v žádné není.
    static func seriesPlacement(
        of pullRequest: PRIdentifier,
        in series: [PullRequestSeries],
        refs: (PRIdentifier) -> BranchRefs? = { _ in nil }
    ) -> SeriesPlacement? {
        guard let group = series.first(where: { $0.members.contains(pullRequest) }),
              let index = group.members.firstIndex(of: pullRequest)
        else { return nil }
        let standsOn = index > 0 ? group.members[index - 1] : nil
        return SeriesPlacement(
            position: index + 1,
            count: group.members.count,
            standsOn: standsOn,
            standsOnBase: standsOn.flatMap { refs($0)?.base }
        )
    }

    // MARK: - Pořadí

    /// Přeskládá **už seřazený** seznam tak, aby členové série drželi pohromadě (#513).
    ///
    /// **Skupina si bere místo svého nejlépe umístěného člena a uvnitř jde od základu nahoru.**
    /// Není to druhé řazení: vstup je pořadí, které rozhodl někdo jiný (`Policy.sorted` podle času
    /// u fronty, `Policy.byUrgency` podle závažnosti na desce), a tahle funkce v něm jen posune
    /// členy skupiny k tomu prvnímu z nich. Bez toho by řazení sérii rozházelo — a to je zrovna to,
    /// kvůli čemu #513 vzniklo.
    ///
    /// **Členové, kteří v seznamu nejsou, se nedoplňují.** Filtr i odložení ze seznamu členy
    /// vyndat můžou a série se tím nemá měnit; skupina se pak nakreslí menší, ne s řádkem, který
    /// jinam nepatří.
    static func grouped<Item>(
        _ items: [Item],
        by id: (Item) -> PRIdentifier,
        keeping series: [PullRequestSeries]
    ) -> [Item] {
        guard !series.isEmpty else { return items }
        var groupOf: [PRIdentifier: Int] = [:]
        for (index, group) in series.enumerated() {
            for member in group.members { groupOf[member] = index }
        }
        let byIdentifier = Dictionary(items.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })

        var result: [Item] = []
        var emitted: Set<Int> = []
        for item in items {
            guard let index = groupOf[id(item)] else {
                result.append(item)
                continue
            }
            guard !emitted.contains(index) else { continue }
            emitted.insert(index)
            result.append(contentsOf: series[index].members.compactMap { byIdentifier[$0] })
        }
        return result
    }

    // MARK: - Věty

    /// Popisky nad skupinami (#513) — klíčem je **první nakreslený člen** série.
    ///
    /// **Počítá se nad tím, co se doopravdy kreslí**, ne nad celou sérií: filtr i odložení členy
    /// ze seznamu vyndají, a popisek `2 PR` nad jedním řádkem by tvrdil víc, než je vidět. Proto
    /// se popisek vydá jedině tehdy, když v seznamu leží **aspoň dva** členové té série a leží
    /// **vedle sebe** — seznam, který si členy nepřeskládal (`grouped(_:by:keeping:)`), popisek
    /// nedostane vůbec, protože čára kolem skupiny by obtáhla cizí řádky.
    static func seriesCaptions(
        in drawn: [PullRequestSummary],
        series: [PullRequestSeries]
    ) -> [PRIdentifier: String] {
        var captions: [PRIdentifier: String] = [:]
        let positions = Dictionary(
            drawn.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        for group in series {
            let present = group.members.compactMap { member in positions[member].map { ($0, member) } }
            guard present.count > 1 else { continue }
            let indexes = present.map(\.0)
            guard let first = indexes.first, let last = indexes.last,
                  last - first == indexes.count - 1
            else { continue }
            let titles = present.map { drawn[$0.0].title }
            captions[present[0].1] = seriesCaption(count: present.count, titles: titles)
        }
        return captions
    }

    /// `série AJDA-563 · 2 PR · review v pořadí ↓` (#513).
    ///
    /// **Číslo ticketu se odvozuje z titulků, nepíše se natvrdo.** Je to jediné, čím se dvě série
    /// ve frontě od sebe poznají na první pohled — a když společný ticket v titulcích není, popisek
    /// ho **vynechá** místo toho, aby si vymyslel jméno.
    static func seriesCaption(count: Int, titles: [String]) -> String {
        let parts = [seriesTicket(in: titles), "\(count) PR", "review v pořadí ↓"].compactMap { $0 }
        return "série · " + parts.joined(separator: " · ")
    }

    /// Společný ticket v titulcích (`AJDA-563`). `nil` = žádný, nebo se neshodují.
    ///
    /// **Průnik, ne první nález.** Titulek `feat(internal-api): AJDA-563 …` nese jen jeden ticket,
    /// ale kdyby jeden z členů zmiňoval dva, vybrat ten první by znamenalo pojmenovat sérii podle
    /// PR, který zrovna stál nahoře.
    static func seriesTicket(in titles: [String]) -> String? {
        guard let first = titles.first else { return nil }
        var candidates = tickets(in: first)
        for title in titles.dropFirst() {
            let next = Set(tickets(in: title))
            candidates = candidates.filter { next.contains($0) }
        }
        return candidates.first
    }

    /// `1. v sérii` / `2. · stojí na #726` (#513) — pilulka v řádku fronty.
    static func seriesPill(_ placement: SeriesPlacement) -> String {
        guard let standsOn = placement.standsOn else { return "\(placement.position). v sérii" }
        return "\(placement.position). · stojí na #\(standsOn.number)"
    }

    /// `#726 · 1. v sérii` (#513) — pilulka **v řetězu větví** v hlavičce. `nil` u základu série.
    ///
    /// **Mluví o tom spodním PR, ne o tomhle.** Řetěz se čte `moje větev → jeho větev → main`,
    /// takže pilulka sedí u prostředního článku a musí říct, čí ta větev je — jinak by v hlavičce
    /// stálo jméno větve, u kterého se nedá poznat, že je to pull request, který jde mergnout dřív.
    static func seriesBasePill(_ placement: SeriesPlacement) -> String? {
        guard let standsOn = placement.standsOn else { return nil }
        return "#\(standsOn.number) · \(placement.position - 1). v sérii"
    }

    /// Nápověda k té pilulce — říká **co z toho plyne**, ne co je vidět.
    static func seriesHint(_ placement: SeriesPlacement) -> String {
        guard let standsOn = placement.standsOn else {
            return "Základ série \(placement.count) pull requestů — tenhle se merguje první, takže dává smysl číst ho dřív než ty nad ním."
        }
        return "Stojí na větvi #\(standsOn.number), takže jeho diff je jen vrstva nad ním. Mergovat se budou odspoda."
    }

    /// Věta pod souřadnicemi v hlavičce (#513). `nil` = k tomuhle PR není co dodat.
    ///
    /// **Jen u horního PR.** Základ série se od obyčejného pull requestu ničím neliší — jeho diff
    /// je celý —, takže věta o vrstvě by u něj byla nepravda.
    ///
    /// - Parameter changedFiles: kolik souborů diff mění. `nil` = diff se ještě nenačetl a věta
    ///   pak číslo **vynechá**; dopsat ho z ničeho by znamenalo tvrdit, co aplikace neví.
    static func seriesNote(_ placement: SeriesPlacement, changedFiles: Int? = nil) -> String? {
        guard let standsOn = placement.standsOn else { return nil }
        let layer = changedFiles.map {
            "Diff je jen tahle vrstva: \(Plural.czech($0, one: "soubor", few: "soubory", many: "souborů")) nad #\(standsOn.number)."
        } ?? "Diff je jen tahle vrstva nad #\(standsOn.number)."
        guard let base = placement.standsOnBase else {
            return layer + " Až se #\(standsOn.number) mergne, GitHub přepne základ a řetěz zmizí sám."
        }
        return layer + " Až se #\(standsOn.number) mergne, GitHub přepne základ na \(base) a řetěz zmizí sám."
    }
}

// MARK: - Pomocné

extension Policy {
    /// Klíč větve — **repozitář a jméno**, protože `main` je v každém repu jiná větev.
    private struct BranchKey: Hashable {
        let repo: RepoID
        let branch: String
    }

    /// Hlavy, na kterých se dá stát: větev → pull request. **Nejednoznačné jméno v mapě není** —
    /// dvě otevřená PR na téže hlavě (GitHub to dovolí) by znamenala dvě odpovědi na jednu otázku.
    private static func headIndex(
        of pullRequests: [PullRequestSummary],
        refs: (PRIdentifier) -> BranchRefs?
    ) -> [BranchKey: PRIdentifier] {
        var index: [BranchKey: PRIdentifier] = [:]
        var ambiguous: Set<BranchKey> = []
        for summary in pullRequests {
            guard let branches = refs(summary.id), branches.livesInBaseRepository else { continue }
            let key = BranchKey(repo: summary.repo, branch: branches.head)
            if index[key] != nil { ambiguous.insert(key) }
            index[key] = summary.id
        }
        for key in ambiguous { index[key] = nil }
        return index
    }

    /// Kořen řetězu. `nil` = řetěz se kousá do ocasu, a pak se **netvrdí nic**: která z těch větví
    /// je spodní, se z dat říct nedá.
    private static func root(
        of pullRequest: PRIdentifier,
        parents: [PRIdentifier: PRIdentifier]
    ) -> PRIdentifier? {
        var current = pullRequest
        var seen: Set<PRIdentifier> = [pullRequest]
        while let parent = parents[current] {
            guard !seen.contains(parent) else { return nil }
            seen.insert(parent)
            current = parent
        }
        return current
    }

    /// Členové od kořene nahoru, do šířky. **Do šířky, ne do hloubky**: když na jednom PR stojí
    /// dva další, je to vidlice, ne dva řetězy — a v seznamu má vedle sebe zůstat to, co je vedle
    /// sebe i v repozitáři.
    private static func chain(
        from root: PRIdentifier,
        children: [PRIdentifier: [PRIdentifier]]
    ) -> [PRIdentifier] {
        var members: [PRIdentifier] = [root]
        var index = 0
        while index < members.count {
            let node = members[index]
            index += 1
            for child in children[node] ?? [] where !members.contains(child) {
                members.append(child)
            }
        }
        return members
    }

    /// Tokeny tvaru `AJDA-563` v titulku, v pořadí výskytu.
    ///
    /// **Bez regulárního výrazu**: vzor je jednoduchý (velká písmena, pomlčka, číslice) a `Regex`
    /// by na každý řádek fronty stavěl automat. Skládá se ze `Character`ů, takže diakritika
    /// v titulku nerozhoduje o ničem.
    private static func tickets(in title: String) -> [String] {
        title
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" })
            .map(String.init)
            .filter(isTicket)
    }

    private static func isTicket(_ token: String) -> Bool {
        let parts = token.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let letters = parts.first, let digits = parts.last else { return false }
        guard letters.count >= 2, letters.allSatisfy({ $0.isLetter && $0.isUppercase }) else { return false }
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }
}
