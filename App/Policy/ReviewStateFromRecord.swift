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
    /// 4. **selhání** — spadlá session bez nálezů,
    /// 5. **čisté** — jen když se z běhů dá vůbec soudit; jinak je to `failed` s vysvětlením.
    ///
    /// Ten poslední krok je celý smysl toho rozlišení: „nic jsem nenašel“ a „nemám co říct“
    /// vypadají v datech stejně a v UI znamenají opak.
    static func reviewState(
        for record: ReviewRecord,
        categories: Set<String> = defaultBlockingCategories
    ) -> ReviewState {
        guard !record.runs.isEmpty else { return .notStarted }
        guard !record.isStale else { return .stale }

        let findings = record.findings.count
        if record.runs.contains(where: { $0.outcome == .timedOut }) {
            return .timedOut(findings: findings)
        }
        if findings > 0 { return .completed(findings: findings) }
        if let detail = record.runs.compactMap(failureDetail).first {
            return .failed(detail: detail)
        }

        return suggestedVerdict(for: record, categories: categories) == .approve
            ? .clean
            : .failed(detail: inconclusiveDetail(for: record))
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

    private static func inconclusiveDetail(for record: ReviewRecord) -> String {
        record.runs.contains { $0.droppedFindings > 0 }
            ? "Část nálezů se nepodařilo přečíst, takže „čisté“ to tvrdit nejde."
            : "Reviewer nenahlásil nálezy — nemají se kde vzít."
    }
}
