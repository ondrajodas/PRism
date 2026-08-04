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
    /// **Konec** rozsahu — u jednořádkového komentáře ten jediný řádek. U víceřádkového je to
    /// poslední řádek, u kterého visí bublina (jako na GitHubu).
    let line: Int
    /// Ke které straně diffu se komentář váže. **Není odvoditelná z `line`**: odebraný
    /// řádek má číslo ze staré verze souboru, takže bez strany by komentář odešel na jiný
    /// řádek. Rozhoduje `Policy.commentAnchors(of:in:)`.
    let side: DiffSide
    /// Začátek rozsahu u víceřádkového komentáře (#110). `nil` = jeden řádek.
    ///
    /// Ploché volitelné klíče, ne vnořený objekt: draft na disku vznikl u #65 bez nich, takže
    /// **chybějící klíč musí znamenat jeden řádek** — synthetizovaný `Codable` u optionalu
    /// dekóduje `decodeIfPresent`, takže starší soubory se čtou dál. Vnořený `DraftAnchor` by
    /// tvar souboru změnil a rozdělaná review by se po aktualizaci nepřečetla.
    let startLine: Int?
    let startSide: DiffSide?
    var body: String
    let origin: Origin

    /// Kotva se předává celá, ne po číslech: `DraftAnchor` je jediné místo, které ví, že
    /// k odebranému řádku patří staré číslo — a od #110 taky to, kde rozsah začíná.
    init(
        id: UUID = UUID(),
        path: String,
        anchor: DraftAnchor,
        body: String,
        origin: Origin
    ) {
        self.id = id
        self.path = path
        line = anchor.line
        side = anchor.side
        startLine = anchor.start?.line
        startSide = anchor.start?.side
        self.body = body
        self.origin = origin
    }

    /// Kotva zpátky jako celek. Rozsah vznikne jen tehdy, když je **celý** — půl kotvy
    /// (číslo bez strany) by znamenalo hádat stranu, a to je zrovna ta chyba, kvůli které
    /// `DraftAnchor` existuje.
    var anchor: DraftAnchor {
        DraftAnchor(
            line: line,
            side: side,
            start: startLine.flatMap { start in startSide.map { DraftAnchor.Endpoint(line: start, side: $0) } }
        )
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
