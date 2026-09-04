import Foundation
import Testing

@testable import PRism

/// Co repozitář o mergi říká (#556) — **dekódování skutečné odpovědi `gh api repos/{o}/{r}`**.
///
/// Fixtures jsou **skutečné výstupy**: `ondrajodas/PRism` (vlastní repo, všechny tři metody
/// povolené) a `cli/cli` (veřejné repo **bez práva zápisu**, kde GitHub ta pole **vůbec nepošle**).
/// Ten druhý je ta podstatnější polovina: „nevím“ je stav, na kterém stojí rozhodnutí nabízet
/// v potvrzení všechny tři metody a netvrdit nic.
///
/// **Fixtures jsou zkrácené o pole, která se nedekódují, a je to nález Copilota** (PR #560): plná
/// odpověď `GET /repos/{o}/{r}` nese `temp_clone_token`, tedy krátkodobý credential — a ten do repa
/// nepatří ani ve fixture. Zůstávají identita repa a jedenáct polí o mergi; **hodnoty jsou pořád ty
/// skutečné**, takže tvar odpovědi (chybějící klíč vs. `false`) fixture dokládá dál.
@Suite("Nastavení merge z repozitáře (#556)")
struct GhRepositoryMergeSettingsTests {
    private static func decoded(_ path: String) throws -> RepositoryMergeSettings {
        try GhOutput.decoder
            .decode(GhRepositoryMergeSettings.self, from: try Fixture.data(path))
            .settings
    }

    /// Změřeno na živém API: `ondrajodas/PRism` má všechny tři metody a
    /// `squash_merge_commit_message = COMMIT_MESSAGES`, tedy stav, ve kterém byla dnešní věta
    /// v potvrzení pravdivá.
    @Test("Repo se všemi třemi metodami se přečte celé")
    func readsAllThreeFlags() throws {
        let settings = try Self.decoded("gh/repo-view-merge-flags.json")

        #expect(settings.allowsSquash == true)
        #expect(settings.allowsMergeCommit == true)
        #expect(settings.allowsRebase == true)
        #expect(settings.squashBody == .commitMessages)
        #expect(settings.mergeCommitBody == .pullRequestTitle)
    }

    /// **Chybějící pole je „nevím“, ne „nepovoluje“** — a je to změřené: nad repem, do kterého
    /// nemáme zápis, GitHub všech pět polí **vůbec nepošle**.
    ///
    /// **Poznat se to dá jedině ze syrového JSONu**, a je to past: `gh api --jq
    /// .allow_merge_commit` na tom vypíše `null`, protože `jq` chybějící klíč vydá jako `null` —
    /// takže z výstupu s `--jq` to vypadá jako explicitní `null`. Pro aplikaci je to jedno
    /// (`decodeIfPresent` vydá `nil` na obojí) a `toleratesExplicitNull` níž to tvrdí i z té druhé
    /// strany; do dokumentace to ale patří správně, protože „změřeno“ znamená změřeno.
    @Test("Repo bez práva zápisu dá nevím u všech pěti polí")
    func readsAbsentKeysAsUnknown() throws {
        let settings = try Self.decoded("gh/repo-view-no-write.json")

        #expect(settings.allowsSquash == nil)
        #expect(settings.allowsMergeCommit == nil)
        #expect(settings.allowsRebase == nil)
        #expect(settings.squashBody == nil)
        #expect(settings.mergeCommitBody == nil)
        // A **`nil` se nesmí srazit na `false`**: tohle je ta hodnota, na které stojí, že se
        // v potvrzení nabídnou všechny tři metody.
        #expect(settings.allows(.rebase) == nil)
    }

    /// Repo s **jednou zakázanou metodou**. Inline JSON schválně: změřeno je to na
    /// `keboola/job-queue-daemon`, tedy na **firemním** repozitáři, a ten do fixtures nepatří
    /// (pravidlo je o firemních datech, ne o veřejnosti repa — druhá fixture je z vlastního
    /// `ondrajodas/PRism`). Tvar odpovědi drží fixtures výš; tady jde jenom o to, že `false`
    /// **není** `nil`.
    @Test("Zakázaná metoda přijde jako false, ne jako chybějící pole")
    func readsFalseAsRefusal() throws {
        let json = Data(
            """
            {"allow_merge_commit":true,"allow_squash_merge":true,"allow_rebase_merge":false,
             "squash_merge_commit_message":"COMMIT_MESSAGES","merge_commit_message":"PR_TITLE"}
            """.utf8
        )
        let settings = try GhOutput.decoder
            .decode(GhRepositoryMergeSettings.self, from: json)
            .settings

        #expect(settings.allows(.rebase) == false)
        #expect(settings.allows(.squash) == true)
    }

    /// **Explicitní `null` je totéž jako chybějící klíč**, tedy „nevím“.
    ///
    /// Inline JSONem schválně: `GET /repos/{o}/{r}` explicitní `null` u těchhle polí **neposílá**
    /// (nad `cli/cli` klíče chybí, viz výš), takže se to ze skutečné odpovědi nedá vzít. Je to
    /// tvrzení o robustnosti dekódování, ne měření — a je u toho napsané proč.
    @Test("Explicitní null se čte stejně jako chybějící klíč")
    func toleratesExplicitNull() throws {
        let json = Data(
            """
            {"allow_merge_commit":null,"allow_squash_merge":null,"allow_rebase_merge":null,
             "squash_merge_commit_message":null,"merge_commit_message":null}
            """.utf8
        )
        let settings = try GhOutput.decoder
            .decode(GhRepositoryMergeSettings.self, from: json)
            .settings

        #expect(settings.allows(.squash) == nil)
        #expect(settings.allows(.mergeCommit) == nil)
        #expect(settings.allows(.rebase) == nil)
        #expect(settings.squashBody == nil)
        #expect(settings.mergeCommitBody == nil)
        // A **je to doopravdy tatáž hodnota** jako u fixture bez klíčů — kdyby se ty dvě cesty
        // rozešly, znamenalo by to dvě různá „nevím“.
        let absent = try Self.decoded("gh/repo-view-no-write.json")
        #expect(settings == absent)
    }

    /// **Neznámý zdroj těla se bere jako „nevím“, ne jako chyba.** GitHub tam smí přidat další
    /// hodnotu a věta „složí GitHub podle nastavení repozitáře“ je pravdivá pořád; položené čtení
    /// kvůli neznámému enumu by byla porucha vyrobená z pole, na kterém nic nestojí.
    @Test("Neznámý zdroj těla nepoloží čtení, jen se o něm nic netvrdí")
    func toleratesUnknownBodySource() throws {
        let json = Data(
            """
            {"allow_squash_merge":true,"squash_merge_commit_message":"SOMETHING_NEW"}
            """.utf8
        )
        let settings = try GhOutput.decoder
            .decode(GhRepositoryMergeSettings.self, from: json)
            .settings

        #expect(settings.allowsSquash == true)
        #expect(settings.squashBody == nil)
        // Chybějící pole se od `null` neliší — obojí je „nevím“.
        #expect(settings.mergeCommitBody == nil)
    }

    /// **Rebase tělo nemá, protože nemá commit** — a GitHub pro ni žádné pole nedává. Otázka na
    /// zdroj těla u rebase proto musí vyjít `nil` **i v repu, kde jsou ostatní zdroje známé**,
    /// jinak by věta pod výpisem mluvila o těle, které nevznikne.
    @Test("U rebase se na zdroj těla neodpovídá ani v plně přečteném repu")
    func rebaseHasNoBody() throws {
        let settings = try Self.decoded("gh/repo-view-merge-flags.json")

        #expect(settings.bodySource(for: .rebase) == nil)
        #expect(settings.bodySource(for: .squash) == .commitMessages)
        #expect(settings.bodySource(for: .mergeCommit) == .pullRequestTitle)
    }
}
