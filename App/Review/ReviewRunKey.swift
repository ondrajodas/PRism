import Foundation

/// Identita jednoho běhu review.
///
/// `headSha` je v klíči schválně: nálezy se klíčují head commitem, takže běh nad novým
/// commitem je jiný běh, ne pokračování starého. `skillID` proto, že nad jedním commitem
/// běží víc reviewerů nezávisle.
struct ReviewRunKey: Hashable, Sendable {
    let pullRequest: PRIdentifier
    let headSha: String
    let skillID: String

    init(pullRequest: PRIdentifier, headSha: String, skillID: String) {
        self.pullRequest = pullRequest
        self.headSha = headSha
        self.skillID = skillID
    }

    var repo: RepoID { pullRequest.repo }
}

extension ReviewRunKey: CustomStringConvertible {
    /// Jeden řetězec pro logy a pro slučování souběžných běhů. Není to formát na disk —
    /// tam se klíč rozpadne na pole, protože `ReviewStore` klíčuje soubory jinak.
    var description: String { "\(pullRequest)@\(headSha)/\(skillID)" }
}
