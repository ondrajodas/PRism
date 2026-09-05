import Foundation
import Testing

@testable import PRism

/// Odložení pull requestu (#512) — rozhodnutí o tom, **kdy odložení skončí**.
///
/// Vyčerpávajícím výčtem, jak se `Policy` testuje: tři podmínky × (splněno / nesplněno / nevíme).
/// Cenná polovina jsou tvrzení o tom, co se **nestane** — odložení, které se zruší dřív, než mělo,
/// vypadá jako porucha odložení, a odložení, které se nezruší nikdy, je ztracená práce. Ani jedno
/// nejde poznat z obrazovky, protože odložený PR není vidět.
@Suite("Policy — odložení PR (#512)")
struct SnoozePolicyTests {
    private let pr = PRIdentifier("cli/cli#1")!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Kalendář s **pevnou zónou**: `Calendar.current` nese zónu stroje, takže by se test
    /// v jiné zóně rozešel s tím, co se počítá v okně (#367 — globální stav procesu).
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    private func snooze(_ condition: SnoozeCondition) -> Snooze {
        Snooze(pullRequest: pr, condition: condition, since: now)
    }

    private func summary(
        _ text: String,
        author: String = "odinuv",
        updatedAt: TimeInterval = 100
    ) -> PullRequestSummary {
        let id = PRIdentifier(text)!
        return PullRequestSummary(
            id: id,
            title: "chore: modernize dependencies",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            state: .open
        )
    }
}

// MARK: - Vypršení podle času

extension SnoozePolicyTests {
    @Test("Před termínem odložení trvá")
    func timeKeepsTheSnooze() {
        let snooze = snooze(.until(now.addingTimeInterval(60)))

        #expect(!Policy.snoozeExpired(snooze, head: nil, comments: nil, now: now))
    }

    /// Hranice, ne okolí: `do 9:00` má v devět skončit.
    @Test("Na termínu odložení končí")
    func timeExpiresOnTheDeadline() {
        let snooze = snooze(.until(now))

        #expect(Policy.snoozeExpired(snooze, head: nil, comments: nil, now: now))
    }

    @Test("Po termínu odložení končí")
    func timeExpiresAfterTheDeadline() {
        let snooze = snooze(.until(now.addingTimeInterval(-1)))

        #expect(Policy.snoozeExpired(snooze, head: nil, comments: nil, now: now))
    }

    /// **Časová podmínka se nedá zablokovat nedostupným GitHubem.** Kdyby čas čekal na odpověď
    /// z rozhlídky, ležel by PR odložený `do zítra` schovaný celý den, ve kterém GitHub zlobí.
    @Test("Čas vyprší i bez odpovědi z GitHubu")
    func timeDoesNotNeedASignal() {
        #expect(!snooze(.until(now)).condition.needsSignal)
        #expect(Policy.snoozeExpired(snooze(.until(now)), head: nil, comments: nil, now: now))
    }
}

// MARK: - Vypršení podle pushe

extension SnoozePolicyTests {
    @Test("Stejná hlava odložení nezruší")
    func sameHeadKeepsTheSnooze() {
        let snooze = snooze(.nextPush(head: "4f2ac91"))

        #expect(!Policy.snoozeExpired(snooze, head: "4f2ac91", comments: nil, now: now))
    }

    @Test("Jiná hlava odložení zruší")
    func newHeadExpiresTheSnooze() {
        let snooze = snooze(.nextPush(head: "4f2ac91"))

        #expect(Policy.snoozeExpired(snooze, head: "9c1de02", comments: nil, now: now))
    }

    /// **Nedoručená odpověď není změna.** PR, na který se rozhlídka nedostala (strop dotazu,
    /// chybějící alias), o svém stavu neříká nic — a „nevíme“ se nesmí přečíst jako „pushlo se“.
    @Test("Nezjištěná hlava odložení nezruší")
    func unknownHeadKeepsTheSnooze() {
        let snooze = snooze(.nextPush(head: "4f2ac91"))

        #expect(!Policy.snoozeExpired(snooze, head: nil, comments: nil, now: now))
    }

    /// **Neznámý základ se nesmí splést s rozchodem.** Ve chvíli odložení se hlava neví (search ji
    /// nevrací), takže by odložení bez tohohle pravidla skončilo první rozhlídkou — tedy do minuty.
    @Test("Bez základu odložení do pushe nikdy nevyprší")
    func missingPushBaselineKeepsTheSnooze() {
        let snooze = snooze(.nextPush(head: nil))

        #expect(!Policy.snoozeExpired(snooze, head: "9c1de02", comments: nil, now: now))
        #expect(!Policy.snoozeExpired(snooze, head: nil, comments: nil, now: now))
    }
}

// MARK: - Vypršení podle komentáře

extension SnoozePolicyTests {
    @Test("Stejný počet příspěvků odložení nezruší")
    func sameCommentCountKeepsTheSnooze() {
        #expect(!Policy.snoozeExpired(snooze(.nextComment(count: 3)), head: nil, comments: 3, now: now))
    }

    @Test("Vyšší počet příspěvků odložení zruší")
    func newCommentExpiresTheSnooze() {
        #expect(Policy.snoozeExpired(snooze(.nextComment(count: 3)), head: nil, comments: 4, now: now))
    }

    /// **Smazaný komentář není příchozí komentář.** Kdyby se porovnávalo `!=`, ukončilo by
    /// odložení to, že někdo něco vzal zpátky — tedy událost, o které jsem výslovně řekl, že mě
    /// zajímat nemá.
    @Test("Nižší počet příspěvků odložení nezruší")
    func deletedCommentKeepsTheSnooze() {
        #expect(!Policy.snoozeExpired(snooze(.nextComment(count: 3)), head: nil, comments: 2, now: now))
    }

    @Test("Nezjištěný počet příspěvků odložení nezruší")
    func unknownCommentCountKeepsTheSnooze() {
        #expect(!Policy.snoozeExpired(snooze(.nextComment(count: 3)), head: nil, comments: nil, now: now))
    }

    @Test("Bez základu odložení do komentáře nikdy nevyprší")
    func missingCommentBaselineKeepsTheSnooze() {
        #expect(!Policy.snoozeExpired(snooze(.nextComment(count: nil)), head: nil, comments: 9, now: now))
    }
}

// MARK: - Základ měření

extension SnoozePolicyTests {
    @Test("Časová podmínka základ nepotřebuje a nedostane ho")
    func timeNeedsNoBaseline() {
        #expect(!Policy.snoozeNeedsBaseline(.until(now)))
        #expect(Policy.snoozeBaseline(snooze(.until(now)), head: "9c1de02", comments: 4) == nil)
    }

    @Test("Chybějící základ se doplní z první rozhlídky")
    func fillsTheMissingBaseline() {
        #expect(Policy.snoozeNeedsBaseline(.nextPush(head: nil)))
        let updated = Policy.snoozeBaseline(snooze(.nextPush(head: nil)), head: "4f2ac91", comments: nil)

        #expect(updated?.condition == .nextPush(head: "4f2ac91"))
    }

    /// **Hotový základ se nepřepisuje.** Přepsat ho dnešní hlavou by u PR, na kterém se mezitím
    /// pushlo, znamenalo odložení, které se nikdy neukončí — a nikdo by se to nedozvěděl.
    @Test("Hotový základ pushe se nepřepíše")
    func keepsAnExistingPushBaseline() {
        let updated = Policy.snoozeBaseline(snooze(.nextPush(head: "4f2ac91")), head: "9c1de02", comments: nil)

        #expect(updated == nil)
    }

    /// Bez tohohle by odložení „do dalšího komentáře“ po smazaném komentáři trvalo navždycky:
    /// příští komentář by počet vrátil jen na původní číslo a `>` by nevyšlo.
    @Test("Základ komentářů klesne se smazaným komentářem")
    func lowersTheCommentBaseline() {
        let updated = Policy.snoozeBaseline(snooze(.nextComment(count: 3)), head: nil, comments: 2)

        #expect(updated?.condition == .nextComment(count: 2))
    }

    @Test("Stejný nebo vyšší počet základ nemění")
    func keepsTheCommentBaseline() {
        #expect(Policy.snoozeBaseline(snooze(.nextComment(count: 3)), head: nil, comments: 3) == nil)
        #expect(Policy.snoozeBaseline(snooze(.nextComment(count: 3)), head: nil, comments: 4) == nil)
    }

    @Test("Bez odpovědi se nemění nic")
    func doesNotTouchTheBaselineWithoutASignal() {
        #expect(Policy.snoozeBaseline(snooze(.nextPush(head: nil)), head: nil, comments: nil) == nil)
        #expect(Policy.snoozeBaseline(snooze(.nextComment(count: nil)), head: nil, comments: nil) == nil)
    }
}

// MARK: - Koho se rozhlídka ptá

extension SnoozePolicyTests {
    private func probe(
        _ summaries: [PullRequestSummary],
        snoozed: [PRIdentifier: SnoozeCondition],
        probedAt: [PRIdentifier: Date] = [:],
        limit: Int = Policy.snoozeProbeLimit
    ) -> [PRIdentifier] {
        Policy.snoozeProbe(
            of: summaries,
            snoozed: { id in
                snoozed[id].map { Snooze(pullRequest: id, condition: $0, since: now) }
            },
            probedAt: { probedAt[$0] },
            limit: limit
        )
    }

    /// **Na klidný den nula volání.** `updatedAt` se nepohnul, takže se hlava ani počet příspěvků
    /// nemá čím změnit — a tohle je ta polovina, kvůli které rozhlídka nestojí nic.
    @Test("Beze změny updatedAt se rozhlídka neptá")
    func skipsUnchangedPullRequests() {
        let asked = probe(
            [summary("cli/cli#1")],
            snoozed: [pr: .nextPush(head: "4f2ac91")],
            probedAt: [pr: Date(timeIntervalSince1970: 100)]
        )

        #expect(asked.isEmpty)
    }

    @Test("Posunutý updatedAt se zeptá")
    func asksWhenSomethingHappened() {
        let asked = probe(
            [summary("cli/cli#1", updatedAt: 200)],
            snoozed: [pr: .nextPush(head: "4f2ac91")],
            probedAt: [pr: Date(timeIntervalSince1970: 100)]
        )

        #expect(asked == [pr])
    }

    /// Bez tohohle by odložení `do dalšího pushe` nemělo od čeho měřit, dokud se na PR něco
    /// nestane — tedy přesně tehdy, kdy by se měřit mělo.
    @Test("Bez základu se zeptá i beze změny updatedAt")
    func asksForAMissingBaseline() {
        let asked = probe(
            [summary("cli/cli#1")],
            snoozed: [pr: .nextPush(head: nil)],
            probedAt: [pr: Date(timeIntervalSince1970: 100)]
        )

        #expect(asked == [pr])
    }

    /// **Dotaz na čas by byl dotaz za nic** — a je to ta nejlevnější polovina úspory: PR odložený
    /// do rána se za celou noc nezeptá ani jednou.
    @Test("Časová podmínka se neptá vůbec")
    func neverAsksAboutTime() {
        #expect(probe([summary("cli/cli#1", updatedAt: 999)], snoozed: [pr: .until(now)]).isEmpty)
    }

    @Test("Neodloženého PR se rozhlídka neptá")
    func ignoresPullRequestsThatAreNotSnoozed() {
        #expect(probe([summary("cli/cli#1", updatedAt: 999)], snoozed: [:]).isEmpty)
    }

    /// Strop je na **velikost dokumentu**, ne na cenu — a uříznout má to nejstarší, tedy to, co
    /// snese počkat na příští tik. Pořadí se bere ze vstupu, který je od naposledy změněného.
    @Test("Strop uřízne konec seznamu")
    func capsTheDocument() {
        let ids = ["cli/cli#1", "cli/cli#2", "cli/cli#3"].map { PRIdentifier($0)! }
        let asked = probe(
            ids.map { summary("\($0)", updatedAt: 200) },
            snoozed: Dictionary(uniqueKeysWithValues: ids.map { ($0, SnoozeCondition.nextPush(head: "a")) }),
            limit: 2
        )

        #expect(asked == Array(ids.prefix(2)))
    }
}

// MARK: - Zúžení fronty

extension SnoozePolicyTests {
    @Test("Odložený PR ze seznamu vypadne a objeví se v bloku")
    func hidesSnoozedFromTheQueue() {
        let summaries = [summary("cli/cli#1"), summary("cli/cli#2")]
        let isSnoozed: (PRIdentifier) -> Bool = { $0 == self.pr }

        #expect(Policy.pullRequests(summaries, withoutSnoozed: isSnoozed).map(\.id) == [PRIdentifier("cli/cli#2")])
        #expect(Policy.snoozedPullRequests(in: summaries, isSnoozed: isSnoozed).map(\.id) == [pr])
    }

    /// Ty dvě množiny musí dohromady dát vstup — jinak by PR zmizel z fronty, aniž by se objevil
    /// v bloku, a to je ta tichá díra, kvůli které tohle issue existuje.
    @Test("Fronta a blok dohromady dávají celý seznam")
    func theTwoSetsCoverTheInput() {
        let summaries = ["cli/cli#1", "cli/cli#2", "cli/cli#3"].map { summary($0) }
        let snoozed: Set<PRIdentifier> = [PRIdentifier("cli/cli#1")!, PRIdentifier("cli/cli#3")!]
        let isSnoozed: (PRIdentifier) -> Bool = { snoozed.contains($0) }

        let visible = Policy.pullRequests(summaries, withoutSnoozed: isSnoozed)
        let hidden = Policy.snoozedPullRequests(in: summaries, isSnoozed: isSnoozed)

        #expect(Set(visible.map(\.id)).union(hidden.map(\.id)) == Set(summaries.map(\.id)))
        #expect(Set(visible.map(\.id)).intersection(hidden.map(\.id)).isEmpty)
    }

    /// **Odložit jde jen cizí PR.** Blok `Odložené` visí pod frontou, takže odložené vlastní PR by
    /// ze sekce `Moje PR` zmizelo a nikde by se neobjevilo.
    @Test("Vlastní PR se odložit nedá")
    func onlyForeignPullRequestsCanBeSnoozed() {
        #expect(Policy.canSnooze(.theirs))
        #expect(!Policy.canSnooze(.mine))
    }
}

// MARK: - Nabídka a věty

extension SnoozePolicyTests {
    @Test("Nabídka má čtyři volby a klávesy ⌥1–⌥4")
    func offersFourChoices() {
        let offers = Policy.snoozeOffers(now: now, calendar: calendar)

        #expect(offers.count == 4)
        #expect(offers.map(\.key) == ["1", "2", "3", "4"])
        #expect(offers.map(\.shortcutLabel) == ["⌥1", "⌥2", "⌥3", "⌥4"])
    }

    /// **Popiska nabídky musí slibovat tentýž čas, jaký se nastaví.** Kdyby hodina bydlela na dvou
    /// místech, uměly by se rozejít — a nabídka by lhala o tom, co udělá.
    @Test("Nabídka slibuje tutéž hodinu, jakou nastaví")
    func theLabelMatchesTheDeadline() {
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 14))!
        let offers = Policy.snoozeOffers(now: afternoon, calendar: calendar)
        guard case .until(let deadline) = offers[0].condition else {
            Issue.record("první volba má být časová")
            return
        }

        #expect(offers[0].title == "do zítra 9:00")
        #expect(offers[0].title.contains(Policy.snoozeMorningLabel))
        #expect(calendar.component(.hour, from: deadline) == Policy.snoozeMorningHour)
        #expect(calendar.component(.minute, from: deadline) == 0)
        #expect(calendar.component(.day, from: deadline) == 6)
    }

    /// **Devátá hodina, ne „za 24 hodin“.** Odložení do rána je o pracovním dni: zadané v jednu
    /// v noci má vrátit PR za osm hodin, ne za dvaatřicet.
    @Test("V noci míří první volba na dnešní ráno")
    func nightMeansThisMorning() {
        let night = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 1))!
        let deadline = Policy.snoozeMorning(after: night, calendar: calendar)

        #expect(calendar.component(.hour, from: deadline) == 9)
        #expect(deadline.timeIntervalSince(night) == 8 * 3600)
    }

    /// **Titulek se odvozuje z okamžiku, ne píše vedle něj.** Napsané `zítra` by lhalo pokaždé,
    /// když si někdo PR odloží ve dvě v noci — a je to zrovna ten vzor, který Copilot v tomhle
    /// repu nachází: text tvrdí víc, než data unesou.
    @Test("V noci nabídka neslibuje zítřek")
    func theTitleFollowsTheDeadline() {
        let night = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 1))!

        #expect(Policy.snoozeMorningTitle(after: night, calendar: calendar) == "do rána 9:00")
    }

    /// Odložení bez měřidla nesmí v bloku vypadat jako odložení do neurčita — poznámka slibuje
    /// **podmínku**, ne odhad, takže na chybějícím základu nezávisí.
    @Test("Poznámka mluví o podmínce, ne o odhadu")
    func theNoteDescribesTheCondition() {
        #expect(Policy.snoozeNote(snooze(.nextPush(head: nil)), now: now) == "vrátí se s dalším pushem")
        #expect(Policy.snoozeNote(snooze(.nextComment(count: 3)), now: now) == "vrátí se s dalším komentářem")
    }

    /// **„Zítra“ se počítá proti `now`, ne proti systémovým hodinám.** `isDateInTomorrow` se ptá
    /// na skutečný dnešek, takže by poznámka vycházela náhodně podle toho, kdy test běží — tentýž
    /// kořen jako globální stav procesu (#367).
    @Test("Poznámka u času říká den slovem")
    func theNoteNamesTheDay() {
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 14))!
        let tomorrow = Policy.snoozeMorning(after: afternoon, calendar: calendar)
        let note = Policy.snoozeNote(snooze(.until(tomorrow)), now: afternoon, calendar: calendar)

        #expect(note.hasPrefix("vrátí se zítra "))
        #expect(Policy.snoozeDeadlineLabel(afternoon, now: afternoon, calendar: calendar)
            .hasPrefix("dnes "))
    }

    @Test("Vzdálený termín se píše datem")
    func distantDeadlinesGetADate() {
        let week = now.addingTimeInterval(Policy.snoozeWeek)
        let note = Policy.snoozeNote(snooze(.until(week)), now: now, calendar: calendar)

        #expect(!note.contains("zítra"))
        #expect(!note.contains("dnes"))
    }

    @Test("Nadpis bloku se na nule nekreslí")
    func noBlockWhenNothingIsSnoozed() {
        #expect(Policy.snoozedBlockTitle(count: 0) == nil)
        #expect(Policy.snoozedBlockTitle(count: 2) == "Odložené · 2")
    }

    /// Řádek dění musí říct **proč** se PR vrátil — z fronty samotné to vidět není.
    @Test("Důvod návratu se překládá výčtem")
    func namesEveryReturnReason() {
        #expect(Policy.snoozeReturn(of: .until(now)) == .time)
        #expect(Policy.snoozeReturn(of: .nextPush(head: nil)) == .push)
        #expect(Policy.snoozeReturn(of: .nextComment(count: nil)) == .comment)
        #expect(Policy.snoozeReturnDetail(.time) == "došel čas")
        #expect(Policy.snoozeReturnDetail(.push) == "přišel push")
        #expect(Policy.snoozeReturnDetail(.comment) == "přišel komentář")
        #expect(Policy.snoozeReturnDetail(.manual) == "vrátil jsem ho ručně")
    }
}

// MARK: - Prázdná fronta a věta na desce

extension SnoozePolicyTests {
    /// **Zelené „vyřízeno“ nad prací, kterou jsem si sám schoval, tvrdí opak toho, co je pravda.**
    /// Je to tatáž lekce jako u filtru — a bez vlastního prázdna by se ty dva stavy slily.
    @Test("Fronta prázdná odložením není `žádné PR k review`")
    func allSnoozedIsItsOwnEmptyState() {
        #expect(Policy.listEmptyReason(poll: nil, visible: 0, hidden: 0, snoozed: 2) == .allSnoozed(count: 2))
        #expect(Policy.listEmptyReason(poll: nil, visible: 0, hidden: 0, snoozed: 0) == .poll(.noPullRequests))
    }

    /// **Filtr má přednost**: dá se vypnout jedním kliknutím, kdežto odložení se vrátí samo.
    @Test("Filtr vyhrává nad odložením")
    func filterWinsOverSnooze() {
        #expect(Policy.listEmptyReason(poll: nil, visible: 0, hidden: 1, snoozed: 2) == .filtered(hidden: 1))
    }

    /// **Nenačtená fronta vyhrává nade vším** — nad daty, která nedorazila, se netvrdí nic.
    @Test("Chyba načtení vyhrává nad odložením")
    func pollFailureWinsOverSnooze() {
        let reason = Policy.listEmptyReason(poll: .loading, visible: 0, hidden: 0, snoozed: 2)

        #expect(reason == .poll(.loading))
    }

    /// Deska odložené PR v žádném pruhu nemá, takže věta pod pozdravem je jediné místo domova,
    /// které řekne, že něco schované je.
    @Test("Věta pod pozdravem odložené připisuje")
    func theBoardSentenceMentionsSnoozed() {
        let empty = Policy.board(entries: [])

        #expect(Policy.boardSentence(empty, snoozed: 0) == "Nic na tahu — fronta je vyřízená a nic vlastního nečeká.")
        #expect(Policy.boardSentence(empty, snoozed: 2) == "Nic na tahu · 2 odložené")
        #expect(Policy.boardSentence(empty, snoozed: 1) == "Nic na tahu · 1 odložený")
    }
}
