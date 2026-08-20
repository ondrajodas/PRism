import Foundation

/// Změna labelů a vyžádání reviewera od kliknutí po odpověď GitHubu — **čtvrtý ze čtyř volajících
/// `ReviewPublishing`** (#392; předchozí jsou `ReviewSubmission`, `ThreadSubmission`
/// a `CommentSubmission`).
///
/// Existuje ze stejného důvodu jako všechny tři předchozí: publisher se skládá **až uvnitř** akce
/// a zaniká s ní, takže cesta ven není otevřená po celou dobu běhu aplikace a `AppStore` ji nemá
/// kde uložit (drží jen cestu ke `gh`).
///
/// **Jeden typ na obě akce, ne dva.** Je to tatáž věc z pohledu toho, co drží tvrdá podmínka č. 1:
/// obojí je metadata **vlastního** PR, obojí má tutéž bránu, obojí se nepotvrzuje sheetem a obojí
/// se ovládá ze stejných dvou sekcí panelu. Dva soubory by ten výčet cest ven prodloužily o jeden
/// řádek za nic — a smyslem toho výčtu je, že je krátký.
///
/// **Nepotvrzuje se**, jako odpověď do vlákna a komentář pod PR, a na rozdíl od review. Label je
/// vratný jedním klikem a nikoho neupozorní. Vyžádání reviewera vratné **není** (upozornění se
/// nedá vzít zpět) — proto na něj nevede `+`, ale pojmenované tlačítko s jménem toho člověka:
/// potvrzení je v tom, co je na tlačítku napsané, ne v druhém okně.
///
/// Proto je to `struct` bez stavu: kdo čeká na odpověď a co se nepovedlo, drží `AppStore`
/// (`MetadataActionState`) — je to stav okna jako každý jiný a musí přežít překliknutí tabu.
struct MetadataSubmission {
    let pullRequest: PRIdentifier

    /// Jak vyrobit **cestu ven**. Volá se až v akci.
    private let publisher: @MainActor () -> any ReviewPublishing

    init(pullRequest: PRIdentifier, publisher: @escaping @MainActor () -> any ReviewPublishing) {
        self.pullRequest = pullRequest
        self.publisher = publisher
    }

    /// Ostrá cesta: publisher se skládá z `gh` a read-only gateway (kvůli pre-flightu) a scope
    /// z konfigurace — stejně jako u vláken a komentářů.
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

    /// Nastaví celou sadu labelů a vrátí ji, jak ji potvrdil GitHub.
    ///
    /// Chyby **nepřevádí ani nepolyká** — volající z nich skládá stav, ve kterém je vidět, co se
    /// nepovedlo. `CancellationError` propouští jako `PublishError.interrupted` ze stejného důvodu
    /// jako review: zrušit jde jedině *během* volání, takže „nic se nestalo“ by bylo tvrzení, které
    /// nemáme čím podložit.
    @MainActor func setLabels(_ names: [String]) async throws -> [PullRequestLabel] {
        do {
            return try await publisher().setLabels(names, on: pullRequest)
        } catch is CancellationError {
            throw PublishError.interrupted
        }
    }

    /// Vyžádá review od jednoho člověka nebo týmu a vrátí to, na koho se podle GitHubu čeká.
    ///
    /// **Bere `ReviewerCandidate`, ne dvě pole**: nabídka je jedna a klikne se vždycky na jednu
    /// položku, takže volání, které umí obojí naráz, by nabízelo stav, do kterého se okno nedostane.
    @MainActor func requestReview(from candidate: ReviewerCandidate) async throws -> RequestedReview {
        do {
            switch candidate {
            case .person(let login):
                return try await publisher().requestReviewers([login], teams: [], on: pullRequest)
            case .team(let slug):
                return try await publisher().requestReviewers([], teams: [slug], on: pullRequest)
            }
        } catch is CancellationError {
            throw PublishError.interrupted
        }
    }
}

/// Co se právě děje s labely nebo reviewery. `nil` (tedy chybějící záznam) znamená „nic“.
///
/// **Jeden stav na obě akce, a je to schválně**: sekce jsou v panelu nad sebou a obě akce se
/// posílají tou samou branou, takže dvě odesílání naráz by znamenala dvě hlášky vedle sebe o dvou
/// věcech — v panelu 300 bodů. Běžící akce druhou nepustí, což je zároveň ta ochrana proti dvojkliku,
/// kterou mají odpovědi do vláken i komentáře.
///
/// **Vlastní typ, ne `CommentActionState`**: ten má jediný činný případ, kdežto tady se musí poznat,
/// **co** se odesílá — hláška „posílám“ nad labely, když se vyžaduje reviewer, mluví o něčem jiném,
/// než na co se člověk dívá.
enum MetadataActionState: Equatable, Sendable {
    case settingLabels
    case requestingReviewer
    /// Nepovedlo se. Drží se, dokud se nezkusí znovu — chyba, která zmizí sama, je chyba, kterou
    /// nikdo nepřečte.
    case failed(PublishError)

    var isBusy: Bool {
        switch self {
        case .settingLabels, .requestingReviewer: true
        case .failed: false
        }
    }

    var failure: PublishError? {
        if case .failed(let error) = self { error } else { nil }
    }
}
