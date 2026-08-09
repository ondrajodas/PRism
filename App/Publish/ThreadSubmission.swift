import Foundation

/// Jedna akce nad vláknem od kliknutí po odpověď GitHubu — **druhý ze tří volajících
/// `ReviewPublishing`** (prvním je `ReviewSubmission`, třetím `CommentSubmission`).
///
/// Existuje ze stejného důvodu jako `ReviewSubmission`: publisher se skládá **až uvnitř**
/// akce a zaniká s ní, takže cesta ven není otevřená po celou dobu běhu aplikace a `AppStore`
/// ji nemá kde uložit (drží jen cestu ke `gh`). Rozdíl je v tom, že tady není sheet ani snímek
/// draftu — odpověď do vlákna se podle #73 **nepotvrzuje**, protože je to jedna věta v diskuzi,
/// dá se smazat a potvrzovat každou by z okna udělalo klikačku.
///
/// Proto je to `struct` bez stavu: kdo čeká na odpověď a co se nepovedlo, drží `AppStore`
/// (`ThreadActionState`) — je to stav okna jako každý jiný a musí přežít odscrollování bubliny,
/// která je buňkou líného seznamu.
struct ThreadSubmission {
    let target: ThreadTarget

    /// Jak vyrobit **cestu ven**. Volá se až v `reply(_:)` a `setResolved(_:)`.
    private let publisher: @MainActor () -> any ReviewPublishing

    init(target: ThreadTarget, publisher: @escaping @MainActor () -> any ReviewPublishing) {
        self.target = target
        self.publisher = publisher
    }

    /// Ostrá cesta: publisher se skládá z `gh` a read-only gateway (kvůli pre-flightu) a scope
    /// z konfigurace — stejně jako u review, jen bez `headSha`.
    init(
        target: ThreadTarget,
        gh: URL,
        gateway: any GitHubGateway,
        scope: PublishScope
    ) {
        self.init(target: target) {
            GhReviewPublisher(gh: gh, runner: SubprocessRunner(), gateway: gateway, scope: scope)
        }
    }

    /// Odpoví do vlákna a vrátí komentář, jak ho potvrdil GitHub.
    ///
    /// Chyby **nepřevádí ani nepolyká** — volající z nich skládá stav, ve kterém je vidět, co
    /// se nepovedlo, a hlavně jestli text zůstal. `CancellationError` se propouští jako
    /// `PublishError.interrupted` ze stejného důvodu jako u review: zrušit jde jedině *během*
    /// volání, takže „nic se nestalo“ by bylo tvrzení, které nemáme čím podložit.
    @MainActor func reply(_ body: String) async throws -> ThreadComment {
        do {
            return try await publisher().reply(to: target, body: body)
        } catch is CancellationError {
            throw PublishError.interrupted
        }
    }

    /// Přepne vyřešení vlákna a vrátí stav i práva, jak je přepočítal GitHub.
    @MainActor func setResolved(_ resolved: Bool) async throws -> ThreadResolution {
        do {
            return try await publisher().setResolved(resolved, of: target)
        } catch is CancellationError {
            throw PublishError.interrupted
        }
    }
}

/// Co se s vláknem právě děje. `nil` (tedy chybějící záznam) znamená „nic“.
enum ThreadActionState: Equatable, Sendable {
    /// Posílá se odpověď.
    case replying
    /// Přepíná se vyřešení. Nese cíl, ať okno umí říct, co se právě děje.
    case resolving(to: Bool)
    /// Odpověď se nepovedla odeslat. Rozepsaný text u toho **zůstává**
    /// (`AppStore.threadReplies`), takže se dá odeslat znovu bez psaní nanovo — to je
    /// nejdůležitější věta celého #73.
    case replyFailed(PublishError)
    /// Nepovedlo se přepnout vyřešení.
    ///
    /// Vlastní případ, ne společné `failed`: hláška u odpovědi končí větou „text zůstal“, a ta
    /// je u vyřešení **nepravdivá** — není co zachraňovat. Bez rozlišení v modelu by to view
    /// nemělo jak poznat, takže by tu větu lepilo k obojímu.
    case resolutionFailed(PublishError)

    /// Selhání se drží, dokud se nezkusí znovu — chyba, která zmizí sama, je chyba, kterou
    /// nikdo nepřečte.
    var isBusy: Bool {
        switch self {
        case .replying, .resolving: true
        case .replyFailed, .resolutionFailed: false
        }
    }

    var failure: PublishError? {
        switch self {
        case .replyFailed(let error), .resolutionFailed(let error): error
        case .replying, .resolving: nil
        }
    }

    /// Zůstal po tomhle selhání v poli text, který se dá poslat znovu?
    var keptText: Bool {
        if case .replyFailed = self { true } else { false }
    }
}

/// Klíč stavu jednoho vlákna. Nese **pull request**, i když `id` vlákna je unikátní samo.
///
/// Je to tatáž úvaha jako u `toggledThreads` z #64: úklid odpovídá na otázku „zmizel PR ze
/// seznamu?“, a ta se z `id` vlákna nepozná. Plochá mapa klíčovaná jen `id` by po výpadku sítě
/// zůstala plná záznamů, které nemá co uklidit.
struct ThreadKey: Hashable, Sendable {
    let pullRequest: PRIdentifier
    let threadID: String
}
