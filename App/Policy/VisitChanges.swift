import Foundation

/// Co se na PR stalo od mojí poslední návštěvy (#173).
///
/// Odpovídá na otázku, kterou se dneska řeší scrollováním PR na GitHubu odshora: **co je tu
/// nového od minule.** Sbírá se ze tří zdrojů, protože „něco se stalo“ neznamená jen commit —
/// cizí review a komentář mění, co mám dělat, stejně jako push.
struct VisitChanges: Hashable, Sendable {
    /// Pushnuté commity, od nejstaršího.
    let commits: [TimelineEvent]
    /// Přepsaná historie větve. **Vlastní pole, ne položka v `events`**, protože jako jediná
    /// událost má důsledek pro naše data: po ní zastarají nálezy i rozdělané review.
    let forcePushes: [TimelineEvent]
    /// Zbytek časové osy — merge, převedení z draftu, změna base, vyžádané review.
    let events: [TimelineEvent]
    /// Cizí review, které mezitím někdo odeslal.
    let reviews: [SubmittedReview]
    /// Komentáře pod PR i ve vláknech.
    let comments: [ThreadComment]

    static let none = VisitChanges(commits: [], forcePushes: [], events: [], reviews: [], comments: [])

    var isEmpty: Bool {
        commits.isEmpty && forcePushes.isEmpty && events.isEmpty && reviews.isEmpty && comments.isEmpty
    }

    // **`rewroteHistory` tu není** (#226). Rozhodovala se jím barva bloku „od minule“ — modrá,
    // nebo žlutá — a s jednotným okrovým tónem z návrhu ji nečetl nikdo. Že se historie přepsala,
    // se pozná z `forcePushes` tam, kde na tom záleží.
}

extension Policy {
    /// Co přibylo od `date`. `nil` (PR jsem nikdy neviděl) dá **prázdno**, ne celou historii:
    /// „od tvé poslední návštěvy“ nad prvním zobrazením by znamenalo „od začátku věků“.
    ///
    /// Porovnává se **ostře** (`>`), takže návštěva zaznamenaná v tutéž sekundu, kdy něco
    /// přišlo, tu položku nezobrazí dvakrát.
    static func changes(
        in conversation: Conversation?,
        since date: Date?
    ) -> VisitChanges {
        guard let conversation, let date else { return .none }

        // Události **bez data** se zahazují. `nil` znamená „nevíme kdy“ (viz `TimelineEvent.at`)
        // a zařadit je do „od minule“ by tvrdilo něco, co z dat neplyne — tady je opatrný směr
        // vynechat, protože položka navíc říká „přišlo to teď“.
        let fresh = displayableEvents(conversation.events.items)
            .filter { event in event.at.map { $0 > date } ?? false }
            .sorted { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) }

        return VisitChanges(
            commits: fresh.filter(\.isCommit),
            forcePushes: fresh.filter(\.isForcePush),
            events: fresh.filter { !$0.isCommit && !$0.isForcePush },
            // Rozdělané cizí review (`submittedAt == nil`) se nepočítá — na GitHubu ještě
            // odeslané není, takže se o něm nemá co říkat.
            reviews: conversation.reviews.items
                .filter { $0.submittedAt.map { $0 > date } ?? false }
                .sorted { ($0.submittedAt ?? .distantPast) < ($1.submittedAt ?? .distantPast) },
            comments: freshComments(in: conversation, since: date)
        )
    }

    /// Komentáře pod PR i ty ve vláknech — obojí je „někdo mi něco napsal“ a rozdíl mezi nimi
    /// řeší až tab, do kterého se jde. Moje vlastní se **nepočítají**: že jsem něco napsal já,
    /// není novinka.
    private static func freshComments(in conversation: Conversation, since date: Date) -> [ThreadComment] {
        let all = conversation.comments.items + conversation.threads.items.flatMap(\.comments.items)
        return all
            .filter { $0.createdAt > date }
            .filter { !conversation.isMine($0) }
            .sorted { $0.createdAt < $1.createdAt }
    }
}

extension TimelineEvent {
    var isCommit: Bool {
        if case .commit = kind { return true }
        return false
    }

    var isForcePush: Bool {
        if case .forcePushed = kind { return true }
        return false
    }
}
