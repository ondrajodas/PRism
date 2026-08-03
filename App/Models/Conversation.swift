import Foundation

/// Konverzace pod pull requestem tak, jak ji vidí GitHub — review ostatních, vlákna
/// u řádků a komentáře pod PR.
///
/// Je to **cizí obsah**, ne nálezy naší aplikace: `Finding` je to, co našel reviewer, kdežto
/// tohle je to, kvůli čemu se člověk vrací na GitHub. Dvě různé věci se stejným místem
/// v diffu, takže se nesmí slít.
///
/// Nepersistuje se — načítá se při zobrazení PR a zahazuje se s ním. `Codable` je tady kvůli
/// konvenci modelů a testům round-tripu, ne kvůli disku.
struct Conversation: Hashable, Codable, Sendable {
    /// Přihlášený uživatel. Drží se **jednou tady**, ne jako příznak na každém komentáři:
    /// „je to moje“ je vztah mezi komentářem a tím, kdo se dívá, ne vlastnost komentáře.
    /// Uložený příznak by navíc po změně účtu tvrdil něco jiného, než je pravda.
    let viewer: String
    let reviews: ConversationPage<SubmittedReview>
    let threads: ConversationPage<ReviewThread>
    /// Komentáře pod PR — konverzace, která nepatří k žádnému řádku.
    let comments: ConversationPage<ThreadComment>

    init(
        viewer: String,
        reviews: ConversationPage<SubmittedReview>,
        threads: ConversationPage<ReviewThread>,
        comments: ConversationPage<ThreadComment>
    ) {
        self.viewer = viewer
        self.reviews = reviews
        self.threads = threads
        self.comments = comments
    }

    /// Přišlo něco zkrácené — ať na kterékoli úrovni, **včetně komentářů uvnitř vláken**.
    ///
    /// Vlákna se počítají zvlášť, protože useknutá odpověď uvnitř jednoho vlákna se ve
    /// výpisu vláken nijak neprojeví: jejich počet vyjde správně a chybí až ta odpověď,
    /// kvůli které se člověk do vlákna dívá.
    var isTruncated: Bool {
        reviews.isTruncated
            || threads.isTruncated
            || comments.isTruncated
            || threads.items.contains { $0.comments.isTruncated }
    }

    func isMine(_ comment: ThreadComment) -> Bool { comment.author == viewer }

    func isMine(_ review: SubmittedReview) -> Bool { review.author == viewer }
}

/// Kus seznamu a to, kolik ho je celkem.
///
/// Drží **oba** signály zkrácení, které GraphQL dává — `hasNextPage` i `totalCount` — a
/// `isTruncated` je jejich **`or`**, ne volba jednoho z nich. Není to nerozhodnost:
/// nebezpečný směr je jediný, totiž tvrdit „máš všechno“, když ne. `or` se v tom směru
/// splést nemůže, kdežto vybraný signál ano, protože jeden z nich může přijít jinak, než
/// čekáme, a druhý by to nezachytil.
///
/// `total` se přitom drží i tak, protože z něj vyjde „1 ze 38“ — samotný `hasNextPage`
/// řekne jen, že něco chybí, ne kolik.
struct ConversationPage<Element: Hashable & Codable & Sendable>: Hashable, Codable, Sendable {
    let items: [Element]
    /// Kolik jich má PR dohromady — ne kolik jich dorazilo.
    let total: Int
    /// `pageInfo.hasNextPage` z GraphQL.
    let hasNextPage: Bool

    init(items: [Element], total: Int, hasNextPage: Bool) {
        self.items = items
        self.total = total
        self.hasNextPage = hasNextPage
    }

    /// Něco se nevešlo do stránky. Utnutá data nesmí vypadat jako úplná — stejné pravidlo
    /// jako u `droppedFindings`.
    var isTruncated: Bool { hasNextPage || items.count < total }

    /// Kolik chybí. Nikdy ne záporné: kdyby `total` z API zůstal pozadu za počtem položek,
    /// je „chybí −3“ horší než „nechybí nic“.
    var missing: Int { max(0, total - items.count) }
}
