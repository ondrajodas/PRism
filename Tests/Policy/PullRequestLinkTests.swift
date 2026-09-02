import Foundation
import Testing

@testable import PRism

/// Vložený odkaz a `prism://` (#531) — jediné místo, kde se z textu stává `PRIdentifier`.
///
/// Testuje se **výčtem tvarů, které se doopravdy kopírují**: adresní řádek prohlížeče na
/// přehledu PR, na `Souborech`, na komentáři, na commitu. A stejně důkladně to, co projít
/// **nesmí** — cizí host je ta nejtišší chyba z celé sady, protože identifikátor z `gitlab.com`
/// vypadá platně a `gh` na něj odpoví o úplně jiném pull requestu.
@Suite("Policy — odkaz na pull request (#531)")
struct PullRequestLinkTests {
    private let vault = PRIdentifier("keboola/vault#85")!

    @Test(
        "Adresa PR se přečte i s tím, co za číslem zbývá",
        arguments: [
            "https://github.com/keboola/vault/pull/85",
            "https://github.com/keboola/vault/pull/85/",
            "https://github.com/keboola/vault/pull/85/files",
            "https://github.com/keboola/vault/pull/85/files#diff-2b1c5f",
            "https://github.com/keboola/vault/pull/85/commits/9c1de02",
            "https://github.com/keboola/vault/pull/85#issuecomment-1234",
            "https://github.com/keboola/vault/pull/85?w=1",
            // Bez schématu a s `www.`: ze Slacku a z terminálu se adresa kopíruje i takhle.
            "github.com/keboola/vault/pull/85",
            "http://github.com/keboola/vault/pull/85",
            "https://www.github.com/keboola/vault/pull/85",
            // Bílé znaky kolem — vložení ze schránky je nese skoro vždycky.
            "  https://github.com/keboola/vault/pull/85\n",
        ]
    )
    func readsPullRequestLinks(_ text: String) {
        #expect(Policy.linkedPullRequest(in: text) == vault)
    }

    @Test(
        "Co adresa pull requestu není, se odmítne",
        arguments: [
            // Cizí host. `notgithub.com` a `github.com.evil.example` jsou tady schválně: obojí
            // obsahuje `github.com` jako podřetězec, takže by je kontrola bez lomítka pustila.
            "https://gitlab.com/keboola/vault/pull/85",
            "https://notgithub.com/keboola/vault/pull/85",
            "https://github.com.evil.example/keboola/vault/pull/85",
            "https://github.enterprise.example/keboola/vault/pull/85",
            // GitHub, ale ne pull request.
            "https://github.com/keboola/vault",
            "https://github.com/keboola/vault/issues/85",
            "https://github.com/keboola/vault/pull/",
            "https://github.com/keboola/vault/pull/abc",
            // Nula ani záporné číslo GitHub nedá a klíčovaly by neexistující PR.
            "https://github.com/keboola/vault/pull/0",
            "https://github.com/keboola/vault/pull/-3",
            // Znak, který se do adresy nedostane — z pole palety ale ano.
            "https://github.com/keb<ola/vault/pull/85",
            // Obyčejné hledání, kvůli kterému se paleta otevírá nejčastěji.
            "secret",
            "vault#85",
            "",
        ]
    )
    func refusesEverythingElse(_ text: String) {
        #expect(Policy.linkedPullRequest(in: text) == nil)
    }

    @Test(
        "prism://open?url=… otevírá totéž co vložený odkaz",
        arguments: [
            "prism://open?url=https://github.com/keboola/vault/pull/85",
            "prism://open?url=https%3A%2F%2Fgithub.com%2Fkeboola%2Fvault%2Fpull%2F85",
            "prism://open/?url=https://github.com/keboola/vault/pull/85/files",
            "PRISM://OPEN?url=https://github.com/keboola/vault/pull/85",
        ]
    )
    func readsTheURLScheme(_ text: String) {
        #expect(Policy.openedPullRequest(from: URL(string: text)!) == vault)
    }

    @Test(
        "Odkazu, kterému se nerozumí, se nedělá nic",
        arguments: [
            // Jiná akce než `open` — z odkazu se nemá dát vyvolat nic, o čem není napsáno,
            // že to dělá.
            "prism://run?url=https://github.com/keboola/vault/pull/85",
            "prism://open",
            "prism://open?pr=keboola/vault%2385",
            "prism://open?url=https://gitlab.com/keboola/vault/pull/85",
            // Cizí schéma: `onOpenURL` dostane, co mu systém pošle.
            "prismx://open?url=https://github.com/keboola/vault/pull/85",
            "https://github.com/keboola/vault/pull/85",
        ]
    )
    func refusesOtherURLs(_ text: String) {
        #expect(Policy.openedPullRequest(from: URL(string: text)!) == nil)
    }

    /// Obě funkce musí mluvit o téže adrese: `githubURL` ji skládá, `linkedPullRequest` rozebírá.
    /// Kdyby se rozešly, `⌘↵` na řádku `Odkaz` by vedl jinam, než co se otevře `↵`.
    @Test("Složená adresa se přečte zpátky na tentýž pull request")
    func theURLRoundTrips() {
        for id in ["keboola/vault#85", "cli/cli#1", "ondrajodas/PRism#531"].map({ PRIdentifier($0)! }) {
            #expect(Policy.linkedPullRequest(in: Policy.githubURL(of: id).absoluteString) == id)
        }
    }

    @Test("Řádek Odkaz říká, jestli je PR ve zdrojích")
    func theLinkRowSaysWhereThePullRequestIs() {
        let outside = Policy.paletteLink(to: vault, origin: .outsideSources)
        #expect(outside.group == .link)
        // **Celý identifikátor s ownerem**: `keboola/vault` proti `ondrajodas/vault` je zrovna ten
        // rozdíl, kvůli kterému se odkaz vkládá.
        #expect(outside.title == "Otevřít keboola/vault#85")
        #expect(outside.subtitle == "není ve zdrojích")
        #expect(outside.target == .pullRequest(vault))
        #expect(outside.url == URL(string: "https://github.com/keboola/vault/pull/85"))

        #expect(Policy.paletteLink(to: vault, origin: .sources).subtitle == "je ve tvých zdrojích")
    }

    /// Schéma je zapsané na dvou místech — v `Info.plist` a v `Policy` —, takže se musí ověřit,
    /// že mluví o tomtéž. Bez toho by aplikace uměla přijmout odkaz, který jí systém nikdy
    /// nepošle (nebo naopak).
    @Test("Schéma v Info.plist sedí na to, co Policy rozebírá")
    func theSchemeMatchesTheBundle() throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let types = try #require((plist as? [String: Any])?["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }

        #expect(schemes == [Policy.urlScheme])
    }
}
