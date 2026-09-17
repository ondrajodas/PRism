import Foundation
import Testing

@testable import PRism

/// Série pull requestů (#513) — kdo na kom stojí, v jakém pořadí se to kreslí a co se o tom napíše.
///
/// **Cennější polovina jsou tvrzení o tom, co série NENÍ**: napříč repozitáři, z forku, nad
/// neznámými větvemi, nad mergnutým členem ani nad dvěma PR na téže hlavě. Všechna se rozbijí
/// potichu — ve frontě by se objevila skupina, která spolu nesouvisí, a řazení by kvůli ní přestalo
/// platit.
@Suite("Policy — série PR (#513)")
struct PullRequestSeriesTests {
    private let moment = Date(timeIntervalSince1970: 1_700_000_000)

    private func summary(
        _ text: String,
        title: String = "titulek",
        state: PullRequestState = .open,
        updatedAt: Date? = nil
    ) -> PullRequestSummary {
        let id = PRIdentifier(text)!
        return PullRequestSummary(
            id: id,
            title: title,
            author: "odinuv",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: updatedAt ?? moment,
            state: state
        )
    }

    /// Větve, jak je vrací dotaz na hlavy — **`isCrossRepository: false`**, tedy větev vlastního
    /// repozitáře. Fork a „nevíme“ mají vlastní testy.
    private func refs(_ head: String, on base: String, fork: Bool? = false) -> BranchRefs {
        BranchRefs(head: head, base: base, isCrossRepository: fork)
    }

    private func series(
        _ summaries: [PullRequestSummary],
        _ branches: [String: BranchRefs]
    ) -> [PullRequestSeries] {
        Policy.series(in: summaries, refs: { branches[$0.description] })
    }

    /// Skutečná série z veřejného repa (`cli/cli`, *Refreshable tokens 2/7–4/7*) — větve jsou
    /// opsané z odpovědi API, ze které je i fixtura `pr-heads-series.json`.
    private var stack: (summaries: [PullRequestSummary], refs: [String: BranchRefs]) {
        (
            [
                summary("cli/cli#14451", title: "Refreshable tokens (2/7): refresher domain"),
                summary("cli/cli#14452", title: "Refreshable tokens (3/7): short-lived login"),
                summary("cli/cli#14453", title: "Refreshable tokens (4/7): gh auth token refresh"),
            ],
            [
                "cli/cli#14451": refs("babakks/refresh-token-b-domain", on: "babakks/refresh-token-a-foundation"),
                "cli/cli#14452": refs("babakks/refresh-token-c1-login", on: "babakks/refresh-token-b-domain"),
                "cli/cli#14453": refs("babakks/refresh-token-c2-auth-token", on: "babakks/refresh-token-c1-login"),
            ]
        )
    }
}

// MARK: - Co série je

extension PullRequestSeriesTests {
    /// Dva PR, z nichž jeden stojí na hlavě druhého. Základ je první.
    @Test("Dvojice je série od základu nahoru")
    func findsAPair() {
        let groups = series(
            [summary("cli/cli#2"), summary("cli/cli#1")],
            [
                "cli/cli#1": refs("feature-a", on: "main"),
                "cli/cli#2": refs("feature-b", on: "feature-a"),
            ]
        )

        #expect(groups.count == 1)
        #expect(groups.first?.members == [PRIdentifier("cli/cli#1")!, PRIdentifier("cli/cli#2")!])
    }

    /// Trojice ze **skutečných dat** — pořadí je pořadí mergování, ne pořadí ve vstupu.
    @Test("Trojice drží pořadí od základu")
    func findsATriple() {
        let stack = stack
        let groups = series(stack.summaries.reversed(), stack.refs)

        #expect(groups.map(\.members) == [[
            PRIdentifier("cli/cli#14451")!,
            PRIdentifier("cli/cli#14452")!,
            PRIdentifier("cli/cli#14453")!,
        ]])
    }

    /// Dvě nezávislé série v jednom seznamu se nesmí slít do jedné.
    @Test("Dvě série jsou dvě skupiny")
    func findsTwoSeries() {
        let groups = series(
            [summary("cli/cli#1"), summary("cli/cli#2"), summary("keboola/vault#7"), summary("keboola/vault#8")],
            [
                "cli/cli#1": refs("a", on: "main"),
                "cli/cli#2": refs("b", on: "a"),
                "keboola/vault#7": refs("x", on: "main"),
                "keboola/vault#8": refs("y", on: "x"),
            ]
        )

        #expect(groups.map(\.members) == [
            [PRIdentifier("cli/cli#1")!, PRIdentifier("cli/cli#2")!],
            [PRIdentifier("keboola/vault#7")!, PRIdentifier("keboola/vault#8")!],
        ])
    }

    /// Když na jednom PR stojí dva další, je to **vidlice, ne dva řetězy**: skupina je jedna
    /// a členové jdou do šířky, tedy v pořadí ze vstupu.
    @Test("Vidlice je jedna skupina")
    func keepsAForkAsOneGroup() {
        let groups = series(
            [summary("cli/cli#1"), summary("cli/cli#2"), summary("cli/cli#3")],
            [
                "cli/cli#1": refs("a", on: "main"),
                "cli/cli#2": refs("b", on: "a"),
                "cli/cli#3": refs("c", on: "a"),
            ]
        )

        #expect(groups.map(\.members) == [[
            PRIdentifier("cli/cli#1")!,
            PRIdentifier("cli/cli#2")!,
            PRIdentifier("cli/cli#3")!,
        ]])
    }

    /// Rozpracovaný PR (`draft`) v sérii je — stojí na větvi stejně jako otevřený.
    @Test("Draft je plnohodnotný člen")
    func countsDrafts() {
        let groups = series(
            [summary("cli/cli#1"), summary("cli/cli#2", state: .draft)],
            ["cli/cli#1": refs("a", on: "main"), "cli/cli#2": refs("b", on: "a")]
        )

        #expect(groups.first?.members.count == 2)
    }
}

// MARK: - Co série není

extension PullRequestSeriesTests {
    /// Dva PR proti `main` nejsou série — a je to ten nejčastější stav fronty.
    @Test("Bez společné větve série není")
    func findsNothingWithoutASharedBranch() {
        let groups = series(
            [summary("cli/cli#1"), summary("cli/cli#2")],
            ["cli/cli#1": refs("a", on: "main"), "cli/cli#2": refs("b", on: "main")]
        )

        #expect(groups.isEmpty)
    }

    /// **Napříč repozitáři série není.** `main` má každé repo vlastní, takže by se z jednoho jména
    /// daly spárovat dvě PR, které spolu nemají nic společného.
    @Test("Napříč repozitáři se větve nepárují")
    func refusesToLinkAcrossRepositories() {
        let groups = series(
            [summary("cli/cli#1"), summary("keboola/vault#8")],
            ["cli/cli#1": refs("release", on: "main"), "keboola/vault#8": refs("b", on: "release")]
        )

        #expect(groups.isEmpty)
    }

    /// **PR z forku základ nedrží**: `headRefName` pojmenovává větev cizího repozitáře.
    @Test("Hlava z forku sérii nezaloží")
    func refusesAForkHead() {
        let groups = series(
            [summary("cli/cli#1"), summary("cli/cli#2")],
            [
                "cli/cli#1": refs("a", on: "main", fork: true),
                "cli/cli#2": refs("b", on: "a"),
            ]
        )

        #expect(groups.isEmpty)
    }

    /// **`nil` u `isCrossRepository` je zákaz, ne povolení** — tatáž škola jako u guardu force pushe.
    @Test("Nejistý původ hlavy sérii nezaloží")
    func treatsUnknownOriginAsForeign() {
        let groups = series(
            [summary("cli/cli#1"), summary("cli/cli#2")],
            [
                "cli/cli#1": refs("a", on: "main", fork: nil),
                "cli/cli#2": refs("b", on: "a"),
            ]
        )

        #expect(groups.isEmpty)
    }

    /// Dokud větve nedorazily, netvrdí se nic — „nevíme“ není „nestojí na ničem“.
    @Test("Bez větví se nespojuje nic")
    func staysSilentWithoutRefs() {
        #expect(series([summary("cli/cli#1"), summary("cli/cli#2")], [:]).isEmpty)
    }

    /// Dvě otevřená PR na téže hlavě (GitHub to dovolí proti dvěma základům): která z nich je ta
    /// spodní, se z dat říct nedá, takže se **nespojuje ani jedna**.
    @Test("Dvě PR na téže hlavě základ nedrží")
    func refusesAnAmbiguousHead() {
        let groups = series(
            [summary("cli/cli#1"), summary("cli/cli#2"), summary("cli/cli#3")],
            [
                "cli/cli#1": refs("a", on: "main"),
                "cli/cli#2": refs("a", on: "release"),
                "cli/cli#3": refs("b", on: "a"),
            ]
        )

        #expect(groups.isEmpty)
    }

    /// **Série zaniká sama**: po mergi spodního PR přepne GitHub base horního na `main`.
    @Test("Po přepnutí základu na main série zmizí")
    func dissolvesWhenTheBaseMovesToMain() {
        let before = series(
            [summary("cli/cli#1"), summary("cli/cli#2")],
            ["cli/cli#1": refs("a", on: "main"), "cli/cli#2": refs("b", on: "a")]
        )
        let after = series(
            [summary("cli/cli#1", state: .merged), summary("cli/cli#2")],
            ["cli/cli#1": refs("a", on: "main"), "cli/cli#2": refs("b", on: "main")]
        )

        #expect(before.count == 1)
        #expect(after.isEmpty)
    }

    /// I kdyby GitHub base ještě nepřepnul, mergnutý člen skupinu nedrží — je to řádek, se kterým
    /// se nedá nic dělat.
    @Test("Mergnutý člen skupinu nedrží")
    func ignoresMergedMembers() {
        let groups = series(
            [summary("cli/cli#1", state: .merged), summary("cli/cli#2")],
            ["cli/cli#1": refs("a", on: "main"), "cli/cli#2": refs("b", on: "a")]
        )

        #expect(groups.isEmpty)
    }

    /// Řetěz zakousnutý do ocasu (dvě PR proti sobě) **nevydá nic**: kdo je spodní, se z takových
    /// dat říct nedá. Testuje se vymyšlenými daty — GitHub takový stav běžně nevyrobí, ale pořadí
    /// by se z něj počítalo donekonečna.
    @Test("Kruh v řetězu nevydá sérii")
    func survivesACycle() {
        let groups = series(
            [summary("cli/cli#1"), summary("cli/cli#2")],
            ["cli/cli#1": refs("a", on: "b"), "cli/cli#2": refs("b", on: "a")]
        )

        #expect(groups.isEmpty)
    }

    /// PR proti **vlastní** hlavě (nesmysl, ale dat se týká) není série o jednom členu.
    @Test("PR sám na sobě sérii netvoří")
    func ignoresSelfReference() {
        let groups = series([summary("cli/cli#1")], ["cli/cli#1": refs("a", on: "a")])

        #expect(groups.isEmpty)
    }
}

// MARK: - Umístění

extension PullRequestSeriesTests {
    @Test("Umístění nese pořadí, počet i to, na čem PR stojí")
    func describesThePlacement() {
        let stack = stack
        let groups = series(stack.summaries, stack.refs)

        let base = Policy.seriesPlacement(
            of: PRIdentifier("cli/cli#14451")!,
            in: groups,
            refs: { stack.refs[$0.description] }
        )
        let top = Policy.seriesPlacement(
            of: PRIdentifier("cli/cli#14453")!,
            in: groups,
            refs: { stack.refs[$0.description] }
        )

        #expect(base?.position == 1)
        #expect(base?.count == 3)
        #expect(base?.standsOn == nil)
        #expect(base?.standsOnBase == nil)
        #expect(top?.position == 3)
        #expect(top?.standsOn == PRIdentifier("cli/cli#14452")!)
        #expect(top?.standsOnBase == "babakks/refresh-token-b-domain")
    }

    /// PR mimo sérii umístění nemá — z toho se rozhoduje, že se pilulka nekreslí.
    @Test("Mimo sérii je umístění nil")
    func hasNoPlacementOutsideASeries() {
        #expect(Policy.seriesPlacement(of: PRIdentifier("cli/cli#9")!, in: [], refs: { _ in nil }) == nil)
    }

    /// Bez znalosti větví spodního PR zůstane řetěz **bez pokračování**, ne s vymyšleným `main`.
    @Test("Neznámá base spodního PR nedá pokračování řetězu")
    func leavesTheChainOpenWithoutRefs() {
        let groups = series(
            [summary("cli/cli#1"), summary("cli/cli#2")],
            ["cli/cli#1": refs("a", on: "main"), "cli/cli#2": refs("b", on: "a")]
        )

        let placement = Policy.seriesPlacement(of: PRIdentifier("cli/cli#2")!, in: groups)

        #expect(placement?.standsOn == PRIdentifier("cli/cli#1")!)
        #expect(placement?.standsOnBase == nil)
    }
}

// MARK: - Pořadí v seznamu

extension PullRequestSeriesTests {
    private func order(_ ids: [String], keeping groups: [[String]]) -> [String] {
        let items = ids.map { PRIdentifier($0)! }
        let series = groups.map { PullRequestSeries(members: $0.map { PRIdentifier($0)! }) }
        return Policy.grouped(items, by: { $0 }, keeping: series).map(\.description)
    }

    /// **Skupina si bere místo svého nejlépe umístěného člena** a uvnitř jde od základu nahoru —
    /// i když je v seznamu obráceně a mezi členy leží cizí řádky.
    @Test("Skupina se stáhne k tomu členovi, který je nejvýš")
    func pullsTheGroupToItsBestMember() {
        let result = order(
            ["cli/cli#9", "cli/cli#2", "cli/cli#8", "cli/cli#1", "cli/cli#7"],
            keeping: [["cli/cli#1", "cli/cli#2"]]
        )

        #expect(result == ["cli/cli#9", "cli/cli#1", "cli/cli#2", "cli/cli#8", "cli/cli#7"])
    }

    /// Bez sérií se pořadím nehýbe vůbec — tohle je stav, ve kterém je fronta většinu dní.
    @Test("Bez sérií se pořadí nemění")
    func leavesTheOrderAloneWithoutSeries() {
        let ids = ["cli/cli#9", "cli/cli#2", "cli/cli#8"]

        #expect(order(ids, keeping: []) == ids)
    }

    /// Člen, kterého v seznamu není (schoval ho filtr nebo odložení), se **nedoplňuje**.
    @Test("Chybějící člen se do seznamu nepřidá")
    func doesNotResurrectMissingMembers() {
        let result = order(
            ["cli/cli#9", "cli/cli#2"],
            keeping: [["cli/cli#1", "cli/cli#2"]]
        )

        #expect(result == ["cli/cli#9", "cli/cli#2"])
    }

    /// Dvě série se přeskládají každá ke svému místu a žádný řádek se neztratí ani nezdvojí.
    @Test("Dvě série se nepromíchají")
    func keepsTwoSeriesApart() {
        let result = order(
            ["cli/cli#4", "keboola/vault#8", "cli/cli#3", "keboola/vault#7"],
            keeping: [["cli/cli#3", "cli/cli#4"], ["keboola/vault#7", "keboola/vault#8"]]
        )

        #expect(result == ["cli/cli#3", "cli/cli#4", "keboola/vault#7", "keboola/vault#8"])
    }

    /// **Řazení podle závažnosti sérii nerozhodí** (#513) — skupina jde tam, kam patří ten
    /// nejzávažnější z ní, a uvnitř od základu nahoru.
    @Test("Řazení podle závažnosti drží sérii pohromadě")
    func keepsTheSeriesTogetherByUrgency() {
        let blocking = QueueEntry(
            pullRequest: summary("cli/cli#2"),
            state: .completed(findings: 2),
            row: QueueRow(blocking: 1),
            hasDraft: false
        )
        let quiet = QueueEntry(
            pullRequest: summary("cli/cli#1"),
            state: .notStarted,
            row: .empty,
            hasDraft: false
        )
        let other = QueueEntry(
            pullRequest: summary("cli/cli#9"),
            state: .clean,
            row: .empty,
            hasDraft: false
        )
        let group = PullRequestSeries(members: [quiet.id, blocking.id])

        let sorted = Policy.byUrgency([other, quiet, blocking], keeping: [group])

        #expect(sorted.map(\.id.description) == ["cli/cli#1", "cli/cli#2", "cli/cli#9"])
        // Bez série by blokující nález šel první a `notStarted` až za `clean`… tedy skupina by se
        // rozpadla. Kdyby to tak zůstalo, tenhle test má spadnout.
        #expect(Policy.byUrgency([other, quiet, blocking]).map(\.id.description)
            == ["cli/cli#2", "cli/cli#1", "cli/cli#9"])
    }
}

// MARK: - Popisek nad skupinou

extension PullRequestSeriesTests {
    /// Popisek sedí u **základu** skupiny, je jeden na skupinu a mluví o počtu nakreslených členů.
    @Test("Popisek je jeden a sedí nad skupinou")
    func writesTheCaption() {
        let stack = stack
        let groups = series(stack.summaries, stack.refs)

        let captions = Policy.seriesCaptions(in: stack.summaries, series: groups)

        #expect(captions.count == 1)
        #expect(captions[PRIdentifier("cli/cli#14451")!] == "série · 3 PR · review v pořadí ↓")
    }

    /// Titulky `cli/cli` ticket nenesou, takže ho popisek **vynechá** místo vymýšlení jména.
    @Test("Bez společného ticketu se popisek obejde")
    func writesACaptionWithoutATicket() {
        #expect(
            Policy.seriesCaption(count: 3, titles: ["Refreshable tokens (2/7)", "Refreshable tokens (3/7)"])
                == "série · 3 PR · review v pořadí ↓"
        )
    }

    @Test("Společný ticket je v popisku")
    func writesACaptionWithATicket() {
        #expect(
            Policy.seriesCaption(
                count: 2,
                titles: [
                    "feat(internal-api): AJDA-563 persist requested job delay [2/3]",
                    "feat(flow-result): AJDA-563 read persisted requested job delay [3/3]",
                ]
            ) == "série · AJDA-563 · 2 PR · review v pořadí ↓"
        )
    }

    /// **Průnik, ne první nález**: ticket, který má jen jeden člen, sérii nepojmenovává.
    @Test("Ticket jen u jednoho členu se nebere")
    func requiresACommonTicket() {
        #expect(Policy.seriesTicket(in: ["AJDA-563 a", "AJDA-999 b"]) == nil)
        #expect(Policy.seriesTicket(in: ["AJDA-563 a", "AJDA-563 a taky AJDA-999"]) == "AJDA-563")
        #expect(Policy.seriesTicket(in: ["bez ticketu", "taky nic"]) == nil)
        // Malá písmena a samotné číslo ticket nejsou — jinak by se sérií jmenovalo kdeco.
        #expect(Policy.seriesTicket(in: ["ajda-563 a", "ajda-563 b"]) == nil)
        #expect(Policy.seriesTicket(in: ["fix 12-34 a", "fix 12-34 b"]) == nil)
    }

    /// Popisek vznikne jedině nad skupinou, která je v seznamu **celá a vedle sebe** — nad jedním
    /// osamoceným členem by `2 PR` tvrdilo víc, než je vidět.
    @Test("Nad osamoceným členem popisek nevznikne")
    func skipsTheCaptionForALonelyMember() {
        let drawn = [summary("cli/cli#2")]
        let group = PullRequestSeries(members: [PRIdentifier("cli/cli#1")!, PRIdentifier("cli/cli#2")!])

        #expect(Policy.seriesCaptions(in: drawn, series: [group]).isEmpty)
    }

    /// Popisek se váže na **prvního nakresleného** člena, ne na základ série: když základ schoval
    /// filtr, čára začíná tam, kde skupina doopravdy začíná.
    @Test("Popisek sedí u prvního nakresleného členu")
    func anchorsTheCaptionToTheFirstDrawnMember() {
        let drawn = [summary("cli/cli#2"), summary("cli/cli#3")]
        let group = PullRequestSeries(members: [
            PRIdentifier("cli/cli#1")!,
            PRIdentifier("cli/cli#2")!,
            PRIdentifier("cli/cli#3")!,
        ])

        let captions = Policy.seriesCaptions(in: drawn, series: [group])

        #expect(captions[PRIdentifier("cli/cli#2")!] == "série · 2 PR · review v pořadí ↓")
        #expect(captions[PRIdentifier("cli/cli#3")!] == nil)
    }

    /// **Rozházená skupina popisek nedostane.** Seznam, který si členy nepřeskládal, by jinak
    /// obtáhl čarou i řádky, které do skupiny nepatří — proto se popisek kreslí jedině ve frontě.
    @Test("Nesousedící členové popisek nedostanou")
    func skipsTheCaptionWhenMembersAreApart() {
        let drawn = [summary("cli/cli#1"), summary("cli/cli#9"), summary("cli/cli#2")]
        let group = PullRequestSeries(members: [PRIdentifier("cli/cli#1")!, PRIdentifier("cli/cli#2")!])

        #expect(Policy.seriesCaptions(in: drawn, series: [group]).isEmpty)
    }
}

// MARK: - Pilulky a věty

extension PullRequestSeriesTests {
    private func placement(_ position: Int, of count: Int, on standsOn: String?, base: String? = nil) -> SeriesPlacement {
        SeriesPlacement(
            position: position,
            count: count,
            standsOn: standsOn.map { PRIdentifier($0)! },
            standsOnBase: base
        )
    }

    @Test("Pilulka řekne pořadí a na čem PR stojí")
    func writesThePill() {
        #expect(Policy.seriesPill(placement(1, of: 2, on: nil)) == "1. v sérii")
        #expect(Policy.seriesPill(placement(2, of: 2, on: "keboola/job-queue#726")) == "2. · stojí na #726")
    }

    /// Pilulka v řetězu větví mluví o **tom spodním** PR, ne o tomhle.
    @Test("Pilulka v hlavičce pojmenuje spodní PR")
    func writesTheBasePill() {
        #expect(Policy.seriesBasePill(placement(1, of: 2, on: nil)) == nil)
        #expect(
            Policy.seriesBasePill(placement(2, of: 2, on: "keboola/job-queue#726"))
                == "#726 · 1. v sérii"
        )
    }

    /// Věta o vrstvě je **jen u horního PR** — diff základu je celý, takže by u něj lhala.
    @Test("Věta o vrstvě u základu série není")
    func staysSilentOnTheBase() {
        #expect(Policy.seriesNote(placement(1, of: 3, on: nil), changedFiles: 9) == nil)
    }

    @Test("Věta o vrstvě řekne počet souborů i to, že řetěz zmizí sám")
    func writesTheNote() {
        #expect(
            Policy.seriesNote(placement(2, of: 2, on: "keboola/job-queue#726", base: "main"), changedFiles: 4)
                == "Diff je jen tahle vrstva: 4 soubory nad #726. Až se #726 mergne, GitHub přepne základ na main a řetěz zmizí sám."
        )
        #expect(
            Policy.seriesNote(placement(2, of: 2, on: "keboola/job-queue#726", base: "main"), changedFiles: 1)
                == "Diff je jen tahle vrstva: 1 soubor nad #726. Až se #726 mergne, GitHub přepne základ na main a řetěz zmizí sám."
        )
    }

    /// Dokud diff nedorazil, věta **číslo vynechá** — dopsat ho z ničeho by znamenalo tvrdit, co
    /// aplikace neví.
    @Test("Bez načteného diffu se počet souborů nepíše")
    func writesTheNoteWithoutACount() {
        #expect(
            Policy.seriesNote(placement(2, of: 2, on: "keboola/job-queue#726", base: "main"))
                == "Diff je jen tahle vrstva nad #726. Až se #726 mergne, GitHub přepne základ na main a řetěz zmizí sám."
        )
        // A bez znalosti základu se neslibuje ani `main`.
        #expect(
            Policy.seriesNote(placement(2, of: 2, on: "keboola/job-queue#726"))
                == "Diff je jen tahle vrstva nad #726. Až se #726 mergne, GitHub přepne základ a řetěz zmizí sám."
        )
    }

    @Test("Nápověda říká, co z pilulky plyne")
    func writesTheHint() {
        #expect(Policy.seriesHint(placement(1, of: 3, on: nil)).contains("3 pull requestů"))
        #expect(Policy.seriesHint(placement(2, of: 2, on: "cli/cli#726")).contains("#726"))
    }
}
