import Foundation

/// Štítek na pull requestu (#392).
///
/// **Barva je data, ne token palety.** GitHub ji drží u labelu v repozitáři jako šestimístný hex
/// (`0366d6`) a může být libovolná, takže se nedá odvodit z `Palette` ani z kategorie — kreslí se
/// z odpovědi. V panelu je z ní **puntík, ne výplň chipu**: plná výplň by u každé barvy musela
/// počítat kontrast textu a přebila by odznak závažnosti nálezu, který je v panelu to jediné plné
/// pole (zdůvodnění je v `docs/navrh.html`, sekce 24, poznámka 3).
struct PullRequestLabel: Hashable, Codable, Sendable {
    /// Jméno, kterým se label na GitHubu identifikuje — a zároveň to, co se kreslí do chipu.
    let name: String
    /// Šestimístný hex **bez `#`**, jak ho vrací GitHub. Prázdný u odpovědi, ve které barva
    /// nepřišla — chybějící barva nemá položit celou sekci.
    let color: String

    init(name: String, color: String = "") {
        self.name = name
        self.color = color
    }
}

/// Jak vyžádaný reviewer odpověděl (#392).
///
/// **Tři hodnoty, ne dvě.** Prostřední je jediná, která něco blokuje, takže sloučit ji s `waiting`
/// by zahodilo zrovna tu informaci, kvůli které se na sekci kouká. Komentář bez verdiktu je
/// `waiting`: člověk se ozval, ale review nezavřel — a v tom je z pohledu „na kom to stojí“
/// k nerozeznání od toho, kdo se ještě neozval.
enum ReviewerAnswer: String, Codable, Sendable, CaseIterable {
    case approved
    case changesRequested
    case waiting

    /// Jak se odpověď píše v panelu. Česky, jako zbytek okna — a patří to k modelu ze stejného
    /// důvodu jako u `PullRequestState.czechLabel`: `rawValue` je anglický, protože jde do JSONu.
    var czechLabel: String {
        switch self {
        case .approved: "schválil"
        case .changesRequested: "chce změny"
        case .waiting: "čeká"
        }
    }
}

/// Reviewer, na kterém pull request stojí (#392).
///
/// Je to **stav, ne událost**: konverzace zná `reviewRequested` a `reviewRequestRemoved`, tedy „to
/// se stalo“, kdežto tady jde o „kdo na tom stojí teď a jak odpověděl“. Z proudu událostí by se to
/// muselo skládat, a špatně: odebrané a znovu vyžádané review dá dvě události a jednoho reviewera.
struct RequestedReviewer: Hashable, Codable, Sendable {
    /// Login, tedy to, čím se reviewer vyžaduje i kreslí. Jméno GitHub u `reviewRequests`
    /// nedává (změřeno na `cli/cli`: `{"__typename":"User","login":"BagToad"}`), takže se
    /// nevymýšlí — okno ukazuje login, jako u autora PR.
    let login: String
    let answer: ReviewerAnswer
}

/// Co o pull requestu platí i mimo kód: labely a reviewery (#392).
///
/// **Vlastní snímek vedle `PullRequest`, ne pole v něm.** `fetchDetail` volá i pre-flight
/// publisheru před každým odesláním, a `latestReviews` (z nichž se skládá odpověď reviewera) nese
/// celá těla review — přidat je do detailu by znamenalo platit tu velikost při každém odeslání
/// review za údaj, který odeslání nezajímá.
///
/// Prázdné pole je **platný výsledek**, ne porucha: PR bez labelů i bez vyžádaných reviewerů je
/// běžný. Sekce, která nemá co ukázat, se proto nekreslí — a to, že se načtení nepovedlo, drží
/// `MetadataState`, aby se „nic tu není“ nespletlo s „nevíme“.
struct PullRequestMetadata: Hashable, Codable, Sendable {
    var labels: [PullRequestLabel] = []
    var reviewers: [RequestedReviewer] = []
    /// Vyžádané **týmy** — slugy bez jména organizace (#392).
    ///
    /// **Vlastní pole, ne `RequestedReviewer` s příznakem**, a je to tvar API i tvar pravdy: GitHub
    /// drží vyžádané reviewery ve **dvou** polích (`requested_reviewers`, `requested_teams`)
    /// a tým **nemá odpověď** — `schválil`/`chce změny`/`čeká` u něj nemá význam, dokud za něj někdo
    /// neodpoví (a ten se pak objeví jako **osoba** v `latestReviews`). Kdyby tým sdílel typ
    /// s člověkem, muselo by být `answer` optional a každé view by na tu možnost muselo myslet;
    /// takhle to drží typ.
    ///
    /// **Změřeno na `keboola/platform-architecture-and-concepts#278`**, kde bylo
    /// `{"requested_reviewers": [], "requested_teams": ["ajda-swimlane"]}` — bez tohohle pole byla
    /// sekce `Reviewery` u čtyř PR ze čtrnácti prázdná, i když review někdo vyžádal.
    var teams: [String] = []
}

/// Koho jde ještě vyžádat (#392) — člověk, nebo tým.
///
/// **Jeden typ pro obojí**, protože nabídka je jedna a odesílají se jedním voláním. Kdyby to byly
/// dvě cesty, byly by to dvě kontroly uzavřenosti množiny a dva stavy odesílání.
enum ReviewerCandidate: Hashable, Sendable {
    case person(String)
    /// Slug **bez jména organizace** — tak, jak ho chce zápis (`team_reviewers`).
    case team(String)

    /// Co se o něm napíše na tlačítko.
    var name: String {
        switch self {
        case .person(let login): login
        case .team(let slug): slug
        }
    }
}
