import Foundation

/// Výstup `gh pr view --json mergeable,mergeStateStatus` (#465).
///
/// **Vlastní dotaz vedle `GhPullRequestDetail`, ne pole navíc v něm** — tatáž úvaha jako u labelů
/// (#392), jen z opačného konce: detail si tahá pre-flight publisheru před **každým** odesláním,
/// a tahle dvě pole se u GitHubu **počítají na vyžádání**, takže by se ta práce na jeho straně
/// spouštěla i tehdy, když se posílá odpověď do vlákna.
///
/// Obě pole jsou optional schválně: `mergeStateStatus` GitHub vydá jen tomu, kdo má na repozitář
/// zápis, takže chybějící hodnota je běžný stav a nemá položit celou sekci.
struct GhBranchStatus: Decodable {
    let mergeable: String?
    let mergeStateStatus: String?

    static let jsonFields = "mergeable,mergeStateStatus"

    /// Překlad na model. **Rozhoduje `Policy`**, ne tenhle typ — tady se jen převádí tvar, stejně
    /// jako u `GhPullRequestMetadata`.
    var status: BranchStatus {
        BranchStatus(
            mergeability: BranchStatus.Mergeability(raw: mergeable),
            mergeState: BranchStatus.MergeState(raw: mergeStateStatus)
        )
    }
}
