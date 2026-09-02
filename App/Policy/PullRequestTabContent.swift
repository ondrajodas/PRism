import Foundation

/// Co je v otevřené záložce k vidění (#531, od #527 i pro obnovenou záložku).
///
/// Do #531 to byly dva stavy a rozhodovalo se o nich `if let` ve `ContentView`: buď se o PR ví ze
/// seznamu, nebo „pull request zmizel“. Se záložkou, kterou si člověk otevřel odkazem, přibyly
/// dva — a **rozdíl mezi „ještě se to načítá“ a „nepodařilo se to“ je zrovna ten, který se
/// v okně nesmí slít** (tatáž zásada jako u `ReviewState`): první je čekání, druhé je porucha,
/// kterou je potřeba umět zopakovat.
enum PullRequestTabContent: Equatable, Sendable {
    /// Ví se, o jaký PR jde — kreslí se detail.
    case detail(PullRequestSummary)
    /// Přijatá záložka, o které se zatím ví jenom adresa — otevřená odkazem (#531), nebo
    /// obnovená po restartu (#527).
    case loading
    /// Přijatá záložka, jejíž detail se nepodařilo dotáhnout.
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
    ///   - detail: stav dotažení detailu. Čte se **jen u přijaté záložky**: u té ze zdrojů
    ///     je shrnutí ze seznamu a nenačtený detail znamená jen chybějící větve v hlavičce,
    ///     ne prázdnou obrazovku.
    ///   - adoption: proč o té záložce polling nic neví — odkaz (#531), nebo obnovení po restartu
    ///     (#527). `nil` = obyčejná záložka ze zdrojů.
    ///
    ///     **Rozhoduje přijetí, ne `PullRequestOrigin`** (#527, mění #531). Pilulka v hlavičce
    ///     a obsah záložky totiž odpovídají na dvě různé otázky: pilulka na „proč tenhle PR není
    ///     ve frontě“ (tam obnovená záložka mlčí, viz `TabAdoption.restored`), kdežto tady jde
    ///     o „kdo tomu PR dotahuje detail“ — a to dělá aplikace u **obou** přijatých záložek.
    ///     S `origin`em by obnovená záložka nad mergnutým PR dostala `gone`, tedy větu
    ///     „pull request zmizel“ nad obrazovkou, kterou si aplikace zrovna sama načítá.
    static func tabContent(
        summary: PullRequestSummary?,
        detail: DetailState?,
        adoption: TabAdoption?
    ) -> PullRequestTabContent {
        if let summary { return .detail(summary) }
        guard adoption != nil else { return .gone }
        // `nil` i `.loaded` znamenají „ještě to nedorazilo“: `.loaded` se sem nedostane, protože
        // shrnutí se z dotaženého detailu skládá (a pak vyjde `.detail` o řádek výš), a `nil` je
        // ta jedna chvíle mezi otevřením záložky a začátkem dotahování.
        switch detail {
        case .failed(let reason): return .failed(reason)
        case .loading, .loaded, nil: return .loading
        }
    }

    /// Věta pod „Načítám pull request“ — a **liší se podle toho, proč se ta záložka dotahuje**
    /// (#527).
    ///
    /// Do #527 tady stála jediná věta, `<pr> není ve zdrojích, takže se o něm aplikace musí zeptat
    /// GitHubu`, a byla napsaná ve `ContentView`. U **obnovené** záložky by ale tvrdila víc, než co
    /// data unesou: obnovení běží před prvním tikem, takže se v tu chvíli **neví**, jestli PR ve
    /// zdrojích je — a u většiny obnovených záložek bude. Věta se proto rozhoduje tady, kde se dá
    /// vyčerpat výčtem.
    static func loadingTabNote(for pullRequest: PRIdentifier, adoption: TabAdoption?) -> String {
        switch adoption {
        case .link:
            "\(pullRequest) není ve zdrojích, takže se o něm aplikace musí zeptat GitHubu."
        case .restored:
            "Záložka se vrátila po restartu, takže se aplikace na \(pullRequest) musí zeptat GitHubu."
        // Sem se v aplikaci nedojde (bez přijetí vydá `tabContent` rovnou `gone`), ale věta musí
        // být pravdivá i tak — a tohle je to jediné, co platí vždycky.
        case nil:
            "Aplikace se na \(pullRequest) musí zeptat GitHubu."
        }
    }

    /// Věta pod „Pull request se nepodařilo načíst“ — taky podle důvodu přijetí (#527).
    ///
    /// U odkazu je první podezřelý **adresa** (může to být překlep). U obnovené záložky adresu
    /// nikdo nepsal — přišla z našeho vlastního snímku —, takže by rada „zkontroluj adresu“
    /// posílala člověka hledat chybu, kterou neudělal.
    static func failedTabNote(for pullRequest: PRIdentifier, adoption: TabAdoption?) -> String {
        switch adoption {
        case .link, nil:
            "\(pullRequest) se nepovedlo dotáhnout. Zkontroluj adresu — a jestli na to repo vidíš."
        case .restored:
            "\(pullRequest) se nepovedlo dotáhnout. Zkontroluj, jestli na to repo pořád vidíš."
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
