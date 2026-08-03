import Foundation

/// Jak z výsledků jednotlivých zdrojů vznikne jeden seznam PR.
///
/// Čistá funkce, žádné I/O — proto `Policy`. Testuje se bez mockování a bez `gh`.
enum PullRequestList {
    /// Sloučí výsledky zdrojů, zahodí duplicity a seřadí je tak, jak se mají ukázat.
    ///
    /// Bere výsledky **po zdrojích**, ne jeden plochý seznam: volající pak nemusí nic
    /// spojovat a je z typu vidět, že vstup je několik nezávislých dotazů.
    static func merged(from resultsBySource: [[PullRequestSummary]]) -> [PullRequestSummary] {
        var byIdentifier: [PRIdentifier: PullRequestSummary] = [:]

        for summary in resultsBySource.joined() {
            byIdentifier[summary.id] = newer(summary, than: byIdentifier[summary.id])
        }

        return byIdentifier.values.sorted(by: shouldPrecede)
    }

    /// Při kolizi vyhrávají novější data. Zdroje se dotazují postupně, takže jeden z nich
    /// může nést stav, který mezitím zastaral — pořadí zdrojů o tom rozhodovat nemá.
    private static func newer(
        _ summary: PullRequestSummary,
        than existing: PullRequestSummary?
    ) -> PullRequestSummary {
        guard let existing else { return summary }
        return summary.updatedAt > existing.updatedAt ? summary : existing
    }

    /// Od naposledy změněného. Při shodě rozhoduje identifikátor — bez druhého kritéria by
    /// se pořadí mezi pollingy měnilo a řádky by v seznamu poskakovaly pod rukou.
    private static func shouldPrecede(_ left: PullRequestSummary, _ right: PullRequestSummary) -> Bool {
        if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
        return left.id < right.id
    }
}
