import Foundation
import Testing

@testable import PRism

/// Kdo se na tomhle diffu pustí a kdo ne (#518).
///
/// **Výčet, ne příklady**: přeskočený reviewer o kódu neřekne nic, takže se každá odpověď „ne“
/// platí chybějícím review. Nejcennější tvrzení jsou tady proto ta, která říkají, že se reviewer
/// **pustí** — bez pravidla, nad prázdným pravidlem i nad seznamem cest, který se nezjistil.
@Suite("Policy — routing reviewerů")
struct ReviewerRoutingTests {
    private let auth = ["src/Auth/**", "*.env*", "composer.lock"]

    private func plan(files: [String], rules: [ReviewerRouting]) -> ReviewerRoutingPlan {
        Policy.reviewersToRun(files: files, rules: rules)
    }

    // MARK: - Bez pravidla se pouští, jako do #518

    @Test("Reviewer bez pravidla se pouští na jakémkoli diffu")
    func aReviewerWithoutARuleAlwaysRuns() {
        let rules = [ReviewerRouting(skill: "code-review")]
        #expect(plan(files: ["README.md"], rules: rules).skills == ["code-review"])
        #expect(plan(files: ["README.md"], rules: rules).skipped.isEmpty)
        #expect(plan(files: [], rules: rules).skills == ["code-review"])
    }

    /// Prázdný seznam vzorů **není** odpověď „nikdy“: řádek v tabulce nastavení vzniká prázdný,
    /// takže by jedno kliknutí revieweera tiše vypnulo. Odpovídá se na to odebráním ze sady.
    @Test("Pravidlo bez použitelného vzoru je totéž jako žádné pravidlo")
    func aRuleWithoutUsablePatternsRuns() {
        let rules = Policy.routingRules(
            of: ["code-review", "security-review"],
            paths: ["code-review": [], "security-review": ["   ", ""]]
        )
        let result = plan(files: ["README.md"], rules: rules)
        #expect(result.skills == ["code-review", "security-review"])
        #expect(result.skipped.isEmpty)
    }

    /// Prázdný seznam souborů znamená „nezjistilo se to“ stejně jako „nic se nezměnilo“ — a v obou
    /// případech je bezpečná strana pustit. Přeskočit review kvůli tomu, že `git` neodpověděl, je
    /// tichá ztráta.
    @Test("Prázdný diff nepřeskočí nikoho, ani s pravidlem")
    func anEmptyFileListSkipsNobody() {
        let rules = Policy.routingRules(of: ["security-review"], paths: ["security-review": auth])
        let result = plan(files: [], rules: rules)
        #expect(result.skills == ["security-review"])
        #expect(result.skipped.isEmpty)
    }

    // MARK: - Shoda a neshoda

    @Test("Shoda na jediném souboru stačí")
    func oneMatchingFileIsEnough() {
        let rules = Policy.routingRules(of: ["security-review"], paths: ["security-review": auth])
        let result = plan(files: ["README.md", "src/Auth/Token.php", "docs/x.md"], rules: rules)
        #expect(result.skills == ["security-review"])
        #expect(result.skipped.isEmpty)
    }

    @Test("Bez shody se přeskočí a nese si vzory, ze kterých nesedělo nic")
    func noMatchSkipsAndKeepsThePatterns() {
        let rules = Policy.routingRules(of: ["security-review"], paths: ["security-review": auth])
        let result = plan(files: ["README.md", "docs/navrh.html"], rules: rules)
        #expect(result.skills.isEmpty)
        #expect(result.skipped == ["security-review": auth])
    }

    /// Rozhoduje se **na revieweera**, ne na review: jeden se pustí, druhý ne, a pořadí sady
    /// zůstane — v tom pořadí stojí dráhy v tabu `Průběh`.
    @Test("Víc reviewerů, každý s vlastní odpovědí, v pořadí sady")
    func eachReviewerDecidesForItself() {
        let rules = Policy.routingRules(
            of: ["php-review", "security-review", "docs-review"],
            paths: [
                "security-review": auth,
                "docs-review": ["docs/**"],
            ]
        )
        let result = plan(files: ["src/Cart.php", "docs/navrh.html"], rules: rules)
        #expect(result.skills == ["php-review", "docs-review"])
        #expect(result.skipped == ["security-review": auth])
    }

    // MARK: - Vzory (`Policy.pathMatches`)

    @Test("Vzor bez lomítka platí na jméno souboru kdekoli")
    func aPatternWithoutASlashMatchesTheFileName() {
        #expect(Policy.pathMatches("composer.lock", pattern: "composer.lock"))
        #expect(Policy.pathMatches("app/composer.lock", pattern: "composer.lock"))
        #expect(Policy.pathMatches("config/.env.local", pattern: "*.env*"))
        // …ale ne na složku toho jména: `env/config.php` o žádném `.env` souboru nemluví.
        #expect(!Policy.pathMatches("env/config.php", pattern: "*.env*"))
        #expect(!Policy.pathMatches("composer.lock.bak", pattern: "composer.lock"))
    }

    @Test("Vzor s lomítkem se čte od korene repa")
    func aPatternWithASlashIsAnchoredAtTheRoot() {
        #expect(Policy.pathMatches("src/Auth/User.php", pattern: "src/Auth/**"))
        #expect(Policy.pathMatches("src/Auth/Token/Jwt.php", pattern: "src/Auth/**"))
        #expect(!Policy.pathMatches("src/Authority.php", pattern: "src/Auth/**"))
        // Od korene, takže `Auth/**` na cestu uvnitř `src/` nesedí.
        #expect(!Policy.pathMatches("src/Auth/User.php", pattern: "Auth/**"))
        // Úvodní lomítko je totéž jako bez něj.
        #expect(Policy.pathMatches("composer.lock", pattern: "/composer.lock"))
    }

    @Test("`*` zůstane v jedné složce, `**` přeskočí i podsložky")
    func starStaysInOneSegmentAndDoubleStarDoesNot() {
        #expect(Policy.pathMatches("src/Cart.php", pattern: "src/*.php"))
        #expect(!Policy.pathMatches("src/Order/Cart.php", pattern: "src/*.php"))
        #expect(Policy.pathMatches("src/Order/Cart.php", pattern: "src/**/*.php"))
        // A `**/` přeskočí i **žádnou** složku — tohle je ta část gitignore, kterou samotné
        // „`**` je libovolný text“ nedá.
        #expect(Policy.pathMatches("src/Cart.php", pattern: "src/**/*.php"))
    }

    @Test("`?` je právě jeden znak a přes lomítko nejde")
    func questionMarkIsExactlyOneCharacter() {
        #expect(Policy.pathMatches("v1.php", pattern: "v?.php"))
        #expect(!Policy.pathMatches("v12.php", pattern: "v?.php"))
        #expect(!Policy.pathMatches("a/b", pattern: "a?b"))
    }

    @Test("Vzor zakončený lomítkem je složka")
    func aTrailingSlashMeansTheFolder() {
        #expect(Policy.pathMatches("src/Auth/User.php", pattern: "src/Auth/"))
        #expect(!Policy.pathMatches("src/Cart.php", pattern: "src/Auth/"))
    }

    @Test("Velikost písmen rozhoduje a prázdný vzor nesedí na nic")
    func caseMattersAndAnEmptyPatternMatchesNothing() {
        #expect(!Policy.pathMatches("src/auth/User.php", pattern: "src/Auth/**"))
        #expect(!Policy.pathMatches("src/Auth/User.php", pattern: ""))
        #expect(!Policy.pathMatches("src/Auth/User.php", pattern: "   "))
        #expect(!Policy.pathMatches("", pattern: "*"))
    }

    // MARK: - Platí přeskočení ještě dnes? (`Policy.standingSkips`)

    private func rules(_ paths: [String: [String]]) -> [ReviewerRouting] {
        Policy.routingRules(of: ["php-review", "security-review"], paths: paths)
    }

    @Test("Přeskočení platí, dokud sedí hlava i vzory")
    func aSkipStandsForTheSameHeadAndTheSameRule() {
        let pass = ReviewerRoutingPass(headSha: "aaa", skipped: ["security-review": auth])
        #expect(
            Policy.standingSkips(pass, head: "aaa", rules: rules(["security-review": auth]))
                == ["security-review"]
        )
    }

    /// Po pushi je to rozhodnutí o **jiném** diffu, takže o dnešní hlavě nevypovídá — bez tohohle
    /// by automat po pushi mlčel.
    @Test("Po pushi přeskočení neplatí")
    func aSkipDoesNotSurviveAPush() {
        let pass = ReviewerRoutingPass(headSha: "aaa", skipped: ["security-review": auth])
        #expect(Policy.standingSkips(pass, head: "bbb", rules: rules(["security-review": auth])).isEmpty)
    }

    /// Změna pravidla review pustí — přesně to, co člověk od úpravy nastavení čeká.
    @Test("Změněné ani zrušené pravidlo přeskočení nedrží")
    func changingTheRuleDropsTheSkip() {
        let pass = ReviewerRoutingPass(headSha: "aaa", skipped: ["security-review": auth])
        #expect(
            Policy.standingSkips(
                pass,
                head: "aaa",
                rules: rules(["security-review": ["src/Crypto/**"]])
            ).isEmpty
        )
        #expect(Policy.standingSkips(pass, head: "aaa", rules: rules([:])).isEmpty)
        #expect(Policy.standingSkips(nil, head: "aaa", rules: rules(["security-review": auth])).isEmpty)
    }
}
