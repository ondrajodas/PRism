import Foundation

/// Itinerář review (#506) — sběr vstupů, ze kterých `Policy.itinerary` skládá zastávky.
///
/// Stav (`openedFailedChecks`, `overviewReadToEnd`, `seenSinceLastVisit`, `previouslyVisited`)
/// zůstává v `AppStore.swift` — dělí se metody, ne data.
///
/// **Store jen sbírá, rozhoduje `Policy`.** Odsud nevede žádný `if` o tom, která zastávka
/// v itineráři je — tady se čtou fakta z pěti různých míst (návštěvy, konverzace, diff, značky,
/// checky) a slévají do jedné struktury, nad kterou se to dá vyčerpat výčtem.
extension AppStore {
    /// Fakta o PR pro itinerář. **Nad nenačteným diffem vrací platnou odpověď**, jen s nulovými
    /// počty souborů — počet, který se teprve načítá, nemá co tvrdit.
    func itineraryFacts(for pr: PRIdentifier) -> ItineraryFacts {
        let changes = changesSinceLastVisit(for: pr)
        let files = loadedDiff(for: pr)?.files ?? []
        let states = fileReviewStates(in: pr)
        let checkList = checks[pr] ?? []
        // **`nil` a prázdný popis nejsou totéž** (`description(of:)`): nenačtený detail znamená
        // „ještě nevím“, kdežto prázdný „autor nenapsal nic“. Zastávka je nehotová v obou
        // případech, ale údaj `bez popisu` patří jen k tomu druhému — proto dvě fakta, ne jedno.
        let body = description(of: pr)

        return ItineraryFacts(
            hasVisitRecord: previouslyVisited.contains(pr),
            commitsSinceVisit: changes.commits.count + changes.forcePushes.count,
            sawChangesSinceVisit: seenSinceLastVisit.contains(pr),
            descriptionKnown: body != nil,
            hasDescription: !(body ?? "").isEmpty,
            descriptionScrolled: overviewReadToEnd.contains(pr),
            fileCount: files.count,
            readFileCount: Policy.readFileCount(in: states),
            unreadLineCount: Policy.unreadLineCount(of: files, states: states),
            checks: Policy.summary(of: checkList),
            openedFailedChecks: openedFailedChecks[pr]?.count ?? 0,
            verdictSubmitted: hasSubmittedVerdict(on: pr),
            verdict: effectiveVerdict(for: pr)?.verdict
        )
    }

    /// Odeslal jsem na tenhle PR review s verdiktem?
    ///
    /// **Čte se z GitHubu, ne z draftu**: draft je rozmyšlené, ne odeslané, a zastávka `Verdikt`
    /// má být hotová právě tehdy, když je na PR vidět, co jsem si myslel. Nezaložená konverzace
    /// tedy znamená `false` — nenačtená data netvrdí odeslané review.
    ///
    /// `submittedAt` musí být, `pending` nestačí: rozepsané review na GitHubu odeslané není.
    func hasSubmittedVerdict(on pr: PRIdentifier) -> Bool {
        guard let conversation = conversation(for: pr) else { return false }
        return conversation.reviews.items.contains { review in
            conversation.isMine(review) && review.isVerdict && review.submittedAt != nil
        }
    }

    /// Zapíše, že se popis v `Přehledu` doroloval na konec (#506).
    ///
    /// **Jednosměrné**: odrolování nahoru značku nesundá, protože otázka je „přečetl jsem popis“,
    /// ne „kde je scroll teď“. A zapisuje se **jen na přechodu** — `overviewReadToEnd` je `Set`,
    /// takže druhé vložení téhož PR je zápis téže hodnoty a nikoho nebudí (`PollObservationTests`),
    /// ale stráž tu je i tak: geometrie scrollu chodí při každém přepočtu rozvržení.
    func noteOverviewReadToEnd(_ atEnd: Bool, for pr: PRIdentifier) {
        guard atEnd, !overviewReadToEnd.contains(pr) else { return }
        overviewReadToEnd.insert(pr)
    }

    /// Zapíše, že jsem viděl, co od minule přibylo (#506).
    func noteSawChangesSinceLastVisit(for pr: PRIdentifier) {
        guard !seenSinceLastVisit.contains(pr) else { return }
        seenSinceLastVisit.insert(pr)
    }

    /// Zapíše, že jsem rozbalil spadlý check (#506).
    ///
    /// **Jen spadlý.** Zelený check nemá co číst, takže jeho rozbalení o hotové zastávce nic
    /// neříká — a kdyby se počítal, dvanáct zelených by odškrtlo kontrolu, ve které je jeden
    /// červený.
    func noteOpenedCheck(_ check: PullRequestCheck, in pr: PRIdentifier) {
        guard check.outcome == .failed || check.outcome == .cancelled else { return }
        openedFailedChecks[pr, default: []].insert(check.name)
    }
}
