import Foundation

/// Co je v tabu `Commity` k vidění (#316).
///
/// **Tři stavy, ne čtyři** — a ten chybějící je celý důvod, proč to tady stojí. `Kontroly` mají
/// `empty` (PR bez CI je běžný stav), kdežto **PR bez commitů neexistuje**, takže hláška o prázdnu
/// by lhala: tvrdila by o pull requestu něco, co o něm platit nemůže. Prázdná odpověď proto není
/// „žádné commity“, ale **porucha** — viz `Policy.commitsTab`.
///
/// Vlastní typ, ne dvojice optionalů ve view: čtou to dvě místa — odznak v pruhu záložek a plocha
/// tabu — a dvě různá skládání znamenají odznak, který mluví o jiném stavu než plocha pod ním.
enum CommitsTabState: Equatable, Sendable {
    /// Ještě nedorazily. **Nesmí tvrdit, že commity nejsou.**
    case loading
    /// Seznam, od nejstaršího. `failure` = poslední pokus o načtení selhal, takže je to **poslední
    /// známý stav**; stará sada se po selhání nechává být, stejně jako u checků (#215).
    ///
    /// Neprázdný vždycky — prázdný seznam se sem nedostane, viz `Policy.commitsTab`.
    case list([PullRequestCommit], failure: String?)
    /// Nepodařilo se je načíst a není co ukázat.
    case failed(String)
}

/// Věta nad seznamem commitů, rozdělená podle toho, jak se sází (#316).
///
/// `count` je tmavý a polotučný, `detail` tlumený — a dohromady je to jedna věta, takže se pro
/// čtečku i pro test skládá zpátky (`sentence`).
struct CommitsHeadline: Equatable, Sendable {
    let count: String
    let detail: String

    var sentence: String { "\(count) · \(detail)" }
}

extension Policy {
    /// Kolik commitů GitHub na jeden PR vydá, ať se stránkuje jak chce. Dokumentovaný strop API;
    /// je tady, aby se z něj dalo poznat, že seznam **není celý**.
    static let commitListCap = 250

    /// Co ukázat v tabu `Commity` (#316).
    ///
    /// Čtyři rozhodnutí v pořadí, ve kterém se ptají — první dvě jsou tatáž jako u `checksTab`,
    /// poslední je ta, kvůli které je tahle funkce vlastní:
    ///
    /// 1. **Neprázdný seznam přebíjí poruchu.** Zastaralý seznam s větou nad sebou je pořád lepší
    ///    než plocha s chybou místo commitů, které se před chvílí načetly.
    /// 2. **Porucha přebíjí nenačteno i prázdno.** Jinak by z chyby sítě vyšlo věčné
    ///    „Načítám commity…“.
    /// 3. **Chybějící klíč je „nenačteno“.** Tentýž rozdíl, kvůli kterému drží store seznam
    ///    a selhání ve dvou mapách.
    /// 4. **Prázdné pole je porucha, ne stav PR.** Pull request bez commitů neexistuje, takže
    ///    prázdná odpověď znamená, že se seznam nesehnal — a to se má říct, ne nakreslit klidnou
    ///    prázdnou plochu. Je to obrácená volba než u `Kontrol`, kde prázdno **je** odpověď (PR bez
    ///    CI), a rozdíl je právě v tom, jestli ten prázdný stav umí v realitě nastat.
    static func commitsTab(commits: [PullRequestCommit]?, failure: String?) -> CommitsTabState {
        if let commits, !commits.isEmpty { return .list(commits, failure: failure) }
        if let failure { return .failed(failure) }
        if commits == nil { return .loading }
        return .failed("GitHub vrátil prázdný seznam commitů. Pull request bez commitů neexistuje.")
    }

    /// Odznak u záložky `Commity` — **prostý počet, ne upozornění**.
    ///
    /// Tichá kapsle schválně: kolik je commitů, je údaj o množství, ne stav, kvůli kterému by se
    /// mělo někam chodit. Nad nenačteným ani spadlým stavem **nic** — nula by tvrdila, že se
    /// spočítalo, a to je zrovna to, co `Kontroly` naučila #306.
    static func commitsBadge(of state: CommitsTabState) -> PullRequestTabBadge? {
        guard case .list(let commits, _) = state, !commits.isEmpty else { return nil }
        return .count(commits.count)
    }

    /// Který commit v seznamu je **hlava PR** — tedy ten, proti kterému jsou klíčované nálezy
    /// (tvrdá podmínka č. 5). `nil` = žádný se tak označit nesmí.
    ///
    /// Rozhoduje **`headSha` z detailu, ne pozice v poli**. Poslední commit je hlavou jedině
    /// tehdy, když je seznam čerstvý; po pushnutém commitu je v seznamu pořád ten starý a pilulka
    /// `hlava` by u něj tvrdila přesně to, čemu má klíčování nálezů bránit. Když se hlava v seznamu
    /// nenajde, **neoznačí se nic** — mlčet je správnější než ukázat na commit, o kterém to neplatí.
    ///
    /// Dokud detail nedorazil (`head == nil`), platí definice endpointu: GitHub vrací commity od
    /// nejstaršího, takže hlavou je poslední. Je to jediný okamžik, kdy se to bere z pořadí, a je
    /// krátký — detail se tahá spolu se seznamem.
    static func headCommit(in commits: [PullRequestCommit], head: String?) -> PullRequestCommit? {
        guard let head else { return commits.last }
        return commits.first { $0.sha == head }
    }

    /// Věta nad seznamem: kolik jich je a v jakém pořadí (`.cbar` v návrhu).
    ///
    /// **Dvě části, ne jeden řetězec**, protože se sázejí různě: počet je tmavý a polotučný,
    /// zbytek tlumený (návrh: `.cbar b` má `--ink` a 620). Skládat to ve view ze dvou volání by
    /// znamenalo dvě místa, kde se dá napsat jiné číslo než to, které se počítá.
    ///
    /// **České skloňování má tři tvary** (`1 commit`, `2 commity`, `7 commitů`) a je to zrovna ten
    /// rozdíl, který zadání jmenuje mezi stavy, co se nesmí slít — „PR má jeden commit“ nemá znít
    /// jako chyba sazby.
    ///
    /// **Na stropu API to řekne.** Když se počet trefí do `commitListCap`, seznam nemusí být celý;
    /// věta o „250 commitech“ by pak tvrdila víc, než data unesou, takže se doplní, odkud ten strop
    /// je. Ověřovat to druhým voláním nemá cenu — GitHub další stránku nevydá, takže se pravdivější
    /// číslo stejně nedozvíme.
    static func commitsHeadline(count: Int) -> CommitsHeadline {
        let noun = commitNoun(count)
        guard count >= commitListCap else {
            return CommitsHeadline(count: "\(count) \(noun)", detail: "od nejstaršího")
        }
        return CommitsHeadline(
            count: "prvních \(count) \(noun)",
            detail: "od nejstaršího · víc jich GitHub přes API nevydá"
        )
    }

    /// `commit` / `commity` / `commitů` — pravidlo, ne tabulka: jedna, dvě až čtyři, ostatní.
    /// Záporné číslo nemá jak vzniknout, ale kdyby, spadne do posledního tvaru, který zní i nad
    /// nulou správně (`0 commitů`).
    static func commitNoun(_ count: Int) -> String {
        switch count {
        case 1: "commit"
        case 2...4: "commity"
        default: "commitů"
        }
    }
}
