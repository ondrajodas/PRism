import Foundation
import Testing

@testable import PRism

/// Druhá úroveň palety ⌘K (#533) — repozitáře v první úrovni, otevřené PR v druhé.
///
/// Nejcennější tvrzení jsou tři a všechna mluví o tom, co se **nestane**: `esc` v druhé úrovni
/// **nezavírá**, `⌫` nad napsaným dotazem **nevrací** (jinak by v paletě přestalo jít mazat) a věta
/// prázdného stavu nad nedotázaným polem **netvrdí**, že se hledalo.
@Suite("Policy — druhá úroveň palety")
struct CommandPaletteLevelTests {
    private let vault = RepoID(owner: "keboola", name: "vault")
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func repository(
        _ name: String,
        open: Int,
        pushedAgo: TimeInterval? = 3_600
    ) -> OrganizationRepository {
        OrganizationRepository(
            repo: RepoID(name)!,
            openPullRequests: open,
            lastPushedAt: pushedAgo.map { now.addingTimeInterval(-$0) }
        )
    }

    private func summary(
        _ number: Int,
        title: String = "titulek",
        author: String = "odinuv",
        ago: TimeInterval = 3_600,
        state: PullRequestState = .open,
        repo: RepoID? = nil
    ) -> PullRequestSummary {
        let id = PRIdentifier(repo: repo ?? vault, number: number)
        return PullRequestSummary(
            id: id,
            title: title,
            author: author,
            url: Policy.githubURL(of: id),
            updatedAt: now.addingTimeInterval(-ago),
            state: state
        )
    }

    // MARK: - Úroveň a klávesy

    @Test("V první úrovni esc zavírá, v druhé vrací o úroveň")
    func escapeMeansSomethingElseInTheSecondLevel() {
        #expect(!Policy.paletteStage(level: .top).goesBack)
        #expect(Policy.paletteStage(level: .repository(vault), repository: .loading).goesBack)
    }

    @Test("Patka mění dvě položky ze čtyř: ↵ a esc")
    func theFooterChangesWithTheLevel() {
        let top = Policy.paletteHints(at: .top)
        let inside = Policy.paletteHints(at: .repository(vault))

        #expect(top.map(\.key) == ["↑↓", "↵", "⌘↵", "esc"])
        #expect(inside.map(\.key) == top.map(\.key))
        #expect(top.map(\.what) == ["pohyb", "otevřít", "otevřít na GitHubu", "zavřít"])
        #expect(inside.map(\.what) == [
            "pohyb", "otevřít ke čtení", "otevřít na GitHubu", "o úroveň zpět",
        ])
    }

    /// **Tohle je ten test, kvůli kterému rozhoduje dotaz, a ne jen úroveň.** Zkratka na `⌫`
    /// platí pro celé okno, takže nad napsaným dotazem by přebila mazání znaků — psát by
    /// v paletě přestalo jít.
    @Test("⌫ vrací o úroveň jedině na prázdném poli")
    func backspaceOnlyGoesBackWithAnEmptyField() {
        #expect(Policy.paletteBackspaceGoesBack(level: .repository(vault), query: ""))
        #expect(!Policy.paletteBackspaceGoesBack(level: .repository(vault), query: "d"))
        #expect(!Policy.paletteBackspaceGoesBack(level: .top, query: ""))
        #expect(!Policy.paletteBackspaceGoesBack(level: .top, query: "vault"))
    }

    /// Vstup do repa je půlka jednoho hmatu, ne jeho konec — všechno ostatní kartu zavírá.
    @Test("Paletu nechává otevřenou jedině vstup do repa")
    func onlyEnteringARepositoryKeepsThePaletteOpen() {
        let pr = PRIdentifier(repo: vault, number: 85)
        #expect(!Policy.paletteClosesAfter(.repository(vault)))
        #expect(Policy.paletteClosesAfter(.pullRequest(pr)))
        #expect(Policy.paletteClosesAfter(.file(pr, path: "a.swift")))
        #expect(Policy.paletteClosesAfter(.finding(pr, file: nil, line: nil)))
        #expect(Policy.paletteClosesAfter(.action(.refresh)))
    }

    @Test("Chip v poli nese repo, v první úrovni tam není")
    func theChipShowsTheRepository() {
        #expect(Policy.paletteStage(level: .top).chip == nil)
        #expect(Policy.paletteStage(level: .repository(vault), repository: .loading).chip == "keboola/vault")
    }

    @Test("Výzva pole v druhé úrovni říká, že se filtruje, ne hledá")
    func thePromptSaysWhatTheFieldDoes() {
        #expect(Policy.palettePrompt(at: .top).contains("repozitář"))
        #expect(Policy.palettePrompt(at: .repository(vault)).hasPrefix("Filtrovat"))
    }

    // MARK: - Věta o dotahování

    @Test("Dokud se seznam tahá, je v kartě věta o tom; po dotažení není")
    func theNoticeSaysWhatIsHappening() {
        let loading = Policy.paletteStage(level: .repository(vault), repository: .loading)
        #expect(loading.notice == .loading("Dotahují se otevřené pull requesty…"))

        let failed = Policy.paletteStage(level: .repository(vault), repository: .failed("gh spadl"))
        #expect(failed.notice == .failed("gh spadl"))

        let loaded = Policy.paletteStage(level: .repository(vault), repository: .loaded([]))
        #expect(loaded.notice == nil)
        #expect(Policy.paletteStage(level: .top).notice == nil)
    }

    // MARK: - Prázdný stav

    /// **Prázdné repo není prázdný výsledek**, a nad nedotázaným polem se to nesmí slít: „Na „“
    /// nic nesedí“ je věta o hledání, které nikdo nezačal.
    @Test("Nad prázdným polem se nepíše, že nic nesedí")
    func theEmptyStateDistinguishesAnEmptyQuery() {
        let inside = Policy.paletteEmpty(at: .repository(vault), query: "")
        #expect(inside.headline == "V repu keboola/vault není žádný otevřený pull request.")
        // Bez druhé věty: nehledalo se, takže „hledá se v otevřených PR“ by odpovídalo na
        // otázku, kterou nikdo nepoložil.
        #expect(inside.note == nil)

        let asked = Policy.paletteEmpty(at: .repository(vault), query: "delay")
        #expect(asked.headline == "Na „delay“ nic nesedí.")
        #expect(asked.note?.contains("titulku") == true)

        // Samé mezery jsou taky „nezeptal jsem se“ — jinak by věta citovala prázdno.
        #expect(Policy.paletteEmpty(at: .repository(vault), query: "  ").note == nil)
    }

    @Test("V první úrovni věta vypisuje i repozitáře, protože se v nich hledá")
    func theTopLevelNoteMentionsRepositories() {
        let empty = Policy.paletteEmpty(at: .top, query: "xyz")
        #expect(empty.headline == "Na „xyz“ nic nesedí.")
        #expect(empty.note?.contains("repozitářích") == true)
    }

    // MARK: - Řádky repozitářů

    @Test("Řádek repa nese počet otevřených PR a stáří posledního pushe")
    func aRepositoryRowSaysWhatIsInIt() throws {
        let rows = Policy.paletteRepositories(
            [repository("keboola/vault", open: 7)],
            query: "vault",
            now: now
        )

        let row = try #require(rows.first)
        #expect(row.id == "repo:keboola/vault")
        #expect(row.group == .repositories)
        #expect(row.title == "keboola/vault")
        #expect(row.mark == .repository)
        #expect(row.target == .repository(vault))
        // `⌘↵` vede na seznam otevřených PR, ne na přehled repa.
        #expect(row.url == URL(string: "https://github.com/keboola/vault/pulls"))
        let subtitle = try #require(row.subtitle)
        #expect(subtitle.hasPrefix("7 otevřených PR · naposledy "))
    }

    /// Nula je **slovo**, ne číslice: `0 otevřených PR` se čte jako počet, který se nepodařilo
    /// spočítat.
    @Test("Repo bez otevřených PR to má napsané slovem")
    func zeroOpenPullRequestsIsAWord() throws {
        let rows = Policy.paletteRepositories(
            [repository("keboola/php-vault-client", open: 0)],
            query: "vault",
            now: now
        )

        #expect(try #require(rows.first?.subtitle).hasPrefix("bez otevřených PR"))
    }

    /// Jednotné a množné číslo — aplikace je česká, takže `2 otevřených PR` praští do očí.
    @Test("Počet se skloňuje")
    func theCountIsDeclined() throws {
        for (count, word) in [(1, "1 otevřený PR"), (2, "2 otevřené PR"), (7, "7 otevřených PR")] {
            let rows = Policy.paletteRepositories(
                [repository("keboola/vault", open: count)],
                query: "vault",
                now: now
            )
            #expect(try #require(rows.first?.subtitle).hasPrefix(word))
        }
    }

    /// **Prázdné razítko se vynechá celé** — `naposledy nikdy` by tvrdilo víc, než co data unesou.
    @Test("Repo, do kterého se nikdy nepushlo, o stáří nepíše nic")
    func aRepositoryWithoutAPushSaysNothingAboutAge() throws {
        let rows = Policy.paletteRepositories(
            [repository("keboola/vault", open: 1, pushedAgo: nil)],
            query: "vault",
            now: now
        )

        #expect(try #require(rows.first?.subtitle) == "1 otevřený PR")
    }

    /// Pořadí ze zákresu: `vault` (7), `vault-cli` (2), `php-vault-client` (0). Je to nabídka,
    /// **kam jít**, takže nahoru patří repo, ve kterém je co číst.
    @Test("Repa se řadí podle počtu otevřených PR")
    func repositoriesAreOrderedByOpenPullRequests() {
        let rows = Policy.paletteRepositories(
            [
                repository("keboola/php-vault-client", open: 0),
                repository("keboola/vault", open: 7),
                repository("keboola/vault-cli", open: 2),
            ],
            query: "vault",
            now: now
        )

        #expect(rows.map(\.title) == [
            "keboola/vault", "keboola/vault-cli", "keboola/php-vault-client",
        ])
    }

    @Test("Při shodném počtu rozhoduje poslední push, pak jméno")
    func tiesAreBrokenByPushAndThenName() {
        let rows = Policy.paletteRepositories(
            [
                repository("org/stare", open: 1, pushedAgo: 86_400),
                repository("org/nove", open: 1, pushedAgo: 60),
                repository("org/bez-pushe", open: 1, pushedAgo: nil),
            ],
            query: "org",
            now: now
        )

        #expect(rows.map(\.title) == ["org/nove", "org/stare", "org/bez-pushe"])
    }

    /// Strop je **na skupinu**, jako u ostatních (#184) — je to nabídka, kam jít, ne odpověď na
    /// to, co je v okně.
    @Test("Ze skupiny Repozitáře se skládá nejvýš strop řádků")
    func theRepositoryGroupHasTheSameCapAsTheOthers() {
        let many = (1...20).map { repository("org/r\($0)", open: $0) }

        #expect(Policy.paletteRepositories(many, query: "org", now: now).count == 6)
        #expect(Policy.paletteRepositories(many, query: "org", limit: 2, now: now).count == 2)
    }

    /// **Filtruje se dřív, než se skládají řádky** — nad tisícem rep by se jinak formátoval
    /// podtitulek při každém úhozu. Test to tvrdí přes výsledek: co nesedí, se nevrátí.
    @Test("Hledá se v owner/name, ne v podtitulku")
    func repositoriesAreSearchedByName() {
        let repositories = [
            repository("keboola/vault", open: 7),
            repository("keboola/connection", open: 3),
        ]

        #expect(Policy.paletteRepositories(repositories, query: "vault", now: now).count == 1)
        #expect(Policy.paletteRepositories(repositories, query: "keboola", now: now).count == 2)
        // `otevřených` je v podtitulku každého řádku, takže by nerozlišilo nic.
        #expect(Policy.paletteRepositories(repositories, query: "otevřených", now: now).isEmpty)
        // Diakritika ani velikost písmen nerozhoduje — tatáž pravidla jako v paletě (#184).
        #expect(Policy.paletteRepositories(repositories, query: "VAULT", now: now).count == 1)
    }

    @Test("Prázdný dotaz vrátí nabídku, ne prázdno")
    func anEmptyQueryStillOffersRepositories() {
        let rows = Policy.paletteRepositories(
            [repository("keboola/vault", open: 7)],
            query: "",
            now: now
        )

        #expect(rows.count == 1)
    }

    // MARK: - Řádky otevřených PR

    @Test("Řádek PR nese číslo v titulku a autora se stářím v podtitulku")
    func aPullRequestRowSaysWhatItIs() throws {
        let rows = Policy.paletteRepositoryPullRequests(
            [summary(91, title: "feat: configurable secret TTL", author: "odinuv", ago: 7_200)],
            now: now
        )

        let row = try #require(rows.first)
        #expect(row.id == "repo-pr:keboola/vault#91")
        #expect(row.group == .repositoryPullRequests)
        #expect(row.title == "#91 · feat: configurable secret TTL")
        #expect(row.mark == .pullRequest(.open))
        #expect(row.target == .pullRequest(PRIdentifier(repo: vault, number: 91)))
        #expect(row.url == URL(string: "https://github.com/keboola/vault/pull/91"))
        #expect(row.badge == nil)
        #expect(try #require(row.subtitle).hasPrefix("odinuv · "))
        // Klíčová slova jsou prázdná schválně: všechny řádky jsou z jednoho repa, takže shoda na
        // jeho jméno by vytáhla celý seznam a nic by mezi řádky nerozlišila.
        #expect(row.keywords.isEmpty)
    }

    /// Tvar značky je u otevřeného a rozpracovaného PR tentýž, takže rozdíl nese jedině barva —
    /// a ta sama nestačí.
    @Test("Draft má slovo v podtitulku, ostatní stavy ne")
    func draftIsAWordNotJustAShade() throws {
        let draft = Policy.paletteRepositoryPullRequests([summary(88, state: .draft)], now: now)
        #expect(try #require(draft.first?.subtitle).hasSuffix(" · draft"))

        let open = Policy.paletteRepositoryPullRequests([summary(85)], now: now)
        #expect(try #require(open.first?.subtitle).contains("draft") == false)
    }

    /// Řadí se tady, protože `gh pr list` vrací PR **podle čísla** (změřeno na `cli/cli`).
    @Test("PR se řadí podle poslední změny, ne podle čísla")
    func pullRequestsAreOrderedByLastChange() {
        let rows = Policy.paletteRepositoryPullRequests(
            [
                summary(85, ago: 3_600),
                summary(91, ago: 7_200),
                summary(88, ago: 86_400),
                summary(84, ago: 60),
            ],
            now: now
        )

        #expect(rows.map(\.title) == ["#84 · titulek", "#85 · titulek", "#91 · titulek", "#88 · titulek"])
    }

    @Test("Při shodném razítku rozhoduje vyšší číslo")
    func tiesAreBrokenByNumber() {
        let rows = Policy.paletteRepositoryPullRequests(
            [summary(84, ago: 60), summary(91, ago: 60)],
            now: now
        )

        #expect(rows.map(\.title) == ["#91 · titulek", "#84 · titulek"])
    }

    // MARK: - Odznaky

    /// `moje` má přednost: fronta je od #332 množina **cizích** PR, takže `ve frontě` u vlastního
    /// PR by tvrdilo, že se na něj čeká review ode mě.
    @Test("Odznak: moje má přednost před ve frontě")
    func ownershipWinsOverTheQueue() {
        let mine = summary(84, author: "ondrajodas")
        let theirs = summary(85, author: "odinuv")
        let unknown = summary(88, author: "kdosi")

        #expect(
            Policy.paletteBadge(of: mine, mine: ["ondrajodas"], sources: [mine.id]) == .mine
        )
        #expect(
            Policy.paletteBadge(of: theirs, mine: ["ondrajodas"], sources: [theirs.id]) == .inQueue
        )
        #expect(Policy.paletteBadge(of: unknown, mine: ["ondrajodas"], sources: []) == nil)
    }

    @Test("Bez známého viewera není nic moje — a to je jiný stav než ve frontě")
    func withoutAViewerNothingIsMine() {
        let pr = summary(84, author: "ondrajodas")

        #expect(Policy.paletteBadge(of: pr, mine: [], sources: []) == nil)
        #expect(Policy.paletteBadge(of: pr, mine: [], sources: [pr.id]) == .inQueue)
    }

    @Test("Odznaky se do řádků dostanou, ne jen spočítají")
    func badgesReachTheRows() throws {
        let mine = summary(84, author: "ondrajodas", ago: 60)
        let queued = summary(85, author: "odinuv", ago: 120)

        let rows = Policy.paletteRepositoryPullRequests(
            [mine, queued],
            mine: ["ondrajodas"],
            sources: [queued.id],
            now: now
        )

        #expect(rows.map(\.badge) == [.mine, .inQueue])
        #expect(rows.map { $0.badge?.czechLabel } == ["moje", "ve frontě"])
    }
}
