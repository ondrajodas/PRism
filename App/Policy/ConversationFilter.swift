import Foundation

/// Čím se zúží časová osa konverzace (#183).
///
/// Zúžení, ne vlastní seznamy: je to **jedna osa** a filtr je způsob čtení, tatáž úvaha jako
/// u filtru seznamu PR (#117). Proto se taky nikam neukládá.
enum ConversationFilter: Hashable, CaseIterable, Sendable {
    case all
    case comments
    case threads
    case events

    var czechLabel: String {
        switch self {
        case .all: "Vše"
        case .comments: "Komentáře"
        case .threads: "Vlákna"
        case .events: "Události"
        }
    }
}

/// Uzel časové osy (#183) — jedna položka, která se kreslí.
///
/// **Není to `ConversationEntry`**: commity se do jednoho uzlu slučují, takže jeden uzel může
/// nést víc událostí. Tvar uzlu nese druh, jak to zavedlo #171.
enum ConversationNode: Hashable, Sendable, Identifiable {
    case entry(ConversationEntry)
    /// Několik pushnutých commitů za sebou v jednom uzlu.
    case commits([TimelineEvent])

    var id: String {
        switch self {
        case .entry(let entry): entry.id
        // Identita z **prvního** commitu ve skupině: skupina se mění tím, co do ní přibude,
        // ale její začátek zůstává — a `ForEach` potřebuje klíč, který nepřeskakuje.
        case .commits(let events): "commits-\(events.first?.id ?? "")"
        }
    }

    /// Kdy se to stalo. `nil` u položky, které GitHub razítko nedal — na ose se pak kreslí
    /// v pořadí, ve kterém přišla, ale čas se u ní nepíše.
    var date: Date? {
        switch self {
        case .entry(let entry): entry.date
        // Skupina commitů se datuje **posledním**: to je okamžik, ve kterém větev vypadá tak,
        // jak vypadá teď.
        case .commits(let events): events.last?.at
        }
    }
}

extension Policy {
    /// Časová osa konverzace: co se kreslí a v jakém pořadí (#183).
    ///
    /// **Commity se slévají do jednoho uzlu.** Jedenáct pushnutých commitů utopí dva komentáře,
    /// kvůli kterým se do konverzace chodí — a jako skupina nesou totéž, co jednotlivě.
    /// Slévají se jen ty, které jdou **za sebou**: commit před komentářem a po něm jsou dvě
    /// různé věci, které se staly kolem něj.
    static func conversation(
        of entries: [ConversationEntry],
        filter: ConversationFilter = .all
    ) -> [ConversationNode] {
        var nodes: [ConversationNode] = []
        for entry in entries where matches(entry, filter) {
            guard case .event(let event) = entry, case .commit = event.kind else {
                nodes.append(.entry(entry))
                continue
            }
            // Přilep k předchozí skupině, jestli je poslední na ose — jinak začni novou.
            if case .commits(let events) = nodes.last {
                nodes[nodes.count - 1] = .commits(events + [event])
            } else {
                nodes.append(.commits([event]))
            }
        }
        return nodes
    }

    private static func matches(_ entry: ConversationEntry, _ filter: ConversationFilter) -> Bool {
        switch (filter, entry) {
        case (.all, _): true
        // Review s prózou je komentář stejně jako komentář pod PR: obojí je něčí text.
        // Prázdný verdikt (`schválil` bez věty) je naopak děj, takže patří k událostem.
        case (.comments, .comment): true
        case (.comments, .review(let review)): !review.body.isEmpty
        case (.threads, .thread): true
        case (.events, .event): true
        case (.events, .review(let review)): review.body.isEmpty
        default: false
        }
    }

    /// Kolik čeho na ose je — do popisků filtru. Počítá se z **plné** osy, ne ze zúžené:
    /// číslo u zúžení, které samo zúžení mění, by se nedalo přečíst.
    static func conversationCounts(of entries: [ConversationEntry]) -> [ConversationFilter: Int] {
        var counts: [ConversationFilter: Int] = [:]
        for filter in ConversationFilter.allCases {
            counts[filter] = entries.count { matches($0, filter) }
        }
        return counts
    }
}
