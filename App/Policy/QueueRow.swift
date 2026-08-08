import Foundation

/// Co řádek seznamu ukazuje **nad rámec** `ReviewState` (#172).
///
/// Vlastní typ, ne další případy ve `ReviewState`: ten odpovídá na otázku „v jaké fázi to je“
/// a je uložený v testech i porovnávaný na rovnost na spoustě míst. Tohle jsou dvě odvozená
/// čísla pro jeden řádek — kolik z nálezů blokuje a jak se rozdělily mezi reviewery — a obojí
/// se dá kdykoli spočítat znovu ze záznamu.
///
/// **Blokující je zvlášť od počtu nálezů schválně.** `completed(findings: 3)` říká, kolik jich
/// je; teprve tohle říká, jestli se kvůli nim PR nemerguje. Do #172 se to v řádku nedalo poznat
/// vůbec, takže tři kosmetické nálezy vypadaly stejně jako jeden, který zastavuje merge.
struct QueueRow: Hashable, Sendable {
    /// Kolik **platných** nálezů blokuje. Odmítnuté se nepočítají — právě proto se odmítají.
    let blocking: Int
    /// Podíl reviewerů na výsledku, v pořadí, ve kterém běželi.
    let spectrum: [ReviewerShare]

    static let empty = QueueRow(blocking: 0, spectrum: [])

    var isEmpty: Bool { blocking == 0 && spectrum.isEmpty }
}

/// Jeden reviewer v barevném proužku u řádku (#172).
///
/// Nese **váhu**, ne šířku: přepočet na body je věc vykreslení, kdežto „kolik toho tenhle
/// reviewer našel“ je údaj o výsledku.
struct ReviewerShare: Hashable, Sendable, Identifiable {
    enum Outcome: Hashable, Sendable {
        /// Má aspoň jeden blokující nález.
        case blocking
        /// Nálezy má, ale žádný neblokuje.
        case findings
        /// Doběhl a nic nenašel. **Není to `findings(0)`** — tatáž úvaha jako u
        /// `ReviewState.finished(findingCount:)`.
        case clean
        /// Našel, ale **všechno jsem to odmítl** (#113). Není to `clean`: „reviewer nic nenašel“
        /// a „našel a já to zamítl“ jsou dvě různá tvrzení a zelený díl by nad tím druhým lhal.
        /// Stejná barva jako `ReviewState.dismissed`, ať řádek a odznak říkají totéž.
        case dismissed
        /// Doběhl, ale za čisté se to brát nedá: spadl, vytimeoutoval, nereportoval, nebo se
        /// část nálezů nepodařilo přečíst. Šedá, ne zelená — jinak by proužek tvrdil klid tam,
        /// kde se nálezy nemají kde vzít.
        case inconclusive
    }

    let reviewer: String
    let outcome: Outcome
    /// Kolik nálezů po sobě nechal. Váha dílu v proužku, minimálně 1 — reviewer, který
    /// doběhl čistý, musí být v proužku vidět, jinak z něj zmizí právě ta informace, že běžel.
    let weight: Int

    var id: String { reviewer }
}

extension Policy {
    /// Odvozená čísla pro jeden řádek seznamu.
    ///
    /// Bere **uložený záznam**, ne stav — stav je z něj poskládaný a počty už v sobě nemá.
    /// Bez záznamu (PR, na kterém se nikdy nic nespustilo) vrací prázdno, takže se řádek
    /// vykreslí bez proužku i bez odznaku navíc.
    static func queueRow(
        for record: ReviewRecord?,
        categories: Set<String> = defaultBlockingCategories
    ) -> QueueRow {
        guard let record, !record.runs.isEmpty else { return .empty }
        return QueueRow(
            blocking: blockingCount(in: record, categories: categories),
            spectrum: record.runs.map { share(of: $0, in: record, categories: categories) }
        )
    }

    private static func share(
        of run: StoredReviewRun,
        in record: ReviewRecord,
        categories: Set<String>
    ) -> ReviewerShare {
        // Platné nálezy **tohohle** běhu: odmítnutí visí na záznamu, ne na běhu, takže se
        // musí protnout. Bez toho by proužek svítil červeně i nad nálezem, který jsem zamítl.
        let active = record.activeFindings.filter { $0.reviewer == run.skillID }
        return ReviewerShare(
            reviewer: run.skillID,
            outcome: outcome(of: run, active: active, categories: categories),
            weight: max(active.count, 1)
        )
    }

    private static func outcome(
        of run: StoredReviewRun,
        active: [Finding],
        categories: Set<String>
    ) -> ReviewerShare.Outcome {
        if active.contains(where: { isBlocking($0, categories: categories) }) { return .blocking }
        if !active.isEmpty { return .findings }

        // **Nejistota přebíjí i odmítnutí.** Ztracený nález jsem neviděl, takže „všechno
        // odmítnuto“ by nad ním tvrdilo víc, než data unesou — posoudil jsem jen to, co dorazilo.
        // Tady se rozhoduje „čisto“ versus „nemám co říct“, stejná dvojice jako
        // u `ReviewerChip.finishedState`, a stejně jako tam se nesmí slít.
        if !run.calledReportFindings || run.droppedFindings > 0 { return .inconclusive }

        switch run.outcome {
        // Zabitý ani přerušený běh se nesmí tvářit jako doběhlý: o tom, co nestihl, nevíme nic.
        // Co našel, se ale počítá — to už vyřídily větve výš.
        case .failed, .timedOut, .interrupted: return .inconclusive
        case .finished: break
        }

        // Něco našel a nic z toho neplatí — všechno jsem to odmítl (#113).
        if !run.findings.isEmpty { return .dismissed }
        return .clean
    }
}
