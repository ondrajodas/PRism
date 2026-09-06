import Foundation

/// Smyčka vlastního pull requestu (#508) — **pět stanic v pořadí, ve kterém se kolo jde**.
///
/// **Proč dráha a ne pět ukazatelů rozsetých po okně.** Do #508 byla smyčka rozsekaná po
/// místech: nálezy v panelu, zadání v sheetu, push a merge v sekci `Větev`, Copilot v konverzaci.
/// Odpověď na „kde v tom kole zrovna jsem“ si člověk skládal sám a řádek v seznamu o tom řekl
/// jen `6 k předání`.
///
/// **Stanice `Agent` a `Merge` na dráze nejsou, a je to změna proti prvnímu kolu** (#508, čtvrté
/// kolo, z proklikání). Do něj jich bylo sedm — *Nálezy → Zadání → Agent → Push → CI → Review →
/// Merge*. Ani jedna z těch dvou v okně nikdy nic neukázala: `Agent` nemá **živý obsah** (aplikace
/// o cizím terminálu neví nic, dodat ho měla #511) a `Merge` stojí na **celém** kole, takže je
/// prakticky vždycky `idle`. **Kapsle, která nikdy nic neřekne, je jen užší místo pro ostatní** —
/// pět stanic se o šířku hlavičky dělí líp než sedm. Nic se tím neztratilo: merge bydlí v sekci
/// `Větev` (#465) a chodí se tam pořád stejnou cestou.
///
/// **Kreslí se třídami dráhy reviewera** (`.lane`, `.phases`, `.ph` — návrh, sekce 52). Je to
/// tentýž druh věci: proces s fázemi, u kterého je otázka „kde to stojí“. Okno jeden způsob, jak
/// proces kreslit, umí; druhý by byl třetí jazyk pro totéž. Ze stejného důvodu je stav stanice
/// **`ReviewerLane.PhaseState`**, ne vlastní výčet — kdyby byl vlastní, dala by se v něm vyrobit
/// hodnota, kterou kresba fází neumí, a slib „bez nového vzoru“ by držel jen komentář.
///
/// **Dráha říká dvě věci naráz: kde stojím a co je hotové** (#508, druhé kolo). Walk jde po
/// pořádku a **zastaví se na první stanici, která není hotová** — ta je aktivní a mluví o ní věta
/// pod fázemi. **Stanice za zastávkou se ale vyhodnocují dál** a zelenají, kdykoli jsou jejich
/// fakta známá a aktuální: schválený PR se zelenými checky má `CI` a `Review` zelené, i když se
/// walk zastavil na `Zadání`. To je celý smysl kresby — na první pohled má být vidět, **co
/// chybí**, ne kam až se došlo.
///
/// **A nehotová stanice za zastávkou řekne jedním slovem proč** (#508, čtvrté kolo). Do téhle
/// změny byla za zastávkou šedá kapsle **bez textu**, takže se z dráhy nedalo poznat, že je větev
/// o jednadvacet commitů pozadu — ta informace zůstávala jen v sekci `Větev`. Teď tam stojí
/// `pozadu`, `konflikt`, `nepřetlačeno`, `zjišťuju`. **Aktivní zůstává pořád jedna** (ta nese větu
/// i akci) a slovo ji aktivní neudělá: stav je dál `idle`, mění se jen text v kapsli.
///
/// **Do prvního kola tady stálo, že všechno za zastávkou je `idle`**, a důvodem bylo, že tvrdit
/// něco o CI nad nepushnutým kódem znamená mluvit o **minulém** pushi. Ten důvod platí, jenom je
/// **užší, než se dvakrát zdálo** (#508, třetí kolo): `CI` a `Review` zhasne jedině to, co říká, že
/// hlava na GitHubu **není ta naše** — tedy nepřetlačená práce v cache. Že je větev pozadu za
/// základem nebo s ním v konfliktu, hlavou nehýbe: checky nad ní doběhly a schválení na ni platí.
/// Druhé kolo tyhle dvě věci spletlo a `keboola/platform-libraries#566` mělo obojí šedé, přestože
/// bylo schválené a se zeleným CI. Rozhoduje `Policy.ownLoopFacts(of:branch:)`, což je jediné
/// místo, které o téhle hranici rozhoduje. Co dráha přesto zamlčí (rozdělaná stanice za
/// zastávkou), je pořád vidět tam, kde to bydlí: tab `Kontroly`, sekce `Větev`, panel `Zadání`.
struct OwnLoop: Equatable, Sendable {
    /// Stanice smyčky **v pořadí, ve kterém se jde**. Pořadí je součást typu, ne věc kresby —
    /// `allCases` je to jediné, podle čeho se dráha skládá, a testuje se, že jich je pět.
    enum Station: CaseIterable, Hashable, Sendable {
        /// Co o kódu řekly moje reviewery.
        case findings
        /// Co z toho zbývá předat agentovi (#334).
        case handoff
        /// Větev: srovnat nad základem a přetlačit (#466).
        case push
        /// Kontroly na GitHubu.
        case ci
        /// Cizí review — kdo se vyjádřil a jak (#392).
        case review

        /// Popisek kapsle. **Krátký schválně**: pět kapslí se dělí o šířku hlavičky, takže se
        /// stav a číslo vejdou jedině za jednoslovný název (tatáž mez jako u `ReviewerLane.Title`).
        var title: String {
            switch self {
            case .findings: "Nálezy"
            case .handoff: "Zadání"
            case .push: "Push"
            case .ci: "CI"
            case .review: "Review"
            }
        }
    }

    /// Jedna stanice na dráze.
    ///
    /// `detail` je to, co v kapsli stojí za názvem, a čte se podle stavu:
    ///
    /// - u **hotové** a u **aktivní** stanice je to, co se v ní stalo (`3 ✓`, `6 předáno`,
    ///   `o 4 vzadu`) — plná odpověď, kterou u aktivní doplňuje věta pod fázemi;
    /// - u **šedé za zastávkou** je to **jedno slovo, proč není zelená** (`pozadu`, `konflikt`,
    ///   `nepřetlačeno`, `zjišťuju`). Nemá pod sebou větu, o kterou by se opřelo, a dělí se
    ///   o šířku s ostatními — proto slovo, ne počet.
    ///
    /// `nil` znamená, že se nedá dodat nic — ne že je něco nula. U šedé stanice je to odpověď
    /// „na tuhle se ještě nedošlo“: její fakta stojí na kroku, který se neudělal, takže se
    /// **nevyhodnocovala** a vymyslet si k ní důvod by bylo tvrzení z chybějících dat.
    struct Stop: Hashable, Sendable {
        let station: Station
        /// Doslova ta hodnota, kterou používá dráha reviewera. Viz poznámka u `OwnLoop`.
        let state: ReviewerLane.PhaseState
        let detail: String?
    }

    /// Jediná akce aktivní stanice — a je to **navigace, ne druhá cesta ven**.
    ///
    /// Obsahem stanic `Zadání` a `Push` je dnešní panel `Zadání` (#334) a sekce `Větev`
    /// (#465, #466); nic z toho se neruší ani nekopíruje. Kdyby dráha odesílala sama, byla by to
    /// druhá cesta na GitHub (tvrdá podmínka č. 1). Dráha proto **otevře to místo, kde ta práce
    /// bydlí**, a nic jiného neumí.
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

    /// Všech pět, vždycky a v pořadí `Station.allCases`. Prázdná dráha neexistuje: stanice, o
    /// které se nedá říct, že je hotová, je `idle`, a to je odpověď. **Rozdělaná (`running`,
    /// `failed`, `stopped`, `unknown`) je nejvýš jedna — ta aktivní.**
    let stations: [Stop]
    /// Kde smyčka stojí. **`nil` = došla** — pull request je mergnutý, zavřený, nebo je hotových
    /// všech pět stanic a zbývá jedině merge v sekci `Větev`.
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

    /// Co v kapsli té stanice stojí za názvem. `nil` = nic, viz `Stop.detail`.
    ///
    /// Dvojče `state(of:)` a je tu ze stejného důvodu: **ptát se adresně**. Kresba jde přes
    /// `stations` (musí projít všechny), takže tohle čtou testy — bez něj by se na `detail`
    /// v každém tvrzení sahalo přes `first { $0.station == … }`, což je ten druh šumu, ve kterém
    /// se přehlédne, že se ptá na jinou stanici.
    func detail(of station: Station) -> String? {
        stations.first { $0.station == station }?.detail
    }
}
