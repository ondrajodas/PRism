import Foundation
import Testing

@testable import PRism

/// Co udělat s klikem na notifikaci (#409).
///
/// Vyčerpává se výčtem, protože je to čistá funkce: PR je / není v seznamu × je / není vidět po
/// filtru × seznam se načetl / nenačetl. **Nejcennější je tvrzení, že se nic nestane** — klik na PR,
/// který ze seznamu zmizel, se nesmí otevřít naslepo, a to je zrovna ten případ, který se rozbije
/// potichu: záložka s prázdným obsahem vypadá jako rozbitá aplikace, ne jako mergnutý PR.
@Suite("Klik na notifikaci (#409)")
struct NotificationClickTests {
    private let pr = PRIdentifier("cli/cli#42")!
    private let other = PRIdentifier("cli/cli#7")!

    private func summary(_ id: PRIdentifier, author: String = "kdosi") -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: "titulek",
            author: author,
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    // MARK: - PR v seznamu se otevře

    @Test("PR ze seznamu se otevře a filtru se to netýká")
    func opensAListedPullRequest() {
        let listed = [summary(pr), summary(other)]

        let click = Policy.notificationClick(on: pr, listed: listed, visible: listed, status: .upToDate)

        #expect(click == .open(clearsFilter: false))
    }

    /// Klik na notifikaci je výslovná žádost tenhle PR vidět, takže filtr (#117) ustoupí. Mlčet by
    /// bylo nejhorší z možností a otevřít ho a filtr nechat je horší než ho zrušit: PR by byl
    /// v okně otevřený, ale v seznamu pod ním by nebyl — a že filtr zmizel, je v liště vidět.
    @Test("PR schovaný filtrem filtr zruší")
    func clearsTheFilterThatHidesIt() {
        let click = Policy.notificationClick(
            on: pr,
            listed: [summary(pr), summary(other)],
            visible: [summary(other)],
            status: .upToDate
        )

        #expect(click == .open(clearsFilter: true))
    }

    /// Rozhoduje **filtr, ne rozřazení podle autora** (#331, #332): vlastní PR je pořád PR, který se
    /// dá otevřít, takže se klik na něj nesmí zahodit ani u něj rušit filtr, který nic neschoval.
    /// Notifikace o cizí aktivitě na vlastním PR (#335) je zrovna ta, která tady může přijít.
    @Test("Vlastní PR se otevře jako každý jiný")
    func opensAnOwnPullRequest() {
        let listed = [summary(pr, author: "ondrajodas")]

        let click = Policy.notificationClick(on: pr, listed: listed, visible: listed, status: .upToDate)

        #expect(click == .open(clearsFilter: false))
    }

    // MARK: - PR mimo seznam se neotevírá naslepo

    @Test("PR, který ze seznamu zmizel, se neotevírá")
    func ignoresAPullRequestThatIsGone() {
        // Notifikace přežije tik, který PR odklidil (mergnul se, review už po mně nikdo nechce).
        let click = Policy.notificationClick(
            on: pr,
            listed: [summary(other)],
            visible: [summary(other)],
            status: .upToDate
        )

        #expect(click == .ignore)
    }

    /// Selhaný tik na tom nic nemění: seznam **jednou dorazil**, takže o tom, co v něm je, něco
    /// víme — a to je celý rozdíl proti `notStarted` níž.
    @Test("Chybující polling z chybějícího PR nedělá otevření")
    func ignoresItEvenWhenPollingFails() {
        let failing = PollStatus.failing(since: Date(timeIntervalSince1970: 100), reason: .notAuthenticated)

        let click = Policy.notificationClick(on: pr, listed: [], visible: [], status: failing)

        #expect(click == .ignore)
    }

    // MARK: - Dokud se seznam nenačetl, klik se drží

    /// Ten případ, kvůli kterému má proud kliknutí buffer: aplikaci spustilo právě tohle kliknutí,
    /// takže polling ještě neproběhl. Prázdný seznam neznamená „PR je zavřený“, ale „ještě nevím“ —
    /// a zahodit klik tady by rozbilo celý ten scénář.
    @Test("Klik před prvním tikem PR otevře, i když je seznam prázdný")
    func opensBeforeTheFirstTick() {
        let click = Policy.notificationClick(on: pr, listed: [], visible: [], status: .notStarted)

        #expect(click == .open(clearsFilter: false))
    }

    /// Filtr se u nenačteného seznamu **neruší**: schovat může jedině řádek, který dorazil, takže
    /// zrušený filtr by tady byl zásah do pohledu za nic.
    @Test("Nenačtený seznam filtr neruší")
    func doesNotClearTheFilterBeforeTheFirstTick() {
        let click = Policy.notificationClick(on: pr, listed: [], visible: [], status: .notStarted)

        #expect(click == .open(clearsFilter: false))
        // A totéž tvrzení z druhé strany: `clearsFilter` je `true` jedině u PR, který v seznamu je.
        #expect(
            Policy.notificationClick(
                on: pr,
                listed: [summary(pr)],
                visible: [],
                status: .notStarted
            ) == .open(clearsFilter: true)
        )
    }
}
