import Foundation

/// **Jediná cesta, kterou z aplikace něco odejde na GitHub.**
///
/// Do #67 to vynucoval typ: `GitHubGateway` schválně neměl metodu, kterou by šlo něco
/// odeslat. Ta vlastnost **zůstává** — zápis dostal vlastní modul, takže polling, diff,
/// checkout ani reviewer nemají čím něco poslat. `grep ReviewPublishing App/` vyjmenuje všechna
/// místa, odkud to jde: **šest souborů a čtyři volající** — protokol, `GhReviewPublisher`,
/// `ReviewSubmission`, `ThreadSubmission`, `CommentSubmission` a `MetadataSubmission`. Roste-li
/// ten výčet, roste to, co aplikace umí odeslat, a to musí být vidět z jednoho grepu.
///
/// Metody jsou **vyjmenované a je jich šest** (do #73 jedna, do #216 tři, do #392 čtyři). Každá
/// odpovídá jedné věci, kterou člověk v okně udělá — odeslat review, odpovědět do vlákna,
/// přepnout jeho vyřešení, napsat komentář pod PR, přeštítkovat svůj PR, vyžádat na něm review.
/// Co tady být **nesmí**: approve mimo review, **merge**, **zavření PR** a **milník**. Roste-li
/// tenhle výčet, roste to, co aplikace umí odeslat, a to má být vidět v jednom souboru.
///
/// **Komentář pod PR přibyl u #216** a je to vědomé rozšíření tvrdé podmínky č. 1, ne její
/// obejití. Důvod je tentýž jako u odpovědi do vlákna: konverzace pod PR je v okně vidět celá,
/// takže napsat do ní jednu větu je poslední věc, kvůli které se odsud přepíná do prohlížeče.
/// Co se **nezměnilo**: výčet je pořád krátký a na jednom místě, každá metoda si sama ověří
/// bránu, a `GitHubGateway` zápis dál nemá.
///
/// **Labely a vyžádání reviewera přibyly u #392** — pátá a šestá metoda, a je to vědomá změna
/// pravidla: do té doby tady stálo, že „label ani zavření PR sem nepatří“. Změnilo se to proto, že
/// štítek a reviewer jsou u **vlastního** PR součástí toho, jak si člověk řídí svoji frontu, a je
/// to poslední věc, kvůli které se od hotového review přepíná do prohlížeče. Tentýž precedens
/// i tatáž úvaha jako u #73 a #216: výčet se rozšířil, protože se ta věc dělá při review,
/// a **zapsal se důvod**. Co se **nezměnilo**: brána je tatáž (`PublishScope`, `allowsPublishing`
/// globálně i per repo — žádný druhý přepínač), výčet je krátký a na jednom místě, `GitHubGateway`
/// zápis dál nemá a **v zákazu zůstává** approve mimo review, merge, zavření PR a milník.
///
/// **Každá metoda si sama ověří bránu `PublishScope`** — proto všechny berou adresu, ze které
/// se dá zjistit repo. Kdyby ji jedna z nich brát nemusela, existovala by cesta ven, která se
/// nedá zakázat v nastavení.
protocol ReviewPublishing: Sendable {
    /// Odešle rozdělané review. Vrací to, co GitHub potvrdil, ne to, co jsme poslali —
    /// z odpovědi je vidět, jak review doopravdy dopadlo.
    ///
    /// Před voláním si ověří, že repo je v `PublishScope`, že draft míří na aktuální hlavu
    /// PR a že je PR otevřený. **Při neshodě se nevolá nic.**
    func submit(_ draft: ReviewDraft) async throws -> SubmittedReview

    /// Odpoví do existujícího vlákna. Vrací komentář, jak ho potvrdil GitHub, takže se dá
    /// vložit do konverzace bez dalšího čtení.
    ///
    /// Pre-flight je **užší než u review**: ověřuje se scope a stav PR, ne `headSha`. Odpověď
    /// se váže na vlákno, ne na commit — odpovědět kolegovi na vlákno, které vzniklo před třemi
    /// pushi, je běžné, takže kontrola hlavy by zakazovala zrovna to, na co se odpovídá.
    /// Prázdné tělo se **neodesílá**: GitHub ho tiše spolkne (změřeno v sandboxu).
    func reply(to thread: ThreadTarget, body: String) async throws -> ThreadComment

    /// Označí vlákno za vyřešené, nebo ho otevře zpátky. Vrací stav i práva, jak je přepočítal
    /// GitHub.
    func setResolved(_ resolved: Bool, of thread: ThreadTarget) async throws -> ThreadResolution

    /// Napíše komentář do diskuze pod PR (#216). Vrací komentář, jak ho potvrdil GitHub, takže
    /// se dá vložit do konverzace bez dalšího čtení.
    ///
    /// Pre-flight je **stejně široký jako u odpovědi do vlákna**: scope a stav PR, ne `headSha`.
    /// Komentář pod PR se neváže na žádný commit — psát „mrknu na to zítra“ pod PR, který mezitím
    /// dostal push, je běžné, takže kontrola hlavy by zakazovala právě to.
    ///
    /// **Není to review.** Neposílá verdikt, nedá se jím schválit ani vyžádat změny a v panelu
    /// `Moje review` se neobjeví; to jde jedině `submit(_:)`, a to s potvrzením.
    func comment(on pullRequest: PRIdentifier, body: String) async throws -> ThreadComment

    /// Nastaví **celou** sadu labelů na PR (#392). Vrací ji, jak ji potvrdil GitHub, takže se dá
    /// zapsat do okna bez dalšího čtení.
    ///
    /// **Celá sada, ne přidání jednoho.** `PUT /issues/{n}/labels` sadu nahrazuje, takže rozdíl
    /// by se musel skládat podruhé tady — a dvě skládání téhož se rozejdou. Volající si sadu
    /// nechá spočítat od `Policy.toggledLabels`, která zároveň hlídá, že v ní není label, který
    /// repo nezná.
    ///
    /// Pre-flight je **stejně široký jako u komentáře**: scope a stav PR, ne `headSha`. Štítek se
    /// neváže na commit — přeštítkovat PR, který mezitím dostal push, je zrovna ta situace, kvůli
    /// které se štítkuje.
    func setLabels(_ labels: [String], on pullRequest: PRIdentifier) async throws -> [PullRequestLabel]

    /// Vyžádá review od uvedených lidí a týmů (#392). Vrací to, na koho se podle GitHubu čeká.
    ///
    /// **Jedna metoda na lidi i na týmy, ne dvě.** GitHub je bere jedním voláním
    /// (`reviewers` a `team_reviewers` v jednom payloadu), takže druhá metoda by výčet cest ven
    /// prodloužila za nic — a tvrdá podmínka č. 1 stojí na tom, že je ten výčet krátký.
    ///
    /// Slugy týmů se posílají **bez předpony organizace** — tak, jak je chce API a jak je dává
    /// `orgs/{org}/teams`.
    ///
    /// **Jen přidává.** Odebrat vyžádané review odsud nejde, a je to schválně: request pošle
    /// člověku upozornění, které se odebráním **nedá vzít zpět**, takže odebrání není opravný krok,
    /// jen zametení. Proto je u něj v okně jméno na tlačítku, ne `+` vedle avatara.
    ///
    /// Pre-flight jako u labelů — scope a stav PR, ne `headSha`.
    func requestReviewers(
        _ logins: [String],
        teams: [String],
        on pullRequest: PRIdentifier
    ) async throws -> RequestedReview
}
