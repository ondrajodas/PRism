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
    /// Seznam **v pořadí, ve kterém se kreslí** — od nejnovějšího, viz `Policy.commitsNewestFirst`.
    /// `failure` = poslední pokus o načtení selhal, takže je to **poslední známý stav**; stará sada
    /// se po selhání nechává být, stejně jako u checků (#215).
    ///
    /// Že je to pořadí kresby, a ne pořadí z API, je vlastnost typu schválně: store drží to, co
    /// přišlo, view kreslí to, co dostane, a **otočit se to smí jen na jednom místě**. Dvě místa by
    /// znamenala dvě pravdy o tom, který řádek je nahoře.
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
    /// čtvrté je to, kvůli kterému je tahle funkce vlastní:
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
    ///
    /// **Pořadí se otáčí tady, a jedině tady** (`commitsNewestFirst`): je to jediná cesta, kterou se
    /// seznam dostane do okna, takže odznak i plocha tabu mluví o témž a view nemá co rozhodovat.
    static func commitsTab(commits: [PullRequestCommit]?, failure: String?) -> CommitsTabState {
        if let commits, !commits.isEmpty { return .list(commitsNewestFirst(commits), failure: failure) }
        if let failure { return .failed(failure) }
        if commits == nil { return .loading }
        return .failed("GitHub vrátil prázdný seznam commitů. Pull request bez commitů neexistuje.")
    }

    /// Pořadí, ve kterém se seznam commitů kreslí: **od nejnovějšího**.
    ///
    /// **Otočeno proti návrhu** (#316). Mockup, sekce 19, i specifikace měly „od nejstaršího, jako
    /// na GitHubu, protože PR se čte jako postup“. Neobstálo to na hotové obrazovce: v tomhle okně
    /// se PR nečte od začátku, ale **od toho, co přibylo naposled** — je to tentýž pohyb, jaký dělá
    /// pruh „Od tvé poslední návštěvy“, a tentýž důvod, proč jsou fakta v `Přehledu` nahoře (#280).
    /// Postup se z otočeného seznamu přečte pořád, jen odspodu; kdežto „co se stalo teď“ by se
    /// v původním pořadí u dlouhého PR muselo doscrollovat.
    ///
    /// **Otáčí se, neřadí.** Pořadí z API je topologické, takže po rebase nebo cherry-picku je
    /// datum starší než pozice — seřadit podle `committedAt` by ten postup rozházelo. Otočení
    /// pořadí zachovává, jen ho čte z druhé strany.
    ///
    /// **Nepamatuje se to, a je to změřené, ne odhadnuté.** `commitsTab` běží při každém překreslení
    /// (odznak i plocha tabu), takže otočení je práce na redraw — jenže **18,7 µs** pro 250 commitů
    /// (strop API, Debug) proti **54 ms**, co stojí sazba téhož seznamu (#316). Cache by tady stála
    /// víc pozornosti, než kolik ušetří.
    static func commitsNewestFirst(_ commits: [PullRequestCommit]) -> [PullRequestCommit] {
        commits.reversed()
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
    /// Rozhoduje **`headSha` z detailu, ne pozice v poli** — a od otočení seznamu na „nejnovější
    /// nahoře“ je ten rozdíl o to snazší přehlédnout: pilulka **bývá** na prvním řádku, ale je to
    /// **důsledek** toho, jak seznam přišel, ne pravidlo. Nahoře je nejnovější commit **z toho, co
    /// GitHub vydal**; hlava je ten, proti kterému jsou klíčované nálezy. Rozejdou se ve dvou
    /// běžných situacích, a v obou by pilulka nahoře lhala:
    ///
    /// - po pushnutém commitu je seznam o krok pozadu, takže nahoře stojí commit, proti kterému
    ///   nálezy neplatí;
    /// - nad stropem API (`commitListCap`) chybí v seznamu zrovna ta novější část, takže hlava
    ///   v něm není vůbec.
    ///
    /// V obou se **neoznačí nic** — mlčet je správnější než ukázat na commit, o kterém to neplatí.
    ///
    /// `commits` se čeká v pořadí, ve kterém se kreslí (`commitsNewestFirst`). Rozhoduje to jen
    /// v jediném případě: dokud detail nedorazil (`head == nil`), platí definice endpointu — GitHub
    /// vrací od nejstaršího a otočením je nejnovější první, takže hlavou je první. Je to **jediný
    /// okamžik, kdy pozice rozhoduje**, a je krátký, protože se detail tahá spolu se seznamem.
    static func headCommit(in commits: [PullRequestCommit], head: String?) -> PullRequestCommit? {
        guard let head else { return commits.first }
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
    /// **Pořadí je v té větě proto, že se dá otočit** — a od #316 otočené je (`commitsNewestFirst`).
    /// Pruh je jediné místo, které o pořadí něco tvrdí, takže se s ním musí měnit: „od nejstaršího“
    /// nad seznamem od nejnovějšího je lež o tom, co je pod ní vidět.
    ///
    /// **Na stropu API to řekne.** Když se počet trefí do `commitListCap`, seznam nemusí být celý;
    /// věta o „250 commitech“ by pak tvrdila víc, než data unesou, takže se doplní, odkud ten strop
    /// je. Zůstává u toho `prvních`, protože GitHub vydá **prvních** 250 commitů PR — pořadí kresby
    /// s tím nehýbe a nahoře je pak nejnovější z nich, ne hlava PR (viz `headCommit`). Ověřovat to
    /// druhým voláním nemá cenu — GitHub další stránku nevydá, takže se pravdivější číslo stejně
    /// nedozvíme.
    static func commitsHeadline(count: Int) -> CommitsHeadline {
        let noun = commitNoun(count)
        guard count >= commitListCap else {
            return CommitsHeadline(count: "\(count) \(noun)", detail: "od nejnovějšího")
        }
        return CommitsHeadline(
            count: "prvních \(count) \(noun)",
            detail: "od nejnovějšího · víc jich GitHub přes API nevydá"
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
