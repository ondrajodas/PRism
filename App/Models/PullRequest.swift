import Foundation

/// Stav pull requestu na GitHubu.
///
/// Jeden plochý výčet, ne `state` + `isDraft`. GitHub to sice vrací jako dvě pole, ale
/// v aplikaci je z toho jeden odznak v řádku a kombinace, které by dvě pole navíc
/// dovolila (mergnutý draft), reálně nevzniknou. Mapování ze `gh` je mechanické:
/// otevřený a `isDraft` → `draft`.
enum PullRequestState: String, Codable, Sendable, CaseIterable {
    case open
    case draft
    case merged
    case closed

    /// Jak se stav píše v okně.
    ///
    /// Patří k modelu, ne do view, které ho zrovna potřebuje: `rawValue` je **anglický**
    /// a jde do JSONu na disk, takže interpolovat ho do české věty znamená ukázat
    /// uživateli `closed` uprostřed češtiny. Chytilo se to v hlášce `PublishError`.
    var czechLabel: String {
        switch self {
        case .open: "otevřený"
        case .draft: "rozpracovaný"
        case .merged: "mergnutý"
        case .closed: "zavřený"
        }
    }
}

/// Pull request tak, jak ho aplikace potřebuje — metadata z `gh`, žádný diff a žádné nálezy.
///
/// `headSha` je klíčové pole, ne jen údaj: nálezy se klíčují jím, takže nové commity
/// předchozí review zneplatní místo aby se tiše ukazovalo proti kódu, který už neexistuje.
struct PullRequest: Hashable, Codable, Sendable {
    let id: PRIdentifier
    let title: String
    let author: String
    let headSha: String
    let baseSha: String
    /// Jméno větve, ze které se merguje. Prázdné u odpovědí z doby před #174 — tatáž úmluva
    /// jako u `body`, aby se starší uložená data nepřestala dekódovat.
    var headRef: String = ""
    /// Jméno cílové větve.
    var baseRef: String = ""
    let url: URL
    let updatedAt: Date
    let state: PullRequestState
    /// Popis PR, tedy to, co autor napsal do těla. Prázdný běžně.
    ///
    /// Patří k **metadatům PR**, ne do `Conversation`: ta je snímek *cizí* diskuze a popis je
    /// PR sám. Bere se z detailu, který se od #66 stejně dotahuje při výběru řádku, takže to
    /// nestojí ani jedno volání navíc.
    let body: String
    /// Je hlava pull requestu v **jiném** repozitáři (fork)? `nil` = **nevím** (#466).
    ///
    /// **Optional, a `nil` blokuje**, ne propouští: `git push` míří do klonu základního
    /// repozitáře, takže u PR z forku by přetlačil **jinou větev, než na kterou se člověk dívá**.
    /// Starší uložená data pole nemají a dostanou tedy `nil`; v okně se sekce `Větev` skládá
    /// z čerstvě načteného detailu, takže se to v praxi projeví jedině tehdy, když detail
    /// nedorazil.
    var isCrossRepository: Bool?
    /// Kolik řádků PR mění — `additions + deletions` z hlavičky PR (#519). `nil` = **nevím**.
    ///
    /// **Z metadat, ne z diffu.** Diff velkého PR se nemusí ani stáhnout (#542 — nad 300 souborů
    /// vrací GitHub 406), takže počítat řádky z něj by práh neuměl změřit zrovna u toho PR, kvůli
    /// kterému práh existuje. `gh pr view` obě čísla vrací vždycky a nic navíc nestojí.
    ///
    /// **Optional, a `nil` neodkládá**, ne odkládá: starší uložená data pole nemají a odložit
    /// review kvůli tomu, co nevíme, je tichá ztráta času. Tatáž bezpečná strana jako u neznámých
    /// cest v routingu (#518).
    ///
    /// **Součet, ne dvě pole.** Práh je o velikosti změny; smazaný a přidaný řádek stojí reviewera
    /// stejně, a dvě čísla v modelu by znamenala dvě místa, kde se dá sečíst jinak.
    var changedLines: Int?

    init(
        id: PRIdentifier,
        title: String,
        author: String,
        headSha: String,
        baseSha: String,
        headRef: String = "",
        baseRef: String = "",
        url: URL,
        updatedAt: Date,
        state: PullRequestState,
        body: String = "",
        isCrossRepository: Bool? = nil,
        changedLines: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.headSha = headSha
        self.baseSha = baseSha
        self.headRef = headRef
        self.baseRef = baseRef
        self.url = url
        self.updatedAt = updatedAt
        self.state = state
        self.body = body
        self.isCrossRepository = isCrossRepository
        self.changedLines = changedLines
    }

    var repo: RepoID { id.repo }
    var number: Int { id.number }
}
