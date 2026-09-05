import Foundation

/// Smyčka vlastního pull requestu (#508) — **sedm stanic v pořadí, ve kterém se kolo jde**.
///
/// **Proč dráha a ne sedm ukazatelů rozsetých po okně.** Do #508 byla smyčka rozsekaná po
/// místech: nálezy v panelu, zadání v sheetu, agent někde v terminálu, push a merge v sekci
/// `Větev`, Copilot v konverzaci. Odpověď na „kde v tom kole zrovna jsem“ si člověk skládal sám
/// a řádek v seznamu o tom řekl jen `6 k předání`.
///
/// **Kreslí se třídami dráhy reviewera** (`.lane`, `.phases`, `.ph` — návrh, sekce 52). Je to
/// tentýž druh věci: proces s fázemi, u kterého je otázka „kde to stojí“. Okno jeden způsob, jak
/// proces kreslit, umí; druhý by byl třetí jazyk pro totéž. Ze stejného důvodu je stav stanice
/// **`ReviewerLane.PhaseState`**, ne vlastní výčet — kdyby byl vlastní, dala by se v něm vyrobit
/// hodnota, kterou kresba fází neumí, a slib „bez nového vzoru“ by držel jen komentář.
///
/// **Sedm stanic je dráha, ne sedm nezávislých odznaků.** Walk jde po pořádku a **zastaví se na
/// první, která není hotová** — všechno za ní je `idle`. Není to úspora: tvrdit něco o CI nad
/// kódem, který ještě není pushnutý, znamená mluvit o **minulém** pushi. Co dráha zamlčí, je
/// pořád vidět tam, kde to bydlí (tab `Kontroly`, sekce `Větev`, panel `Zadání`); dráha říká
/// jedno, a to je pořadí.
struct OwnLoop: Equatable, Sendable {
    /// Stanice smyčky **v pořadí, ve kterém se jde**. Pořadí je součást typu, ne věc kresby —
    /// `allCases` je to jediné, podle čeho se dráha skládá, a testuje se, že jich je sedm.
    enum Station: CaseIterable, Hashable, Sendable {
        /// Co o kódu řekly moje reviewery.
        case findings
        /// Co z toho zbývá předat agentovi (#334).
        case handoff
        /// Agent na tom pracuje. **Bez živého obsahu až do #511**: aplikace o cizím terminálu neví
        /// nic, takže stanice datuje předání a čeká na commit — rozhoduje `Policy.ownLoop`.
        case agent
        /// Větev: srovnat nad základem a přetlačit (#466).
        case push
        /// Kontroly na GitHubu.
        case ci
        /// Cizí review — kdo se vyjádřil a jak (#392).
        case review
        /// Sloučit (#465).
        case merge

        /// Popisek kapsle. **Krátký schválně**: sedm kapslí se dělí o šířku hlavičky, takže se
        /// stav a číslo vejdou jedině za jednoslovný název (tatáž mez jako u `ReviewerLane.Title`).
        var title: String {
            switch self {
            case .findings: "Nálezy"
            case .handoff: "Zadání"
            case .agent: "Agent"
            case .push: "Push"
            case .ci: "CI"
            case .review: "Review"
            case .merge: "Merge"
            }
        }
    }

    /// Jedna stanice na dráze.
    ///
    /// `detail` je to, co v kapsli stojí za názvem (`3 ✓`, `6 předáno`, `o 4 vzadu`). `nil`
    /// znamená, že se nedá dodat nic — ne že je něco nula.
    struct Stop: Hashable, Sendable {
        let station: Station
        /// Doslova ta hodnota, kterou používá dráha reviewera. Viz poznámka u `OwnLoop`.
        let state: ReviewerLane.PhaseState
        let detail: String?
    }

    /// Jediná akce aktivní stanice — a je to **navigace, ne druhá cesta ven**.
    ///
    /// Obsahem stanic `Zadání`, `Push` a `Merge` je dnešní panel `Zadání` (#334) a sekce `Větev`
    /// (#465, #466); nic z toho se neruší ani nekopíruje. Kdyby dráha odesílala sama, byla by to
    /// druhá cesta na GitHub (tvrdá podmínka č. 1) a druhé místo, které skládá plán merge — tedy
    /// dvě odpovědi na jednu otázku. Dráha proto **otevře to místo, kde ta práce bydlí**, a nic
    /// jiného neumí.
    ///
    /// **`Spustit review` mezi nimi není, a je to rozhodnutí z proklikání** (#508): to tlačítko
    /// stojí v hlavičce o pár bodů výš a #218 mu vyhradilo **jediné akcentové místo**
    /// v celém pruhu. Druhá kopie vedle něj by z hlavičky udělala semafor a obě by se přestaly
    /// číst. Stanice `Nálezy` proto akci **nemá** — co dělat, říká věta pod fázemi.
    enum Move: Hashable, Sendable {
        /// Otevřít panel na segmentu `Zadání`.
        case openHandoff
        /// Rozložit panel, kde je sekce `Větev` (rebase, force push, merge).
        case openBranch
        /// Přepnout na záložku `Kontroly`.
        case openChecks
        /// Přepnout na záložku `Konverzace`.
        case openConversation

        var title: String {
            switch self {
            case .openHandoff: "Otevřít zadání"
            case .openBranch: "Otevřít větev"
            case .openChecks: "Otevřít kontroly"
            case .openConversation: "Otevřít konverzaci"
            }
        }

        var symbol: String {
            switch self {
            case .openHandoff: "list.bullet.rectangle"
            case .openBranch: "arrow.triangle.branch"
            case .openChecks: "checkmark.seal"
            case .openConversation: "bubble.left.and.bubble.right"
            }
        }
    }

    /// Všech sedm, vždycky a v pořadí `Station.allCases`. Prázdná dráha neexistuje: stanice, na
    /// kterou se nedošlo, je `idle`, a to je odpověď.
    let stations: [Stop]
    /// Kde smyčka stojí. **`nil` = došla** — pull request je mergnutý, nebo zavřený.
    let active: Station?
    /// Jedna věta o tom, co je na tahu (`.last` z návrhu). Nikdy prázdná.
    let last: String
    /// Jediná akce aktivní stanice. `nil` = tah není můj (běží session, čeká se na kolegu), nebo
    /// se ještě neví.
    let move: Move?
    /// Razítko do hlavičky dráhy (`.meta`) — `předáno 6 položek · proti 9c1de02`. `nil` =
    /// nepředávalo se, takže není co říct.
    let stamp: String?

    /// Stav jedné stanice — pro řádek seznamu (#509) a pro testy, které se ptají adresně.
    func state(of station: Station) -> ReviewerLane.PhaseState {
        stations.first { $0.station == station }?.state ?? .idle
    }
}
