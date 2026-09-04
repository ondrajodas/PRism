import Foundation
import Observation

/// Jeden merge — od otevření potvrzení po odpověď GitHubu. **Pátý z pěti volajících
/// `ReviewPublishing`** (#465).
///
/// **Vlastní typ, ne metoda v `MetadataSubmission`**, a je to jediné místo, kde se tenhle milník
/// od #392 liší: labely a reviewery jsou akce **z panelu**, které se dějí a mizí, kdežto merge má
/// **potvrzovací obrazovku a životnost** — objekt vzniká kliknutím na `Mergnout…`, drží snímek
/// toho, co se potvrzuje, a zaniká zavřením sheetu. Je to tvarem `ReviewSubmission`, ne
/// `MetadataSubmission`, protože je to tatáž věc: poslední brána před tím, než něco opustí stroj.
///
/// **Tady vzniká publisher a tady zaniká** (tvrdá podmínka č. 1). `AppStore` ho nemá kde uložit —
/// drží jen cestu ke `gh`.
@MainActor
@Observable
final class MergeSubmission: Identifiable {
    /// Kvůli `.sheet(item:)`. Identita je „tenhle jeden merge“, ne PR — druhé kliknutí po zavření
    /// sheetu je nový merge s novým snímkem.
    let id = UUID()

    let pullRequest: PullRequestSummary
    /// S čím se sheet otevřel. **Snímek pořízený při otevření**, ne odkaz do storu: co je
    /// v potvrzení vidět, to odejde, i kdyby mezitím dorazil polling s jiným počtem commitů.
    ///
    /// Nese i **výchozí metodu z nastavení** a **co repozitář povoluje** (#556) — obojí jako
    /// snímek, ze stejného důvodu jako brána: co je předvybrané, je to, co v nastavení stálo, když
    /// se sheet otvíral.
    let proposal: MergeProposal

    /// Vybraná metoda. `nil` = **nic není vybráno**, tedy stav, ve kterém se merge zastaví.
    ///
    /// Do `nil` se dostane jedině tak, že **výchozí metodu repozitář nepovoluje**
    /// (`Policy.initialMergeMethod`): tiše podstrčit první povolenou by znamenalo, že u nevratné
    /// akce odejde něco, o co nikdo nepožádal. Ze sheetu se `nil` nastavit nedá — pilulka se
    /// nepřepíná zpátky na „nic“.
    ///
    /// **`var`, ne `let`, a je to jediný proměnný vstup téhle třídy.** Přepnutí platí pro tenhle
    /// jeden merge a s objektem zaniká; nastavení se z něj **nezapisuje** (věta o tom stojí
    /// v sheetu pod výpisem, `Policy.mergeMethodOverrideNote`).
    var method: MergeMethod?

    /// Co odejde. `nil`, dokud není vybraná metoda — a právě proto je `canMerge` v tom stavu
    /// nepravda: payload, ze kterého se nedá složit `merge_method`, se nemá jak potvrdit.
    ///
    /// **Skládá se z návrhu, ne drží zvlášť**, aby se nedalo přepnout metodu a nechat řádky
    /// výpisu od té předchozí: sheet kreslí `commitů`, `titulek` i větu o těle **z tohohle
    /// plánu**, takže se s payloadem nemají jak rozejít.
    var plan: MergePlan? { method.map { proposal.plan(with: $0) } }

    private(set) var state: State

    enum State: Equatable {
        case ready
        case merging
        /// Nepovedlo se. **Na PR se nesáhlo** u všeho kromě `timedOut` a `malformedResponse` —
        /// rozhoduje o tom `PublishError.mightHaveReachedGitHub`, jako u review.
        case failed(PublishError)
        /// GitHub merge potvrdil; tohle je commit, který vznikl.
        case merged(MergedPullRequest)
    }

    /// Jak vyrobit **jedinou cestu ven**. Volá se až v `merge()`.
    private let publisher: @MainActor () -> any ReviewPublishing
    /// Co udělat po úspěchu — načíst stav PR znovu, aby okno nenabízelo merge podruhé. Skládá to
    /// `AppStore`, protože je to jeho stav; tenhle objekt o něm nic neví.
    private let afterSuccess: @MainActor () async -> Void

    init(
        pullRequest: PullRequestSummary,
        proposal: MergeProposal,
        publisher: @escaping @MainActor () -> any ReviewPublishing,
        afterSuccess: @escaping @MainActor () async -> Void
    ) {
        self.pullRequest = pullRequest
        self.proposal = proposal
        self.publisher = publisher
        self.afterSuccess = afterSuccess
        // **Rozhoduje `Policy`, ne tenhle init.** Je to ta samá funkce, kterou se ptá nabídka
        // v sheetu — dvě místa by uměla vybrat metodu, kterou nabídka nedovolí vybrat.
        method = Policy.initialMergeMethod(
            default: proposal.defaultMethod,
            in: proposal.repository
        )
        state = .ready
    }

    /// Ostrá cesta: publisher se skládá z `gh` a read-only gateway (kvůli pre-flightu) — a skládá
    /// se **až** ve chvíli odesílání.
    convenience init(
        pullRequest: PullRequestSummary,
        proposal: MergeProposal,
        gh: URL,
        gateway: any GitHubGateway,
        scope: PublishScope,
        afterSuccess: @escaping @MainActor () async -> Void
    ) {
        self.init(
            pullRequest: pullRequest,
            proposal: proposal,
            // Brána je snímek konfigurace z okamžiku kliknutí — stejně jako plán.
            publisher: {
                GhReviewPublisher(gh: gh, runner: SubprocessRunner(), gateway: gateway, scope: scope)
            },
            afterSuccess: afterSuccess
        )
    }

    /// Dá se (znovu) mergnout?
    ///
    /// **Po selhání jen tehdy, když je jisté, že se nic nestalo.** `timedOut` a `malformedResponse`
    /// znamenají, že merge **mohl** proběhnout — a tlačítko `Mergnout` nad mergnutým PR je
    /// pozvánka ke druhému pokusu, ze kterého v lepším případě vyleze chyba a v horším zmatek.
    /// Tatáž úvaha jako u review, jen o stupeň dražší.
    var canMerge: Bool {
        // **Bez vybrané metody se nemerguje** (#556) — a je to podmínka nad stavem, ne kontrola ve
        // view: sheet se v tom stavu otevře schválně (aby řekl, co repo povoluje), takže tlačítko
        // musí být zakázané z dat, ne z toho, že si to view pohlídá.
        guard plan != nil else { return false }
        switch state {
        case .ready: return true
        case .failed(let error): return !error.mightHaveReachedGitHub
        case .merging, .merged: return false
        }
    }

    /// Mergnulo se a **není k tomu co dodat** — sheet se pak zavírá sám, stejně jako u odeslaného
    /// review (`ReviewSubmission.closesItself`).
    ///
    /// **Bez podmínky, na rozdíl od review.** Tam je to nepravda u odpovědi, jejímuž stavu
    /// nerozumíme, protože ta se jinde v okně nedozví; u merge taková odpověď neexistuje —
    /// `GhMergeResponse.merge()` z ní udělá `malformedResponse`, tedy selhání. A selhání sheet
    /// nechává otevřený schválně: je to jediné místo, kde je vidět, co GitHub odmítl.
    var closesItself: Bool {
        if case .merged = state { true } else { false }
    }

    /// Mergne. **Jediné místo v aplikaci, které volá `ReviewPublishing.merge`.**
    func merge() async {
        // Plán je tady **podmínka, ne údaj**: `canMerge` na něj sahá taky, ale bez vybrané metody
        // není co poslat — a `merge_method` si publisher nedomýšlí.
        guard canMerge, let plan else { return }
        state = .merging
        do {
            let merged = try await publisher().merge(plan)
            // Stav se přepíná **před** úklidem, jako u review: načíst PR znovu je práce po síti
            // a potvrzení, že merge prošel, na ni nemá čekat.
            state = .merged(merged)
            // Úklid **zavírá i záložku toho PR** (#465) a je to první, co udělá — ještě než se
            // `merge()` vrátí volajícímu, který teprve podle `closesItself` zavírá sheet. Pořadí
            // tedy drží tenhle řádek, ne view: sheet se nemá jak zavřít dřív než záložka pod ním.
            await afterSuccess()
        } catch let error as PublishError {
            state = .failed(error)
        } catch is CancellationError {
            // **Ne `.ready`.** Zrušit jde jedině *během* volání, takže se nedá tvrdit, že se nic
            // nestalo — `PUT` mohl doběhnout. Tatáž úvaha jako u review.
            state = .failed(.interrupted)
        } catch {
            state = .failed(.unknown(error.localizedDescription))
        }
    }
}
