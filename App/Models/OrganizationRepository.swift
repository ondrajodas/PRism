import Foundation

/// Jeden repozitář z výpisu organizace (#532).
///
/// Tři údaje, protože přesně tři se v paletě ⌘K kreslí (#533): **jméno** se hledá, **počet
/// otevřených PR** říká, jestli má smysl do repa vůbec vstupovat, a **čas poslední změny** řadí.
/// Čtvrtý údaj by se do řádku palety nevešel a platil by se tím, že se výpis dotahuje pomaleji.
///
/// **Není to `PullRequestSummary` pro repozitáře.** Nic z toho není tvrzení o pull requestu —
/// katalog odpovídá na „která repa v organizaci existují“, ne na „co je v nich k review“. Fronta
/// se odsud neplní a plnit nemá (frontu definují zdroje, #4).
struct OrganizationRepository: Codable, Equatable, Sendable, Identifiable {
    let repo: RepoID
    /// Kolik má repo **otevřených** pull requestů. Ověřeno na živém API: `gh repo list --json
    /// pullRequests` vrací `totalCount` **jen otevřených** — `keboola/keboola-operator` vydalo 17
    /// a `gh pr list --state open` tamtéž taky 17.
    let openPullRequests: Int
    /// Kdy do repa naposledy někdo pushnul. `nil` = **prázdné repo**, do kterého se nikdy
    /// nepushlo; `gh` u něj `pushedAt` nemá. V měřeném výpisu tisíce rep organizace `keboola`
    /// nebyl ani jeden, ale prázdné repo se založit dá a nemá kvůli tomu spadnout celý výpis.
    let lastPushedAt: Date?

    var id: RepoID { repo }
}

/// Výpis repozitářů jedné organizace tak, jak přišel z `gh` (#532).
///
/// **Vlastní typ místo holého pole, a je to kvůli `hitLimit`.** `gh repo list` bere `--limit`
/// a organizace `keboola` na strop **doopravdy naráží** (změřeno: `--limit 1000` vydalo přesně
/// 1000 položek). Pole samo o sobě neunese rozdíl mezi „tohle jsou všechna repa“ a „tohle je
/// prvních tisíc“ — a to je zrovna ta třída textu v okně, který tvrdí víc, než data unesou.
struct OrganizationRepositories: Codable, Equatable, Sendable {
    let repositories: [OrganizationRepository]
    /// Došlo se na strop `--limit`? Pak jich je víc, než kolik jich tady leží.
    let hitLimit: Bool

    init(repositories: [OrganizationRepository], hitLimit: Bool) {
        self.repositories = repositories
        self.hitLimit = hitLimit
    }

    /// Chybějící `hitLimit` v uloženém souboru znamená **„nevím, ale ber to jako úplný výpis“**.
    /// Je to jediné pole, které se dá do souboru dopsat později, a nutit kvůli němu nové čtení
    /// celé cache by znamenalo, že se po aktualizaci aplikace tahá tisíc rep znovu.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repositories = try container.decode([OrganizationRepository].self, forKey: .repositories)
        hitLimit = try container.decodeIfPresent(Bool.self, forKey: .hitLimit) ?? false
    }
}

/// Uložený výpis jedné organizace i s razítkem, kdy se dotáhl (#532).
///
/// Razítko je **součást snímku, ne vedlejší soubor**: podle něj se rozhoduje, jestli je výpis
/// starší než den, a dvě místa (soubor s daty, soubor s razítkem) by se uměla rozejít — pak by
/// se v okně psalo `obnoveno 7:58` nad seznamem z minulého týdne.
struct RepositorySnapshot: Codable, Equatable, Sendable {
    let organization: String
    let fetchedAt: Date
    let listing: OrganizationRepositories

    var repositories: [OrganizationRepository] { listing.repositories }
    var hitLimit: Bool { listing.hitLimit }
}
