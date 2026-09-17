import Foundation
import Testing

@testable import PRism

/// Vstup pro brief, brána spouštění a podoba bloku (#516).
///
/// **Nejcennější tvrzení téhle sady jsou negativní**: že se do vstupu nedostane cesta na disk ani
/// řádek kódu, že se s vypnutou branou nespustí nic a že automat nespustí nic v režimu
/// `Na požádání`. Rozbijí se potichu — výsledkem porušení není chyba, ale session, která stojí
/// peníze, nebo text, který tvrdí víc, než data unesou.
@Suite("Brief — vstup, brána, blok (#516)")
struct BriefInputTests {
    /// Ukázkové řádky briefu — **pojmenované, ne odstavec** (#516, po proklikání).
    static let sample = [
        BriefLine(part: .added, text: "Doběhlo ti čisté review na ondrajodas/PRism #584."),
        BriefLine(part: .burning, text: "Hoří keboola/job-queue #727 se 4 nálezy."),
        BriefLine(part: .next, text: "Vezmi si ondrajodas/PRism #584."),
    ]

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func summary(
        _ number: Int,
        repo: String = "keboola/job-queue",
        author: String = "sykora-ji",
        title: String = "feat(flow-result): read persisted requested job delay",
        updated: TimeInterval = -3600
    ) -> PullRequestSummary {
        PullRequestSummary(
            id: PRIdentifier(repo: RepoID(repo)!, number: number),
            title: title,
            author: author,
            url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
            updatedAt: now.addingTimeInterval(updated),
            state: .open
        )
    }

    private func entry(
        _ number: Int,
        repo: String = "keboola/job-queue",
        state: ReviewState = .notStarted,
        blocking: Int = 0,
        hasDraft: Bool = false,
        author: String = "sykora-ji"
    ) -> QueueEntry {
        QueueEntry(
            pullRequest: summary(number, repo: repo, author: author),
            state: state,
            row: QueueRow(blocking: blocking),
            hasDraft: hasDraft
        )
    }

    private func board(_ entries: [QueueEntry], activity: [ActivityEvent] = []) -> Board {
        Policy.board(entries: entries, activity: activity)
    }

    private func event(_ headline: String, detail: String? = nil, at offset: TimeInterval) -> ActivityEvent {
        ActivityEvent(
            id: "e-\(offset)",
            kind: .findings,
            pullRequest: PRIdentifier("keboola/job-queue#727")!,
            at: now.addingTimeInterval(offset),
            headline: headline,
            detail: detail
        )
    }
}

// MARK: - Co ve vstupu je

extension BriefInputTests {
    /// Vstup nese **pruhy, počty a řádky** — tedy přesně to, co je na obrazovce.
    @Test("Vstup nese pruhy, počty a řádky desky")
    func carriesTheBoard() {
        let input = Policy.briefInput(
            board: board([
                entry(4, state: .completed(findings: 5), blocking: 5),
                entry(726),
            ]),
            snoozed: 2,
            now: now
        ).text

        #expect(input.contains("na tahu 2"))
        #expect(input.contains("odložených 2"))
        #expect(input.contains("Pruh Rozhodnout (1):"))
        #expect(input.contains("Pruh Přečíst (1):"))
        #expect(input.contains("keboola/job-queue #4"))
        #expect(input.contains("5 nálezů"))
        // **Počet musí být ve vstupu jednoznačný.** `blokuje 5` model přečetl jako počet
        // **reviewerů** a napsal to tak i do briefu (změřeno u #516) — jsou to blokující nálezy.
        #expect(input.contains("z toho 5 blokujících"))
        #expect(!input.contains("blokuje 5"))
    }

    /// **Seznam cílů odkazů vzniká z týchž pruhů jako text** (#516), takže do něj patří právě ty
    /// pull requesty, o kterých se session dozvěděla — nic míň a nic navíc.
    @Test("Materiál nese pull requesty, které do textu doopravdy šly")
    func carriesTheMentionedPullRequests() {
        let material = Policy.briefInput(
            board: board([
                entry(4, state: .completed(findings: 5), blocking: 5),
                entry(584, repo: "ondrajodas/PRism"),
            ]),
            now: now
        )

        #expect(material.mentioned == [
            PRIdentifier("keboola/job-queue#4")!,
            PRIdentifier("ondrajodas/PRism#584")!,
        ])
        for pullRequest in material.mentioned {
            #expect(material.text.contains("\(pullRequest.repo) #\(pullRequest.number)"))
        }
    }

    /// Prázdný pruh se do vstupu **nedostane** — je to tatáž množina, jakou kreslí deska
    /// (`visibleLanes`), takže brief nemluví o pruzích, které na obrazovce nejsou.
    @Test("Prázdné pruhy se do vstupu nepíšou")
    func skipsEmptyLanes() {
        let input = Policy.briefInput(board: board([entry(726)]), now: now).text

        #expect(input.contains("Pruh Přečíst (1):"))
        #expect(!input.contains("Pruh Rozhodnout"))
        #expect(!input.contains("Pruh Čeká na ostatní"))
    }

    /// Dění do vstupu patří — je to druhý blok domova a brief má říct, co se stalo.
    @Test("Dění je ve vstupu i s časem")
    func carriesActivity() {
        let input = Policy.briefInput(
            board: board([entry(726)], activity: [event("Review doběhlo", detail: "1 nález", at: -600)]),
            now: now
        ).text

        #expect(input.contains("Dění (1 nejnovějších):"))
        #expect(input.contains("před 10 min: Review doběhlo — 1 nález"))
    }

    /// Prázdné dění **nedostane ani nadpis**: „Dění (0)“ je hlášení o ničem a brief by o něm psal
    /// větu.
    @Test("Prázdné dění se nepíše vůbec")
    func skipsEmptyActivity() {
        #expect(!Policy.briefInput(board: board([entry(726)]), now: now).text.contains("Dění"))
    }

    /// Nad tímtéž stavem vyjde **tentýž text**. Bez toho by se nedalo tvrdit, že o obsahu
    /// rozhoduje `Policy` a ne model — a nedal by se testovat výčtem.
    @Test("Stejný stav dá stejný vstup")
    func isDeterministic() {
        let entries = [entry(4, state: .clean), entry(726, hasDraft: true)]
        let first = Policy.briefInput(board: board(entries), snoozed: 1, now: now)
        let second = Policy.briefInput(board: board(entries), snoozed: 1, now: now)

        #expect(first == second)
    }
}

// MARK: - Co ve vstupu NENÍ

extension BriefInputTests {
    /// **Nejdůležitější tvrzení téhle sady.** Session nemá jediný nástroj, takže se o repozitáři
    /// dozví jenom to, co je ve vstupu — a ve vstupu nesmí být cesta na disk, adresa pull requestu
    /// ani kus kódu. Kdyby se to porušilo, nic by nespadlo: brief by jen začal mluvit o kódu, což
    /// je přesně ta hranice, kvůli které je ta session bez nástrojů.
    @Test("Vstup nenese cestu na disk, URL ani kód")
    func carriesNoPathsNoCode() {
        let input = Policy.briefInput(
            board: board(
                [entry(4, state: .checkoutFailed(detail: "/Users/ondra/Library/x nejde"))],
                activity: [event("Review spadlo", at: -60)]
            ),
            now: now
        ).text

        // Cesty a schémata — ani z chybové hlášky, která je v `ReviewState` nese.
        #expect(!input.contains("/Users/"))
        #expect(!input.contains("Library/Application Support"))
        #expect(!input.contains("https://"))
        #expect(!input.contains("file://"))
        // Kód a soubory.
        #expect(!input.contains(".swift"))
        #expect(!input.contains("diff --git"))
        #expect(!input.contains("@@"))
    }

    /// Stav review se do vstupu píše **slovem z výčtu**, ne syntetizovaným popisem případu:
    /// `String(describing:)` by tam pustil jména z kódu a měnil by se s každým přejmenováním.
    @Test("Stav review je slovo, ne jméno případu")
    func describesStatesInWords() {
        let states: [ReviewState] = [
            .notStarted, .queued, .cloning, .checkoutFailed(detail: "x"),
            .running(finished: 1, total: 3), .clean, .completed(findings: 2),
            .dismissed(findings: 1), .inconclusive(reason: .noReport), .failed(detail: "x"),
            .timedOut(findings: 0), .interrupted(findings: 1), .stale,
        ]
        for state in states {
            let text = Policy.briefReviewState(state)
            #expect(!text.isEmpty, "\(state)")
            // Jména z kódu: `completed(findings: 3)` ani `detail:` se do promptu dostat nesmí.
            #expect(!text.contains("findings"), "\(state) → \(text)")
            #expect(!text.contains("detail"), "\(state) → \(text)")
            #expect(!text.contains("reason"), "\(state) → \(text)")
        }
        #expect(Policy.briefReviewState(.running(finished: 1, total: 3)) == "běží (1 z 3)")
        #expect(Policy.briefReviewState(.completed(findings: 1)) == "1 nález")
    }

    /// Stáří je hrubé a **bez locale**, aby tentýž stav nevyšel na každém stroji jinak. Posunuté
    /// hodiny (budoucí datum) jsou `právě teď`, ne záporný čas.
    @Test("Stáří se píše hrubě a nikdy záporně")
    func writesAgeCoarsely() {
        #expect(Policy.briefAge(from: now, to: now) == "právě teď")
        #expect(Policy.briefAge(from: now.addingTimeInterval(600), to: now) == "právě teď")
        #expect(Policy.briefAge(from: now.addingTimeInterval(-90), to: now) == "před 1 min")
        #expect(Policy.briefAge(from: now.addingTimeInterval(-7200), to: now) == "před 2 h")
        #expect(Policy.briefAge(from: now.addingTimeInterval(-172_800), to: now) == "před 2 dny")
    }
}

// MARK: - Kdy se pouští

extension BriefInputTests {
    private func decision(
        mode: BriefMode,
        state: BriefState = .never,
        last: Brief? = nil,
        isLoaded: Bool = true,
        trigger: Policy.BriefTrigger
    ) -> Policy.BriefDecision {
        Policy.brief(
            mode: mode,
            state: state,
            last: last,
            isLoaded: isLoaded,
            now: now,
            trigger: trigger
        )
    }

    /// **Vypnuto znamená, že se nespustí nic** — ani tlačítkem, ani tikem. Je to ta brána, na které
    /// stojí „samo nic nezačne“, a testuje se výčtem obou spouštěčů.
    @Test("Vypnutá brána nepustí ani tlačítko, ani tik")
    func startsNothingWhenOff() {
        #expect(decision(mode: .off, trigger: .button) == .notAllowed)
        #expect(decision(mode: .off, trigger: .tick) == .notAllowed)
    }

    /// **`Na požádání` je požádání, ne automat.** Tik v tomhle režimu nesmí spustit nic — jinak by
    /// se brief skládal každý den, aniž by si o to kdo řekl.
    @Test("Na požádání nespustí tik nic")
    func tickDoesNothingOnDemand() {
        #expect(decision(mode: .onDemand, trigger: .tick) == .notAllowed)
        #expect(decision(mode: .onDemand, trigger: .button) == .start)
    }

    /// Nenačtená fronta: brief by mluvil o datech, která se ještě nestáhla. **Tatáž strana jako
    /// u věty pod pozdravem** — „nic na tahu“ nad prázdným seznamem je ta nebezpečná odpověď.
    @Test("Nenačtená fronta brief nepustí")
    func waitsForTheQueue() {
        #expect(decision(mode: .firstTickOfDay, isLoaded: false, trigger: .tick) == .notLoaded)
        #expect(decision(mode: .onDemand, isLoaded: false, trigger: .button) == .notLoaded)
    }

    /// Běžící session se nespouští podruhé — ani tlačítkem.
    @Test("Běžící brief se nespustí podruhé")
    func refusesWhileRunning() {
        #expect(decision(mode: .onDemand, state: .running, trigger: .button) == .running)
        #expect(decision(mode: .firstTickOfDay, state: .running, trigger: .tick) == .running)
    }

    /// **Jednou za den znamená jednou za den** — a rozhoduje o tom razítko uloženého briefu, ne
    /// paměť. Tlačítko limit nezná: za tím vždycky stojí člověk.
    @Test("Automat shrnuje jednou za den, tlačítko kdykoli")
    func summarizesOncePerDay() {
        let today = Brief(lines: Self.sample, writtenAt: now.addingTimeInterval(-3600), cost: 0.09)
        let yesterday = Brief(lines: Self.sample, writtenAt: now.addingTimeInterval(-90_000), cost: 0.09)

        #expect(decision(mode: .firstTickOfDay, state: .ready(today), last: today, trigger: .tick) == .alreadyToday)
        #expect(decision(mode: .firstTickOfDay, state: .ready(yesterday), last: yesterday, trigger: .tick) == .start)
        #expect(decision(mode: .firstTickOfDay, state: .ready(today), last: today, trigger: .button) == .start)
    }
}

// MARK: - Co je v bloku vidět

extension BriefInputTests {
    /// **Vypnutý brief se nekreslí vůbec**, ne zašedle: vypnutý se nedělá nikdy, takže zašedlé
    /// tlačítko by tvrdilo „tady se to dělá, jen teď ne“.
    @Test("S vypnutou branou se blok nekreslí")
    func drawsNothingWhenOff() {
        for state: BriefState in [.never, .running, .failed(reason: "x")] {
            #expect(Policy.briefBlock(mode: .off, state: state) == nil)
        }
    }

    /// Čtyři stavy, čtyři různé podoby — a **žádná z nich není prázdná**. Prázdný blok je
    /// k nerozeznání od vypnutého, a u spadlé session by to byla lež o tom, že se nic nedělo.
    @Test("Každý stav má vlastní větu a vlastní tlačítko")
    func everyStateSaysSomething() throws {
        let brief = Brief(lines: Self.sample, writtenAt: now, cost: 0.09)

        let never = try #require(Policy.briefBlock(mode: .onDemand, state: .never))
        #expect(never.action == "Shrň")
        guard case .never(let text) = never.body else { Issue.record("čekala se věta"); return }
        #expect(!text.isEmpty)

        let running = try #require(Policy.briefBlock(mode: .onDemand, state: .running))
        // **Tlačítko se nekreslí**: běžící session se nedá spustit podruhé.
        #expect(running.action == nil)
        guard case .running(let note) = running.body else { Issue.record("čekala se věta"); return }
        #expect(!note.isEmpty)

        let ready = try #require(Policy.briefBlock(mode: .firstTickOfDay, state: .ready(brief)))
        #expect(ready.action == "Shrň znovu")
        #expect(ready.body == .text(brief))

        let failed = try #require(
            Policy.briefBlock(mode: .onDemand, state: .failed(reason: "Session skončila chybou."))
        )
        #expect(failed.action == "Zkusit znovu")
        guard case .failed(let headline, let detail) = failed.body else {
            Issue.record("čekaly se dvě věty")
            return
        }
        #expect(headline == "Shrnutí se nepovedlo.")
        #expect(detail == "Session skončila chybou.")
    }

    /// **`nil` cena není nula.** Session, která cenu nenahlásila, peníze stála taky — `0,00 $` by
    /// bylo tvrzení o účtu, které neplatí.
    @Test("Řádek pod textem mlčí o ceně, kterou nikdo nenahlásil")
    func neverClaimsAFreeRun() {
        #expect(
            Policy.briefMeta(at: "21:48", cost: "0,03 $")
                == "shrnuto 21:48 · 0,03 $ · ze stavu aplikace, ne z kódu"
        )
        let unknown = Policy.briefMeta(at: "21:48", cost: nil)
        #expect(unknown == "shrnuto 21:48 · cenu nenahlásilo · ze stavu aplikace, ne z kódu")
        #expect(!unknown.contains("0,00"))
    }
}
