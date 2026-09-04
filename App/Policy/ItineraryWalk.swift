import Foundation

/// Klávesa a to, co dělá — jeden řádek patky itineráře (#507).
///
/// **Popiska se odvozuje z katalogu** (`WindowShortcut.title`), nikdy neopisuje vedle klávesy:
/// je to tatáž podmínka, kvůli které katalog vůbec vznikl (#441). Kdyby se do patky psalo
/// `␣ další zastávka` jako literál, změna klávesy by o tom textu nevěděla.
struct ShortcutHint: Identifiable, Hashable, Sendable {
    /// Kombinace tak, jak se kreslí — `␣`, `⌥↓`, `⌥V`.
    let key: String
    /// Co udělá. Z titulku akce, malým písmem věty.
    let label: String

    var id: String { key }
}

extension Policy {
    // MARK: - Mezerník jako další zastávka (#507)

    /// Kam mezerník posune — `nil` znamená **nikam, klávesa patří scrollu** (#507).
    ///
    /// Tohle je celé jádro issue a proto je to čistá funkce a ne `if` ve view: **mezerník
    /// normálně scrolluje**, takže si ho aplikace smí vzít jen tam, kde se tím nic nesebere.
    /// Tři podmínky, každá vyjmenovaná zvlášť:
    ///
    /// - **Fokus v poli.** Do textu se mezera píše, a to přebíjí všechno ostatní. Že v okně někdo
    ///   píše, se čte z `TextFieldFocus` — ne z toho, který tab je vidět: composer rozdělaného
    ///   review stojí v panelu vedle `Přehledu` i `Změněných souborů`, takže odpověď „podle tabu“
    ///   by byla vedle právě v těch dvou tabech, o kterých itinerář mluví nejvíc.
    /// - **Výřez na konci obsahu.** Dokud je kam scrollovat, mezerník scrolluje — jinak by
    ///   se z klávesy, kterou se čte, stala klávesa, která uteče pryč. **`nil` je „neměří se“
    ///   a odpověď je pak tatáž jako u „není na konci“**: v tabech, o kterých dráha nic neříká
    ///   (`Konverzace`, `Commity`, `Nálezy`, `Průběh`, `Zeptat se`), zůstává mezerník klávesou
    ///   scrollu. Tvrdit „jsem na konci“ o obsahu, který nikdo nezměřil, je přesně ten text, co
    ///   nese víc, než data unesou.
    /// - **Poslední zastávka.** Za koncem dráhy není kam jít, takže se klávesa nebere a propadne
    ///   dál — zakázané tlačítko klávesu nebere (tentýž vzorec jako `⌘⏎` v tabu `Zeptat se`).
    static func itineraryStep(
        stops: [ItineraryStop],
        cursor: ItineraryStop.Kind?,
        isEditing: Bool,
        atEnd: Bool?
    ) -> ItineraryStop? {
        guard !isEditing, atEnd == true else { return nil }
        return nextItineraryStop(after: cursor, in: stops)
    }

    /// Další zastávka za `cursor`em. `nil` = **není kam**, tedy poslední zastávka nebo hotová
    /// dráha.
    ///
    /// **Bez kurzoru se jde na aktuální zastávku** (`state == .current`, tedy první nehotovou),
    /// ne na první v seznamu: první stisk má člověka posunout tam, kde podle dat stojí, ne zpátky
    /// na začátek k tomu, co má odškrtnuté. Když je hotové všechno, `current` žádná není a
    /// odpověď je `nil` — dráha došla do konce a mezerník se vrací scrollu.
    ///
    /// **Kurzor, který v seznamu není, se bere jako žádný.** Zastávky se skládají z dat
    /// (`Policy.itinerary`), takže `Od minule` nebo `Kontroly` v seznamu být přestanou — a
    /// hledat další za zastávkou, která zmizela, nemá odpověď. Vrátit se na `current` je jediné,
    /// co v takové chvíli platí.
    ///
    /// Kurzor je **kde jsem v procházení**, ne co je hotové (tentýž rozdíl jako `FindingCursor`,
    /// #187): hotovo se pozná z dat a mezerníkem se nezaškrtává nic.
    static func nextItineraryStop(
        after cursor: ItineraryStop.Kind?,
        in stops: [ItineraryStop]
    ) -> ItineraryStop? {
        guard let cursor, let index = stops.firstIndex(where: { $0.kind == cursor }) else {
            return stops.first { $0.state == .current }
        }
        let next = stops.index(after: index)
        return stops.indices.contains(next) ? stops[next] : nil
    }

    /// Je výřez na konci obsahu? (#507)
    ///
    /// **Třetí funkce téhle rodiny a je to schválně** — `stepFeedAtEnd` (#325) mluví o výpisu
    /// kroků a odečítá si jeho vnitřní odsazení, `overviewAtEnd` (#506) přidává podmínku
    /// „popis je načtený“, protože z něj plyne odškrtnutá zastávka. Tady se nic neodškrtává, jen
    /// se rozhoduje o klávese, takže by ani jedna z těch dvou neodpovídala na tuhle otázku.
    ///
    /// Společné mají to podstatné: **obsah, který se vejde celý, je na konci**. Kdyby ne,
    /// mezerník by v krátkém tabu nefungoval nikdy — a přitom je to přesně ten tab, ve kterém
    /// není co scrollovat, takže by se klávesou nic nesebralo.
    ///
    /// Vůle se odečítá ze stejného důvodu jako u těch dvou: offset i výšky přicházejí jako
    /// `Double` po rozvržení, takže rovnost na bod nevyjde.
    static func contentAtEnd(offset: Double, visible: Double, content: Double) -> Bool {
        guard content > visible else { return true }
        return offset + visible >= content - contentEndSlack
    }

    /// Kolik bodů od dolní hrany se ještě počítá za konec. Dva body jsou pod výškou řádku, takže
    /// se do vůle nevejde řádek kódu.
    static let contentEndSlack = 2.0

    // MARK: - Průběh ve stavovém řádku (#507)

    /// `Krok 4 z 9 · 12 min` do stavového řádku (#507). `nil` = **není co říct**.
    ///
    /// **Je to tentýž počet jako v hlavičce itineráře** (`itineraryHeading`), ne druhé číslo —
    /// dvě počítadla nad jednou dráhou by se rozešla při první úpravě. Minuty jsou naproti tomu
    /// **jiná veličina než v hlavičce a je to vědomé**: hlavička odhaduje, **co zbývá**
    /// (`itineraryMinutes` z neprošlých řádků), kdežto pruh říká, **jak dlouho jsem tu**. Proto
    /// se v pruhu píše `Krok`, ne `Itinerář`, a celá věta stojí v nápovědě.
    ///
    /// Nad nenačteným PR (`total == 0`) se nepíše nic: `Krok 0 z 0` je řádek o tom, že se nic
    /// neví.
    static func itineraryStatus(progress: ItineraryProgress, openedAt: Date?, now: Date) -> String? {
        guard progress.total > 0 else { return nil }
        var parts = ["Krok \(progress.done) z \(progress.total)"]
        if let minutes = minutesInTab(openedAt: openedAt, now: now) {
            parts.append("\(minutes) min")
        }
        return parts.joined(separator: " · ")
    }

    /// Kolik minut je záložka otevřená. `nil` = **míň než minuta, nebo se neví od kdy**.
    ///
    /// **Nečinnost se neodečítá, a je to zapsané rozhodnutí, ne zjednodušení** (#507): je to
    /// orientace („dělám to dýl, než jsem myslel“), ne měření práce. Kdyby se odečítala,
    /// aplikace by musela rozhodovat, co je práce — a to je otázka, na kterou by odpovídala
    /// špatně (čtení diffu bez jediného kliknutí je práce, otevřená záložka přes oběd ne).
    ///
    /// **Nula se nepíše** ze stejného důvodu jako u odhadu v hlavičce: `0 min` v první minutě je
    /// šum. Záporný rozdíl (hodiny se posunuly) je `nil` — čas, který ještě nezačal, se nedá
    /// vypsat.
    static func minutesInTab(openedAt: Date?, now: Date) -> Int? {
        guard let openedAt else { return nil }
        let minutes = Int(now.timeIntervalSince(openedAt) / 60)
        return minutes >= 1 ? minutes : nil
    }

    // MARK: - Patka itineráře (#507)

    /// Klávesy v patce itineráře — `␣ další zastávka · ⌥↓ další nález · ⌥V prošlo`.
    ///
    /// **Tři, a všechny tři jsou o práci nad diffem**: posun po dráze, posun po nálezech a
    /// značka `Prošlo`. Skládají se z katalogu (#441), takže popiska ani kombinace nejdou napsat
    /// vedle sebe nesouhlasně; `⌘1` v patce **není**, protože složení sloupce je v jeho hlavičce
    /// jako šipka i s nápovědou.
    static let itineraryKeyHints: [ShortcutHint] = [
        shortcutHint(.nextItineraryStop),
        shortcutHint(.nextFinding),
        shortcutHint(.toggleFileRead),
    ]

    /// Jeden řádek patky. Titulek se **odvozuje**, ne opisuje — viz `ShortcutHint`.
    static func shortcutHint(_ action: WindowShortcut.Action) -> ShortcutHint {
        let shortcut = windowShortcut(action)
        return ShortcutHint(key: shortcut.display, label: shortcut.title.lowercased())
    }
}
