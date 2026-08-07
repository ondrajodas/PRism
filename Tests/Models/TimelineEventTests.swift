import Foundation
import Testing

@testable import PRism

/// Model události časové osy (#171).
@Suite("TimelineEvent")
struct TimelineEventTests {
    private let actor = EventActor(
        login: "ondrajodas",
        avatarURL: URL(string: "https://avatars.githubusercontent.com/u/12143866?s=40&v=4"),
        isBot: false
    )

    private func event(_ kind: TimelineEvent.Kind) -> TimelineEvent {
        TimelineEvent(id: "E_1", kind: kind, actor: actor, at: Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// **Každý případ zvlášť.** Asociovaná hodnota se z JSONu ztrácí nejtišeji — u `oid`
    /// commitu by z toho byla událost bez odkazu na kód, která vypadá jako úplná.
    @Test(
        "Round-trip u každého druhu události",
        arguments: [
            TimelineEvent.Kind.commit(oid: "4a7469f0", headline: "feat: change one line"),
            .reviewRequested(reviewer: "ondrajodas"),
            .reviewRequested(reviewer: nil),
            .reviewRequestRemoved(reviewer: "ondrajodas"),
            .forcePushed(before: "b23bc28e", after: "90449b51"),
            .readyForReview,
            .convertedToDraft,
            .merged(into: "main"),
            .closed,
            .reopened,
            .baseChanged(from: "main", to: "develop"),
        ]
    )
    func survivesTheRoundTrip(kind: TimelineEvent.Kind) throws {
        let value = event(kind)

        #expect(try roundTrip(value) == value)
    }

    @Test("Round-trip nese i bota a chybějícího aktéra")
    func survivesTheRoundTripWithoutAnActor() throws {
        let bot = TimelineEvent(
            id: "E_2",
            kind: .reviewRequested(reviewer: "copilot-pull-request-reviewer"),
            actor: EventActor(login: "github-actions", avatarURL: nil, isBot: true),
            at: nil
        )
        let nobody = TimelineEvent(id: "E_3", kind: .closed, actor: nil, at: nil)

        #expect(try roundTrip(bot) == bot)
        #expect(try roundTrip(nobody) == nobody)
    }

    /// Vyžádání review od sebe sama GitHub píše jako „self-requested a review“, takže se to
    /// musí dát poznat — a pozná se to **z modelu**, ne z textu ve view.
    @Test("Vyžádání review od sebe sama je poznat")
    func tellsSelfRequestedApart() {
        #expect(event(.reviewRequested(reviewer: "ondrajodas")).isSelfDirected)
        #expect(event(.reviewRequestRemoved(reviewer: "ondrajodas")).isSelfDirected)
        #expect(!event(.reviewRequested(reviewer: "janvanicek")).isSelfDirected)
        // Bez aktéra ani bez cíle se to tvrdit nedá.
        #expect(!event(.reviewRequested(reviewer: nil)).isSelfDirected)
        #expect(!event(.closed).isSelfDirected)
    }
}

/// Stránka, u které se **celkový počet nedá zjistit** (#171).
@Suite("ConversationPage bez celkového počtu")
struct ConversationPageWithoutTotalTests {
    /// `timelineItems` s `itemTypes` vrací `totalCount` **bez filtru** — změřeno na
    /// `cli/cli#13084`: 49 proti 22 skutečným uzlům. Kdyby se ten počet vzal jako celek,
    /// hlásila by konverzace „chybí 27“ na PR, kde nechybí nic.
    @Test("Nedostupný celkový počet nehlásí, že něco chybí")
    func doesNotClaimAnythingIsMissing() {
        let page = ConversationPage(items: ["a", "b"], hasNextPage: false)

        #expect(page.total == 2)
        #expect(page.missing == 0)
        #expect(!page.isTruncated)
    }

    /// `hasNextPage` je jediný signál, který zůstal — a pořád ukazuje tím nebezpečným
    /// směrem správně.
    @Test("Další stránka je pořád zkrácení")
    func stillReportsTheNextPage() {
        let page = ConversationPage(items: ["a"], hasNextPage: true)

        #expect(page.isTruncated)
    }
}
