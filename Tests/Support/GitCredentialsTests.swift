import Foundation
import Testing

@testable import PRism

/// Uzávorkování cesty ke `gh` v credential helperu (#466).
///
/// **Proč to má vlastní testy:** helper je řetězec, který **spouští shell**, a jde po něm i push —
/// tedy jediná cesta, kterou aplikace zapisuje do remote. Rozejde se to přitom **potichu**:
/// apostrof v cestě uzávorkování předčasně uzavře a `git` pak dostane rozstřelený příkaz, což se
/// pozná teprve tehdy, až se někdo jmenuje `o'brien`.
///
/// Do #466 se escapování skládalo v `GitCredentials` vlastním `replacingOccurrences` — kopie toho,
/// co dělá `ShellQuoting`. Nález z revize; tenhle soubor je ta chybějící stráž, protože existující
/// test v `GitRepoCheckoutTests` tvrdil jen to, že cesta v helperu **je**, ne že je uzávorkovaná.
@Suite("Credential helper")
struct GitCredentialsTests {
    private func helper(for path: String) throws -> String {
        let arguments = GitCredentials.configuration(gh: URL(filePath: path))
        #expect(arguments.first == "-c")
        return try #require(arguments.last)
    }

    @Test("Cesta jde do apostrofů")
    func quotesThePath() throws {
        let helper = try helper(for: "/opt/homebrew/bin/gh")

        #expect(helper == "credential.helper=!'/opt/homebrew/bin/gh' auth git-credential")
    }

    /// **Apostrof v cestě se uzavře a otevře znovu** (`'\''`) — jinak by uzávorkování skončilo
    /// uprostřed cesty a zbytek by shell přečetl jako další slova příkazu.
    @Test("Apostrof v cestě uzávorkování neuzavře")
    func escapesAnApostropheInThePath() throws {
        let helper = try helper(for: "/Users/o'brien/bin/gh")

        #expect(helper.contains("'/Users/o'\\''brien/bin/gh'"))
        // A **nezůstane tam neescapovaný**: tohle je ta podoba, která by příkaz rozstřelila.
        #expect(!helper.contains("/Users/o'brien"))
    }

    /// **Mezera v cestě nepotřebuje nic navíc** — je uvnitř apostrofů. Tvrdí se to proto, že by se
    /// někdo mohl nechat zlákat k `replacingOccurrences(of: " ", …)` a tím uzávorkování obejít.
    @Test("Mezera v cestě zůstane uvnitř apostrofů")
    func keepsSpacesInsideTheQuotes() throws {
        let helper = try helper(for: "/Volumes/My Disk/gh")

        #expect(helper == "credential.helper=!'/Volumes/My Disk/gh' auth git-credential")
    }

    /// **Uzávorkuje `ShellQuoting`, ne vlastní kopie.** Tvrzení je nad **výsledkem**, ne nad
    /// zdrojákem: kdyby se do `GitCredentials` vrátilo vlastní escapování, které se od
    /// `ShellQuoting` v čemkoli liší, položí to tenhle test.
    @Test("Escapování je totéž, co dělá ShellQuoting")
    func matchesShellQuoting() throws {
        for path in [
            "/opt/homebrew/bin/gh",
            "/Users/o'brien/bin/gh",
            "/Volumes/My Disk/gh",
            "/x'y'z/gh",
        ] {
            let expected = "credential.helper=!\(ShellQuoting.quoted(URL(filePath: path))) "
                + "auth git-credential"
            #expect(try helper(for: path) == expected)
        }
    }

    /// `git` se nesmí zeptat na heslo a čekat — podproces bez terminálu by na tom visel do timeoutu.
    @Test("Git se na heslo neptá")
    func neverPromptsForCredentials() {
        #expect(GitCredentials.environment["GIT_TERMINAL_PROMPT"] == "0")
    }
}
