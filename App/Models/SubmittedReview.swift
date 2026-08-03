import Foundation

/// Review, které na PR odeslal někdo jiný (nebo já, dřív a ručně).
///
/// **Není to `ReviewState` ani `ReviewVerdict`.** Ty dva popisují naši aplikaci: `ReviewState`
/// stav běhu reviewera v seznamu, `ReviewVerdict` návrh, co s PR udělat. Tohle je cizí
/// hotové rozhodnutí z GitHubu. Proto je stav **vnořený** (`SubmittedReview.State`) — aby
/// se ta tři slova nedala zaměnit ani při doplňování v editoru.
struct SubmittedReview: Hashable, Codable, Sendable {
    let id: String
    let author: String
    /// `nil` = GitHub poslal stav, který neznáme.
    ///
    /// Nehádá se a **nepokládá celou konverzaci** — stejně jako `FindingVerdict`. Kdyby
    /// neznámý stav vyhodil chybu (jak to dělá `PullRequestState`), zmizela by kvůli jedné
    /// nové hodnotě všechna vlákna i komentáře. U stavu PR je přísnost na místě, protože
    /// z něj plyne chování; tady jde o zobrazení cizího názoru.
    let state: State?
    /// Próza review. Prázdná běžně — schválení bez komentáře je čtvrtina vzorku
    /// (`cli/cli#11451`), takže z prázdného těla nesmí být „nic tu není“.
    let body: String
    /// `nil` u rozepsaného (`pending`) review, které odeslané ještě není.
    let submittedAt: Date?

    init(id: String, author: String, state: State?, body: String, submittedAt: Date?) {
        self.id = id
        self.author = author
        self.state = state
        self.body = body
        self.submittedAt = submittedAt
    }

    /// Co ten člověk odeslal.
    enum State: String, Codable, Sendable {
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case commented = "COMMENTED"
        case dismissed = "DISMISSED"
        case pending = "PENDING"
    }

    /// Nese verdikt, ne jen komentář. `dismissed` mezi ně **nepatří** — zamítnuté review
    /// svoje rozhodnutí pozbylo, takže tvrdit „někdo schválil“ by bylo nepravdivé.
    var isVerdict: Bool { state == .approved || state == .changesRequested }
}
