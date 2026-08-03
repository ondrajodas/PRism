import Foundation

/// Rozdělané review — to, co se **jednou** odešle na GitHub, dokud to člověk nepotvrdí.
///
/// Bydlí **lokálně**, ne jako serverové pending review. Pending review na GitHubu jsou už
/// odeslaná data: jsou vidět v API, blokují další review (ověřeno u #62: 422 `User can only
/// have one pending review per pull request`) a každá úprava komentáře by byla volání API.
/// Tím by padla zásada, že bez potvrzení nic neopustí stroj.
///
/// Jeden draft na PR, ne na `(PR, headSha)` jako uložené nálezy. Nálezy jsou strojový
/// výsledek proti konkrétnímu commitu, tohle je moje rozdělaná práce — a ta se novým
/// commitem nezahazuje.
struct ReviewDraft: Hashable, Codable, Sendable {
    let pullRequest: PRIdentifier
    /// Proti čemu je draft psaný. Nový commit ho **nemaže**, jen zablokuje odeslání —
    /// stejný vzor jako `isStale` u nálezů. Vlastní próza nezastarává tak rychle jako
    /// strojové nálezy, takže ji zahodit je dražší než ji nechat s poctivým příznakem.
    /// Přenesení na nový commit řeší #67.
    var headSha: String
    /// Souhrnné tělo review. Prázdné běžně — schválení bez prózy je normální (čtvrtina
    /// vzorku v `cli/cli#11451`).
    var body: String
    /// `nil` = ještě nevybráno. Není to totéž jako `.comment`, což je vědomé „jen komentuju“.
    var verdict: Verdict?
    var comments: [ReviewDraftComment]

    init(
        pullRequest: PRIdentifier,
        headSha: String,
        body: String = "",
        verdict: Verdict? = nil,
        comments: [ReviewDraftComment] = []
    ) {
        self.pullRequest = pullRequest
        self.headSha = headSha
        self.body = body
        self.verdict = verdict
        self.comments = comments
    }

    /// Co se s PR má stát — hodnota, která jde do `event` při odeslání.
    ///
    /// **Vnořený, ne vedle `ReviewVerdict`.** Ten je náš *návrh* odvozený z nálezů a má
    /// dva případy; tohle je *volba člověka* a má tři, protože `COMMENT` je na GitHubu
    /// plnohodnotná varianta — a na vlastním PR jediná povolená (ověřeno u #62: `APPROVE`
    /// i `REQUEST_CHANGES` vrátí 422). Vnoření je totéž řešení jako u `SubmittedReview.State`:
    /// tři významy slova „review“ se nemají dát zaměnit ani při doplňování v editoru.
    enum Verdict: String, Codable, Sendable, CaseIterable {
        case approve = "APPROVE"
        case requestChanges = "REQUEST_CHANGES"
        case comment = "COMMENT"

        /// Jak se verdikt píše v okně.
        ///
        /// U modelu ze stejného důvodu jako `PullRequestState.czechLabel`: `rawValue` je
        /// anglický, protože ho takhle chce API, a překládat ho v každém view, které ho
        /// ukazuje, znamená dva překlady, které se rozejdou.
        var czechLabel: String {
            switch self {
            case .approve: "Schválit"
            case .requestChanges: "Vyžádat změny"
            case .comment: "Jen komentář"
            }
        }
    }

    /// Není v něm nic, co by se dalo odeslat.
    ///
    /// Na tom stojí `ReviewDraftStore.save`: prázdný draft se **maže**, ne ukládá. Jinak by
    /// v cache zůstávaly soubory po každém PR, které si někdo jen otevřel — a „draft
    /// existuje“ by přestalo znamenat „je co poslat“.
    var isEmpty: Bool {
        body.isEmpty && verdict == nil && comments.isEmpty
    }
}

/// Jeden řádkový komentář v rozdělaném review.
struct ReviewDraftComment: Hashable, Codable, Sendable, Identifiable {
    /// Vlastní identita, ne `path:line`. Dva komentáře na jednom řádku jsou legitimní
    /// (jiná věc ke stejnému kódu) a `ForEach` i editace potřebují je rozlišit.
    let id: UUID
    let path: String
    let line: Int
    /// Ke které straně diffu se komentář váže. **Není odvoditelná z `line`**: odebraný
    /// řádek má číslo ze staré verze souboru, takže bez strany by komentář odešel na jiný
    /// řádek. Rozhoduje `Policy.commentableSide(of:in:)`.
    let side: DiffSide
    var body: String
    let origin: Origin

    init(
        id: UUID = UUID(),
        path: String,
        line: Int,
        side: DiffSide,
        body: String,
        origin: Origin
    ) {
        self.id = id
        self.path = path
        self.line = line
        self.side = side
        self.body = body
        self.origin = origin
    }

    /// Odkud se komentář vzal.
    ///
    /// Převzatý nález si nese **jméno revieweera** — doplněno v #66, kde se to poprvé má kde
    /// přečíst. Do #65 tady žádný odkaz na nález nebyl a bylo to tak správně: uložené jméno,
    /// které nikdo nečte, je mrtvá váha. Čtenář se ale našel a je jich dvakrát: bublina hlásí
    /// odznakem, že nález už v draftu je, a psát to jen podle kotvy `(cesta, řádek, strana)`
    /// nejde. Dva reviewery na jednom řádku jsou běžné (odznak `2×`), takže by se odznak
    /// objevil i u toho druhého — a nález, který vypadá jako převzatý, z odeslaného review
    /// tiše vypadne.
    ///
    /// Odkaz na `Finding` to pořád není, protože `Finding` identitu nemá. Zbytková
    /// nepřesnost: dva nálezy **téhož** revieweera na jednom řádku se od sebe nerozliší.
    enum Origin: Hashable, Codable, Sendable {
        /// Napsal jsem ho sám.
        case own
        /// Vznikl převzetím nálezu od revieweera.
        case finding(reviewer: String)

        /// Kdo nález našel; `nil` u vlastního komentáře.
        var reviewer: String? {
            switch self {
            case .own: nil
            case .finding(let reviewer): reviewer
            }
        }
    }
}
