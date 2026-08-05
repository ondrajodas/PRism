import Foundation

/// Jedno vydání aplikace na GitHubu — to, co ukazuje okno s novinkami (#127).
///
/// **Není `Codable`**, na rozdíl od většiny modelů — jako `ReviewVerdict` nebo
/// `PullRequestTab`. Historie se drží v paměti do konce běhu a na disk nejde, takže by
/// `Codable` tvrdil, že se někam ukládá; kdo by se na to spolehl, hledal by soubor, který
/// neexistuje. Důvod, proč se necachuje, je u `ReleaseNotesModel`.
struct Release: Hashable, Sendable, Identifiable {
    /// Tag vydání (`v1.1.23`). Zároveň identita: dvě vydání na jednom tagu neexistují,
    /// takže vlastní `id` by bylo druhé jméno téhož.
    let tag: String
    /// Název vydání. V tomhle repu začíná tagem (`v1.1.23 — notifikace o re-review`);
    /// co s tím v seznamu, řeší `ReleaseRow`.
    let name: String
    /// Kdy se vydalo. **Neoptional**, protože rozdělané (`draft`) vydání datum nemá a do
    /// seznamu se vůbec nedostane — viz `GhRelease`.
    let publishedAt: Date
    /// Release notes jako GitHub Markdown. Prázdné být můžou (vydání bez popisu).
    let body: String
    /// Odkaz na vydání na GitHubu.
    let url: URL

    var id: String { tag }
}

extension Release {
    /// Repozitář, ze kterého se novinky tahají.
    ///
    /// **Konstanta, ne položka konfigurace** (#127): je to vlastní repo aplikace, ne něco,
    /// co si někdo nastavuje. Nastavitelné repo by znamenalo, že okno „co je nového v PRismu“
    /// umí ukazovat novinky odjinud — což není funkce, ale způsob, jak si rozbít značku
    /// naposledy viděného vydání.
    static let repository = RepoID(owner: "ondrajodas", name: "PRism")
}
