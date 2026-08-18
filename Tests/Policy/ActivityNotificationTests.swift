import Foundation
import Testing

@testable import PRism

/// Notifikace o cizí aktivitě na vlastním PR (#335) — pátá událost, s vlastním textem.
///
/// Testuje se **text i skupina**: text proto, že „2 nové komentáře“ je celý důvod, proč se na
/// notifikaci kouká, a skupina proto, že se rozejde potichu — hláška, která přebije výsledek review,
/// se pozná jedině tím, že něco na obrazovce chybí.
@Suite("Policy.activityNotification — ozval se někdo na mém PR (#335)")
struct ActivityNotificationTests {
    private let pr = PRIdentifier("keboola/app-project-restore#91")!

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    private func comment(
        id: String = "c1",
        by author: String = "odinuv",
        body: String = "opravdu to potřebuje ten mutex?",
        at seconds: TimeInterval = 2000
    ) -> ThreadComment {
        ThreadComment(
            id: id,
            author: author,
            body: body,
            createdAt: at(seconds),
            url: URL(string: "https://github.com/keboola/app-project-restore/pull/91#c-\(id)")!
        )
    }

    private func review(
        id: String = "r1",
        by author: String = "Copilot",
        state: SubmittedReview.State? = .changesRequested,
        at seconds: TimeInterval = 2000
    ) -> SubmittedReview {
        SubmittedReview(id: id, author: author, state: state, body: "", submittedAt: at(seconds))
    }

    private func notification(_ activity: ForeignActivity) -> PullRequestNotification? {
        Policy.activityNotification(for: pr, activity: activity)
    }

    /// **Tvrzení, že se nic nestalo**: prázdná aktivita notifikaci nevydá. Bez toho by rozhlídka
    /// posílala banner po každém tiku, na kterém se nic nezměnilo.
    @Test("Prázdná aktivita nedá notifikaci")
    func staysQuietWithoutActivity() {
        #expect(notification(.none) == nil)
        #expect(Policy.activityHeadline(.none) == nil)
    }

    @Test("Titulek nese počet a druh, skloněný")
    func theTitleCarriesTheCountAndKind() {
        #expect(Policy.activityHeadline(ForeignActivity(comments: [comment()], reviews: []))
            == "1 nový komentář")
        #expect(Policy.activityHeadline(
            ForeignActivity(comments: [comment(id: "a"), comment(id: "b")], reviews: [])
        ) == "2 nové komentáře")
        #expect(Policy.activityHeadline(
            ForeignActivity(comments: (1...5).map { comment(id: "c\($0)") }, reviews: [])
        ) == "5 nových komentářů")
        #expect(Policy.activityHeadline(ForeignActivity(comments: [], reviews: [review()]))
            == "1 nové review")
        #expect(Policy.activityHeadline(
            ForeignActivity(comments: [], reviews: [review(id: "a"), review(id: "b")])
        ) == "2 nová review")
    }

    /// U obojího se přídavné jméno v druhé půlce **vynechává**: „nové“ platí pro obojí a dvakrát
    /// v jedné větě se čte jako dvě různá tvrzení.
    @Test("Komentáře a review dohromady dají jednu větu")
    func mergesBothKindsIntoOneSentence() {
        let activity = ForeignActivity(
            comments: [comment(id: "a"), comment(id: "b")],
            reviews: [review()]
        )

        #expect(Policy.activityHeadline(activity) == "2 nové komentáře a 1 review")
    }

    @Test("Tělo nese nejnovější větu a pod ní PR")
    func theBodyCarriesTheNewestLine() {
        // Rozvržení je titulek → detail → PR (#200): banner se čte odshora a čtvrtý řádek se ořízne.
        let activity = ForeignActivity(comments: [comment()], reviews: [])

        #expect(notification(activity)?.body == """
            odinuv: opravdu to potřebuje ten mutex?
            keboola/app-project-restore#91
            """)
    }

    /// Rozhoduje **datum**, ne druh — jinak by u PR, kde kolega odpověděl po Copilotovi, stálo
    /// v banneru starší review a novější odpověď by se nikde neukázala.
    @Test("Do detailu jde ta novější položka, ne komentář vždycky")
    func picksTheNewerItemForTheDetail() {
        let laterReview = ForeignActivity(comments: [comment(at: 2000)], reviews: [review(at: 2500)])
        let laterComment = ForeignActivity(comments: [comment(at: 2500)], reviews: [review(at: 2000)])

        #expect(notification(laterReview)?.body.hasPrefix("Copilot vyžádal změny") == true)
        #expect(notification(laterComment)?.body.hasPrefix("odinuv:") == true)
    }

    @Test("U review nese větu verdikt")
    func theReviewLineCarriesTheVerdict() {
        #expect(notification(ForeignActivity(comments: [], reviews: [review(state: .approved)]))?
            .body.hasPrefix("Copilot schválil") == true)
        #expect(notification(ForeignActivity(comments: [], reviews: [review(state: .commented)]))?
            .body.hasPrefix("Copilot komentoval") == true)
        // „zamítnuté review“ **není sloveso**, takže by věta zněla `Copilot zamítnuté review`.
        #expect(notification(ForeignActivity(comments: [], reviews: [review(state: .dismissed)]))?
            .body.hasPrefix("Copilot napsal review") == true)
        #expect(notification(ForeignActivity(comments: [], reviews: [review(state: nil)]))?
            .body.hasPrefix("Copilot napsal review") == true)
    }

    /// Prázdné tělo (komentář jen s obrázkem) nechá **samotného autora**: visící dvojtečka vypadá
    /// jako uříznutý text.
    @Test("Komentář bez textu nechá jen autora")
    func anEmptyCommentKeepsTheAuthor() {
        let activity = ForeignActivity(comments: [comment(body: "")], reviews: [])

        #expect(notification(activity)?.body == """
            odinuv
            keboola/app-project-restore#91
            """)
    }

    /// Dlouhý komentář se krátí **tímtéž řezem jako nález**: banner má čtyři řádky a na tom čtvrtém
    /// musí zbýt PR. Kdyby se neřezal, macOS by odřízl celý zbytek — tedy i identifikaci.
    @Test("Dlouhý komentář se zkrátí a PR v banneru zůstane")
    func cutsALongCommentSoThePullRequestSurvives() throws {
        let long = String(repeating: "opravdu dlouhá věta ", count: 20)
        let activity = ForeignActivity(comments: [comment(body: long)], reviews: [])
        let body = try #require(notification(activity)?.body)

        #expect(body.contains("keboola/app-project-restore#91"))
        #expect(body.contains("…"))
        // Řádek s komentářem se vejde do meze, se kterou se počítalo u #200 (a tři tečky navíc).
        #expect(TextLines.content(body).first?.count ?? 0 <= Policy.notificationFindingLimit + 1)
    }

    /// Řádkové zlomy z cizího textu se **slévají** — a `CRLF` v komentáři z Windows je pravidlo,
    /// ne výjimka (#292). Jeden `\n` navíc by odsunul PR mimo banner.
    @Test("Zlomy řádků v komentáři se slijí")
    func collapsesLineBreaksInTheComment() {
        let activity = ForeignActivity(
            comments: [comment(body: "první řádek\r\ndruhý řádek")],
            reviews: []
        )

        #expect(notification(activity)?.body == """
            odinuv: první řádek druhý řádek
            keboola/app-project-restore#91
            """)
    }

    /// **Vlastní skupina**, tedy to, co se rozbije potichu: kdyby cizí aktivita spadla do skupiny
    /// `review`, přepsala by na obrazovce viset zůstávající „3 nálezy“ — a naopak.
    @Test("Cizí aktivita nepřebíjí výsledek review")
    func doesNotReplaceTheReviewResult() {
        let activity = ForeignActivity(comments: [comment()], reviews: [])
        let notice = notification(activity)

        #expect(notice?.event == .activity)
        #expect(notice?.event.replacementGroup == "activity")
        #expect(notice?.identifier != PullRequestNotification(
            pullRequest: pr,
            title: "3 nálezy · 1 blokuje",
            body: "",
            event: .findings
        ).identifier)
        // A patří k **tomu PR**, takže ho klik na banner vybere a systém ji zařadí k jeho ostatním.
        #expect(notice?.pullRequest == pr)
        #expect(notice?.threadIdentifier == pr.description)
    }

    /// Přepínač v nastavení je **vlastní** (#86): kdo si vypne hlášky o review, o komentáři kolegy
    /// vědět chce — a naopak.
    @Test("Přepínač je vlastní a výchozí je zapnuto")
    func hasItsOwnSwitch() {
        #expect(NotificationSettings().allows(.activity))
        #expect(!NotificationSettings(activity: false).allows(.activity))
        #expect(NotificationSettings(activity: false).allows(.findings))
        #expect(!NotificationSettings(isEnabled: false).allows(.activity))
    }
}
