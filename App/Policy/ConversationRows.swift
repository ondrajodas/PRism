import Foundation

/// Jeden řádek časové osy konverzace — uzel plus to, co se o něm musí vědět **před** kreslením.
///
/// Existuje kvůli dvěma věcem, které se obě dají změřit (#361):
///
/// - **Identita je uložená, ne počítaná.** `ConversationNode` je enum s asociovanými hodnotami,
///   takže každé přečtení jeho `id` rozbalí payload a **zkopíruje** ho (`ConversationEntry` nese
///   pole komentářů). Líný seznam se přitom na identitu ptá při **každém** přerovnání obsahu:
///   ve vzorku ze ztuhlého okna je `ConversationNode.id` s tou kopií ~5 % vzorků hlavního
///   vlákna. Uložený `String` je čtení pole.
/// - **Značka „odsud dolů je nové“ je rozhodnutí, ne kresba.** Do #361 se počítala ve view
///   z indexu a sousedního uzlu (`isFirstNew(_:at:in:)`) a **neměla ani jeden test**. Tady je to
///   čistá funkce s vyčerpávajícím výčtem.
struct ConversationRow: Identifiable, Hashable, Sendable {
    /// Identita uzlu. Tatáž hodnota jako `node.id` — jen spočítaná jednou, ne při každém dotazu.
    let id: String
    let node: ConversationNode
    /// Kreslí se **před** tímhle řádkem značka poslední návštěvy?
    let isFirstNew: Bool
}

extension Policy {
    /// Řádky časové osy: co se kreslí, v jakém pořadí a kde je značka poslední návštěvy (#361).
    ///
    /// Skládá se ze dvou už existujících rozhodnutí — `conversation(of:filter:)` (co na osu patří)
    /// a značky — a nepřidává třetí: pořadí ani slévání commitů se tady neřeší.
    static func conversationRows(
        of entries: [ConversationEntry],
        filter: ConversationFilter = .all,
        since lastVisit: Date?
    ) -> [ConversationRow] {
        let nodes = conversation(of: entries, filter: filter)
        return nodes.enumerated().map { index, node in
            ConversationRow(id: node.id, node: node, isFirstNew: isFirstNew(node, at: index, in: nodes, since: lastVisit))
        }
    }

    /// Je tohle první uzel, který přibyl od poslední návštěvy?
    ///
    /// Bez `lastVisit` nikdy — „nové“ se nedá tvrdit, když není proti čemu. **Značka se kreslí
    /// před** první novou položkou, ne za poslední starou: říká „odsud dolů je nové“, což je
    /// směr, ve kterém se osa čte.
    private static func isFirstNew(
        _ node: ConversationNode,
        at index: Int,
        in nodes: [ConversationNode],
        since lastVisit: Date?
    ) -> Bool {
        guard let lastVisit, let date = node.date, date > lastVisit else { return false }
        // První uzel značku dostat **smí**: když je nové všechno, patří značka úplně nahoru.
        // (Nález Copilota na #173 — původní `index > 0` ji v tom případě zahodil.)
        guard index > 0 else { return true }
        // Jinak musí být předchozí uzel starý, jinak by se značka kreslila u každé nové položky.
        // Prokládané datum tím dostane **druhou** značku, a je to schválně: dvě staré položky
        // mezi novými znamenají dvě různá místa, odkud dolů je něco nového.
        return nodes[index - 1].date.map { $0 <= lastVisit } ?? false
    }
}
