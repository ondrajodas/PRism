import Foundation

/// Co řádek seznamu ukazuje **nad rámec** `ReviewState` (#172).
///
/// Vlastní typ, ne další případy ve `ReviewState`: ten odpovídá na otázku „v jaké fázi to je“
/// a je uložený v testech i porovnávaný na rovnost na spoustě míst. Tohle je odvozené číslo pro
/// jeden řádek — kolik z nálezů blokuje — a dá se kdykoli spočítat znovu ze záznamu.
///
/// **Blokující je zvlášť od počtu nálezů schválně.** `completed(findings: 3)` říká, kolik jich
/// je; teprve tohle říká, jestli se kvůli nim PR nemerguje. Do #172 se to v řádku nedalo poznat
/// vůbec, takže tři kosmetické nálezy vypadaly stejně jako jeden, který zastavuje merge.
///
/// **Od #502 je to jedno číslo, ne dvě.** Druhým bylo `spectrum`, tedy podíl reviewerů na
/// výsledku — a ten z řádku odešel spolu se `SpectrumBar`em: na jeho místě je mapa PR, která
/// odpovídá na „kde a jak zle“ místo na „kdo“. Typ se **neruší**, protože blokující počet je
/// pořád údaj o výsledku a čte ho hrana řádku i odznak; zdůvodnění je v záznamu rozhodnutí
/// u #172 ve specifikaci.
struct QueueRow: Hashable, Sendable {
    /// Kolik **platných** nálezů blokuje. Odmítnuté se nepočítají — právě proto se odmítají.
    let blocking: Int

    static let empty = QueueRow(blocking: 0)
}

extension Policy {
    /// Odvozená čísla pro jeden řádek seznamu.
    ///
    /// Bere **uložený záznam**, ne stav — stav je z něj poskládaný a počty už v sobě nemá.
    /// Bez záznamu (PR, na kterém se nikdy nic nespustilo) vrací prázdno, takže se řádek
    /// vykreslí bez odznaku navíc.
    static func queueRow(
        for record: ReviewRecord?,
        categories: Set<String> = defaultBlockingCategories
    ) -> QueueRow {
        guard let record, !record.runs.isEmpty else { return .empty }
        return QueueRow(blocking: blockingCount(in: record, categories: categories))
    }
}
