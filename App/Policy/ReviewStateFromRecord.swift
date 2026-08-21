import Foundation

extension Policy {
    /// Stav řádku PR ze všeho, co se o něm ví.
    ///
    /// Pořadí je dané: **co běží, přebíjí to, co doběhlo**, a výsledek přebíjí stav
    /// pracovní kopie. Jinak by řádek u rozběhnutého review ukazoval nálezy z minula.
    static func reviewState(
        phase: ReviewPhase?,
        record: ReviewRecord?,
        checkout: CheckoutState,
        categories: Set<String> = defaultBlockingCategories
    ) -> ReviewState {
        switch phase {
        case .preparing: return .cloning
        case .running(let finished, let total): return .running(finished: finished, total: total)
        case .failed(let detail): return .failed(detail: detail)
        case nil: break
        }

        guard let record else { return reviewState(for: checkout) }
        return reviewState(for: record, categories: categories)
    }

    /// Stav řádku z doběhlého review.
    ///
    /// Kritéria odshora, každé kvůli něčemu jinému:
    ///
    /// 1. **zastaralé** — nálezy patří ke commitu, který v PR není, a to přebíjí všechno,
    /// 2. **timeout** — zabitý běh si nálezy nechává, ale nesmí se tvářit jako doběhlý,
    /// 3. **nálezy** — to je to, kvůli čemu se review pouštělo,
    /// 4. **odmítnuté** — nálezy byly, ale všechny jsem posoudil jako falešné (#113),
    /// 5. **selhání** — spadlá session bez nálezů,
    /// 6. **čisté** — jen když se z běhů dá vůbec soudit; jinak `inconclusive` s důvodem.
    ///
    /// Ten poslední krok je celý smysl toho rozlišení: „nic jsem nenašel“ a „nemám co říct“
    /// vypadají v datech stejně a v UI znamenají opak. Přesně proto je čtvrtý krok vlastní
    /// stav a ne `clean`: „našel a já to zamítl“ je třetí tvrzení, které v datech vypadá
    /// stejně jako ta dvě.
    ///
    /// **Do #383 byl ten šestý krok `failed`**, tedy odznak `selhalo` nad session, která doběhla
    /// `success`. Změnilo se to proto, že tam od #383 spadá i běh, který **nepřečetl kód** —
    /// a „selhalo“ o něm lže stejně jako „čisté“: neselhalo nic, jen se nedá z čeho soudit.
    ///
    /// Odmítnuté stojí až za `completed` a `timedOut` schválně — tam se počítají **platné**
    /// nálezy, takže na řadu přijde jen tehdy, když nezbyl žádný. A před `failed` proto, že
    /// stejné pořadí platí u nálezů, které se neodmítly: co reviewer našel, přebíjí to, že
    /// jiný běh spadl.
    static func reviewState(
        for record: ReviewRecord,
        categories: Set<String> = defaultBlockingCategories
    ) -> ReviewState {
        guard !record.runs.isEmpty else { return .notStarted }
        guard !record.isStale else { return .stale }

        let findings = record.activeFindings.count
        if record.runs.contains(where: { $0.outcome == .timedOut }) {
            return .timedOut(findings: findings)
        }
        // Přerušený běh stojí **za** timeoutem: když se sešly oba, je timeout konkrétnější
        // (víme, proč skončil), kdežto „skončil s aplikací“ je jen to, co jsme dopočítali.
        if record.runs.contains(where: { $0.outcome == .interrupted }) {
            return .interrupted(findings: findings)
        }
        if findings > 0 { return .completed(findings: findings) }
        if record.dismissedCount > 0 {
            return .dismissed(findings: record.dismissedCount)
        }
        if let detail = record.runs.compactMap(failureDetail).first {
            return .failed(detail: detail)
        }

        return suggestedVerdict(for: record, categories: categories) == .approve
            ? .clean
            : .inconclusive(reason: inconclusiveReason(for: record))
    }

    /// Který záznam je pro PR ten platný.
    ///
    /// Na disku jich je víc — historie po jednotlivých commitech. Vyhrává neaktuální nad
    /// aktuálním nikdy: nejdřív rozhoduje, jestli je zastaralý, teprve pak čas doběhnutí.
    static func currentRecords(from records: [ReviewRecord]) -> [PRIdentifier: ReviewRecord] {
        var current: [PRIdentifier: ReviewRecord] = [:]
        for record in records {
            guard let existing = current[record.pullRequest] else {
                current[record.pullRequest] = record
                continue
            }
            if isNewer(record, than: existing) { current[record.pullRequest] = record }
        }
        return current
    }

    private static func isNewer(_ record: ReviewRecord, than other: ReviewRecord) -> Bool {
        guard record.isStale == other.isStale else { return !record.isStale }
        return (record.finishedAt ?? .distantPast) > (other.finishedAt ?? .distantPast)
    }

    private static func failureDetail(_ run: StoredReviewRun) -> String? {
        guard case .failed(let detail) = run.outcome else { return nil }
        return detail
    }

    /// Věta k důvodu, proč se čisto tvrdit nedá (#383).
    ///
    /// Bydlí v `Policy`, ne ve view, protože ji čtou **tři** místa — prázdný tab nálezů,
    /// notifikace a nápověda — a tři kopie téže věty se rozejdou. Do #383 to byl text
    /// u `failed`, takže se v okně kreslil mono a k vybrání jako stderr od `claude`; je to ale
    /// **naše věta**, ne cizí výstup.
    static func inconclusiveDetail(_ reason: InconclusiveReason) -> String {
        switch reason {
        case .droppedFindings:
            "Část nálezů se nepodařilo přečíst, takže „čisté“ to tvrdit nejde."
        case .noReport:
            "Reviewer nenahlásil nálezy — nemají se kde vzít."
        case .unreadCode:
            "Reviewer neotevřel ani jeden soubor z pracovní kopie, takže „čisté“ to tvrdit nejde."
        }
    }
}
