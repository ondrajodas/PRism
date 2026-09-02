import Foundation

/// Co je v otevřené záložce k vidění (#531).
///
/// Do #531 to byly dva stavy a rozhodovalo se o nich `if let` ve `ContentView`: buď se o PR ví ze
/// seznamu, nebo „pull request zmizel“. Se záložkou, kterou si člověk otevřel odkazem, přibyly
/// dva — a **rozdíl mezi „ještě se to načítá“ a „nepodařilo se to“ je zrovna ten, který se
/// v okně nesmí slít** (tatáž zásada jako u `ReviewState`): první je čekání, druhé je porucha,
/// kterou je potřeba umět zopakovat.
enum PullRequestTabContent: Equatable, Sendable {
    /// Ví se, o jaký PR jde — kreslí se detail.
    case detail(PullRequestSummary)
    /// Záložka mimo zdroje, o které se zatím ví jenom adresa.
    case loading
    /// Záložka mimo zdroje, jejíž detail se nepodařilo dotáhnout.
    case failed(String)
    /// PR ze zdrojů, který ze seznamu vypadl — mergnul se, nebo po mně review nikdo nechce.
    case gone
}

extension Policy {
    /// Co má záložka ukázat.
    ///
    /// - Parameters:
    ///   - summary: co se o PR ví (`AppStore.summary(for:)`). Nenulová hodnota rozhoduje sama —
    ///     u PR ze zdrojů i u dotaženého PR mimo ně.
    ///   - detail: stav dotažení detailu. Čte se **jen u záložky mimo zdroje**: u té ze zdrojů
    ///     je shrnutí ze seznamu a nenačtený detail znamená jen chybějící větve v hlavičce,
    ///     ne prázdnou obrazovku.
    ///   - origin: odkud se záložka vzala.
    static func tabContent(
        summary: PullRequestSummary?,
        detail: DetailState?,
        origin: PullRequestOrigin
    ) -> PullRequestTabContent {
        if let summary { return .detail(summary) }
        guard origin == .outsideSources else { return .gone }
        // `nil` i `.loaded` znamenají „ještě to nedorazilo“: `.loaded` se sem nedostane, protože
        // shrnutí se z dotaženého detailu skládá (a pak vyjde `.detail` o řádek výš), a `nil` je
        // ta jedna chvíle mezi otevřením záložky a začátkem dotahování.
        switch detail {
        case .failed(let reason): return .failed(reason)
        case .loading, .loaded, nil: return .loading
        }
    }

    /// Shrnutí záložky, o které se zatím ví jenom adresa (#531) — **jen pro pruh záložek**.
    ///
    /// Pruh kreslí `repo#číslo` a puntík stavu review, takže mu identifikátor stačí; titulek je
    /// v něm jedině jako tooltip a `Načítá se…` je přesně to, co v tu chvíli platí. Zbylá pole
    /// jsou vyplněná tak, aby nic netvrdila: autor je prázdný a `updatedAt` je `distantPast`,
    /// tedy hodnota, ze které se nedá udělat věta o stáří.
    ///
    /// **Nesmí se dostat do `summary(for:)`.** Tam by z něj byla hlavička s vymyšleným stavem
    /// `otevřený` a diff načtený proti `distantPast` — dokud detail nedorazí, je správná odpověď
    /// „ještě nevím“ (`PullRequestTabContent.loading`), ne shrnutí, které vypadá jako hotové.
    static func pendingSummary(for pullRequest: PRIdentifier) -> PullRequestSummary {
        PullRequestSummary(
            id: pullRequest,
            title: "Načítá se…",
            author: "",
            url: githubURL(of: pullRequest),
            updatedAt: .distantPast,
            state: .open
        )
    }
}
