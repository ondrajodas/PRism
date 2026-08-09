import Foundation

/// **Jediná cesta, kterou z aplikace něco odejde na GitHub.**
///
/// Do #67 to vynucoval typ: `GitHubGateway` schválně neměl metodu, kterou by šlo něco
/// odeslat. Ta vlastnost **zůstává** — zápis dostal vlastní modul, takže polling, diff,
/// checkout ani reviewer nemají čím něco poslat. `grep ReviewPublishing` vyjmenuje všechna
/// místa, odkud to jde; má jich být jedno.
///
/// Metody jsou **vyjmenované a jsou čtyři** (do #73 jedna, do #216 tři). Každá odpovídá jedné
/// věci, kterou člověk v okně udělá — odeslat review, odpovědět do vlákna, přepnout jeho
/// vyřešení, napsat komentář pod PR — a nic dalšího tady být nesmí: approve mimo review, label
/// ani zavření PR by byly cesty ven, o kterých okno nemluví. Roste-li tenhle výčet, roste to,
/// co aplikace umí odeslat, a to má být vidět v jednom souboru.
///
/// **Komentář pod PR přibyl u #216** a je to vědomé rozšíření tvrdé podmínky č. 1, ne její
/// obejití. Důvod je tentýž jako u odpovědi do vlákna: konverzace pod PR je v okně vidět celá,
/// takže napsat do ní jednu větu je poslední věc, kvůli které se odsud přepíná do prohlížeče.
/// Co se **nezměnilo**: výčet je pořád krátký a na jednom místě, každá metoda si sama ověří
/// bránu, a `GitHubGateway` zápis dál nemá.
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
}
