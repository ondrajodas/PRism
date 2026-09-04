import Foundation
import Testing

@testable import PRism

/// Co repozitář o mergi říká (#556) — **dekódování skutečné odpovědi `gh api repos/{o}/{r}`**.
///
/// Fixtures jsou **skutečné výstupy** a jsou z **veřejných** repozitářů: `ondrajodas/PRism`
/// (všechny tři metody povolené) a `cli/cli` (repo bez práva zápisu, kde přijdou všechna pole jako
/// `null`). Ten druhý je ta podstatnější polovina: „nevím“ je stav, na kterém stojí rozhodnutí
/// nabízet v potvrzení všechny tři metody a netvrdit nic — a **ručně napsaný literál by ho
/// nedoložil**, protože GitHub ta pole v odpovědi **má**, jen s hodnotou `null`.
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

    /// **`null` je „nevím“, ne „nepovoluje“** — a je to změřené: nad repem, do kterého nemáme
    /// zápis, vrací GitHub všech pět polí jako `null`. Klíče v odpovědi **jsou**, takže je to
    /// explicitní `null`, ne chybějící pole.
    @Test("Repo bez práva zápisu dá nevím u všech pěti polí")
    func readsNullAsUnknown() throws {
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
    /// `keboola/job-queue-daemon` (`allow_rebase_merge: false`), což je firemní repozitář — a do
    /// fixtures v tomhle repu patří jen veřejná data. Tvar odpovědi drží fixtures výš; tady jde
    /// jenom o to, že `false` **není** `nil`.
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
