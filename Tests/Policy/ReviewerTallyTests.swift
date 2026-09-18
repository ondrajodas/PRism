import Foundation
import Testing

@testable import PRism

/// Součet odmítnutí po reviewerech (#514).
///
/// **Vyčerpávající výčet nad čistou funkcí**, bez mockování: vstupem jsou uložené záznamy, tedy
/// přesně to, co má funkce sečíst. Nejcennější tvrzení tu jsou ta, která říkají, že se něco
/// **ne**stalo — že se přenesený nález nezapočítá dvakrát a že věta nad čtyřmi nálezy mlčí.
@Suite("Policy.reviewerTallies")
struct ReviewerTallyTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let repo = RepoID(owner: "keboola", name: "job-queue")
    private let otherRepo = RepoID(owner: "ondrajodas", name: "PRism")

    private func pullRequest(_ number: Int, in repo: RepoID? = nil) -> PRIdentifier {
        PRIdentifier(repo: repo ?? self.repo, number: number)
    }

    /// Záznam s jedním během. `summaries` jsou věty nálezů — každá je jiný nález, protože do
    /// klíče (`Policy.key(of:)`) vstupuje `summary`.
    private func record(
        _ number: Int = 1,
        in repo: RepoID? = nil,
        skill: String = "code-review",
        headSha: String = "aaaa1111",
        summaries: [String],
        finishedAt: Date? = nil,
        isStale: Bool = false,
        closedAt: Date? = nil,
        dismissals: [FindingKey: FindingDismissal] = [:],
        carriedFrom: String? = nil
    ) -> ReviewRecord {
        let pr = pullRequest(number, in: repo)
        // Přenesený nález jde do běhu **tou cestou, jakou vzniká doopravdy** (#517): z běhu
        // samotného nevypadne nic a `StoredReviewRun.init` si ho složí z `ReviewRun.increment`.
        var run = ReviewRun(
            key: ReviewRunKey(pullRequest: pr, headSha: headSha, skillID: skill),
            summary: carriedFrom == nil ? summary(summaries) : summary([]),
            outcome: .finished
        )
        if let carriedFrom {
            run.increment = IncrementalReviewOutcome(
                range: IncrementalDiffRange(seen: carriedFrom, head: headSha),
                carried: summaries.map {
                    makeFinding(
                        file: "Cart.swift",
                        line: 13,
                        summary: $0,
                        reviewer: skill,
                        headSha: headSha,
                        carriedFrom: carriedFrom
                    )
                },
                statuses: [:],
                askedForVerdicts: true
            )
        }
        return ReviewRecord(
            pullRequest: pr,
            headSha: headSha,
            runs: [StoredReviewRun(run, finishedAt: finishedAt ?? now)],
            isStale: isStale,
            closedAt: closedAt,
            dismissals: dismissals
        )
    }

    private func summary(_ summaries: [String]) -> StreamSummary {
        var summary = StreamSummary()
        summary.calledReportFindings = true
        summary.findings = summaries.map { makeReported(file: "Cart.swift", line: 13, summary: $0) }
        return summary
    }

    private func dismissals(
        _ summaries: [String],
        skill: String = "code-review",
        headSha: String = "aaaa1111",
        reason: FindingDismissal.Reason
    ) -> [FindingKey: FindingDismissal] {
        makeDismissals(
            summaries.map { makeFinding(file: "Cart.swift", line: 13, summary: $0, reviewer: skill, headSha: headSha) },
            reason: reason
        )
    }

    private func names(_ count: Int, prefix: String = "n") -> [String] {
        (1...count).map { "\(prefix)\($0)" }
    }

    // MARK: - Prázdno

    @Test("Bez záznamů není co sečíst")
    func noRecordsMeansNoRows() {
        #expect(Policy.reviewerTallies(from: [], now: now).isEmpty)
    }

    @Test("Období, ve kterém nic není, nevydá prázdný řádek")
    func aQuietPeriodDoesNotProduceAnEmptyRow() {
        // Běh starší než okno se **zahodí celý**, ne započítá jako nula: řádek `0 nálezů` by
        // v bloku vypadal jako reviewer, který nic nenašel, a to je jiné tvrzení.
        let old = record(summaries: names(3), finishedAt: now.addingTimeInterval(-31 * 24 * 3600))

        #expect(Policy.reviewerTallies(from: [old], now: now).isEmpty)
    }

    @Test("Okno je třicet dní a měří se od konce běhu")
    func theWindowIsThirtyDaysFromTheEndOfTheRun() {
        let inside = record(1, summaries: names(2), finishedAt: now.addingTimeInterval(-29 * 24 * 3600))
        let outside = record(2, summaries: names(5), finishedAt: now.addingTimeInterval(-31 * 24 * 3600))

        let tallies = Policy.reviewerTallies(from: [inside, outside], now: now)

        #expect(tallies.count == 1)
        #expect(tallies.first?.total == 2)
    }

    // MARK: - Čtyři kategorie

    @Test("Nález na živé hlavě je nerozhodnuto, ne převzato")
    func aFindingOnALiveHeadIsUndecided() {
        let tally = try? #require(Policy.reviewerTallies(from: [record(summaries: names(3))], now: now).first)

        #expect(tally?.undecided == 3)
        #expect(tally?.taken == 0)
    }

    @Test("Uzavřený případ je převzato — zastaralá hlava i zavřený PR")
    func aSettledCaseIsTaken() {
        let stale = record(1, summaries: names(2), isStale: true)
        let closed = record(2, summaries: names(3), closedAt: now)

        let tallies = Policy.reviewerTallies(from: [stale, closed], now: now)

        #expect(tallies.map(\.taken).reduce(0, +) == 5)
        #expect(tallies.map(\.undecided).reduce(0, +) == 0)
    }

    @Test("Přenesený nález je převzato i na živé hlavě — přežil push, na kterém šel odmítnout")
    func aCarriedFindingCountsAsTaken() {
        let carried = record(headSha: "bbbb2222", summaries: names(2), carriedFrom: "aaaa1111")

        let tally = try? #require(Policy.reviewerTallies(from: [carried], now: now).first)

        #expect(tally?.taken == 2)
        #expect(tally?.undecided == 0)
    }

    @Test("Oba důvody se počítají zvlášť")
    func bothReasonsAreCountedSeparately() {
        let record = record(
            summaries: names(4),
            dismissals: dismissals(["n1", "n2"], reason: .invalid)
                .merging(dismissals(["n3"], reason: .irrelevant)) { _, new in new }
        )

        let tally = try? #require(Policy.reviewerTallies(from: [record], now: now).first)

        #expect(tally?.invalid == 2)
        #expect(tally?.irrelevant == 1)
        #expect(tally?.undecided == 1)
        #expect(tally?.total == 4)
    }

    // MARK: - Jeden nález se počítá jednou

    @Test("Přenesený nález ležící ve dvou záznamech se nezapočítá dvakrát")
    func aFindingStoredUnderTwoHeadsIsCountedOnce() {
        // #517: staré nálezy se přenášejí na novou hlavu, takže týž nález leží ve dvou souborech
        // jednoho PR. Bez slití by dvakrát vážil zrovna ten nález, na kterém reviewer trval.
        let old = record(1, headSha: "aaaa1111", summaries: names(3), isStale: true)
        let new = record(1, headSha: "bbbb2222", summaries: names(3), carriedFrom: "aaaa1111")

        let tally = try? #require(Policy.reviewerTallies(from: [old, new], now: now).first)

        #expect(tally?.total == 3)
        #expect(tally?.taken == 3)
    }

    @Test("Odmítnutí zapsané u starší hlavy přebíjí nerozhodnuto u té dnešní")
    func aDismissalOnAnOlderHeadWins() {
        let old = record(
            1,
            headSha: "aaaa1111",
            summaries: names(2),
            isStale: true,
            dismissals: dismissals(["n1"], reason: .invalid)
        )
        let new = record(1, headSha: "bbbb2222", summaries: names(2))

        let tally = try? #require(Policy.reviewerTallies(from: [old, new], now: now).first)

        #expect(tally?.invalid == 1)
        #expect(tally?.total == 2)
    }

    @Test("Týž nález ve dvou pull requestech je dvakrát — je to dvakrát nahlášeno")
    func theSameSentenceInTwoPullRequestsCountsTwice() {
        let first = record(1, summaries: names(1))
        let second = record(2, summaries: names(1))

        let tally = try? #require(Policy.reviewerTallies(from: [first, second], now: now).first)

        #expect(tally?.total == 2)
    }

    // MARK: - Dvojice repo × reviewer

    @Test("Tentýž skill ve dvou repech jsou dva řádky")
    func oneSkillInTwoRepositoriesIsTwoRows() {
        let here = record(1, summaries: names(2))
        let there = record(1, in: otherRepo, summaries: names(3))

        let tallies = Policy.reviewerTallies(from: [here, there], now: now)

        #expect(tallies.count == 2)
        #expect(Set(tallies.map(\.repo)) == [repo, otherRepo])
    }

    @Test("Dva skilly v jednom repu jsou dva řádky")
    func twoSkillsInOneRepositoryAreTwoRows() {
        let one = record(1, skill: "code-review", summaries: names(2))
        let two = record(1, skill: "security-review", summaries: names(3))

        let tallies = Policy.reviewerTallies(from: [one, two], now: now)

        #expect(tallies.count == 2)
        #expect(Set(tallies.map(\.reviewer)) == ["code-review", "security-review"])
    }

    // MARK: - Pořadí

    @Test("Nahoře je ten, u kterého je nejvíc co opravit")
    func theWorstRatioComesFirst() {
        let bad = record(1, skill: "security-review", summaries: names(6), dismissals: dismissals(
            names(5),
            skill: "security-review",
            reason: .invalid
        ))
        let good = record(1, in: otherRepo, skill: "code-review", summaries: names(20))

        let tallies = Policy.reviewerTallies(from: [bad, good], now: now)

        #expect(tallies.first?.reviewer == "security-review")
    }

    @Test("Při shodě podílu jde napřed ten s víc nálezy, pak abecedně")
    func tiesAreBrokenBySizeThenName() {
        let small = record(1, skill: "b-review", summaries: names(2))
        let big = record(1, skill: "a-review", summaries: names(4))
        let same = record(2, skill: "c-review", summaries: names(4))

        let tallies = Policy.reviewerTallies(from: [small, big, same], now: now)

        #expect(tallies.map(\.reviewer) == ["a-review", "c-review", "b-review"])
    }
}

/// Věta pod pruhem a podíl v tabulce — dvě různé otázky nad týmž řádkem.
@Suite("Policy.reviewerSignal a reviewerShare")
struct ReviewerSignalTests {
    private let repo = RepoID(owner: "keboola", name: "job-queue")

    private func tally(taken: Int = 0, invalid: Int = 0, irrelevant: Int = 0, undecided: Int = 0) -> ReviewerTally {
        ReviewerTally(
            reviewer: "code-review",
            repo: repo,
            taken: taken,
            invalid: invalid,
            irrelevant: irrelevant,
            undecided: undecided
        )
    }

    // MARK: - Věta

    @Test("Bez nálezů není věta")
    func noFindingsMeansNoSentence() {
        #expect(Policy.reviewerSignal(of: tally()) == nil)
    }

    @Test("Pod prahem podílu je to prostý součet")
    func belowTheShareThresholdItIsJustACount() {
        let signal = Policy.reviewerSignal(of: tally(taken: 31, invalid: 3, irrelevant: 2, undecided: 2))

        #expect(signal == ReviewerSignal(text: "31 z 38 převzato", aim: .none))
    }

    @Test("Přesně polovina mlčí — práh je „přes polovinu“, ne „polovina a víc“")
    func exactlyHalfStaysQuiet() {
        let signal = Policy.reviewerSignal(of: tally(taken: 7, invalid: 7))

        #expect(signal?.aim == ReviewerSignal.Aim.none)
        #expect(signal?.text == "7 z 14 převzato")
    }

    @Test("Přes polovinu a nejvíc „neplatí“ míří na skill")
    func mostlyInvalidPointsAtTheSkill() {
        let signal = Policy.reviewerSignal(of: tally(taken: 3, invalid: 9, irrelevant: 2))

        #expect(signal == ReviewerSignal(text: "9 z 14 neplatí → skill", aim: .skill))
    }

    @Test("Přes polovinu a nejvíc „nepatří sem“ míří na pravidla repa")
    func mostlyIrrelevantPointsAtTheRepositoryRules() {
        let signal = Policy.reviewerSignal(of: tally(taken: 5, invalid: 1, irrelevant: 5))

        #expect(signal == ReviewerSignal(text: "5 z 11 nepatří sem → pravidla repa", aim: .repoRules))
    }

    @Test("Při shodě obou důvodů vyhrává „neplatí“ — ta věta míří na to, co se opravit dá")
    func aTieBetweenReasonsGoesToTheSkill() {
        let signal = Policy.reviewerSignal(of: tally(taken: 2, invalid: 3, irrelevant: 3))

        #expect(signal?.aim == ReviewerSignal.Aim.skill)
    }

    @Test("Pod pěti nálezy věta mlčí, i když podíl přes polovinu je")
    func underTheFloorTheSentenceStaysQuiet() {
        // `3 ze 4 neplatí → skill` se čte stejně naléhavě jako `9 ze 14`, přitom je to jedno
        // kliknutí od `2 ze 4`, tedy od stavu, ve kterém by věta zmizela.
        let signal = Policy.reviewerSignal(of: tally(taken: 1, invalid: 3))

        #expect(signal == ReviewerSignal(text: "1 z 4 převzato", aim: .none))
    }

    @Test("Přesně na podlaze už věta mluví")
    func atTheFloorTheSentenceSpeaks() {
        let signal = Policy.reviewerSignal(of: tally(taken: 1, invalid: 4))

        #expect(signal?.aim == ReviewerSignal.Aim.skill)
    }

    @Test("Samé nerozhodnuto nechválí ani neobviňuje")
    func allUndecidedSaysNothingEitherWay() {
        let signal = Policy.reviewerSignal(of: tally(undecided: 9))

        #expect(signal == ReviewerSignal(text: "0 z 9 převzato", aim: .none))
    }

    // MARK: - Podíl v tabulce

    @Test("Podíl pojmenuje to, čeho je nejvíc — čtyři řádky ze zákresu")
    func theShareNamesWhateverIsLargest() {
        #expect(Policy.reviewerShare(of: tally(taken: 3, invalid: 9, irrelevant: 2))
            == ReviewerSignal(text: "64 % neplatí", aim: .skill))
        #expect(Policy.reviewerShare(of: tally(taken: 6, invalid: 1))
            == ReviewerSignal(text: "86 % převzato", aim: .none))
        #expect(Policy.reviewerShare(of: tally(taken: 5, invalid: 1, irrelevant: 5))
            == ReviewerSignal(text: "45 % nepatří sem", aim: .repoRules))
        #expect(Policy.reviewerShare(of: tally(taken: 31, invalid: 3, irrelevant: 2, undecided: 2))
            == ReviewerSignal(text: "82 % převzato", aim: .none))
    }

    @Test("Podíl práh nezná — tabulka je výpis, ne výstraha")
    func theShareIgnoresTheThreshold() {
        // Týž řádek, u kterého věta v bloku mlčí (pod podlahou).
        #expect(Policy.reviewerShare(of: tally(taken: 1, invalid: 3))
            == ReviewerSignal(text: "75 % neplatí", aim: .skill))
    }

    @Test("Samé nerozhodnuto se pojmenuje, ne schová pod nulové „převzato“")
    func allUndecidedIsNamed() {
        #expect(Policy.reviewerShare(of: tally(undecided: 4))
            == ReviewerSignal(text: "100 % nerozhodnuto", aim: .none))
    }

    @Test("Bez nálezů není podíl")
    func noFindingsMeansNoShare() {
        #expect(Policy.reviewerShare(of: tally()) == nil)
    }
}

/// `Otevřít skill ↗` — buď je cesta, nebo tlačítko není.
@Suite("Policy.skillFolder")
struct SkillFolderTests {
    @Test("Skill bez zapsané cesty tlačítko nedostane")
    func anUnknownSkillHasNoFolder() {
        #expect(Policy.skillFolder(of: "code-review", in: [:]) == nil)
        #expect(Policy.skillFolder(of: "code-review", in: ["security-review": "/x"]) == nil)
    }

    @Test("Prázdná a bílá hodnota je totéž co chybějící klíč")
    func blankIsTheSameAsMissing() {
        #expect(Policy.skillFolder(of: "a", in: ["a": ""]) == nil)
        #expect(Policy.skillFolder(of: "a", in: ["a": "   \n"]) == nil)
    }

    @Test("Relativní cesta se odmítá — proti čemu by byla, se z GUI aplikace říct nedá")
    func aRelativePathIsRefused() {
        #expect(Policy.skillFolder(of: "a", in: ["a": "skills/code-review"]) == nil)
        #expect(Policy.skillFolder(of: "a", in: ["a": "./skills"]) == nil)
    }

    @Test("Vlnovka se rozbaluje — v config.json ji člověk napíše")
    func theTildeIsExpanded() {
        let folder = Policy.skillFolder(of: "a", in: ["a": "~/.claude/skills/code-review"])

        #expect(folder?.path(percentEncoded: false) == NSHomeDirectory() + "/.claude/skills/code-review")
    }

    @Test("Absolutní cesta projde i s bílými znaky kolem")
    func anAbsolutePathIsTakenAsIs() {
        let folder = Policy.skillFolder(of: "a", in: ["a": "  /opt/skills/code-review  "])

        #expect(folder?.path(percentEncoded: false) == "/opt/skills/code-review")
    }
}
