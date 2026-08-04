import Foundation

/// Adresa vlákna, do kterého se odesílá.
///
/// Pull request je součástí adresy schválně, i když GraphQL mutace vystačí se samotným
/// `threadID`: brána `PublishScope` se ptá na **repo** a pre-flight na **stav PR**, takže
/// operace, která by PR neznala, by šla obojí obejít. Takhle to vynucuje typ — stejná úvaha,
/// kvůli které `GhReviewPublisher` nedostane scope s výchozí hodnotou.
struct ThreadTarget: Hashable, Sendable {
    let pullRequest: PRIdentifier
    /// `id` vlákna z GraphQL (`PRRT_…`), tedy to, co drží `ReviewThread.id`.
    ///
    /// **Ne `databaseId` komentáře**, se kterým pracuje REST `…/comments/{id}/replies`.
    /// Odpověď i vyřešení jdou přes GraphQL právě proto, že obojí adresuje **vlákno** —
    /// viz `ThreadRequest`.
    let threadID: String
}

/// Jak vlákno dopadlo po přepnutí vyřešení — to, co potvrdil GitHub.
///
/// Nese i **práva**, ne jen nový stav: mutace je vrací přepočítané (po vyřešení je
/// `canResolve` false a `canUnresolve` true), takže bez nich by okno po vyřešení nabízelo
/// `Znovu otevřít` podle práva, které platilo před akcí.
struct ThreadResolution: Hashable, Sendable {
    let threadID: String
    let isResolved: Bool
    let canResolve: Bool
    let canUnresolve: Bool
}
