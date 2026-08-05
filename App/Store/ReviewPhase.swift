import Foundation

/// Co se s review jednoho PR **právě** děje.
///
/// Odděleno od uloženého výsledku schválně: `ReviewRecord` je to, co doběhlo, tohle je to,
/// co běží. Když je `nil`, neběží nic a stav řádku se odvozuje z výsledku (nebo z checkoutu,
/// když ani ten není).
enum ReviewPhase: Hashable, Sendable {
    /// Dotahuje se detail PR a připravuje pracovní strom.
    case preparing
    /// Běží reviewery — `finished` z `total` je hotovo.
    case running(finished: Int, total: Int)
    /// Review se nepodařilo ani spustit; `detail` říká proč.
    ///
    /// Vlastní případ, ne `CheckoutState.failed`: selhat umí i dotažení detailu z GitHubu
    /// nebo zápis na disk, a to jsou chyby jednoho PR, kdežto checkout je stav celého repa.
    case failed(detail: String)
}

/// Rozsah, který se právě táhne přes řádky diffu (#110).
///
/// Nese **složený** rozsah, ne dvojici konců: složit ho umí jen `Policy` nad diffem, takže se
/// tím zaručí, že zvýraznění při tažení ukazuje přesně to, co z něj vznikne.
struct CommentRangeDrag: Equatable, Sendable {
    let pullRequest: PRIdentifier
    let path: String
    let anchor: DraftAnchor
}

/// Jedna kotva ke kontrole při přenesení draftu na nový commit (#69).
///
/// Vlastní typ, ne dvojice: `Equatable` nad n-ticí se nesyntetizuje a stav odesílání se s ním
/// porovnává (`ReviewSubmission.State`).
struct DraftAnchorCheck: Equatable, Sendable, Identifiable {
    let comment: ReviewDraftComment
    let state: DraftAnchorState

    var id: UUID { comment.id }
}
