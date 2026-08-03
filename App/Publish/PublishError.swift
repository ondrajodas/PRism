import Foundation

/// Proč se review neodeslalo.
///
/// Typované schválně, stejně jako `GitHubError`: každý případ vede jinam. `lineOutsideDiff`
/// se spraví přesunutím komentáře, `pendingReviewExists` zavřením rozdělaného review
/// v prohlížeči, `ownPullRequest` změnou verdiktu na komentář, `staleDraft` novým čtením
/// diffu. Jedna hláška „nepovedlo se“ by z toho udělala hádanku.
///
/// Klasifikace z výstupu `gh` je **čistá funkce** (`init(failure:)`) a testuje se tabulkou
/// skutečných hlášek z fixtures ze spike #62 — je to křehké rozpoznávání z textu, takže
/// právě proto patří na jedno místo bez I/O.
enum PublishError: Error, Equatable {
    /// Repo není v `PublishScope`. Nic se nevolalo.
    case outsideAllowedScope(RepoID)
    /// Draft je psaný proti jinému commitu, než je teď hlava PR. Nic se nevolalo.
    case staleDraft(draft: String, head: String)
    /// PR není otevřený.
    case pullRequestNotOpen(PullRequestState)
    /// Draft je prázdný nebo bez verdiktu. Nic se nevolalo.
    case nothingToSend
    /// Komentář míří na řádek, který v diffu není. **Neodeslalo se nic** — volání je
    /// atomické (změřeno u #62).
    case lineOutsideDiff(String)
    /// Komentář míří na **soubor**, který v diffu není vůbec.
    ///
    /// Vlastní případ, ne varianta `lineOutsideDiff`: rada „přesuň komentář na řádek uvnitř
    /// diffu“ je tady nepravdivá, protože v diffu není celý soubor. Narazilo se na to při
    /// ověřování #67 proti živému API — GitHub vrací `Path could not be resolved`.
    case pathOutsideDiff(String)
    /// Na PR leží rozdělané (pending) review z prohlížeče.
    case pendingReviewExists
    /// Verdikt na vlastní PR. `APPROVE` i `REQUEST_CHANGES` GitHub zakazuje, `COMMENT` pustí.
    case ownPullRequest(String)
    case notAuthenticated
    case rateLimited(String)
    case network(String)
    case timedOut
    case toolUnavailable(String)
    /// Odpověď se nepodařilo přečíst — review možná odešlo, ale nevíme, jak vypadá.
    case malformedResponse(String)
    /// Cokoli, co se nepodařilo zařadit. Text `gh` se nese dál, protože je to jediné, co
    /// o tom víme.
    case unknown(String)
}

extension PublishError {
    /// Klasifikace selhání `gh api`. Tabulka sedí na skutečné hlášky z `Tests/Fixtures/gh/
    /// review-error-*.json`, které vznikly voláním živého API u #62.
    init(failure result: ProcessResult) {
        let text = result.failureText

        // `gh` má vlastní exit kód 4 pro chybějící přihlášení — jediné, co se pozná jinak
        // než z textu.
        if result.exitCode == 4 {
            self = .notAuthenticated
            return
        }

        switch true {
        case text.contains("Line could not be resolved"):
            self = .lineOutsideDiff(text)
        case text.contains("Path could not be resolved"):
            self = .pathOutsideDiff(text)
        case text.contains("one pending review"):
            self = .pendingReviewExists
        case text.contains("Can not approve your own"),
             text.contains("Can not request changes on your own"):
            self = .ownPullRequest(text)
        case text.contains("HTTP 401"), text.contains("gh auth login"):
            self = .notAuthenticated
        case text.lowercased().contains("rate limit"):
            self = .rateLimited(text)
        case text.contains("error connecting to"), text.contains("Could not resolve to"):
            self = .network(text)
        default:
            self = .unknown(text)
        }
    }

    /// Věta pro okno. Ke každé chybě patří i to, co s ní jde udělat — chyba, ze které
    /// nevyplývá další krok, je jen zpráva o smůle.
    var userDescription: String {
        switch self {
        case .outsideAllowedScope(let repo):
            "Odesílání je zatím povolené jen do sandboxu, ne do \(repo). Viz #107."
        case .staleDraft(let draft, let head):
            "Draft je psaný proti commitu \(draft.prefix(7)), ale hlava PR je \(head.prefix(7)). Načti diff znovu."
        case .pullRequestNotOpen(let state):
            "Pull request není otevřený — je \(state.czechLabel). Review se dá poslat jen na otevřený PR."
        case .nothingToSend:
            "Není co poslat — draft je prázdný nebo v něm chybí verdikt."
        case .lineOutsideDiff:
            "Některý komentář míří na řádek, který v diffu není. Neodeslalo se nic; přesuň ho na řádek uvnitř diffu."
        case .pathOutsideDiff:
            "Některý komentář míří na soubor, který v diffu není vůbec. Neodeslalo se nic; smaž ho nebo načti diff znovu."
        case .pendingReviewExists:
            "Na PR leží rozdělané review z prohlížeče. Dokonči ho nebo zahoď a zkus to znovu."
        case .ownPullRequest:
            "Na vlastní PR nejde poslat verdikt. Přepni na „jen komentář“."
        case .notAuthenticated:
            "`gh` není přihlášený. Spusť `gh auth login`."
        case .rateLimited:
            "GitHub omezuje počet dotazů. Zkus to za chvíli."
        case .network(let detail):
            "GitHub není dostupný: \(detail)"
        case .timedOut:
            "Odeslání trvalo moc dlouho. Zkontroluj na GitHubu, jestli review přesto nedošlo."
        case .toolUnavailable(let detail):
            "`gh` se nepodařilo spustit: \(detail)"
        case .malformedResponse(let detail):
            "Odpověď GitHubu nejde přečíst, takže nevím, jak review vypadá — zkontroluj ho na GitHubu. \(detail)"
        case .unknown(let detail):
            "Odeslání se nepovedlo: \(detail)"
        }
    }
}
