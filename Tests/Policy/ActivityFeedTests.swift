import Foundation
import Testing

@testable import PRism

/// Rozhodování o dění (#414) — co je novinka, o čem se **nehlásí vůbec**, co je nepřečtené, jak se
/// to řadí a co se stane při stropu.
///
/// Čisté funkce, takže **vyčerpávajícím výčtem**: nad `ActivityEvent.Kind` se jde `allCases`, ať
/// devátý druh nepropadne bránou nebo nezůstane bez cíle kliknutí.
@Suite("Dění (#414)")
struct ActivityFeedTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "keboola", name: "vault"), number: 85)
    private let other = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(
        _ kind: ActivityEvent.Kind = .findings,
        at seconds: TimeInterval,
        pr: PRIdentifier? = nil,
        announced: Bool = true
    ) -> ActivityEvent {
        ActivityEvent(
            id: "\(kind.rawValue)|\(pr ?? self.pr)|\(seconds)",
            kind: kind,
            pullRequest: pr ?? self.pr,
            at: Date(timeIntervalSince1970: seconds),
            headline: "cokoli",
            wasAnnounced: announced
        )
    }
}

// MARK: - Brána: o čem se nehlásí vůbec

extension ActivityFeedTests {
    /// **Tohle je to tvrzení, kvůli kterému brána existuje**: z dění se nesmí stát obchvat
    /// pravidla „o vlastním PR se nehlásí“ (#332). Kdyby chyběla, hláška, kterou banner vydat
    /// nesmí, by na obrazovce zůstala navěky.
    @Test("Cizí PR: hlásí se všechno kromě cizí aktivity")
    func reportsEverythingButForeignActivityOnTheirs() {
        for kind in ActivityEvent.Kind.allCases {
            #expect(Policy.isReported(kind, on: .theirs) == (kind != .foreignActivity))
        }
    }

    /// Opačná strana: na **mém** PR je novinka jedině to, že se ozval někdo jiný. „Nový PR
    /// k review“ o vlastním pushi ani zastaralé nálezy po vlastním commitu novinky nejsou.
    @Test("Vlastní PR: hlásí se jedině cizí aktivita")
    func reportsOnlyForeignActivityOnMine() {
        for kind in ActivityEvent.Kind.allCases {
            #expect(Policy.isReported(kind, on: .mine) == (kind == .foreignActivity))
        }
    }

    @Test("Vlastní PR nedostane řádek o novém PR ani o zastaralých nálezech")
    func skipsOwnPullRequests() {
        #expect(Policy.newPullRequestActivity(
            for: pr,
            title: "cokoli",
            ownership: .mine,
            at: now,
            announced: true
        ) == nil)
        #expect(Policy.staleFindingsActivity(
            for: pr,
            ownership: .mine,
            head: "9c1f0ab",
            commits: 3,
            at: now
        ) == nil)
        #expect(Policy.departureActivity(for: pr, ownership: .mine, at: now) == nil)
        #expect(Policy.reviewActivity(
            for: pr,
            ownership: .mine,
            state: .clean,
            at: now,
            announced: true
        ) == nil)
    }

    /// Cizí aktivita je opačný směr, takže brána sedí opačně — a je to jediný druh, u kterého to
    /// tak je.
    @Test("Cizí aktivita se na cizím PR nehlásí")
    func skipsForeignActivityOnTheirs() {
        let activity = ForeignActivity(comments: [comment(body: "cokoli")], reviews: [])

        #expect(Policy.foreignActivityEvent(
            for: pr,
            ownership: .theirs,
            activity: activity,
            at: now,
            announced: true
        ) == nil)
    }

    /// Druh se **neodvozuje z textu** — je to překlad notifikační události, a `newPullRequest`
    /// se dělí podle toho, jestli jsem PR už reviewoval (#137).
    @Test("Druh se překládá z notifikační události")
    func mapsNotificationEventsToKinds() {
        #expect(Policy.activityKind(of: .newPullRequest) == .newPullRequest)
        #expect(Policy.activityKind(of: .newPullRequest, isReReview: true) == .reReview)
        #expect(Policy.activityKind(of: .findings) == .findings)
        #expect(Policy.activityKind(of: .clean) == .clean)
        #expect(Policy.activityKind(of: .failure) == .failure)
        #expect(Policy.activityKind(of: .activity) == .foreignActivity)
    }
}

// MARK: - Kresba řádku

extension ActivityFeedTests {
    /// Každý druh **někam vede** a jediný vede ven: novinka, která nikam nevede, je nakreslená
    /// chyba (poznámka 91 v návrhu).
    @Test("Každý druh má cíl a jediný vede na GitHub")
    func everyKindLeadsSomewhere() {
        var external = 0
        for kind in ActivityEvent.Kind.allCases {
            if Policy.destination(of: kind) == .gitHub { external += 1 }
        }
        #expect(external == 1)
        #expect(Policy.destination(of: .leftQueue) == .gitHub)
        #expect(Policy.destination(of: .findings) == .tab(.findings))
        #expect(Policy.destination(of: .foreignActivity) == .tab(.conversation))
        #expect(Policy.destination(of: .staleFindings) == .tab(.commits))
        #expect(Policy.destination(of: .clean) == .tab(.progress))
        #expect(Policy.destination(of: .failure) == .tab(.progress))
        #expect(Policy.destination(of: .newPullRequest) == .tab(.overview))
        #expect(Policy.destination(of: .reReview) == .tab(.overview))
    }

    /// `čisté review` a `review se nepovedlo` se nesmí slít ani barvou puntíku — je to tentýž
    /// pár jako všude jinde v okně.
    @Test("Barva puntíku odděluje klid od poruchy")
    func tonesTellCalmFromFailure() {
        #expect(Policy.tone(of: .clean) == .ok)
        #expect(Policy.tone(of: .failure) == .critical)
        #expect(Policy.tone(of: .findings) == .critical)
        #expect(Policy.tone(of: .staleFindings) == .stale)
        #expect(Policy.tone(of: .leftQueue) == .neutral)
        #expect(Policy.tone(of: .newPullRequest) == .accent)
    }

    @Test("Každý druh má vlastní glyf")
    func everyKindHasASymbol() {
        let symbols = ActivityEvent.Kind.allCases.map { Policy.symbol(of: $0) }

        #expect(symbols.allSatisfy { !$0.isEmpty })
        // Dva druhy se stejným glyfem by na ose byly k nerozeznání.
        #expect(Set(symbols).count == ActivityEvent.Kind.allCases.count)
    }

    /// **Chip `bez banneru` se nesmí objevit u druhu, za který banner nechodí nikdy.** Tvrdil by,
    /// že něco nedorazilo, přitom to nemělo — a tím by z půlky hodnoty téhle obrazovky udělal šum.
    @Test("Chip bez banneru dostanou jen druhy, které banner umí")
    func silentChipOnlyWhereABannerIsPossible() {
        for kind in ActivityEvent.Kind.allCases {
            let computed = kind == .staleFindings || kind == .leftQueue
            #expect(Policy.showsSilentChip(kind, announced: false) == !computed)
            // Doručený banner chip nedostane nikdy — o tom, že nepřišel, není co říct.
            #expect(!Policy.showsSilentChip(kind, announced: true))
        }
    }
}

// MARK: - Skládání textu

extension ActivityFeedTests {
    /// Titulek PR patří do **detailu**, ne do headline: banner ho v titulku nese jen proto, že
    /// v něm není kde napsat identifikaci PR — v řádku se PR kreslí samostatně.
    @Test("Nový PR: titulek jde do detailu, headline je krátký")
    func newPullRequestRow() {
        let event = Policy.newPullRequestActivity(
            for: pr,
            title: "chore: modernize dependencies",
            at: now,
            announced: true
        )

        #expect(event?.kind == .newPullRequest)
        #expect(event?.headline == "Nový PR k review")
        #expect(event?.detail == "chore: modernize dependencies")
        #expect(event?.wasAnnounced == true)
    }

    @Test("Re-review má vlastní headline i druh")
    func reReviewRow() {
        let event = Policy.newPullRequestActivity(
            for: pr,
            title: "cokoli",
            isReReview: true,
            at: now,
            announced: false
        )

        #expect(event?.kind == .reReview)
        #expect(event?.headline == "Znovu k review")
        #expect(event?.wasAnnounced == false)
    }

    /// Headline je **titulek banneru**, ne druhá tabulka slov — jinak by nad tímtéž během řekly
    /// banner a řádek dvě různé věci.
    @Test("Review s nálezy nese tentýž titulek jako banner")
    func findingsRowMatchesTheBanner() {
        let event = Policy.reviewActivity(
            for: pr,
            state: .completed(findings: 3),
            blocking: 1,
            at: now,
            announced: true
        )

        #expect(event?.kind == .findings)
        #expect(event?.headline == "3 nálezy · 1 blokuje")
    }

    /// U čistého review by detail jen zopakoval titulek („Reviewer nenašel žádný nález“), takže
    /// se zahazuje. U selhání je to naopak jediné, z čeho se pozná, co dělat.
    @Test("Čisté review nemá detail, selhání ho má")
    func dropsTheDetailOnlyWhenItRepeatsTheHeadline() {
        let clean = Policy.reviewActivity(for: pr, state: .clean, at: now, announced: true)
        let failed = Policy.reviewActivity(
            for: pr,
            state: .failed(detail: "session skončila s kódem 1"),
            at: now,
            announced: true
        )

        #expect(clean?.headline == "Čisté review")
        #expect(clean?.detail == nil)
        #expect(failed?.kind == .failure)
        #expect(failed?.detail == "session skončila s kódem 1")
    }

    /// Stavy, které nejsou konec běhu, se do dění nedostanou — je to tatáž množina jako u banneru,
    /// protože se řádek skládá z `Policy.reviewNotification`.
    @Test("Rozdělané review a zastaralý záznam řádek nedostanou")
    func skipsStatesThatAreNotAnEnding() {
        let states: [ReviewState] = [
            .notStarted, .queued, .cloning, .running(finished: 1, total: 3), .stale
        ]
        for state in states {
            #expect(Policy.reviewActivity(for: pr, state: state, at: now, announced: true) == nil)
        }
    }

    /// V seznamu je věta to, podle čeho se řádek pozná — kdežto banner se čte odshora a nahoru
    /// patří počet. Proto jsou proti banneru **obrácené**.
    @Test("Cizí aktivita: věta je headline, počet detail")
    func foreignActivityRow() {
        let activity = ForeignActivity(
            comments: [
                comment(body: "opravdu to potřebuje ten mutex?"),
                comment(body: "a ještě jedna věc", id: "c2")
            ],
            reviews: []
        )

        let event = Policy.foreignActivityEvent(for: pr, activity: activity, at: now, announced: true)

        #expect(event?.kind == .foreignActivity)
        #expect(event?.headline == "odinuv: a ještě jedna věc")
        #expect(event?.detail == "2 nové komentáře")
    }

    /// Jedna položka detail nedostane: „odinuv: …“ a za tím „1 nový komentář“ je totéž dvakrát.
    @Test("Jediný komentář nemá počet v detailu")
    func skipsTheCountForASingleItem() {
        let activity = ForeignActivity(comments: [comment(body: "jedna věta")], reviews: [])

        let event = Policy.foreignActivityEvent(for: pr, activity: activity, at: now, announced: false)

        #expect(event?.headline == "odinuv: jedna věta")
        #expect(event?.detail == nil)
    }

    /// Skloňuje se **sloveso zvlášť** (`Plural.word`), jako u blokujících nálezů: „přišly 1 commit“
    /// je ta třída chyby, kterou u #131 našel Copilot.
    @Test("Zastaralé nálezy skloňují commity i sloveso")
    func staleFindingsRow() {
        #expect(row(commits: 1)?.detail == "přišel 1 commit, hlava je teď")
        #expect(row(commits: 3)?.detail == "přišly 3 commity, hlava je teď")
        #expect(row(commits: 5)?.detail == "přišlo 5 commitů, hlava je teď")
        // Neznámý počet (force-push) o commitech **nemluví** — vymyslet číslo je horší.
        #expect(row(commits: nil)?.detail == "hlava je teď")
        #expect(row(commits: 0)?.detail == "hlava je teď")
        #expect(row(commits: 3)?.head == "9c1f0ab")
        #expect(row(commits: 3)?.headline == "Nálezy zastaraly")
    }

    /// Identita nese **hlavu, ne okamžik**: rozchodu si aplikace všimne při každém dotažení
    /// detailu, a druhý řádek o téže věci by byl šum.
    @Test("Zastaralé nálezy jsou klíčované hlavou, ne časem")
    func staleFindingsAreKeyedByHead() {
        let first = row(commits: 3, at: now)
        let later = row(commits: 3, at: now.addingTimeInterval(3600))
        let moved = Policy.staleFindingsActivity(for: pr, head: "aa11bb2", commits: 1, at: now)

        #expect(first?.id == later?.id)
        #expect(first?.id != moved?.id)
    }

    @Test("Odchod z fronty netvrdí, proč PR odešel")
    func departureRow() {
        let event = Policy.departureActivity(for: pr, at: now)

        #expect(event?.kind == .leftQueue)
        #expect(event?.headline == "Už není ve frontě")
        #expect(event?.detail == "mergnuto, nebo zrušený request — z fronty se to nepozná")
        // Banner za to nechodí, takže se ani nemá co tvářit jako nedoručený.
        #expect(event?.wasAnnounced == false)
    }

    @Test("Adresa na GitHubu se skládá z identity, ne ze shrnutí")
    func buildsTheGitHubURLFromTheIdentifier() {
        #expect(
            Policy.gitHubURL(of: pr)?.absoluteString == "https://github.com/keboola/vault/pull/85"
        )
    }

    private func row(commits: Int?, at date: Date? = nil) -> ActivityEvent? {
        Policy.staleFindingsActivity(for: pr, head: "9c1f0ab", commits: commits, at: date ?? now)
    }

    private func comment(body: String, id: String = "c1", author: String = "odinuv") -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: body,
            createdAt: Date(timeIntervalSince1970: id == "c1" ? 1_699_999_000 : 1_699_999_500),
            url: URL(string: "https://github.com/keboola/vault/pull/85#discussion_r1")!
        )
    }
}

// MARK: - Záznam a strop

extension ActivityFeedTests {
    @Test("Záznam je od nejnovějšího")
    func ordersNewestFirst() {
        let log = Policy.activityLog(
            [],
            adding: [event(at: 100), event(.clean, at: 300), event(.leftQueue, at: 200)]
        )

        #expect(log.map(\.kind) == [.clean, .leftQueue, .findings])
    }

    /// **Strop je na položky, ne na dny** a při jeho překročení odcházejí **nejstarší**: dění je
    /// o tom, co jsem prošvihl, a to nejstarší jsem prošvihl nejdřív.
    @Test("Strop odřízne nejstarší, ne nejnovější")
    func dropsTheOldestOverTheLimit() {
        let events = (1...10).map { event(at: TimeInterval($0) * 100) }

        let log = Policy.activityLog([], adding: events, limit: 3)

        #expect(log.count == 3)
        #expect(log.map(\.at) == [1000, 900, 800].map { Date(timeIntervalSince1970: $0) })
    }

    /// Mez je vidět v typu, ne v souboru s daty — cache bez vyjmenované meze je únik paměti
    /// s odkladem (#224).
    @Test("Výchozí strop je 200 položek")
    func theLimitIsTwoHundred() {
        #expect(Policy.activityLimit == 200)

        let log = Policy.activityLog([], adding: (1...250).map { event(at: TimeInterval($0)) })

        #expect(log.count == 200)
    }

    /// Duplicita podle identity: téhož rozchodu hlav si aplikace všimne opakovaně, a druhý řádek
    /// o jedné věci je šum.
    @Test("Položka s touž identitou se nezapíše dvakrát")
    func mergesDuplicates() {
        let stale = Policy.staleFindingsActivity(for: pr, head: "9c1f0ab", commits: 2, at: now)
        let again = Policy.staleFindingsActivity(
            for: pr,
            head: "9c1f0ab",
            commits: 2,
            at: now.addingTimeInterval(600)
        )

        let log = Policy.activityLog([stale!], adding: [again!])

        #expect(log.count == 1)
        // Zůstává **ta první**, takže se čas nepřepíše na „všiml jsem si znovu“.
        #expect(log[0].at == now)
    }

    /// Nulový nebo záporný strop znamená prázdno, ne pád — `prefix` by na tom neupadl, ale
    /// tvrzení je o tom, že se z toho nemá stát nekonečno položek.
    @Test("Nulový strop nechá prázdno")
    func anEmptyLimitKeepsNothing() {
        #expect(Policy.activityLog([], adding: [event(at: 100)], limit: 0).isEmpty)
    }
}

// MARK: - Co je nepřečtené

extension ActivityFeedTests {
    /// **Bez značky je nové všechno**, a je to opačná volba než u konverzace: záznam vzniká teprve
    /// za běhu aplikace, takže „nikdy jsem tu nebyl“ znamená, že jsem opravdu nic z toho neviděl.
    @Test("Bez značky je nepřečtené všechno")
    func countsEverythingWithoutAMark() {
        let events = [event(at: 100), event(.clean, at: 200)]

        #expect(Policy.unreadActivity(events, since: nil) == 2)
    }

    @Test("Nepřečtené je to, co přišlo po značce")
    func countsWhatCameAfterTheMark() {
        let events = [event(at: 300), event(.clean, at: 200), event(.leftQueue, at: 100)]

        #expect(Policy.unreadActivity(events, since: Date(timeIntervalSince1970: 200)) == 1)
        #expect(Policy.unreadActivity(events, since: Date(timeIntervalSince1970: 400)) == 0)
    }

    /// Odznak **počítá nepřečtené**, ne celý záznam — a na aktivní položce se nekreslí, protože
    /// by v tomhle railu překryl ikonu (poznámka 95 v návrhu).
    @Test("Odznak: nula a aktivní sekce se nekreslí")
    func theBadgeStaysAwayWhenItHasNothingToSay() {
        #expect(Policy.activityBadge(unread: 4, isActive: false) == 4)
        #expect(Policy.activityBadge(unread: 4, isActive: true) == nil)
        #expect(Policy.activityBadge(unread: 0, isActive: false) == nil)
        #expect(Policy.activityBadge(unread: 0, isActive: true) == nil)
    }
}

// MARK: - Řádky, bloky a pruh návštěvy

extension ActivityFeedTests {
    /// Pruh `Tady jsem skončil` stojí **pod** novinkami, protože se řadí od nejnovějšího (#316).
    @Test("Pruh se kreslí před první už viděnou položkou")
    func marksTheBoundaryBelowTheNewOnes() {
        let events = [event(at: 400), event(.clean, at: 300), event(.leftQueue, at: 200)]

        let days = Policy.activityFeed(
            events,
            since: Date(timeIntervalSince1970: 300),
            now: Date(timeIntervalSince1970: 500)
        )
        let rows = days.flatMap(\.rows)

        #expect(rows.map(\.isFirstSeen) == [false, true, false])
    }

    /// Pruh úplně nahoře by říkal „všechno pod tebou znáš“, tedy nic — a bez značky nedává smysl
    /// vůbec, protože tehdy je nové všechno.
    @Test("Bez novinek se pruh nekreslí")
    func drawsNoMarkerWithoutAnythingNew() {
        let events = [event(at: 400), event(.clean, at: 300)]

        let seen = Policy.activityFeed(
            events,
            since: Date(timeIntervalSince1970: 500),
            now: Date(timeIntervalSince1970: 600)
        )
        let never = Policy.activityFeed(events, since: nil, now: Date(timeIntervalSince1970: 600))

        #expect(seen.flatMap(\.rows).allSatisfy { !$0.isFirstSeen })
        #expect(never.flatMap(\.rows).allSatisfy { !$0.isFirstSeen })
    }

    /// Identita řádku je **uložená hodnota**, ne keypath přes tuple (#361): líný seznam se na ni
    /// ptá při každém přerovnání obsahu.
    @Test("Řádek nese identitu položky")
    func rowsCarryTheEventIdentity() {
        let one = event(at: 400)

        let rows = Policy.activityFeed([one], now: Date(timeIntervalSince1970: 500)).flatMap(\.rows)

        #expect(rows.map(\.id) == [one.id])
    }

    @Test("Dnešek a včerejšek mají vlastní nadpis, starší datum")
    func namesTheDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        let noon = Date(timeIntervalSince1970: 1_700_000_000)

        let days = Policy.activityFeed(
            [
                event(at: noon.timeIntervalSince1970),
                event(.clean, at: noon.timeIntervalSince1970 - 86_400),
                event(.leftQueue, at: noon.timeIntervalSince1970 - 3 * 86_400)
            ],
            since: noon,
            now: noon,
            calendar: calendar
        )

        #expect(days.count == 3)
        #expect(days[0].title == "Dnes")
        #expect(days[1].title == "Včera")
        // Starší den nese datum v titulku, takže mu za tečkou nic nezbývá.
        #expect(days[2].title != "Dnes" && days[2].title != "Včera")
        #expect(days[2].note == nil)
    }

    /// Počet nepřečtených patří do **nadpisu bloku**, protože na aktivní položce railu se odznak
    /// nekreslí — a je to počet **za ten den**, ne za celý záznam.
    @Test("Nadpis bloku nese počet nepřečtených toho dne")
    func countsUnreadPerDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        let noon = Date(timeIntervalSince1970: 1_700_000_000)

        let days = Policy.activityFeed(
            [
                event(at: noon.timeIntervalSince1970),
                event(.clean, at: noon.timeIntervalSince1970 - 60),
                event(.leftQueue, at: noon.timeIntervalSince1970 - 86_400)
            ],
            since: noon.addingTimeInterval(-120),
            now: noon,
            calendar: calendar
        )

        #expect(days[0].note == "2 nové")
        // Včerejší blok nepřečtené nemá, takže mu za tečkou zbývá datum.
        #expect(days[1].note != nil)
        #expect(days[1].note != "1 nová")
    }

    /// Relativní čas má hodnotu jen u toho, co se stalo teď; blok už den nese v nadpisu, takže
    /// `před 14 hodinami` je nad hlavičkou `Dnes` horší než `v 07:58`.
    @Test("Starší než dvě hodiny se píše hodinami")
    func switchesFromRelativeToClock() {
        #expect(Policy.showsRelativeTime(of: now.addingTimeInterval(-120), now: now))
        #expect(Policy.showsRelativeTime(of: now.addingTimeInterval(-7100), now: now))
        #expect(!Policy.showsRelativeTime(of: now.addingTimeInterval(-7300), now: now))
    }

    @Test("Věta v hlavičce mluví o značce, když žádná není")
    func explainsAMissingMark() {
        let never = Policy.activityHeaderSentence(lastVisit: nil, hasEvents: true, now: now)
        let empty = Policy.activityHeaderSentence(lastVisit: nil, hasEvents: false, now: now)
        let visited = Policy.activityHeaderSentence(lastVisit: now, hasEvents: true, now: now)

        #expect(never.contains("nové všechno"))
        // Nad prázdným seznamem není o čem tvrdit, že je nové — o tom mluví prázdný stav.
        #expect(!empty.contains("nové všechno"))
        #expect(!visited.contains("nové všechno"))
        #expect(visited.contains("Naposledy jsem tu byl"))
    }

    /// Den se dopisuje, jen když **není dnešní**: `v 08:12` u značky staré tři dny je ta chyba,
    /// kterou nikdo nepozná — a zrovna tady na tom záleží, protože pruh dělí seznam.
    @Test("Popisek návštěvy dopisuje den, jen když není dnešní")
    func labelsTheVisitDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!

        let today = Policy.visitLabel(now, now: now, calendar: calendar)
        let yesterday = Policy.visitLabel(now.addingTimeInterval(-86_400), now: now, calendar: calendar)
        let older = Policy.visitLabel(now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar)

        #expect(today.hasPrefix("v "))
        #expect(yesterday.hasPrefix("včera v "))
        #expect(!older.hasPrefix("v ") && !older.hasPrefix("včera"))
        // Hodiny jsou u všech tří — pruh bez nich by neřekl, odkud dolů je viděné.
        #expect(today.contains(":") && yesterday.contains(":") && older.contains(":"))
    }

    /// Autor jde do řádku jen u příchodu do fronty (návrh, sekce 27) — u výsledku review o té
    /// události neříká nic.
    @Test("Autor je jen u příchodu do fronty")
    func carriesTheAuthorOnArrivalOnly() {
        let arrival = Policy.newPullRequestActivity(
            for: pr,
            title: "cokoli",
            author: "odinuv",
            at: now,
            announced: true
        )
        let review = Policy.reviewActivity(for: pr, state: .clean, at: now, announced: true)

        #expect(arrival?.author == "odinuv")
        #expect(review?.author == nil)
        // Prázdný autor se zahazuje, ať za `owner/repo#85` nezůstane visící tečka.
        #expect(Policy.newPullRequestActivity(
            for: pr,
            title: "cokoli",
            author: "",
            at: now,
            announced: true
        )?.author == nil)
    }
}

// MARK: - Prázdno

extension ActivityFeedTests {
    /// **Tři prázdna, která se nesmí slít**: klid, zakázané oprávnění a vypnutý přepínač se
    /// spravují každé jinde.
    @Test("Prázdný stav rozlišuje klid od mlčící aplikace")
    func tellsCalmFromASilentApp() {
        #expect(Policy.activityEmptyState(
            hasEvents: false,
            notificationsDenied: false,
            notificationsEnabled: true
        ) == .calm)
        #expect(Policy.activityEmptyState(
            hasEvents: false,
            notificationsDenied: false,
            notificationsEnabled: false
        ) == .notificationsOff)
        // Zakázané oprávnění má přednost: je to stav, o kterém člověk nemusí vědět.
        #expect(Policy.activityEmptyState(
            hasEvents: false,
            notificationsDenied: true,
            notificationsEnabled: false
        ) == .notificationsDenied)
        #expect(Policy.activityEmptyState(
            hasEvents: false,
            notificationsDenied: true,
            notificationsEnabled: true
        ) == .notificationsDenied)
    }

    /// Plný seznam prázdný stav nedostane ani tehdy, když notifikace nechodí — o tom mluví
    /// stavový řádek, kdežto tady by to schovalo obsah.
    @Test("Neprázdný seznam prázdný stav nedostane")
    func drawsNoEmptyStateOverContent() {
        #expect(Policy.activityEmptyState(
            hasEvents: true,
            isUnreadable: true,
            notificationsDenied: true,
            notificationsEnabled: false
        ) == nil)
    }

    /// **Nejcennější tvrzení celého prázdna**: rozbitý soubor a prázdný záznam dají obojí prázdný
    /// seznam, takže by nad ztracenou historií stálo klidné „nic se nestalo“ — tedy text, který
    /// tvrdí víc, než data unesou.
    @Test("Ztracený záznam přebije i zakázané notifikace")
    func tellsALostLogFromCalm() {
        #expect(Policy.activityEmptyState(
            hasEvents: false,
            isUnreadable: true,
            notificationsDenied: false,
            notificationsEnabled: true
        ) == .unreadable)
        // Nad rozbitým souborem se o notifikacích nedá tvrdit nic — prázdno není jejich vina.
        #expect(Policy.activityEmptyState(
            hasEvents: false,
            isUnreadable: true,
            notificationsDenied: true,
            notificationsEnabled: false
        ) == .unreadable)
    }
}

// MARK: - Commity pod nálezy

extension ActivityFeedTests {
    @Test("Commity po hlavě nálezů se počítají ze seznamu")
    func countsCommitsAfterTheFindingsHead() {
        let commits = ["a1", "b2", "c3", "d4"].map { commit(sha: $0) }

        #expect(Policy.commitsAfter("a1", in: commits) == 3)
        #expect(Policy.commitsAfter("c3", in: commits) == 1)
        #expect(Policy.commitsAfter("d4", in: commits) == 0)
    }

    /// Po force-pushi hlava nálezů v seznamu být nemusí — a číslo dopočítané odjinud by tvrdilo,
    /// co se nestalo.
    @Test("Chybějící sha dá neznámý počet, ne nulu")
    func returnsNilForAMissingSha() {
        #expect(Policy.commitsAfter("zz9", in: [commit(sha: "a1")]) == nil)
        #expect(Policy.commitsAfter("a1", in: []) == nil)
    }

    private func commit(sha: String) -> PullRequestCommit {
        PullRequestCommit(
            sha: sha,
            message: "cokoli",
            authorName: "odinuv",
            authorLogin: nil,
            avatarURL: nil,
            committedAt: nil,
            isMerge: false
        )
    }
}
