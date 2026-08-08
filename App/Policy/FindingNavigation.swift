import Foundation

/// Kde jsem v procházení nálezů (#187).
///
/// Kurzor drží **místo**, ne index: seznam se pod rukama mění — doběhne další reviewer, nález
/// se odmítne, zapne se filtr — a index by po každé takové změně ukazoval jinam, aniž by se
/// cokoli stalo. Místo je `file:line`, tedy totéž, čím se skupina identifikuje v diffu.
struct FindingCursor: Hashable, Sendable {
    /// Kde stojím. `nil` = ještě jsem nikam neskočil.
    var current: FindingPlace?
    /// Kudy jsem prošel. Kvůli tomu se pozná, že jsem viděl **všechny** — a to je jediné
    /// tvrzení, které tahle lišta o hotové práci dělá.
    var seen: Set<FindingPlace> = []
    /// Skáče se jen po blokujících?
    var onlyBlocking = false

    /// Nový kurzor po skoku na místo.
    func moved(to place: FindingPlace) -> FindingCursor {
        var moved = self
        moved.current = place
        moved.seen.insert(place)
        return moved
    }
}

/// Místo v kódu, na které se dá skočit. Skupina nálezů se pozná podle něj i po překreslení.
struct FindingPlace: Hashable, Sendable {
    let file: String
    let line: Int?

    init?(_ group: FindingGroup) {
        guard let file = group.file else { return nil }
        self.file = file
        self.line = group.line
    }

    /// Místo jednoho nálezu. Skupiny se skládají právě podle `file:line`, takže nález a jeho
    /// skupina dají **totéž** místo — a panel se tím trefí do téhož, na co skáče lišta.
    init?(_ finding: Finding) {
        guard let file = finding.file else { return nil }
        self.file = file
        self.line = finding.line
    }
}

/// Co lišta ukazuje.
struct FindingNavigation: Hashable, Sendable {
    /// Kolikátý ze zúženého seznamu je ten aktuální, počítáno od jedné. `nil` = stojím mimo
    /// (kurzor nikde, nebo se místo pod ním ztratilo).
    let position: Int?
    let total: Int
    let hasPrevious: Bool
    let hasNext: Bool
    /// Prošel jsem všechna místa. **Ne** „jsem na posledním“ — přeskákat je zprostředka
    /// a skončit na konci neznamená, že jsem viděl i ta před ním.
    let isComplete: Bool
    /// Nálezy, na které se skočit nedá, protože nepatří k místu v kódu. Musí to být vidět,
    /// jinak „3 ze 3“ tvrdí hotovo nad PR, kde zbývají dva nálezy v panelu.
    let withoutPlace: Int

    static let none = FindingNavigation(
        position: nil,
        total: 0,
        hasPrevious: false,
        hasNext: false,
        isComplete: false,
        withoutPlace: 0
    )

    var isEmpty: Bool { total == 0 && withoutPlace == 0 }
}

extension Policy {
    /// Místa, po kterých se dá skákat — v pořadí, ve kterém jsou v diffu.
    ///
    /// **Odmítnuté se přeskakují.** Nález, kterému nevěřím, není práce k projití; kdyby v řadě
    /// zůstal, „prošel jsem všechno“ by znamenalo i „proklikal jsem to, co jsem už zamítl“.
    /// Skupina, ze které odmítnutím nezbylo nic, tedy vypadne celá.
    static func navigablePlaces(
        in groups: [FindingGroup],
        onlyBlocking: Bool = false,
        categories: Set<String> = defaultBlockingCategories
    ) -> [FindingPlace] {
        groups.compactMap { group in
            let active = group.activeFindings
            guard !active.isEmpty, let place = FindingPlace(group) else { return nil }
            guard !onlyBlocking else {
                return active.contains { isBlocking($0, categories: categories) } ? place : nil
            }
            return place
        }
    }

    /// Stav lišty nad diffem.
    static func navigation(
        over groups: [FindingGroup],
        cursor: FindingCursor,
        categories: Set<String> = defaultBlockingCategories
    ) -> FindingNavigation {
        let places = navigablePlaces(in: groups, onlyBlocking: cursor.onlyBlocking, categories: categories)
        let index = cursor.current.flatMap { places.firstIndex(of: $0) }

        return FindingNavigation(
            position: index.map { $0 + 1 },
            total: places.count,
            // Bez kurzoru se dá jít **dopředu**, ne dozadu: první skok má vzít první nález,
            // ne poslední.
            hasPrevious: (index ?? 0) > 0,
            hasNext: index.map { $0 + 1 < places.count } ?? !places.isEmpty,
            isComplete: !places.isEmpty && places.allSatisfy(cursor.seen.contains),
            withoutPlace: groups.count { group in
                !group.activeFindings.isEmpty && FindingPlace(group) == nil
            }
        )
    }

    /// Kam skočit. `nil` = není kam.
    ///
    /// Když kurzor stojí mimo zúžený seznam (zapnul jsem `jen blokující` a poslední skok byl
    /// jinam), začíná se **od začátku**, ne od nuly odjinud: skákat od místa, které v seznamu
    /// není, by přeskočilo tu část, kterou zúžení zrovna vybralo.
    static func step(
        _ direction: NavigationStep,
        over groups: [FindingGroup],
        cursor: FindingCursor,
        categories: Set<String> = defaultBlockingCategories
    ) -> FindingPlace? {
        let places = navigablePlaces(in: groups, onlyBlocking: cursor.onlyBlocking, categories: categories)
        guard !places.isEmpty else { return nil }

        guard let index = cursor.current.flatMap({ places.firstIndex(of: $0) }) else {
            // Dozadu se bez kurzoru **nejde**, i když by poslední místo existovalo: lišta má
            // šipku nahoru zhasnutou (`hasPrevious`), a kdyby ji zkratka přesto poslechla,
            // dělalo by `⌥↑` něco, co okno v tu chvíli tvrdí, že nejde. Skok na poslední nález
            // navíc není, co člověk od „předchozí“ čeká.
            return direction == .forward ? places.first : nil
        }

        let next = direction == .forward ? index + 1 : index - 1
        guard places.indices.contains(next) else { return nil }
        return places[next]
    }
}

enum NavigationStep: Hashable, Sendable {
    case forward
    case backward
}
