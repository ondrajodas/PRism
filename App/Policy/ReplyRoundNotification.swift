import Foundation

/// Druhé kolo dá vědět samo (#523) — banner a řádek v `Dění` o tom, co autor s mými komentáři
/// udělal.
///
/// **Vlastní cesta vedle `reviewNotification` i `activityNotification`, ne jejich třetí použití.**
/// První mluví o tom, co našel **náš reviewer**, druhá o tom, že se **na mém PR** někdo ozval;
/// tahle je třetí směr — na **cizím** PR se pohnulo to, na co jsem se ptal já. Má proto vlastní
/// přepínač (`NotificationEvent.replies`) a vlastní `replacementGroup`: že autor opravil tři body,
/// nemá přebít zprávu o doběhlém review a naopak.
///
/// Rozvržení je **titulek → detail → PR** jako u ostatních (#200): banner se čte odshora a dolní
/// řádek se ořízne, takže nahoře stojí to, podle čeho se člověk rozhoduje, jestli jít k počítači.
extension Policy {
    /// Banner o druhém kole. `nil` = nehlásí se.
    ///
    /// **Na vlastním PR nikdy** a **bez jediného mého vlákna taky ne** — obojí je stav, ve kterém
    /// není o čem mluvit. A **nic se nestalo taky nehlásí**: běh, po kterém zůstalo všech pět
    /// komentářů bez odpovědi, je zpráva „nic nového“, tedy ten druh vyrušení, kvůli kterému si
    /// člověk notifikace vypne. Řádek v `Dění` za něj nechodí ze stejného důvodu.
    static func replyRoundNotification(
        for pr: PRIdentifier,
        ownership: PullRequestOwnership,
        author: String?,
        report: ReviewReplyReport
    ) -> PullRequestNotification? {
        guard let tally = reportableReplyTally(report, ownership: ownership) else { return nil }
        guard let title = replyRoundHeadline(author: author, tally: tally) else { return nil }
        return PullRequestNotification(
            pullRequest: pr,
            title: title,
            body: [replyRoundDetail(tally), pr.description].joined(separator: "\n"),
            event: .replies
        )
    }

    /// Řádek v `Dění` o druhém kole. `nil` = nehlásí se.
    ///
    /// **Headline je tentýž text jako titulek banneru**, jako u agenta (#511): pozná se podle něj,
    /// jak to dopadlo, a druhé skládání téhož by se s bannerem rozešlo.
    static func replyRoundActivity(
        for pr: PRIdentifier,
        ownership: PullRequestOwnership,
        author: String?,
        report: ReviewReplyReport,
        at: Date,
        announced: Bool
    ) -> ActivityEvent? {
        guard isReported(.replyRound, on: ownership) else { return nil }
        guard let tally = reportableReplyTally(report, ownership: ownership) else { return nil }
        guard let headline = replyRoundHeadline(author: author, tally: tally) else { return nil }
        return ActivityEvent(
            id: identity(ActivityEvent.Kind.replyRound, pr, at: at),
            kind: .replyRound,
            pullRequest: pr,
            at: at,
            headline: headline,
            detail: replyRoundDetail(tally),
            wasAnnounced: announced
        )
    }

    /// Souhrn, o kterém se **smí** mluvit. `nil` = nehlásí se nic.
    private static func reportableReplyTally(
        _ report: ReviewReplyReport,
        ownership: PullRequestOwnership
    ) -> ReviewReplyTally? {
        guard ownership == .theirs else { return nil }
        guard case .current(let tally) = report, !tally.entries.isEmpty else { return nil }
        return tally
    }

    /// `sykora-ji opravil 3 z 5`. `nil` = nic se nepohnulo, tedy není o čem dát vědět.
    ///
    /// **Dvě věty, ne jedna se sníženým číslem.** Opravit komentář a odpovědět na něj jsou dvě
    /// různé věci (#522: fakt přebíjí tvrzení) a sloučit je do `vyřídil 3 z 5` by znamenalo, že
    /// z banneru nepoznám, jestli mám číst kód, nebo diskuzi.
    ///
    /// Neznámý autor nechá větu **bez podmětu** (`Opraveno 3 z 5`): vymyslet jméno nejde a věta
    /// začínající mezerou vypadá jako uříznutý text.
    static func replyRoundHeadline(author: String?, tally: ReviewReplyTally) -> String? {
        let total = tally.entries.count
        if tally.fixed > 0 {
            guard let author, !author.isEmpty else {
                return "Opraveno \(tally.fixed.formatted()) z \(total.formatted())"
            }
            return "\(author) opravil \(tally.fixed.formatted()) z \(total.formatted())"
        }
        guard tally.answered > 0 else { return nil }
        guard let author, !author.isEmpty else {
            return "Odpovězeno na \(tally.answered.formatted()) z \(total.formatted())"
        }
        return "\(author) odpověděl na \(tally.answered.formatted()) z \(total.formatted())"
    }

    /// Druhá řádka: **co zbývá**, ne účet. Nikdy prázdná — banner bez dalšího kroku je vyrušení
    /// bez pointy.
    static func replyRoundDetail(_ tally: ReviewReplyTally) -> String {
        guard tally.unanswered > 0 else {
            return "nic nezbývá · \(replyProposalLabel(replyProposal(tally)))"
        }
        return "\(tally.unanswered.formatted()) bez odpovědi"
    }
}
