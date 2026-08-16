import Foundation
import Testing

@testable import PRism

/// Dekódování odpovědi `gh api repos/{o}/{r}/pulls/{n}/commits` (#316).
///
/// Dvě věci, které se tu dají pokazit potichu:
///
/// - **položit celý seznam kvůli poli, které se nekreslí.** Odpověď má přes šedesát polí a my
///   z ní bereme šest; kdyby dekódování bylo přísné, přišel by tab o data kvůli něčemu, co v něm
///   není vidět;
/// - **udělat ze `sloučení` obyčejný commit** (nebo naopak). Diff sloučení je proti prvnímu
///   rodiči a umí vyjít prázdný, takže na tom příznaku stojí to, jestli se prázdný diff v #317
///   bude číst jako porucha.
@Suite("Commity z GitHub API")
struct GhCommitTests {
    private func decode(_ json: String) throws -> [PullRequestCommit] {
        try GhOutput.decoder.decode([GhCommit].self, from: Data(json.utf8))
            .compactMap(\.pullRequestCommit)
    }

    /// **Skutečná odpověď, ne vymyšlená** — `cli/cli#13899` má sedm commitů a mezi nimi tři
    /// sloučení, takže se na ní dá ověřit obojí naráz. Z veřejného repa schválně; titulky firemních
    /// PR do fixture nepatří.
    @Test("Skutečná odpověď se přeloží na řádky seznamu")
    func decodesTheRealResponse() throws {
        let commits = try decode(Fixture.text("gh/pr-commits.json"))

        #expect(commits.count == 7)

        let first = try #require(commits.first)
        #expect(first.sha == "c82266c2dcc3285033605501837434af1faeddfe", "sha se drží celé, ne zkrácené")
        #expect(first.shortSha == "c82266c")
        #expect(first.subject == "Warn instead of failing when issue fields can't be set")
        #expect(first.authorName == "imkp1")
        #expect(first.authorLogin == "imkp1")
        #expect(first.avatarURL?.host() == "avatars.githubusercontent.com")
        #expect(first.committedAt == Date(timeIntervalSince1970: 1_784_230_763), "2026-07-16T19:39:23Z")
        #expect(!first.isMerge)

        // Tři sloučení — `parents` má u nich dvě položky.
        #expect(commits.count(where: \.isMerge) == 3)
        let merge = try #require(commits.first { $0.isMerge })
        #expect(merge.subject.hasPrefix("Merge branch 'trunk'"))
        // U sloučení je `commit.author.name` celé jméno, kdežto `author.login` přezdívka — řádek
        // kreslí to první, takže se ty dva nesmí zaměnit.
        #expect(merge.authorName == "Kumar Prateek")
        #expect(merge.authorLogin == "imkp1")
    }

    /// Pořadí zůstává, jak přišlo — GitHub vrací commity od nejstaršího a přerovnat je podle data
    /// by po rebase rozházelo postup, kvůli kterému se ten seznam čte.
    @Test("Pořadí se nemění")
    func keepsTheOrder() throws {
        let commits = try decode(Fixture.text("gh/pr-commits.json"))
        let dates = commits.compactMap(\.committedAt)
        #expect(dates.count == commits.count)
        #expect(commits.first?.subject.hasPrefix("Warn instead") == true)
        #expect(commits.last?.subject.hasPrefix("Merge branch 'trunk'") == true)
    }

    /// **`author: null` je běžný stav, ne porucha** — GitHub ho vrátí, když e-mail z commitu
    /// k žádnému účtu nepřiřadí. Změřeno na `keboola/job-queue-daemon#858`, kde je `null` u všech
    /// sedmi commitů; inline JSONem proto, že fixture z veřejného repa tenhle tvar nemá a titulky
    /// firemních PR sem nepatří.
    @Test("Commit bez účtu na GitHubu zůstane v seznamu")
    func keepsCommitsWithoutAnAccount() throws {
        let commits = try decode("""
            [{
              "sha": "b8608f8f68ce695129b2fb1fece8e13f6802d65c",
              "commit": {
                "message": "feat(daemon): emit per-row children\\n\\nDelší tělo, které se v seznamu nekreslí.",
                "author": {"name": "Erik Zigo", "email": "erik.zigo@keboola.com", "date": "2026-04-28T16:18:19Z"}
              },
              "author": null,
              "parents": [{"sha": "aaaa"}]
            }]
            """)

        let commit = try #require(commits.first)
        #expect(commit.authorName == "Erik Zigo", "jméno z gitu zbývá i bez účtu")
        #expect(commit.authorLogin == nil)
        #expect(commit.avatarURL == nil, "bez účtu není odkud vzít obrázek — kreslí se monogram")
        #expect(commit.subject == "feat(daemon): emit per-row children")
        #expect(commit.message.contains("Delší tělo"), "tělo se nezahazuje, patří do hlavičky #317")
    }

    /// Chybějící pole nesmí položit seznam. Zbývá jediná tvrdá podmínka — **sha**, protože je to
    /// klíč řádku i to, čím se commit rozklikne.
    @Test("Chybějící pole nepoloží seznam, chybějící sha řádek zahodí")
    func toleratesMissingFields() throws {
        let commits = try decode("""
            [
              {"sha": "1111111"},
              {"sha": "", "commit": {"message": "prázdné sha"}},
              {"sha": "2222222", "commit": {"message": "", "author": {"name": ""}}, "author": {"login": "x"}}
            ]
            """)

        #expect(commits.count == 2, "položka bez sha se zahazuje, ostatní zůstávají")

        let bare = try #require(commits.first)
        #expect(bare.subject.isEmpty, "za autora se zpráva nevymýšlí")
        #expect(bare.authorName == "?", "prázdné kolečko vypadá jako chyba kreslení")
        #expect(bare.committedAt == nil)
        #expect(!bare.isMerge, "chybějící `parents` znamená „nevíme“, a to není sloučení")

        let emptyName = try #require(commits.last)
        #expect(emptyName.authorName == "?")
        #expect(emptyName.authorLogin == "x")
    }

    /// `avatar_url` je `snake_case`, na rozdíl od `gh … --json`, které dává `camelCase`.
    /// Kdyby se převod klíčů zapnul na sdíleném dekodéru, rozbil by ostatní odpovědi — proto to
    /// řeší `CodingKeys` u jednoho pole a tenhle test hlídá, že to nezmizí.
    @Test("Adresa obrázku se čte ze `snake_case` klíče")
    func readsTheSnakeCaseAvatarKey() throws {
        let commits = try decode("""
            [{"sha": "1111111", "author": {"login": "odinuv", "avatar_url": "https://example.com/a.png"}}]
            """)
        #expect(commits.first?.avatarURL?.absoluteString == "https://example.com/a.png")
    }
}
