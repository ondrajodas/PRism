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
    /// Rozbalený: okno o pevné výšce s vlastním scrollem.
    case expanded
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
    static func stepFeedArrivals(follows: Bool, newest: Int?, anchor: Int?) -> Int? {
        guard !follows, let newest, let anchor, newest > anchor else { return nil }
        return newest - anchor
    }
}
