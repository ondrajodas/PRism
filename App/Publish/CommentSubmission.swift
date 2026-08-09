import Foundation

/// Napsání komentáře do diskuze pod PR od kliknutí po odpověď GitHubu — **třetí ze tří
/// volajících `ReviewPublishing`** (#216; prvním je `ReviewSubmission`, druhým `ThreadSubmission`).
///
/// Existuje ze stejného důvodu jako oba předchozí: publisher se skládá **až uvnitř** akce
/// a zaniká s ní, takže cesta ven není otevřená po celou dobu běhu aplikace a `AppStore` ji nemá
/// kde uložit (drží jen cestu ke `gh`).
///
/// **Nepotvrzuje se**, jako odpověď do vlákna a na rozdíl od review: je to jedna věta v diskuzi,
/// dá se na GitHubu smazat a nenese verdikt. Review se potvrzuje proto, že schvaluje kód —
/// tohle o kódu netvrdí nic.
///
/// Proto je to `struct` bez stavu: kdo čeká na odpověď a co se nepovedlo, drží `AppStore`
/// (`CommentActionState`) — je to stav okna jako každý jiný a musí přežít překliknutí tabu.
struct CommentSubmission {
    let pullRequest: PRIdentifier

    /// Jak vyrobit **cestu ven**. Volá se až v `send(_:)`.
    private let publisher: @MainActor () -> any ReviewPublishing

    init(pullRequest: PRIdentifier, publisher: @escaping @MainActor () -> any ReviewPublishing) {
        self.pullRequest = pullRequest
        self.publisher = publisher
    }

    /// Ostrá cesta: publisher se skládá z `gh` a read-only gateway (kvůli pre-flightu) a scope
    /// z konfigurace — stejně jako u vláken.
    init(
        pullRequest: PRIdentifier,
        gh: URL,
        gateway: any GitHubGateway,
        scope: PublishScope
    ) {
        self.init(pullRequest: pullRequest) {
            GhReviewPublisher(gh: gh, runner: SubprocessRunner(), gateway: gateway, scope: scope)
        }
    }

    /// Odešle komentář a vrátí ho tak, jak ho potvrdil GitHub.
    ///
    /// Chyby **nepřevádí ani nepolyká** — volající z nich skládá stav, ve kterém je vidět, co se
    /// nepovedlo, a hlavně jestli text zůstal. `CancellationError` se propouští jako
    /// `PublishError.interrupted` ze stejného důvodu jako u review: zrušit jde jedině *během*
    /// volání, takže „nic se nestalo“ by bylo tvrzení, které nemáme čím podložit.
    @MainActor func send(_ body: String) async throws -> ThreadComment {
        do {
            return try await publisher().comment(on: pullRequest, body: body)
        } catch is CancellationError {
            throw PublishError.interrupted
        }
    }
}

/// Co se právě děje s komentářem pod PR. `nil` (tedy chybějící záznam) znamená „nic“.
///
/// Vlastní typ, ne `ThreadActionState`: ten má případy pro vyřešení vlákna, které tady nikdy
/// nenastanou. Stav, jehož polovina se nedá dosáhnout, svádí k tomu psát nad ním větve, které
/// nikdo neprojde — a `isBusy` by pak odpovídalo i na otázku, která se sem nehodí.
enum CommentActionState: Equatable, Sendable {
    /// Komentář se odesílá.
    case sending
    /// Odeslání se nepovedlo. Rozepsaný text u toho **zůstává** (`AppStore.pullRequestComments`),
    /// takže se dá odeslat znovu bez psaní nanovo — tatáž pojistka jako u odpovědi do vlákna.
    case failed(PublishError)

    /// Selhání se drží, dokud se nezkusí znovu — chyba, která zmizí sama, je chyba, kterou
    /// nikdo nepřečte.
    var isBusy: Bool {
        if case .sending = self { true } else { false }
    }

    var failure: PublishError? {
        if case .failed(let error) = self { error } else { nil }
    }
}
