import Foundation
import Testing

@testable import PRism

/// Zápis odeslané odpovědi a vyřešení do načtené konverzace (#73).
///
/// Jde o to, aby odeslaná odpověď byla vidět **bez kola po síti** — a aby se přitom
/// nerozbilo, co konverzace tvrdí o zkrácení.
@Suite("Policy — zápis do vlákna")
struct ThreadUpdatePolicyTests {
    private func comment(
        _ id: String,
        author: String = "kolega",
        replyTo: String? = nil
    ) -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: "text \(id)",
            createdAt: Date(timeIntervalSince1970: 100),
            url: URL(string: "https://github.com/o/r/pull/1#discussion_r\(id)")!,
            replyToID: replyTo
        )
    }

    private func thread(
        _ id: String = "PRRT_1",
        isResolved: Bool = false,
        canResolve: Bool = true,
        canUnresolve: Bool = true,
        comments: [ThreadComment]? = nil,
        total: Int? = nil,
        hasNextPage: Bool = false
    ) -> ReviewThread {
        let items = comments ?? [comment("c1")]
        return ReviewThread(
            id: id,
            path: "src/Cart.php",
            line: 5,
            originalLine: 5,
            side: .right,
            isResolved: isResolved,
            isOutdated: false,
            canResolve: canResolve,
            canUnresolve: canUnresolve,
            comments: ConversationPage(
                items: items,
                total: total ?? items.count,
                hasNextPage: hasNextPage
            )
        )
    }

    /// Konverzace **vždycky s jednou událostí**: zápis do ní nesmí osu vyprázdnit, a bez
    /// události v datech by to žádný z testů nepoznal.
    private func conversation(
        _ threads: [ReviewThread],
        comments: [ThreadComment] = [],
        commentsTotal: Int? = nil,
        commentsHaveNextPage: Bool = false
    ) -> Conversation {
        Conversation(
            viewer: "ondrajodas",
            reviews: ConversationPage(items: [], total: 0, hasNextPage: false),
            threads: ConversationPage(items: threads, total: threads.count, hasNextPage: false),
            comments: ConversationPage(
                items: comments,
                total: commentsTotal ?? comments.count,
                hasNextPage: commentsHaveNextPage
            ),
            events: ConversationPage(items: [event], total: 1, hasNextPage: false)
        )
    }

    private var event: TimelineEvent {
        TimelineEvent(
            id: "e1",
            kind: .commit(oid: "aaaa1111", headline: "feat: něco"),
            actor: EventActor(login: "autor", avatarURL: nil, isBot: false),
            at: Date(timeIntervalSince1970: 60)
        )
    }

    // MARK: - Vložení odpovědi

    @Test("Odpověď se vloží na konec svého vlákna")
    func appendsTheReply() throws {
        let original = conversation([thread(), thread("PRRT_2")])

        let updated = try #require(Policy.inserting(
            comment("c2", author: "ondrajodas", replyTo: "c1"),
            intoThread: "PRRT_1",
            of: original
        ))

        let first = try #require(updated.threads.items.first { $0.id == "PRRT_1" })
        #expect(first.comments.items.map(\.id) == ["c1", "c2"])
        // Cizí vlákno zůstane, jak bylo.
        let second = try #require(updated.threads.items.first { $0.id == "PRRT_2" })
        #expect(second.comments.items.map(\.id) == ["c1"])
    }

    /// **`total` roste s komentářem.** Bez toho by `missing` (`total − items.count`) po každé
    /// odpovědi klesl a useknuté vlákno by tvrdilo, že chybí méně — tedy přesně ten směr,
    /// proti kterému `ConversationPage` drží oba signály zkrácení.
    @Test("Vložení nesníží, kolik komentářů chybí")
    func keepsTheShortfallHonest() throws {
        let truncated = thread(comments: [comment("c1")], total: 5, hasNextPage: true)
        let original = conversation([truncated])
        #expect(truncated.comments.missing == 4)

        let updated = try #require(Policy.inserting(comment("c2"), intoThread: "PRRT_1", of: original))

        let after = try #require(updated.threads.items.first)
        #expect(after.comments.total == 6)
        #expect(after.comments.missing == 4)
        #expect(after.comments.isTruncated)
    }

    /// **Osa nesmí zmizet zápisem do vlákna** (regrese opravená u #216). `Conversation.init`
    /// má `events` s výchozí prázdnou hodnotou kvůli odpovědím z doby před #171, takže je při
    /// přeskládání konverzace lze vynechat bez chyby překladu — a osa se pak po odeslané
    /// odpovědi tiše vyprázdnila o commity, pushe a vyžádaná review.
    @Test("Zápis do vlákna nechá události na ose")
    func keepsEventsWhenWritingToAThread() throws {
        let original = conversation([thread()])

        let replied = try #require(Policy.inserting(comment("c2"), intoThread: "PRRT_1", of: original))
        let resolved = try #require(Policy.applying(
            ThreadResolution(threadID: "PRRT_1", isResolved: true, canResolve: false, canUnresolve: true),
            to: original
        ))

        #expect(replied.events.items.map(\.id) == ["e1"])
        #expect(resolved.events.items.map(\.id) == ["e1"])
    }

    // MARK: - Komentář pod PR (#216)

    @Test("Komentář se připíše na konec diskuze")
    func appendsThePullRequestComment() throws {
        let original = conversation([thread()], comments: [comment("ic1")])

        let updated = Policy.appending(comment("ic2", author: "ondrajodas"), to: original)

        #expect(updated.comments.items.map(\.id) == ["ic1", "ic2"])
        // Vlákna a osa zůstanou, jak byly — komentář pod PR s nimi nesouvisí.
        #expect(updated.threads.items.map(\.id) == ["PRRT_1"])
        #expect(updated.events.items.map(\.id) == ["e1"])
    }

    /// Tatáž past jako u odpovědi: bez zvýšeného `total` by zkrácená konverzace po každém
    /// odeslaném komentáři tvrdila, že chybí méně, než chybí.
    @Test("Připsání komentáře nesníží, kolik jich chybí")
    func keepsTheCommentShortfallHonest() throws {
        let original = conversation(
            [],
            comments: [comment("ic1")],
            commentsTotal: 5,
            commentsHaveNextPage: true
        )
        #expect(original.comments.missing == 4)

        let updated = Policy.appending(comment("ic2"), to: original)

        #expect(updated.comments.total == 6)
        #expect(updated.comments.missing == 4)
        #expect(updated.comments.isTruncated)
    }

    @Test("Nezkrácené vlákno zůstane nezkrácené")
    func staysComplete() throws {
        let original = conversation([thread()])

        let updated = try #require(Policy.inserting(comment("c2"), intoThread: "PRRT_1", of: original))

        let after = try #require(updated.threads.items.first)
        #expect(after.comments.total == 2)
        #expect(after.comments.missing == 0)
        #expect(!after.comments.isTruncated)
    }

    /// `nil`, ne konverzace beze změny: odeslaná odpověď, která není vidět, vypadá jako
    /// neodeslaná — volající na `nil` konverzaci načte znovu.
    @Test("Chybějící vlákno vrátí nil")
    func returnsNilForAMissingThread() {
        let original = conversation([thread()])

        #expect(Policy.inserting(comment("c2"), intoThread: "PRRT_zmizelo", of: original) == nil)
    }

    @Test("Vložení nesahá na review ani na komentáře pod PR")
    func touchesNothingElse() throws {
        let original = conversation([thread()])

        let updated = try #require(Policy.inserting(comment("c2"), intoThread: "PRRT_1", of: original))

        #expect(updated.viewer == original.viewer)
        #expect(updated.reviews == original.reviews)
        #expect(updated.comments == original.comments)
        #expect(updated.threads.total == original.threads.total)
    }

    // MARK: - Vyřešení

    @Test("Vyřešení zapíše stav i přepočítaná práva")
    func writesTheResolution() throws {
        let original = conversation([thread(canResolve: true, canUnresolve: false)])
        let resolution = ThreadResolution(
            threadID: "PRRT_1",
            isResolved: true,
            canResolve: false,
            canUnresolve: true
        )

        let updated = try #require(Policy.applying(resolution, to: original))

        let after = try #require(updated.threads.items.first)
        #expect(after.isResolved)
        #expect(!after.canResolve)
        #expect(after.canUnresolve)
        // A tedy jde otevřít zpátky — na tom stojí, co ukáže tlačítko.
        #expect(after.canToggleResolution)
    }

    @Test("Vyřešení nechá komentáře být")
    func keepsTheComments() throws {
        let original = conversation([thread(comments: [comment("c1"), comment("c2")])])
        let resolution = ThreadResolution(
            threadID: "PRRT_1",
            isResolved: true,
            canResolve: false,
            canUnresolve: true
        )

        let updated = try #require(Policy.applying(resolution, to: original))

        let after = try #require(updated.threads.items.first)
        #expect(after.comments.items.map(\.id) == ["c1", "c2"])
    }

    @Test("Vyřešení chybějícího vlákna vrátí nil")
    func returnsNilWhenResolvingAMissingThread() {
        let original = conversation([thread()])
        let resolution = ThreadResolution(
            threadID: "PRRT_zmizelo",
            isResolved: true,
            canResolve: false,
            canUnresolve: true
        )

        #expect(Policy.applying(resolution, to: original) == nil)
    }

    /// Otevření zpátky je tatáž cesta, jen s obrácenými hodnotami — a nesmí zapomenout, že se
    /// tím právo `canResolve` vrací.
    @Test("Otevření zpátky vrátí právo vyřešit")
    func reopensTheThread() throws {
        let original = conversation([thread(isResolved: true, canResolve: false, canUnresolve: true)])
        let resolution = ThreadResolution(
            threadID: "PRRT_1",
            isResolved: false,
            canResolve: true,
            canUnresolve: false
        )

        let updated = try #require(Policy.applying(resolution, to: original))

        let after = try #require(updated.threads.items.first)
        #expect(!after.isResolved)
        #expect(after.canToggleResolution)
    }
}
