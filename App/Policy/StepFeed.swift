import Foundation

/// Které dráhy mají v tabu `Průběh` rozbalený výpis kroků (#325).
///
/// **Drží to tab, ne dráha.** Do #325 to byl `@State` uvnitř `ReviewerLaneView` a dráhy jsou
/// v `LazyVStack`u: odrolovaná dráha se zahodí i se svým stavem, takže se výpis po návratu **sám
/// zavřel** — a to zrovna u běžícího revieweera, tedy tam, kam se člověk díval. Je to tatáž past
/// jako `@State` v detailu PR, který přetéká mezi pull requesty; jen se projeví scrollováním
/// místo přepnutím.
///
/// Klíčem je jméno skillu, jako u všeho ostatního v tabu.
struct StepFeedExpansion: Equatable, Sendable {
    /// Skilly, u kterých je výpis rozbalený.
    var expanded: Set<String> = []
    /// Skilly, u kterých už automatické rozbalení proběhlo.
    ///
    /// **Drží se jen dokud běží**, a to je celé kouzlo dvou množin místo jedné: bez téhle by se
    /// zavřený výpis běžícího revieweera při každé události otevřel znovu (automat proti kliku),
    /// kdežto s ní se automat spustí **jednou za běh** — a nový běh téhož skillu (`Pustit znovu`)
    /// dostane rozbalení zase, protože do té doby ze množiny vypadl.
    var opened: Set<String> = []
}

/// Co se u dráhy kreslí místo výpisu kroků (#325).
enum StepFeedState: Equatable, Sendable {
    /// Osa je prázdná — kreslit se nemá nic. Řádek `0 kroků session` by nabízel rozbalení
    /// prázdného okna, a to je tvrzení, že se něco stalo.
    case none
    /// Sbalený: jeden řádek s počtem kroků, ne okno.
    case collapsed
    /// Rozbalený: okno o výšce obsahu do stropu, s vlastním scrollem.
    case expanded
}

/// Rozměry, ze kterých se počítá výška okna výpisu (#325).
///
/// **Čísla dodává view, ne `Policy`.** Kreslí se ve `StepFeedView` a v `TimelineEntryRow`, takže se
/// tam i měří (#236) — jinak by o jedné výšce rozhodovala dvě místa a rozešla by se. `Policy` z nich
/// jen počítá, což je celý důvod, proč sem chodí jako parametr a ne jako konstanta.
struct StepFeedMetrics: Equatable, Sendable {
    /// Výška jednoho řádku výpisu (`TimelineEntryRow.height`).
    let row: Double
    /// Výška řádku s řezem („N starších kroků se nevešlo do stropu“).
    let cut: Double
    /// Vzduch nad prvním a pod posledním řádkem — počítá se na **obou** stranách.
    let inset: Double
    /// Strop výšky okna. Nad ním okno neroste a začne se rolovat.
    let cap: Double
}

/// Jak vysoké je okno výpisu a je-li v něm co rolovat (#325).
struct StepFeedWindow: Equatable, Sendable {
    /// Výška okna: **obsah do stropu**, ne strop od začátku.
    let height: Double
    /// Přerostl obsah strop? Když ne, není kam rolovat — a `Sledovat konec` ani `↓ N nových` se
    /// proto nekreslí.
    let scrolls: Bool
}

/// Co má výpis udělat s tím, co mu řekla geometrie scrollu (#325).
enum StepFeedReaction: Equatable, Sendable {
    /// Dojet na nejnovější krok.
    case catchUp
    /// Přepnout sledování konce na tuhle hodnotu.
    case follow(Bool)
    /// Nedělat nic — poloha v tuhle chvíli o vůli člověka nic neříká.
    case ignore
}

extension Policy {
    /// **Rozdíl mezi „obsah narostl“ a „člověk odscrolloval“** — jediné netriviální rozhodnutí
    /// v celém sledování konce, a proto čistá funkce a ne `if` ve view.
    ///
    /// Narostlý obsah shodí `isAtEnd` na `false` o ten jeden řádek, který se ještě nedoscrolloval
    /// (změřeno 20 bodů, `StepFeedTailTests`). Kdyby se z toho vyvozovalo „člověk odscrolloval“,
    /// sledování konce by se vypnulo samo první událostí — proto se u narostlého obsahu **jen
    /// dohání** a sledování se nesahá.
    ///
    /// A dokud dohánění nedojelo (`isCatchingUp`), neříká poloha nic ani při **nezměněné** výšce:
    /// ta se totiž při rozvržení mění i naplano (změřeno `1825 → 3505 → 1825` na jedné scéně),
    /// takže by se mezi dvěma planými hodnotami našla dvojice, ze které vyjde „stejná výška“ nad
    /// polohou, která ještě není dojetá.
    ///
    /// Kolo „posun → přeměření → posun“ tady zastavuje to, že **posun výšku obsahu nemění**: druhé
    /// kolo tedy skončí v `follow`, ne v dalším `catchUp`.
    static func stepFeedReaction(grew: Bool, isAtEnd: Bool, isCatchingUp: Bool) -> StepFeedReaction {
        if grew { return .catchUp }
        return isCatchingUp ? .ignore : .follow(isAtEnd)
    }

    /// Rozbalí výpis u toho, kdo **běží** — a nezavře ho, když doběhne (#325).
    ///
    /// Výchozí stav se řídí **stavem dráhy, ne posledním klikem**: běžící rozbalený, doběhlý
    /// sbalený. Při doběhnutí se ale nezavírá sám — to by sebralo obrazovku zrovna ve chvíli, kdy
    /// je na ni nejvíc důvodů koukat. Proto se automat propíše do `expanded` (co je rozbalené) a
    /// zvlášť se poznamená do `opened` (že už se to stalo).
    ///
    /// **Rozbaluje se jen `running`.** `queued` dráha osu nemá, takže by rozbalení otevřelo prázdné
    /// okno; a `stopped` ani `failed` se rozbalovat nemá, protože o zrušený běh se kouká přes
    /// hlášku, ne přes kroky.
    static func stepFeedExpansion(_ state: StepFeedExpansion, lanes: [ReviewerLane]) -> StepFeedExpansion {
        let live = Set(lanes.filter { $0.state == .running }.map(\.skill))
        var next = state
        for skill in live.subtracting(state.opened) { next.expanded.insert(skill) }
        // Co už neběží, z `opened` vypadne — jinak by druhý běh téhož revieweera automat nedostal.
        // `expanded` se u toho **nesahá**: rozbalený výpis doběhnutím nezavíráme.
        next.opened = live
        return next
    }

    /// Klik na hlavičku výpisu. Zapíše se i do `opened`, aby automat rozhodnutí člověka nepřebil
    /// při příští události.
    static func toggledStepFeed(_ state: StepFeedExpansion, of skill: String) -> StepFeedExpansion {
        var next = state
        if next.expanded.contains(skill) {
            next.expanded.remove(skill)
        } else {
            next.expanded.insert(skill)
        }
        next.opened.insert(skill)
        return next
    }

    /// Co se u dráhy kreslí.
    static func stepFeed(of lane: ReviewerLane, expansion: StepFeedExpansion) -> StepFeedState {
        guard !lane.entries.isEmpty else { return .none }
        return expansion.expanded.contains(lane.skill) ? .expanded : .collapsed
    }

    /// Výška okna výpisu: **obsah do stropu, ne strop od začátku** (#325, připomínka z proklikání).
    ///
    /// Do téhle opravy byla výška pevná vždycky, takže běh o třech krocích nakreslil okno vysoké
    /// 138 bodů a dvě třetiny z něj byly prázdné — a to při **každém** otevření tabu, protože
    /// každé review začíná krátkou osou. Důvod, kvůli kterému strop je, se tím nevrací: okno roste
    /// jedině **do** stropu, takže přerovnání obsahu pod sebou stojí nejvýš prvních osm událostí
    /// běhu, ne každá z tří stovek.
    ///
    /// **Počítá se z dat, ne z přeměřeného obsahu**, a tady je to celé rozhodnutí. Výška obsahu
    /// hlášená scrollem se při rozvržení mění **i naplano** (změřeno `1825 → 3505 → 1825` na jedné
    /// scéně), takže okno navěšené na ni by u nezměněného obsahu poskakovalo o řádek tam a zpět.
    /// Řádek výpisu má proto **pevnou výšku** (`TimelineEntryRow.height`) a obsah se dá spočítat:
    /// hodnota je funkcí počtu řádků, tedy roste **monotónně** a na hranici stropu se zastaví.
    ///
    /// `scrolls` je druhá polovina téže odpovědi. Dokud se obsah vejde celý, nabídka `Sledovat
    /// konec` ani pilulka `↓ N nových` nemají co dělat — obojí slibuje posun tam, kam se posunout
    /// nedá, a je to ta „nabídka, která nic nedělá“, kterou `CLAUDE.md` zakazuje. Rozhoduje se to
    /// tady, aby to nebyl `if` ve view.
    static func stepFeedWindow(rows: Int, cut: Bool, metrics: StepFeedMetrics) -> StepFeedWindow {
        let content = 2 * metrics.inset + (cut ? metrics.cut : 0) + Double(rows) * metrics.row
        return StepFeedWindow(height: min(content, metrics.cap), scrolls: content > metrics.cap)
    }

    /// Vůle, do které se scroll ještě počítá za „na konci“.
    ///
    /// Musí být: offset i výšky přicházejí jako `Double` po rozvržení, takže rovnost na bod
    /// nevyjde — a sledování konce, které se samo vypne setinou bodu, by vypadalo jako porucha.
    /// Dva body jsou pod výškou jednoho řádku výpisu, takže se do vůle nevejde událost.
    static let stepFeedEndSlack = 2.0

    /// Je výpis odrolovaný **na konec**? (#325)
    ///
    /// Tohle je ta funkce, kterou se `Sledovat konec` vypíná a zapíná — ne klik. Klikem to jde
    /// taky, ale rozhodovat musí poloha: přepínač, který se drží kliku, zápasí s kolečkem myši.
    ///
    /// **Krátký obsah je vždycky na konci.** Dokud se výpis nevejde přes celé okno, není kam
    /// odrolovat, takže by `false` znamenalo, že se konec nesleduje hned od první události.
    static func stepFeedAtEnd(offset: Double, visible: Double, content: Double) -> Bool {
        guard content > visible else { return true }
        return offset + visible >= content - stepFeedEndSlack
    }

    /// Kolik událostí přibylo od chvíle, kdy se konec přestal sledovat. `nil` = pilulka se nekreslí.
    ///
    /// Počítá se z **`id` poslední události, ne z jejich počtu**: se stropem (`entryLimit`) počet
    /// přestane růst, jakmile se osa začne ořezávat, takže by pilulka u dlouhého běhu tvrdila, že
    /// nepřibylo nic. `id` roste dál (`droppedEntries` mu čísla nevrací).
    ///
    /// **Bez rolovatelného obsahu se nekreslí vůbec** (`scrolls`): pilulka slibuje posun na konec,
    /// jenže obsah, který se vejde celý, žádný neviditelný konec nemá. Je to tatáž úvaha jako
    /// u přepínače `Sledovat konec` a proto tentýž příznak z `stepFeedWindow`.
    static func stepFeedArrivals(scrolls: Bool, follows: Bool, newest: Int?, anchor: Int?) -> Int? {
        guard scrolls, !follows, let newest, let anchor, newest > anchor else { return nil }
        return newest - anchor
    }
}
