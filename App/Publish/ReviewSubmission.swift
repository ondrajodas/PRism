import Foundation
import Observation

/// Jedno odeslání review — od otevření potvrzovacího sheetu po odpověď GitHubu.
///
/// **Tady vzniká publisher a tady zaniká.** Tvrdá podmínka č. 1 říká, že `ReviewPublishing`
/// není pole `AppStore`: kdyby ho store držel, byla by cesta ven otevřená po celou dobu běhu
/// aplikace a stačilo by ji omylem zavolat odjinud. Takhle se skládá až uvnitř `send()`,
/// z toho, co dostal `init`, a s koncem tohohle objektu je pryč. Že je cest ven jedna,
/// vyjmenuje `grep ReviewPublishing`: protokol, `GhReviewPublisher` a tenhle soubor.
///
/// Objekt vzniká **kliknutím na „Odeslat review…“** a zaniká zavřením sheetu. Draft si drží
/// jako **snímek**, ne odkaz do store: co je v sheetu vidět, to se odešle, i kdyby se draft
/// mezitím změnil.
@MainActor
@Observable
final class ReviewSubmission: Identifiable {
    /// Kvůli `.sheet(item:)`. Identita je „tohle jedno odeslání“, ne PR — druhé kliknutí
    /// po zavření sheetu je nové odeslání s novým snímkem.
    let id = UUID()

    let pullRequest: PullRequestSummary
    /// Co odejde. Snímek pořízený při otevření sheetu.
    ///
    /// Přepsat ho umí **jedině přenesení na nový commit** (#69), a to je výslovná akce člověka
    /// v tomtéž okně — takže „co je v potvrzení vidět, to se odešle“ platí dál.
    private(set) var draft: ReviewDraft
    /// Návrh verdiktu z nálezů — v sheetu stojí **vedle** zvoleného, aby se dal porovnat.
    /// Nepředvyplňuje nic; volba už padla v tabu `Moje review`.
    let suggestion: ReviewVerdict?

    /// Kotvy ke kontrole, když je draft psaný proti staršímu commitu (#69). Prázdné, když
    /// není co kontrolovat.
    private(set) var anchors: [DraftAnchorCheck]
    /// Commit, na který se draft přenáší — **hlava PR**, ne to, proti čemu je draft psaný
    /// (`draft.headSha`). `nil` = nepřenáší se.
    ///
    /// Drží se zvlášť schválně: po přenesení ho má draft v `headSha`, ale **před** ním se musí
    /// vzít odjinud — a v okně se jmenuje v tlačítku, takže si ho nesmí splést s identifikátorem PR.
    let targetHead: String?

    private(set) var state: State

    enum State: Equatable {
        /// Draft je psaný proti staršímu commitu — **než se dá odeslat, musí se zkontrolovat**,
        /// co se stane s každou kotvou. Odsud se dá jen přenést (nebo zavřít).
        case checking
        case ready
        case sending
        /// Odeslání selhalo. **Draft zůstal netknutý** — nic se nemazalo.
        case failed(PublishError)
        /// GitHub review přijal; tohle je to, co potvrdil.
        case sent(SubmittedReview)
    }

    /// Jak vyrobit **jedinou cestu ven**. Volá se až v `send()`.
    private let publisher: @MainActor () -> any ReviewPublishing
    /// Co udělat po úspěchu — smazat draft a načíst konverzaci znovu. Skládá to `AppStore`,
    /// protože obojí je jeho stav; tenhle objekt o něm nic neví.
    private let afterSuccess: @MainActor () async -> Void
    /// Jak draft přenést na nový commit (#69). Vrací **nový snímek**, nebo `nil`, když to
    /// nešlo. Dělá to `AppStore`, protože přenesený draft se ukládá na disk.
    private let applyTransfer: @MainActor ([UUID: DraftTransferChoice]) -> ReviewDraft?

    init(
        pullRequest: PullRequestSummary,
        draft: ReviewDraft,
        suggestion: ReviewVerdict?,
        anchors: [DraftAnchorCheck] = [],
        needsTransfer: Bool = false,
        targetHead: String? = nil,
        publisher: @escaping @MainActor () -> any ReviewPublishing,
        afterSuccess: @escaping @MainActor () async -> Void,
        applyTransfer: @escaping @MainActor ([UUID: DraftTransferChoice]) -> ReviewDraft? = { _ in nil }
    ) {
        self.pullRequest = pullRequest
        self.draft = draft
        self.suggestion = suggestion
        self.anchors = anchors
        self.targetHead = targetHead
        self.publisher = publisher
        self.afterSuccess = afterSuccess
        self.applyTransfer = applyTransfer
        // **Ne podle prázdnosti kotev**: draft bez řádkových komentářů (jen tělo a verdikt) je
        // zastaralý taky a přenesením se mu posune commit, proti kterému je psaný. Odvozovat to
        // z kotev by ho poslalo proti staré hlavě, kterou pre-flight odmítne.
        state = needsTransfer ? .checking : .ready
    }

    /// Ostrá cesta: publisher se skládá z `gh` a read-only gateway (kvůli pre-flightu) —
    /// a skládá se **až** ve chvíli odesílání.
    convenience init(
        pullRequest: PullRequestSummary,
        draft: ReviewDraft,
        suggestion: ReviewVerdict?,
        anchors: [DraftAnchorCheck] = [],
        needsTransfer: Bool = false,
        targetHead: String? = nil,
        gh: URL,
        gateway: any GitHubGateway,
        scope: PublishScope,
        afterSuccess: @escaping @MainActor () async -> Void,
        applyTransfer: @escaping @MainActor ([UUID: DraftTransferChoice]) -> ReviewDraft? = { _ in nil }
    ) {
        self.init(
            pullRequest: pullRequest,
            draft: draft,
            suggestion: suggestion,
            anchors: anchors,
            needsTransfer: needsTransfer,
            targetHead: targetHead,
            // Brána je snímek konfigurace z okamžiku kliknutí — stejně jako draft. Co je
            // vidět v potvrzení, to platí i při odeslání.
            publisher: {
                GhReviewPublisher(gh: gh, runner: SubprocessRunner(), gateway: gateway, scope: scope)
            },
            afterSuccess: afterSuccess,
            applyTransfer: applyTransfer
        )
    }

    /// Přenese draft na nový commit podle rozhodnutí z kontroly a přepne na potvrzení payloadu.
    ///
    /// Dva kroky v jednom okně schválně (#69): zkontrolovat kotvy se musí tak či tak, než se
    /// review pošle, takže druhé okno by byl jen mezikrok. Odesílá se pořád **dvěma kliknutími
    /// na dvě různá tlačítka**, což je pravidlo z #68 — jen to první je teď „přenést“.
    func transfer(choices: [UUID: DraftTransferChoice]) {
        guard state == .checking, let transferred = applyTransfer(choices) else { return }
        draft = transferred
        anchors = []
        state = .ready
    }

    /// Verdikt, který odejde. Bez něj by se sheet neotevřel (`Policy.sendBlock`), takže
    /// `nil` znamená rozbitý stav, ne nabídku hádat.
    var verdict: ReviewDraft.Verdict? { draft.verdict }

    /// Rozchází se moje volba s tím, co navrhly nálezy?
    ///
    /// Není to zákaz — nálezy jsou návrh a člověk je od toho, aby je přebil. Ale schválit PR,
    /// u kterého reviewer hlásí blokující nález, je ta nejdražší záměna, jakou tohle okno umí,
    /// takže se to v potvrzení říká nahlas.
    var contradictsSuggestion: Bool {
        switch (suggestion, draft.verdict) {
        case (.requestChanges, .approve), (.approve, .requestChanges): true
        default: false
        }
    }

    /// Odeslalo se a **není k tomu co dodat** — sheet se pak zavírá sám.
    ///
    /// Že review odešlo, je za sheetem vidět líp než v něm: rozdělané review zmizelo z panelu
    /// i z řádku a v `Přehledu` přibylo to moje. Nechat kvůli tomu okno otevřené znamená jedno
    /// kliknutí navíc za informaci, kterou má člověk stejně před sebou.
    ///
    /// `false` u odpovědi, **jejímuž stavu nerozumíme**: tam je jediná zpráva ta, že se to má
    /// zkontrolovat na GitHubu — a ta se jinde v okně nedozví, protože review tam bude vypadat
    /// jako každé jiné. Zavřít sheet by ji spolklo.
    var closesItself: Bool {
        guard case .sent(let review) = state else { return false }
        return review.state != nil
    }

    /// Dá se (znovu) odeslat? Za běhu ne a po úspěchu už vůbec — druhé review by bylo druhé
    /// review, ne oprava toho prvního.
    ///
    /// **A po selhání jen tehdy, když je jisté, že nic neodešlo.** Chyba typu „vypršel čas“
    /// nebo „odpovědi nerozumím“ znamená, že review na PR **může ležet** — a nabídnout nad ní
    /// tlačítko `Odeslat` je přesně ta cesta, jak poslat approve dvakrát. Zkusit to znovu jde
    /// pořád, jen se to musí vědomě otevřít znovu; draft zůstal.
    var canSend: Bool {
        switch state {
        case .ready: true
        case .failed(let error): !error.mightHaveReachedGitHub
        // `.checking` je zastaralý draft (#69): dokud se nepřenese, odeslat se nemá co.
        case .checking, .sending, .sent: false
        }
    }

    /// Odešle review. **Jediné místo v aplikaci, které volá `ReviewPublishing.submit`.**
    ///
    /// Selhání nechává draft beze změny: uklízí se až po potvrzené odpovědi, takže se po
    /// chybě dá zkusit znovu, aniž by se text musel psát podruhé.
    /// Odeslání. V `.checking` **nedělá nic**: dokud se draft nepřenesl, je psaný proti jinému
    /// commitu, než na který by se odeslal — a přesně to `GhReviewPublisher` v pre-flightu odmítne.
    /// Kontrola tady je proto, aby se na tu chybu nešlo naběhnout z UI.
    func send() async {
        guard canSend else { return }
        state = .sending
        do {
            let review = try await publisher().submit(draft)
            // Stav se přepíná **před** úklidem: mazání draftu a načtení konverzace je práce
            // na disku a po síti, a potvrzení, že review odešlo, na ni nemá čekat.
            state = .sent(review)
            await afterSuccess()
        } catch let error as PublishError {
            state = .failed(error)
        } catch is CancellationError {
            // **Ne `.ready`.** Zrušit se dá jedině *během* volání, takže se nedá tvrdit, že se
            // nic nestalo — POST mohl doběhnout. Je to tentýž omyl jako u `timedOut`, jen
            // schovanější, a dnes nedosažitelný (task odeslání se neruší). Přesto se tvar
            // drží: až něco rušit půjde (#73), nesmí se to spolknout jako „nic se nestalo“.
            state = .failed(.interrupted)
        } catch {
            state = .failed(.unknown(error.localizedDescription))
        }
    }
}
