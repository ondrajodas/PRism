import Foundation

/// Jeden komentář — ve vlákně u řádku i v konverzaci pod PR.
///
/// Sdílený tvar pro obojí schválně: konverzace pod PR je tentýž komentář bez vlákna,
/// takže `replyTo` je u ní vždycky `nil`. Dva téměř shodné typy by znamenaly dvě cesty
/// mapování a dvě místa, kde se dá zapomenout na `isMine`.
struct ThreadComment: Hashable, Codable, Sendable {
    let id: String
    /// Kdo komentář napsal. Jestli jsem to já, ví `Conversation` — potřebuje k tomu
    /// přihlášeného uživatele, kterého komentář sám nezná.
    let author: String
    let body: String
    let createdAt: Date
    /// Odkaz na komentář na GitHubu. Aplikace na GitHub nic neposílá, ale otevřít ho
    /// v prohlížeči je jediná cesta, jak na komentář odpovědět — dokud nebude #73.
    let url: URL
    /// Identita komentáře, na který tenhle odpovídá. `nil` = první ve vlákně.
    ///
    /// Drží se **identita, ne vnořený komentář**: GitHub vrací vlákno jako plochý seznam
    /// a skládat z něj strom by znamenalo rozhodovat, co s odpovědí na komentář, který
    /// v odpovědi není (useknutá stránka). Plochý seznam s odkazem zpátky žádnou takovou
    /// otázku neotevírá.
    let replyToID: String?

    init(
        id: String,
        author: String,
        body: String,
        createdAt: Date,
        url: URL,
        replyToID: String? = nil
    ) {
        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.url = url
        self.replyToID = replyToID
    }
}
