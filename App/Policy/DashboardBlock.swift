import Foundation

/// Blok fronty na dashboardu (#371) — kolik řádků se z něj kreslí a co říká patka.
///
/// Do #371 blok vypisoval **všechny** řádky, takže s delší frontou přestal být dashboard přehled:
/// blok `Moje PR` se schoval pod hranu okna a muselo se k němu rolovat. Změřeno na živé aplikaci
/// u #331 (32 PR ve frontě, blok `Moje PR` o celou obrazovku níž) a po #332 na 13 řádcích, tedy
/// o půl obrazovky.
///
/// **Strop je o kresbě, ne o množině.** Karta nad blokem dál počítá celou frontu (`Čeká na mě 13`),
/// blok z ní kreslí pět řádků a zbytek shrne patka. Kdyby strop sestoupil do počítání, začal by
/// dashboard tvrdit, že práce je méně, než jí je — a to je ta regrese, která se pozná až za týden.
struct DashboardBlock: Hashable, Sendable {
    /// Řádky, které se doopravdy nakreslí — nejvýš `Policy.dashboardRowLimit`.
    let rows: [QueueEntry]
    /// Patka se zbytkem. `nil` = blok se vejde pod strop, takže se patka **nekreslí**: „Zobrazit
    /// všechny“ nad seznamem, který je celý vidět, je akce, po které se nic nezmění.
    let footer: Footer?

    /// Co stojí v patce: `Zobrazit všech 13 ve frontě` · `+8` · šipka.
    ///
    /// **Text i počet skládá `Policy`, ne view.** „+8“ musí vyjít z týchž řádků, které blok
    /// nakreslil — jinak se patka rozejde s kresbou a nikdo si toho nevšimne, protože obě čísla
    /// vypadají platně.
    ///
    /// **Patka není řádek**: nepočítá se do `rows`, takže se nedostane ani do klávesové navigace,
    /// ani do toho, kolik řádků blok hlásí.
    struct Footer: Hashable, Sendable {
        /// `Zobrazit všech 13 ve frontě`
        let title: String
        /// `+8` — kolik řádků se nevešlo.
        let rest: String
        /// Kam vede klik. **Totéž, kam vede karta nad blokem** — patka je druhá cesta k témuž
        /// seznamu, ne vlastní obrazovka.
        let section: RailSection
    }
}

/// Karta na dashboardu (#371).
///
/// **Výčet, ne jen popisek**, protože se u každé karty rozhoduje jedna věc: kam vede klik. Bez
/// výčtu by to rozhodnutí bylo pětkrát ve view, tedy tam, kde se netestuje — a `Dneska stálo`
/// je ta pátá, u které je správná odpověď „nikam“.
enum DashboardCard: String, CaseIterable, Sendable {
    case queue
    case blocking
    case mine
    case drafts
    case spend
}

/// Kam vede klik z dashboardu (#371).
///
/// **Sekce railu, ne hotová akce.** Karta nemá vědět, že nějaký rail existuje — jen říct, co se má
/// ukázat; přepnutí si přebírá store (`AppStore.show(_:)`), jako u palety.
enum DashboardDestination: Hashable, Sendable {
    /// Sekce railu, jak je.
    case section(RailSection)
    /// Fronta **se zapnutým filtrem „jen blokující“** — cíl karty `Blokuje`.
    ///
    /// Vlastní případ, ne `section(.queue)`: bez filtru by karta `Blokuje` skákala na totéž místo
    /// jako `Čeká na mě`, což je matoucí. Že se tím přepíše osa filtru, kterou si člověk mohl
    /// nastavit jinak, je **vědomé** — zapíná se jedna osa a ostatní volby zůstávají.
    case blockingQueue

    /// Nápověda u karty (`title` v návrhu) — co se po kliknutí stane.
    ///
    /// Bydlí to na cíli, ne u karty: dvě karty se stejným cílem mají mít i stejnou nápovědu.
    var help: String {
        switch self {
        case .section(let section): "Přepne do sekce \(section.title)"
        case .blockingQueue: "Přepne do sekce \(RailSection.queue.title) a zapne filtr „jen blokující“"
        }
    }
}

extension Policy {
    /// Kolik řádků se z jedné fronty na dashboardu kreslí (#371).
    ///
    /// Pět je z návrhu (sekce 21) a je to horní hranice toho, co se dá přejet očima, ne dolní
    /// hranice užitečnosti: dashboard odpovídá na „co dneska hoří“, takže šestý nejhorší PR na něm
    /// nemá co dělat. Celá fronta je o jedno kliknutí dál.
    static let dashboardRowLimit = 5

    /// Blok fronty na dashboardu — strop na řádky a patka se zbytkem (#371).
    ///
    /// **Rozřazení dělá `PullRequestOwnership`**, tedy tentýž typ, kterým se obě fronty rozdělují
    /// (`Policy.pullRequests(_:ownedBy:mine:)`). Nový výčet „který blok to je“ by znamenal druhé
    /// místo, kde se dvě fronty vyjmenovávají — a tady se ptáme právě na to, čí ta množina je.
    ///
    /// **Vstup se nepřerovnává.** Pořadí rozhoduje `byUrgency` a strop je řez, ne řazení: horních
    /// pět je horních pět proto, že už je někdo seřadil.
    static func dashboardBlock(
        _ entries: [QueueEntry],
        of ownership: PullRequestOwnership,
        limit: Int = dashboardRowLimit
    ) -> DashboardBlock {
        guard entries.count > limit else { return DashboardBlock(rows: entries, footer: nil) }
        return DashboardBlock(
            rows: Array(entries.prefix(limit)),
            footer: DashboardBlock.Footer(
                title: "Zobrazit všech \(entries.count) \(phrase(of: ownership))",
                rest: "+\(entries.count - limit)",
                section: section(of: ownership)
            )
        )
    }

    /// Kam vede karta dashboardu. `nil` = **nikam**.
    ///
    /// `Dneska stálo` nemá kam vést: útrata není seznam, na který by se dalo přepnout. Karta, po
    /// které se nic nestane, je lež o tom, co okno umí — je to tatáž úvaha, kvůli které #331
    /// nekreslí `Prompt →` u řádku bez akce.
    static func destination(of card: DashboardCard) -> DashboardDestination? {
        switch card {
        case .queue: .section(.queue)
        case .blocking: .blockingQueue
        case .mine: .section(.mine)
        case .drafts: .section(.drafts)
        case .spend: nil
        }
    }

    /// Jak se fronta pojmenuje v patce: `Zobrazit všech 13 **ve frontě**`.
    ///
    /// Znění fronty je z návrhu doslova; u vlastních PR návrh patku nekreslí (blok je tam pod
    /// stropem), takže se drží téže věty bez opisu sekce — „všech 13 v Moje PR“ se česky nedá číst.
    private static func phrase(of ownership: PullRequestOwnership) -> String {
        switch ownership {
        case .theirs: "ve frontě"
        case .mine: "vlastních"
        }
    }

    private static func section(of ownership: PullRequestOwnership) -> RailSection {
        switch ownership {
        case .theirs: .queue
        case .mine: .mine
        }
    }
}
