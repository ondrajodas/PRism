import Foundation
import Testing

@testable import PRism

/// Hláška o druhém kole (#523) — banner a řádek v `Dění`.
///
/// Nejcennější tvrzení téhle sady jsou ta, která říkají, že se **nic neohlásí**: na vlastním PR,
/// bez mého vlákna a po běhu, po kterém se nepohnulo nic. Notifikace za „nic nového“ je první
/// důvod, proč si člověk hlášky vypne — a rozbila by se potichu.
@Suite("Policy — hláška o druhém kole")
struct ReplyRoundNotificationTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "keboola", name: "job-queue"), number: 727)

    private func entry(_ id: String, _ state: Policy.ReviewReplyState) -> Policy.ReviewReplyEntry {
        Policy.ReviewReplyEntry(
            comment: SentComment(threadID: id, path: "Cart.swift", line: 60, body: "nonce"),
            state: state
        )
    }

    private func report(
        fixed: Int,
        answered: Int,
        unanswered: Int
    ) -> Policy.ReviewReplyReport {
        var entries: [Policy.ReviewReplyEntry] = []
        for index in 0..<fixed { entries.append(entry("f\(index)", .fixed(in: "9c1de02"))) }
        for index in 0..<answered { entries.append(entry("a\(index)", .answered)) }
        for index in 0..<unanswered { entries.append(entry("u\(index)", .unanswered(.unchanged))) }
        return .current(Policy.ReviewReplyTally(
            entries: entries,
            fixed: fixed,
            answered: answered,
            unanswered: unanswered,
            missingThreads: 0,
            isTruncated: false,
            verdicts: Policy.ReviewReplyVerdicts(
                againstHeadSha: "9c1de02",
                outcome: .finished,
                finishedAt: Date(timeIntervalSince1970: 2_000_000)
            )
        ))
    }

    /// Věta ze zadání #523 doslova: `sykora-ji opravil 3 z 5 … 1 bez odpovědi`. Rozdělená na
    /// titulek a detail, protože banner se čte odshora a na čtvrtém řádku musí zbýt PR (#200).
    @Test("Banner řekne kdo, kolik z kolika a co zbývá")
    func theSentenceFromTheBrief() throws {
        let notification = try #require(Policy.replyRoundNotification(
            for: pr,
            ownership: .theirs,
            author: "sykora-ji",
            report: report(fixed: 3, answered: 1, unanswered: 1)
        ))
        #expect(notification.title == "sykora-ji opravil 3 z 5")
        #expect(notification.body == "1 bez odpovědi\nkeboola/job-queue#727")
        #expect(notification.event == .replies)
    }

    /// **Na vlastním PR se nehlásí nic** — ani banner, ani řádek. „Odpověď na tvoje review“ je
    /// otázka o cizí práci; na vlastním PR by z ní byla hláška o tom, že jsem si odpověděl sám.
    /// Je to tatáž dvojitá kontrola jako u `isReported(_:on:)`.
    @Test("Na vlastním PR se nehlásí nic")
    func nothingOnMyOwnPullRequest() {
        #expect(Policy.replyRoundNotification(
            for: pr,
            ownership: .mine,
            author: "ondrajodas",
            report: report(fixed: 3, answered: 0, unanswered: 0)
        ) == nil)
        #expect(Policy.replyRoundActivity(
            for: pr,
            ownership: .mine,
            author: "ondrajodas",
            report: report(fixed: 3, answered: 0, unanswered: 0),
            at: Date(timeIntervalSince1970: 3_000_000),
            announced: true
        ) == nil)
        #expect(Policy.isReported(.replyRound, on: .mine) == false)
        #expect(Policy.isReported(.replyRound, on: .theirs))
    }

    /// **Nic se nepohnulo = nehlásí se.** Běh, po kterém zůstalo všech pět komentářů bez
    /// odpovědi, je zpráva „nic nového“ — a ta nemá vyrušit ani zabrat řádek v `Dění`.
    @Test("Bez jediné opravy a odpovědi se nehlásí nic")
    func silenceWhenNothingMoved() {
        #expect(Policy.replyRoundNotification(
            for: pr,
            ownership: .theirs,
            author: "sykora-ji",
            report: report(fixed: 0, answered: 0, unanswered: 5)
        ) == nil)
        #expect(Policy.replyRoundActivity(
            for: pr,
            ownership: .theirs,
            author: "sykora-ji",
            report: report(fixed: 0, answered: 0, unanswered: 5),
            at: Date(timeIntervalSince1970: 3_000_000),
            announced: false
        ) == nil)
    }

    /// Bez jediného mého vlákna není o čem mluvit — a nenačtená konverzace je totéž prázdno
    /// z jiného důvodu (#522: `unknown` není „žádné nemám“).
    @Test("Bez mého vlákna a bez konverzace se nehlásí nic")
    func silenceWithoutMyThreads() {
        let empty = Policy.ReviewReplyReport.current(Policy.ReviewReplyTally(
            entries: [],
            fixed: 0,
            answered: 0,
            unanswered: 0,
            missingThreads: 0,
            isTruncated: false,
            verdicts: nil
        ))
        for report in [empty, .unknown] {
            #expect(Policy.replyRoundNotification(
                for: pr,
                ownership: .theirs,
                author: "sykora-ji",
                report: report
            ) == nil)
        }
    }

    /// **Opravit a odpovědět jsou dvě různé věci** (#522: fakt přebíjí tvrzení), takže se do
    /// jednoho čísla nesčítají — z banneru se musí poznat, jestli číst kód, nebo diskuzi.
    @Test("Samotné odpovědi dostanou vlastní větu")
    func answersGetTheirOwnSentence() throws {
        let notification = try #require(Policy.replyRoundNotification(
            for: pr,
            ownership: .theirs,
            author: "sykora-ji",
            report: report(fixed: 0, answered: 2, unanswered: 1)
        ))
        #expect(notification.title == "sykora-ji odpověděl na 2 z 3")
    }

    /// Neznámý autor nechá větu **bez podmětu** — vymyslet jméno nejde a věta začínající mezerou
    /// vypadá jako uříznutý text.
    @Test("Bez autora zůstane věta bez podmětu")
    func headlineWithoutAnAuthor() {
        let tally = report(fixed: 3, answered: 0, unanswered: 2)
        guard case .current(let counts) = tally else { return }
        #expect(Policy.replyRoundHeadline(author: nil, tally: counts) == "Opraveno 3 z 5")
        #expect(Policy.replyRoundHeadline(author: "", tally: counts) == "Opraveno 3 z 5")
    }

    /// Druhá řádka je **další krok**, nikdy prázdná: banner bez něj je vyrušení bez pointy.
    /// Když nic nezbývá, nese rovnou návrh, který na kartě uvidím.
    @Test("Bez zbytku nese detail rovnou návrh")
    func detailCarriesTheProposal() {
        guard case .current(let done) = report(fixed: 3, answered: 0, unanswered: 0) else { return }
        #expect(Policy.replyRoundDetail(done) == "nic nezbývá · návrh: Schválit")
    }

    /// Řádek v `Dění` nese **týž titulek jako banner** — druhé skládání téhož by se s ním
    /// rozešlo (tatáž úvaha jako u agenta, #511) — a vede na `Přehled`, kde karta stojí.
    @Test("Řádek v Dění nese týž titulek a vede na Přehled")
    func activityRowMatchesTheBanner() throws {
        let event = try #require(Policy.replyRoundActivity(
            for: pr,
            ownership: .theirs,
            author: "sykora-ji",
            report: report(fixed: 3, answered: 1, unanswered: 1),
            at: Date(timeIntervalSince1970: 3_000_000),
            announced: false
        ))
        #expect(event.headline == "sykora-ji opravil 3 z 5")
        #expect(event.detail == "1 bez odpovědi")
        #expect(event.kind == .replyRound)
        #expect(Policy.destination(of: .replyRound) == .tab(.overview))
        // Nedoručený banner se pozná chipem `bez banneru` — tenhle druh banner **umí**.
        #expect(Policy.showsSilentChip(.replyRound, announced: false))
        #expect(Policy.activityKind(of: .replies) == .replyRound)
    }

    /// Přepínač je **vlastní** a nesmí přebít výsledek review na tomtéž PR: že autor opravil tři
    /// body, je jiná zpráva než že náš reviewer něco našel.
    @Test("Vlastní přepínač a vlastní skupina")
    func ownToggleAndGroup() {
        #expect(NotificationSettings().allows(.replies))
        #expect(NotificationSettings(replies: false).allows(.replies) == false)
        // Hlavní vypínač přebíjí i tenhle.
        #expect(NotificationSettings(isEnabled: false).allows(.replies) == false)
        #expect(NotificationEvent.replies.replacementGroup != NotificationEvent.findings.replacementGroup)
        #expect(NotificationEvent.replies.replacementGroup != NotificationEvent.activity.replacementGroup)
    }
}
