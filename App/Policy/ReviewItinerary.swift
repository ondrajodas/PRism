import Foundation

/// Co itinerář o pull requestu ví (#506) — **vstupy, ze kterých se skládají zastávky**.
///
/// Je to schválně jedna struktura hodnot a ne parametry: zastávky se rozhodují **matricí**, tedy
/// vyčerpávajícím výčtem kombinací, a ten se nad devíti argumenty napsat nedá.
///
/// **Nic z toho není „odklikáno“.** Každé pole je záznam o tom, co se stalo — návštěva, commit,
/// odscrollovaný popis, rozbalený check, odeslané review, značka `Prošlo` (#500). Itinerář, který
/// si člověk odškrtává sám, je druhý seznam úkolů; tenhle popisuje, co se doopravdy stalo.
struct ItineraryFacts: Hashable, Sendable {
    /// Je u tohohle PR **zaznamenaná** předchozí návštěva? Bez ní zastávka `Od minule`
    /// v itineráři **není** — „od tvé poslední návštěvy“ nad prvním otevřením by znamenalo
    /// „od začátku věků“ (tatáž úvaha jako `Policy.changes(in:since:)`).
    var hasVisitRecord = false
    /// Kolik commitů od minule přišlo (#171). Nula = není o čem mluvit, i když návštěva
    /// zaznamenaná je.
    var commitsSinceVisit = 0
    /// Viděl jsem, co přibylo — rozsah `Od tvé poslední návštěvy` se otevřel (#284), nebo se
    /// značka posunula tlačítkem `Přečteno` (#173).
    var sawChangesSinceVisit = false

    /// Je detail PR načtený? **Bez toho se o popisu nesmí tvrdit nic** — `bez popisu` nad
    /// obrazovkou, kterou si aplikace zrovna načítá, je text, který data neunesou.
    var descriptionKnown = false
    /// Má PR popis? Prázdný popis se **za hotový nepovažuje automaticky** — kreslí se s údajem
    /// `bez popisu`, protože chybějící záměr je informace, ne odškrtnutá práce.
    var hasDescription = false
    /// Dorolovalo se v `Přehledu` na konec? Rozhoduje `Policy.overviewAtEnd`.
    var descriptionScrolled = false

    /// Kolik souborů PR mění. Nula znamená **nenačtený nebo prázdný diff** a zastávka
    /// `Soubory podle rizika` pak do počítadla nepřináší nic — počet, který se teprve načítá,
    /// nemá co tvrdit.
    var fileCount = 0
    /// Kolik z nich je prošlých (#500) — `Policy.readFileCount`.
    var readFileCount = 0
    /// Kolik řádků diffu leží v neprošlých souborech. Z toho je odhad zbývajícího času.
    var unreadLineCount = 0

    /// Souhrn checků (#306). Prázdný = PR žádné CI nemá a zastávka `Kontroly` v itineráři
    /// **není**.
    var checks = ChecksSummary(passed: 0, failed: 0, running: 0, skipped: 0)
    /// Kolik spadlých checků jsem rozbalil. Spadlý check je hotový, teprve když se otevřel —
    /// „červené CI“ bez podívání do logu není přečtená kontrola.
    var openedFailedChecks = 0

    /// Odeslal jsem na tenhle PR review s verdiktem? Čte se z GitHubu (`SubmittedReview`), ne
    /// z rozdělaného draftu — draft je rozmyšlené, ne odeslané.
    var verdictSubmitted = false
    /// Verdikt, který na rozdělaném review **platí** (#114) — vybraný, nebo předvyplněný
    /// návrhem. `nil` = není z čeho soudit, a to je odpověď, ne mlčení.
    var verdict: ReviewDraft.Verdict?
}

/// Jedna zastávka itineráře (#506).
struct ItineraryStop: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case sinceLastVisit
        case description
        case files
        case checks
        case verdict
    }

    /// Stav zastávky. Tři, jak je má návrh: ✓ hotovo, ● aktuální, ○ zbývá.
    ///
    /// **`current` je právě jedna** — první nehotová v pořadí. Itinerář je dráha, ne seznam
    /// nezávislých úkolů, takže „kde jsem“ má jednu odpověď.
    enum State: Hashable, Sendable {
        case done
        case current
        case todo
    }

    let kind: Kind
    let state: State
    /// Údaj vpravo — `3 commity`, `3 ze 7`, `1 spadl`. `nil` = nic se nepíše.
    let detail: String?
    /// Kolik položek zastávka přináší do počítadla `4 z 11`.
    let units: Int
    /// Kolik z nich je hotových.
    let doneUnits: Int

    var id: Kind { kind }

    /// Nadpis zastávky. Z návrhu, doslova.
    var title: String {
        switch kind {
        case .sinceLastVisit: "Od minule"
        case .description: "Popis a záměr"
        case .files: "Soubory podle rizika"
        case .checks: "Kontroly"
        case .verdict: "Verdikt"
        }
    }

    /// Do kterého tabu klik na zastávku přepne (`klik na zastávku přepne tab i soubor`).
    var tab: PullRequestTab {
        switch kind {
        case .sinceLastVisit, .description: .overview
        case .files: .filesChanged
        case .checks: .checks
        case .verdict: .filesChanged
        }
    }
}

/// Hlavička itineráře — `Itinerář · 4 z 11 · 10 min` a proužek pod ní (#506).
struct ItineraryProgress: Hashable, Sendable {
    let done: Int
    let total: Int
    /// Odhad zbývajícího času v minutách. `nil` = **nemá se z čeho odhadnout** (nenačtený diff),
    /// takže se nepíše nic — nula by tvrdila „hotovo“ nad prací, o které nic nevíme.
    let minutes: Int?

    /// Podíl pro proužek (`0…1`). `nil` = proužek se nekreslí; tatáž úvaha jako
    /// u `Policy.readFileShare` (#500): prázdná linka nad nezapočatou prací je stálý prvek
    /// bez informace.
    var share: Double? {
        guard total > 0, done > 0 else { return nil }
        return min(1, Double(done) / Double(total))
    }
}

extension Policy {
    /// Zastávky itineráře v pořadí, ve kterém se čtou (#506).
    ///
    /// **Skládá je `Policy` z dat, ne šablona**, a to je celé jádro issue: pořadí je pevné, ale
    /// *které* zastávky v seznamu jsou, plyne z toho, co ten PR má. Tři pravidla o přítomnosti:
    ///
    /// - **`Od minule` jen když je záznam návštěvy a přišly commity** (#171). Obojí naráz: bez
    ///   záznamu není proti čemu měřit, bez commitů není o čem mluvit.
    /// - **`Kontroly` jen když PR má CI** (#306). Prázdná zastávka `Kontroly · 0 checků` je
    ///   řádek o tom, že se nic nestalo — a v itineráři by navíc zvedla jmenovatele počítadla.
    /// - **`Popis a záměr`, `Soubory podle rizika` a `Verdikt` vždycky.** Popis chybět může
    ///   (pak nese údaj `bez popisu`), soubory se můžou načítat, verdikt je důvod, proč je okno
    ///   otevřené.
    ///
    /// A jedno o stavu: **`current` je první nehotová**, ostatní nehotové jsou `todo`. Když je
    /// hotové všechno, `current` není žádná — dráha došla do konce a nemá kde stát.
    static func itinerary(_ facts: ItineraryFacts) -> [ItineraryStop] {
        var stops: [(kind: ItineraryStop.Kind, done: Bool, detail: String?, units: Int, doneUnits: Int)] = []

        if facts.hasVisitRecord, facts.commitsSinceVisit > 0 {
            stops.append((
                .sinceLastVisit,
                facts.sawChangesSinceVisit,
                Plural.czech(facts.commitsSinceVisit, one: "commit", few: "commity", many: "commitů"),
                1,
                facts.sawChangesSinceVisit ? 1 : 0
            ))
        }

        // **Popis bez textu není hotový.** Chybějící záměr je věc, kterou má člověk vidět —
        // a jediné, co se s ní dá udělat, je zeptat se autora, takže zastávka zůstane otevřená.
        //
        // Údaj `bez popisu` se přitom píše jedině nad **načteným** detailem: nad tím, který se
        // teprve stahuje, by tvrdil něco, co se ještě neví.
        let descriptionDone = facts.hasDescription && facts.descriptionScrolled
        stops.append((
            .description,
            descriptionDone,
            facts.descriptionKnown && !facts.hasDescription ? "bez popisu" : nil,
            1,
            descriptionDone ? 1 : 0
        ))

        stops.append((
            .files,
            facts.fileCount > 0 && facts.readFileCount >= facts.fileCount,
            fileStopDetail(read: facts.readFileCount, of: facts.fileCount),
            // **Soubor je jednotka počítadla, zastávka ne.** `4 z 11` má být počet věcí, které
            // se doopravdy čtou — a to jsou soubory, ne pět nadpisů nad nimi. Nenačtený diff
            // (`fileCount == 0`) tedy do počítadla nepřináší nic.
            facts.fileCount,
            min(facts.readFileCount, facts.fileCount)
        ))

        if !facts.checks.isEmpty {
            let done = checksStopIsDone(facts)
            stops.append((.checks, done, checksStopDetail(facts.checks), 1, done ? 1 : 0))
        }

        stops.append((
            .verdict,
            facts.verdictSubmitted,
            verdictStopDetail(facts),
            1,
            facts.verdictSubmitted ? 1 : 0
        ))

        let firstOpen = stops.firstIndex { !$0.done }
        return stops.enumerated().map { index, stop in
            ItineraryStop(
                kind: stop.kind,
                state: stop.done ? .done : (index == firstOpen ? .current : .todo),
                detail: stop.detail,
                units: stop.units,
                doneUnits: stop.doneUnits
            )
        }
    }

    /// Údaj u `Soubory podle rizika`: `3 ze 7`, nebo `7 souborů`, dokud není prošlé nic.
    ///
    /// **Nula se nepíše jako podíl** — `0 ze 7` je stálý řádek o tom, že se nic nestalo, tatáž
    /// úvaha jako u `fileTreeSummary` (#500). A nad nenačteným diffem se nepíše nic.
    static func fileStopDetail(read: Int, of total: Int) -> String? {
        guard total > 0 else { return nil }
        guard read > 0 else { return Plural.czech(total, one: "soubor", few: "soubory", many: "souborů") }
        return "\(read) ze \(total)"
    }

    /// Je zastávka `Kontroly` hotová?
    ///
    /// Dvě podmínky a druhá je ta zajímavá: **nic neběží** (dokud CI běží, není co uzavřít)
    /// a **každý spadlý check je rozbalený**. Zelené CI je tedy hotové rovnou; červené se
    /// odškrtne, teprve když se člověk podíval do logu — a přesně to je ta věc, kterou se
    /// u spadlého buildu přeskakuje.
    static func checksStopIsDone(_ facts: ItineraryFacts) -> Bool {
        guard facts.checks.running == 0 else { return false }
        return facts.openedFailedChecks >= facts.checks.failed
    }

    /// Údaj u `Kontroly`: spadlé přebíjejí všechno, pak běžící, pak `12 prošlo`.
    ///
    /// **Podle nejhoršího, ne podle většiny** — tatáž úvaha jako `ChecksSummary.worst`.
    static func checksStopDetail(_ checks: ChecksSummary) -> String? {
        if checks.failed > 0 {
            return Plural.czech(checks.failed, one: "spadl", few: "spadly", many: "spadlo")
        }
        if checks.running > 0 {
            return Plural.czech(checks.running, one: "běží", few: "běží", many: "běží")
        }
        if checks.passed > 0 { return "\(checks.passed) prošlo" }
        return checks.skipped > 0 ? "přeskočeno" : nil
    }

    /// Údaj u `Verdikt`: `odesláno` u hotového, jinak návrh (#114), jinak nic.
    ///
    /// **`nil` u chybějícího návrhu je odpověď, ne mlčení**: `suggestedVerdict` vrací `nil`
    /// tehdy, když není z čeho soudit, a napsat tam `Schválit` by byla ta nejdražší chyba, kterou
    /// tahle aplikace umí udělat.
    static func verdictStopDetail(_ facts: ItineraryFacts) -> String? {
        if facts.verdictSubmitted { return "odesláno" }
        guard let verdict = facts.verdict else { return nil }
        return "návrh: \(verdict.czechLabel.lowercased())"
    }

    /// Počítadlo a odhad času do hlavičky itineráře (#506).
    static func itineraryProgress(of stops: [ItineraryStop], facts: ItineraryFacts) -> ItineraryProgress {
        ItineraryProgress(
            done: stops.reduce(0) { $0 + $1.doneUnits },
            total: stops.reduce(0) { $0 + $1.units },
            minutes: itineraryMinutes(of: stops, facts: facts)
        )
    }

    /// Kolik minut zbývá — **odhad z neprošlých řádků, ne z počtu zastávek**.
    ///
    /// Stojí na jedné konstantě (`reviewLinesPerMinute`) a je to odhad, ne měření: čtení diffu
    /// při review je pomalejší než čtení prózy, protože se u každé změny rozhoduje. Třicet řádků
    /// za minutu je půl řádku za sekundu, tedy tempo, ve kterém se dvěstěřádkový soubor přečte
    /// za sedm minut — což odpovídá tomu, jak dlouho takový soubor v tomhle okně doopravdy
    /// zabere.
    ///
    /// K tomu **minuta za každou nehotovou zastávku, která soubory nečte**: popis, kontroly
    /// a verdikt nejsou nula, i když v nich žádné řádky nejsou.
    ///
    /// `nil` znamená **nemám z čeho odhadovat**: nenačtený diff. Nula se nevrací nikdy — když je
    /// hotovo všechno, vrací se `nil` a v hlavičce se nepíše nic; `0 min` nad nehotovou prací by
    /// lhalo a nad hotovou by bylo šum.
    static func itineraryMinutes(of stops: [ItineraryStop], facts: ItineraryFacts) -> Int? {
        guard facts.fileCount > 0 else { return nil }
        let open = stops.filter { $0.state != .done }
        guard !open.isEmpty else { return nil }
        let reading = Double(facts.unreadLineCount) / reviewLinesPerMinute
        let overhead = open.count(where: { $0.kind != .files })
        let minutes = Int(reading.rounded(.up)) + overhead
        return max(minutes, 1)
    }

    /// Kolik řádků diffu se při review přečte za minutu. Odhad, viz `itineraryMinutes`.
    static let reviewLinesPerMinute = 30.0

    /// Kolik řádků leží v souborech, které prošlé nejsou (#506) — vstup pro odhad času.
    ///
    /// Počítá se z **hlaviček hunků** (`newCount`), ne procházením řádků, a je to rozhodnutí
    /// o ceně: `FileDiff.additions` a `.deletions` iterují **každý řádek každého hunku**, takže
    /// nad tisícřádkovým diffem je to tisíc kroků — a tahle funkce běží při **každém průchodu
    /// tělem detailu PR**, tedy v místě, kde se za lineární práci platí (#472). Hlaviček je
    /// řádově desítky.
    ///
    /// Rozdíl v čísle je věcný, ne jen výkonový: `newCount` je **kolik řádků se u toho souboru
    /// ukáže**, tedy včetně kontextu — a přesně to se čte. Odhad je odhad (viz `itineraryMinutes`),
    /// takže je poctivější měřit to, co je na obrazovce, než součet `+/−`.
    ///
    /// `changed` (změněno od prošlého, #500) se počítá **jako neprošlý** — je to práce, která se
    /// vrátila.
    static func unreadLineCount(of files: [FileDiff], states: [String: FileReviewState]) -> Int {
        files.reduce(0) { total, file in
            guard !(states[file.displayPath] ?? .unread).isRead else { return total }
            return total + file.hunks.reduce(0) { $0 + $1.newCount }
        }
    }

    /// Dorolovalo se v `Přehledu` na konec popisu? (#506)
    ///
    /// **Obsah, který se vejde celý, je přečtený rovnou** (`content <= visible`): neviditelný
    /// konec nemá, takže čekat na scroll, který nemá kam jít, by znamenalo, že se u krátkého
    /// popisu zastávka neodškrtne nikdy.
    ///
    /// Od dolní hrany se odečítá **tolerance** — tatáž úvaha jako u `stepFeedAtEnd`: `NSScrollView`
    /// dojede na poslední bod obsahu se subpixelovou odchylkou a pod ní má karta popisu vnitřní
    /// odsazení, takže „poslední bod obsahu“ a „poslední řádek textu je vidět“ nejsou totéž.
    ///
    /// **Dokud se popis nenačetl, je odpověď `false`, ne „vejde se“** (nález Copilota na #506).
    /// Ve stavu `Načítám popis…` je obsah krátký, takže by `content <= visible` vydalo `true`
    /// a store si to uloží **jednosměrně** (`noteOverviewReadToEnd` značku nikdy nesundá) —
    /// zastávka `Popis a záměr` by tím byla hotová u PR, jehož popis nikdo neviděl. Je to tatáž
    /// třída jako *text v UI, který tvrdí víc, než data unesou*, jen zapsaná do stavu.
    ///
    /// **`isLoaded`, ne „je neprázdný“**, a je to rozdíl, na kterém záleží: PR **bez** popisu je
    /// načtený a přečíst na něm není co, takže se zastávka odškrtnout **musí** — jinak by u něj
    /// počítadlo itineráře nikdy nedošlo na konec. Ta hodnota je proto `description != nil`
    /// (`nil` = detail se ještě nenačetl), ne `!description.isEmpty`.
    static func overviewAtEnd(
        offset: Double,
        visible: Double,
        content: Double,
        isLoaded: Bool
    ) -> Bool {
        guard isLoaded else { return false }
        guard content > visible else { return true }
        return offset + visible >= content - overviewEndSlack
    }

    /// Kolik bodů od dolní hrany se ještě počítá za konec.
    static let overviewEndSlack = 24.0

    /// Nápověda u zastávky — **co se klikem stane**, ne jak se jmenuje.
    ///
    /// Klik přepíná tab, takže se do nápovědy píše kam: sloupec stojí u diffu a `Kontroly` jsou
    /// na druhém konci pruhu záložek, takže „přepne se ti obrazovka“ je informace, kterou je
    /// poctivé mít dřív než po kliknutí.
    static func itineraryStopHelp(_ stop: ItineraryStop) -> String {
        "\(stop.title) — přepne na \(stop.tab.czechLabel)"
    }

    /// Popisek hlavičky: `Itinerář · 4 z 11 · 10 min`.
    ///
    /// Skládá se tady, ne ve view, ze stejného důvodu jako `fileTreeSummary`: počet v hlavičce
    /// se nesmí rozejít s tím, co je v seznamu pod ní.
    static func itineraryHeading(_ progress: ItineraryProgress) -> String {
        var parts = ["Itinerář"]
        if progress.total > 0 { parts.append("\(progress.done) z \(progress.total)") }
        if let minutes = progress.minutes { parts.append("\(minutes) min") }
        return parts.joined(separator: " · ")
    }
}
