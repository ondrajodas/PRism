import Foundation

extension Policy {
    /// Schéma, kterým se aplikace dá požádat o otevření PR zvenku (#531) — `prism://open?url=…`.
    ///
    /// **Konstanty, ne literály v `Info.plist` a v kódu zvlášť**: schéma se deklaruje v bundlu
    /// a rozebírá tady, takže by dvě místa znamenala dvě pravdy o tom, na co aplikace reaguje.
    /// Test proto srovnává tuhle hodnotu s tím, co je v `Info.plist`.
    static let urlScheme = "prism"
    /// Jediná akce, kterou schéma umí. Cokoli jiného za `prism://` je **odmítnutí**, ne otevření
    /// něčeho podobného — z odkazu se nemá dát vyvolat nic, o čem tady není napsáno, že to dělá.
    static let urlOpenHost = "open"
    /// Jméno parametru s adresou pull requestu.
    static let urlOpenQuery = "url"

    /// Pull request z vloženého odkazu (#531). `nil` = tohle není adresa PR na GitHubu.
    ///
    /// Bere adresu tak, jak se **doopravdy kopíruje z prohlížeče**, tedy i s tím, co za číslem
    /// zbývá: `/files`, `/commits/<sha>`, kotva na komentář, parametry pohledu. Číslo je poslední
    /// věc, které se rozumí — zbytek cesty se **zahazuje**, protože záložka se otevírá na PR, ne
    /// na jeho podstránce.
    ///
    /// **Cizí host je odmítnutí, ne pokus** (`gitlab.com`, GitHub Enterprise): aplikace mluví
    /// s `gh` proti github.com, takže identifikátor z cizí adresy by vedl na dotaz, který
    /// odpoví o něčem jiném, nebo o ničem. Kontroluje se `github.com/` **i s lomítkem** — bez něj
    /// by prošlo `github.com.evil.example/keboola/vault/pull/85`.
    ///
    /// Schéma i `www.` jsou volitelné, protože adresa se do palety dostane vložením ze schránky
    /// a ta ji občas nese oříznutou (Slack, terminál).
    static func linkedPullRequest(in text: String) -> PRIdentifier? {
        var rest = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        for scheme in ["https://", "http://"] where rest.lowercased().hasPrefix(scheme) {
            rest = rest.dropFirst(scheme.count)
            break
        }
        if rest.lowercased().hasPrefix("www.") { rest = rest.dropFirst(4) }

        let host = "github.com/"
        guard rest.lowercased().hasPrefix(host) else { return nil }
        rest = rest.dropFirst(host.count)

        // Dotaz i kotva pryč **před** dělením na segmenty: `#issuecomment-1` je v adrese kotva,
        // kdežto v `PRIdentifier` je to oddělovač čísla, takže by se ta dvě `#` popletla.
        let path = rest.prefix { $0 != "?" && $0 != "#" }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 4, parts[2] == "pull" else { return nil }
        guard let number = Int(parts[3]), number > 0 else { return nil }
        guard isLinkName(parts[0]), isLinkName(parts[1]) else { return nil }
        guard let repo = RepoID("\(parts[0])/\(parts[1])") else { return nil }

        return PRIdentifier(repo: repo, number: number)
    }

    /// Jméno vlastníka nebo repozitáře tak, jak ho GitHub dovolí — písmena, číslice, `.`, `_`, `-`.
    ///
    /// **Užší než `RepoID`, a je to schválně.** `RepoID` odmítá jen to, co by ublížilo cestě
    /// v cache (`.`, `..`, lomítko, `#`, bílé znaky), protože jinak bere, co vrátí `gh`. Sem se
    /// ale text dostane z **pole palety**, tedy z čehokoli, co je zrovna ve schránce — a z toho
    /// se skládá adresa (`githubURL(of:)`). Bez tohohle by `github.com/a<b/c/pull/1` prošlo
    /// a `URL(string:)` nad ním vrátil `nil`.
    private static func isLinkName(_ name: Substring) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    /// Pull request z `prism://open?url=…` (#531). `nil` = tomuhle odkazu se nerozumí.
    ///
    /// **Adresa se rozebírá toutéž funkcí jako vložený odkaz** — schéma je zkratka téže cesty,
    /// takže co se dá otevřít z palety, se má dát otevřít i odsud, a ani o znak víc.
    static func openedPullRequest(from url: URL) -> PRIdentifier? {
        guard url.scheme?.lowercased() == urlScheme else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard components.host?.lowercased() == urlOpenHost else { return nil }
        guard let link = components.queryItems?.first(where: { $0.name == urlOpenQuery })?.value
        else { return nil }

        return linkedPullRequest(in: link)
    }

    /// Řádek skupiny `Odkaz` v paletě ⌘K (#531).
    ///
    /// **Nehledá se, skládá se z dotazu.** Zbytek palety je hledání nad katalogem, který store
    /// drží v paměti; tenhle řádek je odpověď na to, co je v poli napsané — PR z cizího repa
    /// v žádném katalogu není a být nemá (byl by to dotaz na GitHub při každém úhozu).
    ///
    /// Podtitulek říká, **co ten `↵` udělá**: u PR mimo zdroje že se otevře jen ke čtení, u PR ze
    /// zdrojů že je to tentýž pull request, který je ve frontě. Bez toho by z řádku nebylo poznat,
    /// jestli vložený odkaz vede někam jinam než klik v seznamu.
    static func paletteLink(to pullRequest: PRIdentifier, origin: PullRequestOrigin) -> CommandPalette.Item {
        CommandPalette.Item(
            // Konstantní `id`: v jednom dotazu je vždycky nejvýš jeden odkaz, takže se s ničím
            // nesrazí — a `ForEach` si na něm nemá co splést, protože skupina má jediný řádek.
            id: "link",
            group: .link,
            // **Celý identifikátor, ne `paletteLabel`** (`vault#85`): ostatní řádky palety mluví
            // o PR, které jsou v okně, takže jim stačí jméno repa. Tenhle je z repa, které na
            // obrazovce nikde není — a `keboola/vault` proti `ondrajodas/vault` je zrovna ten
            // rozdíl, kvůli kterému se odkaz vkládá.
            title: "Otevřít \(pullRequest)",
            subtitle: linkNote(origin),
            mark: .link,
            url: githubURL(of: pullRequest),
            target: .pullRequest(pullRequest)
        )
    }

    /// Co se o odkazu ví, než se na něj klikne.
    private static func linkNote(_ origin: PullRequestOrigin) -> String {
        switch origin {
        case .sources: "je ve tvých zdrojích"
        case .outsideSources: "není ve zdrojích"
        }
    }

    /// Adresa pull requestu na GitHubu, složená z identifikátoru (#531).
    ///
    /// Existuje kvůli PR **mimo zdroje**: u těch ze seznamu se adresa bere z odpovědi `gh`
    /// (`PullRequestSummary.url`), ale řádek palety musí umět `⌘↵` dřív, než se cokoli dotáhne.
    /// Tvar je `owner/repo/pull/číslo`, tedy přesně to, co `linkedPullRequest(in:)` rozebírá zpátky
    /// — a je na to test, aby se ty dvě funkce nerozešly.
    static func githubURL(of pullRequest: PRIdentifier) -> URL {
        URL(string: "https://github.com/\(pullRequest.repo)/pull/\(pullRequest.number)")!
    }
}
