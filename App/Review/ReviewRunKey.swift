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
    /// Co za běh to je (#150).
    ///
    /// **Vlastní druh, ne vyhrazené jméno skillu**, a je to rozhodnutí: kontrola nálezů běží nad
    /// tímtéž PR a tímtéž commitem jako review, takže by se jinak slila s běžným během — sloučila
    /// by se s ním ve `WorkCoordinatoru` (klíčem je `description`) a uložila by se na jeho místo.
    /// Vyhrazený `skillID` by to udělal taky, jenže by se dal potkat se skutečným skillem toho
    /// jména; výčet ne.
    let kind: ReviewRunKind

    init(
        pullRequest: PRIdentifier,
        headSha: String,
        skillID: String,
        kind: ReviewRunKind = .review
    ) {
        self.pullRequest = pullRequest
        self.headSha = headSha
        self.skillID = skillID
        self.kind = kind
    }

    /// Klíč kontroly nálezů (#150).
    ///
    /// Kontrola je nad jedním commitem **jedna**, ne jedna na skill: otázka „je to opravené“ se
    /// ptá na nálezy všech reviewerů naráz. `skillID` proto nese jen jméno druhu — nikdo ho u téhle
    /// větve nečte (nálezy z ní nevznikají, viz `ReviewStore.save`), identitu drží `kind`.
    static func recheck(of pullRequest: PRIdentifier, at headSha: String) -> ReviewRunKey {
        ReviewRunKey(
            pullRequest: pullRequest,
            headSha: headSha,
            skillID: ReviewRunKind.recheck.rawValue,
            kind: .recheck
        )
    }

    var repo: RepoID { pullRequest.repo }
}

/// Druh běhu — review, nebo kontrola nálezů z minula (#150).
///
/// Prompt i to, co se z běhu ukládá, se podle toho rozhodují. Sada nástrojů **ne**: obojí je
/// read-only reviewer se stejnými `--allowedTools` i `--disallowedTools` (tvrdá podmínka č. 2),
/// kontrola dostane nálezy jako **materiál v promptu**, ne jako nový nástroj.
enum ReviewRunKind: String, Hashable, Sendable, Codable {
    case review
    case recheck
}

extension ReviewRunKey: CustomStringConvertible {
    /// Jeden řetězec pro logy a pro slučování souběžných běhů. Není to formát na disk —
    /// tam se klíč rozpadne na pole, protože `ReviewStore` klíčuje soubory jinak.
    ///
    /// Kontrola má `!recheck` místo skillu, takže se s běžným během neslije ani tehdy, když by
    /// se nějaký skill jmenoval `recheck`.
    var description: String {
        switch kind {
        case .review: "\(pullRequest)@\(headSha)/\(skillID)"
        case .recheck: "\(pullRequest)@\(headSha)/!recheck"
        }
    }
}
