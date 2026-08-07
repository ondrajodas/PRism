import Foundation
import Testing

@testable import PRism

/// Rozhodování nad konverzací — čisté funkce, nic se nemockuje.
@Suite("Policy — konverzace")
struct ConversationPolicyTests {
    private func thread(
        id: String = "t1",
        path: String = "Cart.php",
        line: Int? = 27,
        originalLine: Int? = 27,
        resolved: Bool = false,
        outdated: Bool = false,
        side: DiffSide? = .right
    ) -> ReviewThread {
        ReviewThread(
            id: id,
            path: path,
            line: line,
            originalLine: originalLine,
            side: side,
            isResolved: resolved,
            isOutdated: outdated,
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }

    /// Diff s hunkem, ve kterém jsou nové řádky 25–27 (26 je přidaný, 25 a 27 kontext).
    private func diff(path: String = "Cart.php") throws -> Diff {
        let text = """
        diff --git a/\(path) b/\(path)
        --- a/\(path)
        +++ b/\(path)
        @@ -25,3 +25,3 @@
         kontext
        -staré
        +nové
         další
        """
        return DiffParser.parse(text)
    }

    // MARK: - Rozbalení

    @Test("Nevyřešené vlákno je rozbalené, vyřešené sbalené")
    func usesResolutionAsTheDefault() {
        #expect(Policy.isThreadExpanded(thread(resolved: false), toggled: []))
        #expect(!Policy.isThreadExpanded(thread(resolved: true), toggled: []))
    }

    /// Drží se **odchylka** od výchozího stavu, takže tatáž množina obrací obojí.
    @Test("Překliknutí obrátí výchozí stav v obou směrech")
    func flipsTheDefaultBothWays() {
        #expect(!Policy.isThreadExpanded(thread(resolved: false), toggled: ["t1"]))
        #expect(Policy.isThreadExpanded(thread(resolved: true), toggled: ["t1"]))
    }

    @Test("Cizí vlákno v množině nic nezmění")
    func ignoresOtherThreads() {
        #expect(Policy.isThreadExpanded(thread(id: "t1"), toggled: ["t2", "t3"]))
    }

    // MARK: - Kotvení

    @Test("Vlákno na řádku v hunku má kotvu")
    func anchorsAThreadInsideAHunk() throws {
        let threads = [thread(line: 27)]

        #expect(Policy.threadsInTheDiff(threads, renderedIn: try diff()).count == 1)
        #expect(Policy.threadsOutsideTheDiff(threads, renderedIn: try diff()).isEmpty)
    }

    /// Zastaralé vlákno má `line == nil` a do diffu nepatří: jeho `originalLine` platilo pro
    /// starý head, takže by bublina sedla na cizí kód. Domov má v `Overview` (#72).
    @Test("Zastaralé vlákno kotvu nemá, i když originalLine v diffu je")
    func neverAnchorsAnOutdatedThread() throws {
        let threads = [thread(line: nil, originalLine: 27, outdated: true)]

        #expect(Policy.threadsInTheDiff(threads, renderedIn: try diff()).isEmpty)
        #expect(Policy.threadsOutsideTheDiff(threads, renderedIn: try diff()).count == 1)
    }

    @Test("Vlákno na řádku mimo hunky kotvu nemá")
    func doesNotAnchorOutsideHunks() throws {
        let threads = [thread(line: 500)]

        #expect(Policy.threadsInTheDiff(threads, renderedIn: try diff()).isEmpty)
        #expect(Policy.threadsOutsideTheDiff(threads, renderedIn: try diff()).count == 1)
    }

    @Test("Vlákno k souboru mimo diff kotvu nemá")
    func doesNotAnchorInAnotherFile() throws {
        let threads = [thread(path: "Jinde.php", line: 27)]

        #expect(Policy.threadsInTheDiff(threads, renderedIn: try diff()).isEmpty)
    }

    /// Dokud diff není, nemá se kde kotvit — a vlákna se nesmí ztratit, takže vyjdou jako
    /// „mimo diff“.
    @Test("Bez diffu nemá kotvu nic, ale nic se neztratí")
    func keepsEverythingWithoutADiff() {
        let threads = [thread(line: 27), thread(id: "t2", line: nil, outdated: true)]

        #expect(Policy.threadsInTheDiff(threads, renderedIn: nil).isEmpty)
        #expect(Policy.threadsOutsideTheDiff(threads, renderedIn: nil).count == 2)
    }

    /// Rozdělení musí být úplné — vlákno, které vypadne z obou seznamů, zmizí z okna.
    @Test("Každé vlákno je právě v jednom ze dvou seznamů")
    func splitsExhaustively() throws {
        let threads = [
            thread(id: "a", line: 27),
            thread(id: "b", line: nil, outdated: true),
            thread(id: "c", line: 500),
            thread(id: "d", path: "Jinde.php", line: 27),
        ]
        let diff = try diff()

        let inside = Policy.threadsInTheDiff(threads, renderedIn: diff).map(\.id)
        let outside = Policy.threadsOutsideTheDiff(threads, renderedIn: diff).map(\.id)

        #expect(Set(inside).isDisjoint(with: Set(outside)))
        #expect(Set(inside).union(outside) == ["a", "b", "c", "d"])
    }

    /// `side` rozhoduje, se kterým číslem se porovnává. Bez toho by vlákno na odebraném
    /// řádku vyšlo jako „v diffu“ na základě **nového** čísla, tedy u jiného kódu.
    @Test("Levá strana se porovnává se starým číslem")
    func matchesTheLeftSideByOldNumber() throws {
        let diff = try diff()
        // Starý řádek 26 je ten odebraný; nový 26 je „nové“.
        #expect(Policy.threadsInTheDiff([thread(line: 26, side: .left)], renderedIn: diff).count == 1)
        #expect(Policy.threadsInTheDiff([thread(line: 27, side: .left)], renderedIn: diff).count == 1)
        // Odebraný řádek nové číslo nemá, takže na pravé straně na 26 nic není…
        #expect(Policy.threadsInTheDiff([thread(line: 26, side: .right)], renderedIn: diff).count == 1)
    }

    @Test("Chybějící strana se bere jako pravá")
    func treatsAMissingSideAsRight() throws {
        #expect(Policy.threadsInTheDiff([thread(line: 27, side: nil)], renderedIn: try diff()).count == 1)
    }

    @Test("Kotvení je jedna pravda pro výběr i umístění")
    func sharesOneRuleWithTheRows() throws {
        let file = try #require(try diff().files.first)
        let left = thread(line: 26, side: .left)
        let renderedLine = try #require(file.hunks.first?.lines.first { $0.oldNumber == 26 })

        #expect(Policy.matches(left, renderedLine))
        #expect(Policy.threadsInTheDiff([left], renderedIn: try diff()).count == 1)
    }

    // MARK: - Výběr a pořadí

    @Test("Vlákna se řadí podle řádku, ne podle pořadí v odpovědi")
    func ordersThreadsByLine() throws {
        let file = try #require(try diff().files.first)
        let threads = [thread(id: "c", line: 30), thread(id: "a", line: 26), thread(id: "b", line: 27)]

        #expect(Policy.threads(of: file, from: threads).map(\.id) == ["a", "b", "c"])
    }

    /// Bez druhého kritéria by dvě vlákna na jednom řádku poskakovala mezi překresleními.
    @Test("Při shodě řádku rozhoduje id")
    func breaksTiesByIdentity() throws {
        let file = try #require(try diff().files.first)
        let threads = [thread(id: "b", line: 27), thread(id: "a", line: 27)]

        #expect(Policy.threads(of: file, from: threads).map(\.id) == ["a", "b"])
    }

    /// Přejmenovaný soubor se pozná i pod starou cestou, stejně jako u nálezů.
    @Test("Vlákno se najde i pod starou cestou souboru")
    func matchesTheOldPath() {
        let renamed = DiffParser.parse("""
            diff --git a/Staré.php b/Nové.php
            rename from Staré.php
            rename to Nové.php
            --- a/Staré.php
            +++ b/Nové.php
            @@ -1,2 +1,2 @@
             kontext
            -staré
            +nové
            """)
        guard let file = renamed.files.first else { return }

        #expect(Policy.threads(of: file, from: [thread(path: "Staré.php", line: 2)]).count == 1)
        #expect(Policy.threads(of: file, from: [thread(path: "Nové.php", line: 2)]).count == 1)
    }

    @Test("Vlákna cizího souboru se nepřipletou")
    func ignoresThreadsOfOtherFiles() throws {
        let file = try #require(try diff().files.first)

        #expect(Policy.threads(of: file, from: [thread(path: "Jinde.php")]).isEmpty)
    }

    /// Zastaralé vlákno se z výběru **nevyhazuje** — do bublin se nedostane, ale `Overview`
    /// (#72) ho potřebuje, takže se jen řadí na začátek.
    @Test("Vlákno bez řádku se řadí na začátek, nezmizí")
    func keepsThreadsWithoutALine() throws {
        let file = try #require(try diff().files.first)
        let threads = [thread(id: "s-radkem", line: 27), thread(id: "bez-radku", line: nil)]

        #expect(Policy.threads(of: file, from: threads).map(\.id) == ["bez-radku", "s-radkem"])
    }

    // MARK: - Přehled (#72)

    private func comment(
        id: String = "c1",
        author: String = "kolega",
        body: String = "komentář",
        at seconds: TimeInterval
    ) -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: body,
            createdAt: Date(timeIntervalSince1970: seconds),
            url: URL(string: "https://github.com/cli/cli/pull/1#issuecomment-\(id)")!
        )
    }

    private func review(
        id: String = "r1",
        author: String = "kolega",
        state: SubmittedReview.State? = .approved,
        body: String = "",
        at seconds: TimeInterval? = 100
    ) -> SubmittedReview {
        SubmittedReview(
            id: id,
            author: author,
            state: state,
            body: body,
            submittedAt: seconds.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private func conversation(
        reviews: [SubmittedReview] = [],
        threads: [ReviewThread] = [],
        comments: [ThreadComment] = [],
        events: [TimelineEvent] = []
    ) -> Conversation {
        Conversation(
            viewer: "ja",
            reviews: ConversationPage(items: reviews, total: reviews.count, hasNextPage: false),
            threads: ConversationPage(items: threads, total: threads.count, hasNextPage: false),
            comments: ConversationPage(items: comments, total: comments.count, hasNextPage: false),
            events: ConversationPage(items: events, hasNextPage: false)
        )
    }

    private func event(
        id: String = "e1",
        _ kind: TimelineEvent.Kind,
        by login: String = "kolega",
        at seconds: TimeInterval? = 100
    ) -> TimelineEvent {
        TimelineEvent(
            id: id,
            kind: kind,
            actor: EventActor(login: login, avatarURL: nil, isBot: false),
            at: seconds.map { Date(timeIntervalSince1970: $0) }
        )
    }

    /// Tři různé věci v jednom seznamu, protože se na GitHubu čtou za sebou.
    @Test("Přehled řadí review, komentáře a vlákna podle času")
    func ordersEverythingChronologically() throws {
        let value = conversation(
            reviews: [review(id: "r", body: "koukám na to", at: 200)],
            threads: [thread(id: "t", line: nil)],
            comments: [comment(id: "c", at: 100)]
        )

        let entries = Policy.overview(of: value, renderedIn: try diff())

        #expect(entries.map(\.id) == ["cc", "rr", "tt"], "vlákno bez komentářů datum nemá, jde naspod")
    }

    /// Vlákno **s kotvou** je bublina u kódu, takže se do přehledu nesmí dostat — jinak se
    /// tentýž komentář čte na dvou místech.
    @Test("Vlákno s kotvou v diffu se do přehledu nedostane")
    func skipsAnchoredThreads() throws {
        let value = conversation(threads: [thread(id: "kotva", line: 27)])

        #expect(Policy.overview(of: value, renderedIn: try diff()).isEmpty)
    }

    @Test("Vlákno bez kotvy v přehledu je")
    func keepsUnanchoredThreads() throws {
        let value = conversation(threads: [thread(id: "zastaralé", line: nil, outdated: true)])

        #expect(Policy.overview(of: value, renderedIn: try diff()).map(\.id) == ["tzastaralé"])
    }

    /// Každý řádkový komentář na GitHubu patří do nějakého review, takže u PR s komentáři
    /// u kódu přijdou i review, která nejsou tvrzením — jen obálky. Jako „někdo napsal review:
    /// (nic)“ by z nich byl seznam prázdných položek.
    @Test("Review bez verdiktu a bez prózy se zahodí")
    func dropsEmptyContainerReviews() throws {
        let value = conversation(reviews: [review(id: "obálka", state: .commented, body: "")])

        #expect(Policy.overview(of: value, renderedIn: try diff()).isEmpty)
    }

    /// Schválení bez prózy je plnohodnotný verdikt — čtvrtina vzorku u #63.
    @Test("Schválení s prázdným tělem v přehledu zůstane")
    func keepsAnEmptyApproval() throws {
        let value = conversation(reviews: [review(id: "ok", state: .approved, body: "")])

        #expect(Policy.overview(of: value, renderedIn: try diff()).map(\.id) == ["rok"])
    }

    /// Neznámý stav review (`nil`) konverzaci nepokládá, ale bez prózy taky nic neříká.
    @Test("Neznámý stav review se bez prózy zahodí, s prózou zůstane")
    func handlesAnUnknownReviewState() throws {
        let mute = conversation(reviews: [review(id: "neznámé", state: nil, body: "")])
        let talking = conversation(reviews: [review(id: "neznámé", state: nil, body: "něco")])

        #expect(Policy.overview(of: mute, renderedIn: try diff()).isEmpty)
        #expect(Policy.overview(of: talking, renderedIn: try diff()).map(\.id) == ["rneznámé"])
    }

    /// Rozdělané review na GitHubu odeslané ještě není, takže do historie nepatří — ale
    /// zmizet nesmí: je to důvod, proč odsud nejde poslat naše (422 `one pending review`).
    @Test("Review bez data odeslání jde naspod, ne pryč")
    func sortsUndatedEntriesLast() throws {
        let value = conversation(
            reviews: [review(id: "rozdělané", state: .pending, body: "rozepsané", at: nil)],
            comments: [comment(id: "c", at: 500)]
        )

        #expect(Policy.overview(of: value, renderedIn: try diff()).map(\.id) == ["cc", "rrozdělané"])
    }

    /// Bez diffu se nedá poznat, co má kotvu — a vlákno, které by se nikde neukázalo, je
    /// horší než vlákno v přehledu.
    @Test("Bez načteného diffu jsou v přehledu všechna vlákna")
    func keepsEveryThreadWithoutADiff() {
        let value = conversation(threads: [thread(id: "a", line: 27), thread(id: "b", line: nil)])

        #expect(Policy.overview(of: value, renderedIn: nil).count == 2)
    }

    /// Review a komentář mají vlastní číselné řady, takže shoda `id` mezi nimi je možná —
    /// a v `ForEach` by jedna z položek zmizela.
    @Test("Stejné id u review a komentáře dá dvě položky")
    func keepsItemsWithTheSameRawID() throws {
        let value = conversation(
            reviews: [review(id: "1", body: "review", at: 100)],
            comments: [comment(id: "1", at: 200)]
        )

        let entries = Policy.overview(of: value, renderedIn: try diff())

        #expect(entries.count == 2)
        #expect(Set(entries.map(\.id)).count == 2)
    }

    /// Shodný čas nesmí nechat pořadí na náhodě — dvě položky ve stejné sekundě jsou běžné
    /// (review a jeho komentář).
    @Test("Při shodném čase rozhoduje identita")
    func breaksOverviewTiesByIdentity() throws {
        let value = conversation(comments: [comment(id: "b", at: 100), comment(id: "a", at: 100)])

        #expect(Policy.overview(of: value, renderedIn: try diff()).map(\.id) == ["ca", "cb"])
    }

    // MARK: - Události časové osy (#171)

    /// Události se **prokládají** s komentáři a review, ne aby stály zvlášť: přehled odpovídá
    /// na „co se od minula stalo“ a push mezi dvěma komentáři je půlka té odpovědi.
    @Test("Přehled proloží události komentáři a review")
    func interleavesEventsWithTheConversation() throws {
        let value = conversation(
            reviews: [review(id: "r1", body: "díky", at: 300)],
            comments: [comment(id: "c1", at: 100)],
            events: [
                event(id: "e2", .commit(oid: "abc1234", headline: "fix"), at: 400),
                event(id: "e1", .reviewRequested(reviewer: "ja"), at: 200),
            ]
        )

        #expect(Policy.overview(of: value, renderedIn: try diff()).map(\.id) == ["cc1", "ee1", "rr1", "ee2"])
    }

    /// Mergnutím se PR zavírá, takže GitHub kreslí **jeden** řádek. Dva („mergnul“ a „zavřel“
    /// pár sekund po sobě) by tvrdily, že se staly dvě věci.
    @Test("Zavření po mergi se nekreslí jako druhá událost")
    func hidesTheCloseThatFollowsAMerge() throws {
        let value = conversation(events: [
            event(id: "m", .merged(into: "main"), at: 500),
            event(id: "z", .closed, at: 501),
        ])

        #expect(Policy.overview(of: value, renderedIn: try diff()).map(\.id) == ["em"])
    }

    /// Zavřený **bez** mergnutí je naopak to, co je potřeba vidět — někdo se rozhodl PR
    /// nevzít.
    @Test("Zavření bez mergnutí zůstane")
    func keepsACloseWithoutAMerge() throws {
        let value = conversation(events: [event(id: "z", .closed, at: 500)])

        #expect(Policy.overview(of: value, renderedIn: try diff()).map(\.id) == ["ez"])
    }

    /// Tatáž past jako u review a komentáře: `id` z GitHubu se mezi typy může potkat.
    @Test("Stejné id u události a komentáře dá dvě položky")
    func keepsEventsAndCommentsApart() throws {
        let value = conversation(
            comments: [comment(id: "1", at: 100)],
            events: [event(id: "1", .readyForReview, at: 100)]
        )

        let entries = Policy.overview(of: value, renderedIn: try diff())
        #expect(entries.count == 2)
        #expect(Set(entries.map(\.id)).count == 2)
    }

    /// Odznak u záložky `Přehled` říká, **kolik je toho k přečtení** — a commit ani „vyžádal
    /// review“ text k přečtení není. Bez toho by na PR s dvaceti commity ukazoval třicet, tedy
    /// číslo, ze kterého se nedá poznat, že tam čekají tři komentáře.
    @Test("Do počtu k přečtení se události nepočítají")
    func doesNotCountEventsAsSomethingToRead() throws {
        let value = conversation(
            reviews: [review(id: "r1", body: "díky", at: 300)],
            comments: [comment(id: "c1", at: 100)],
            events: [
                event(id: "e1", .commit(oid: "abc1234", headline: "fix"), at: 200),
                event(id: "e2", .readyForReview, at: 250),
            ]
        )

        let entries = Policy.overview(of: value, renderedIn: try diff())
        #expect(entries.count == 4)
        #expect(entries.count { $0.isReadable } == 2)
    }

    /// Datum u události chybět nemá, ale kdyby chybělo, patří naspod — jako review bez data
    /// odeslání. Pryč ne: událost, o které nevíme kdy, se pořád stala.
    @Test("Událost bez data jde naspod, ne pryč")
    func putsUndatedEventsLast() throws {
        let value = conversation(
            comments: [comment(id: "c1", at: 100)],
            events: [event(id: "e1", .readyForReview, at: nil)]
        )

        #expect(Policy.overview(of: value, renderedIn: try diff()).map(\.id) == ["cc1", "ee1"])
    }
}
